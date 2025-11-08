import Foundation
import Security
import Utils
import Core
import SmartVestor

/// Robinhood exchange connector with Ed25519 authentication for checking balances and placing orders.
///
/// Uses the Robinhood Crypto Trading API with Ed25519 key-pair authentication.
/// Credentials should be provided via environment variables:
/// - ROBINHOOD_API_KEY: Your Robinhood API key
/// - ROBINHOOD_PRIVATE_KEY: Base64-encoded private key
public final class RobinhoodConnector: ExchangeConnector, @unchecked Sendable {
    public struct Configuration: Sendable {
        public struct Credentials: Sendable {
            public let apiKey: String
            let privateKey: Data

            public init(apiKey: String, privateKeyBase64: String) throws {
                self.apiKey = apiKey
                guard let privateKeyData = Data(base64Encoded: privateKeyBase64) else {
                    throw RobinhoodError.invalidPrivateKey
                }
                self.privateKey = privateKeyData
            }
        }

        public let credentials: Credentials?
        public let baseURL: URL
        public let requestTimeout: TimeInterval
        let rateLimiter: RateLimiter?

        public init(
            credentials: Credentials? = nil,
            baseURL: URL = URL(string: "https://trading.robinhood.com")!,
            requestTimeout: TimeInterval = 30
        ) {
            self.credentials = credentials
            self.baseURL = baseURL
            self.requestTimeout = requestTimeout
            self.rateLimiter = RateLimiter(
                maxCapacity: 100,
                refillAmount: 100,
                refillInterval: 60
            )
        }
    }

    public let name: String = "Robinhood"

    public var priceUpdates: AsyncStream<RawPriceData> { _priceStream }
    public var connectionEvents: AsyncStream<ConnectionEvent> { _eventStream }

    public var connectionStatus: ConnectionStatus {
        get { _connectionStatus }
    }

    private var _connectionStatus: ConnectionStatus = .disconnected
    private let logger: StructuredLogger
    private let configuration: Configuration
    private let session: URLSession
    private let component = "connector.robinhood"

    // Mock streams for ExchangeConnector protocol compliance
    private let _priceStream: AsyncStream<RawPriceData>
    private let _eventStream: AsyncStream<ConnectionEvent>

    public init(
        logger: StructuredLogger,
        configuration: Configuration,
        session: URLSession = URLSession(configuration: .default)
    ) {
        self.logger = logger
        self.configuration = configuration
        self.session = session

        // Create mock streams for ExchangeConnector protocol compliance
        let priceStreamPair = AsyncStream.makeStream(of: RawPriceData.self, bufferingPolicy: .bufferingNewest(10))
        let eventStreamPair = AsyncStream.makeStream(of: ConnectionEvent.self, bufferingPolicy: .bufferingNewest(10))
        self._priceStream = priceStreamPair.stream
        self._eventStream = eventStreamPair.stream
        _ = priceStreamPair.continuation
        _ = eventStreamPair.continuation

        // Load credentials from environment if not provided
        let _ = loadCredentialsFromEnvironment()
    }

    private func loadCredentialsFromEnvironment() -> Bool {
        guard configuration.credentials == nil else { return true }

        guard let apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"] else {
            logger.warn(
                component: component,
                event: "credentials_missing",
                data: ["message": "ROBINHOOD_API_KEY environment variable not set"]
            )
            return false
        }

        if let privateKeyBase64 = ProcessInfo.processInfo.environment["ROBINHOOD_PRIVATE_KEY"],
           let _ = try? Configuration.Credentials(apiKey: apiKey, privateKeyBase64: privateKeyBase64) {
            logger.info(
                component: component,
                event: "credentials_loaded_from_environment",
                data: ["api_key_prefix": String(apiKey.prefix(10)), "has_private_key": "true"]
            )
            // Store credentials in configuration for later use
            return true
        } else {
            logger.warn(
                component: component,
                event: "partial_credentials",
                data: [
                    "message": "ROBINHOOD_PRIVATE_KEY not set - read-only operations only",
                    "has_api_key": "true",
                    "has_private_key": "false"
                ]
            )
            return false
        }
    }

    public func connect() async throws {
        guard _connectionStatus != .connected else { return }

        _connectionStatus = .connected
        logger.info(component: component, event: "connected")
    }

    public func disconnect() async {
        _connectionStatus = .disconnected
        logger.info(component: component, event: "disconnected")
    }

    public func subscribeToPairs(_ pairs: [String]) async throws {
        // Robinhood uses REST API, not WebSocket for market data
        // This is a no-op to satisfy the protocol
        logger.debug(
            component: component,
            event: "subscribe_ignored",
            data: ["pairs": pairs.joined(separator: ",")]
        )
    }

    // MARK: - Trading Methods

    public func getHoldings() async throws -> [[String: Any]] {
        let holdings = try await getHoldings(assetCode: nil)
        return holdings.map { holding in
            [
                "asset": holding.assetCode,
                "quantity": String(holding.quantity),
                "available": String(holding.available),
                "pending": String(holding.pending),
                "staked": String(holding.staked)
            ]
        }
    }

    public func getAccountBalance() async throws -> [String: String] {
        let account = try await getAccountDetails()
        var result: [String: String] = [
            "id": account.id,
            "updated_at": ISO8601DateFormatter().string(from: account.updatedAt)
        ]
        if let accountNumber = account.accountNumber {
            result["account_number"] = accountNumber
        }
        if let buyingPower = account.cryptoBuyingPower {
            result["crypto_buying_power"] = buyingPower
        }
        return result
    }

    public func getOrderBook(symbol: String) async throws -> Core.OrderBook {
        throw ArbitrageError.logic(.internalError(
            component: "RobinhoodConnector",
            reason: "getOrderBook not implemented for \(name)"
        ))
    }

    public func getRecentTransactions(limit: Int) async throws -> [Core.Transaction] {
        guard let credentials = configuration.credentials else {
            throw ArbitrageError.connection(.authenticationFailed(
                exchange: name,
                reason: "No credentials provided"
            ))
        }

        let endpoint = "/api/v1/crypto/trading/orders/"
        let response = try await makeAuthenticatedRequest(
            method: "GET",
            endpoint: endpoint,
            body: nil,
            credentials: credentials
        )

        guard let results = response["results"] as? [[String: Any]] else {
            logger.debug(component: component, event: "orders_response_empty", data: ["response_keys": Array(response.keys).joined(separator: ",")])
            return []
        }

        var transactions: [Core.Transaction] = []
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for order in results.prefix(limit) {
            guard let id = order["id"] as? String,
                  let sideStr = order["side"] as? String,
                  let symbol = order["symbol"] as? String,
                  let state = order["state"] as? String,
                  state == "filled" else {
                continue
            }

            logger.debug(component: component, event: "parsing_order", data: [
                "id": id,
                "side": sideStr,
                "symbol": symbol,
                "state": state,
                "order_keys": Array(order.keys).joined(separator: ",")
            ])

            let side: Core.OrderSide = sideStr.lowercased() == "buy" ? .buy : .sell

            var asset = symbol
            if asset.hasSuffix("-USD") {
                asset = String(asset.dropLast(4))
            }

            var quantity = 0.0
            if let qtyStr = order["quantity"] as? String {
                quantity = Double(qtyStr) ?? 0.0
            } else if let qtyNum = order["quantity"] as? Double {
                quantity = qtyNum
            } else if let qtyNum = order["quantity"] as? Int {
                quantity = Double(qtyNum)
            }

            if quantity == 0.0 {
                if let filledQuantityStr = order["filled_asset_quantity"] as? String {
                    quantity = Double(filledQuantityStr) ?? 0.0
                } else if let filledQuantityNum = order["filled_asset_quantity"] as? Double {
                    quantity = filledQuantityNum
                } else if let filledQuantityNum = order["filled_asset_quantity"] as? Int {
                    quantity = Double(filledQuantityNum)
                }
            }

            if quantity == 0.0 {
                if let marketOrderConfig = order["market_order_config"] as? [String: Any],
                   let qtyStr = marketOrderConfig["asset_quantity"] as? String {
                    quantity = Double(qtyStr) ?? 0.0
                } else if let limitOrderConfig = order["limit_order_config"] as? [String: Any],
                          let qtyStr = limitOrderConfig["asset_quantity"] as? String {
                    quantity = Double(qtyStr) ?? 0.0
                }
            }

            var averagePrice = 0.0
            if let priceStr = order["average_price"] as? String {
                averagePrice = Double(priceStr) ?? 0.0
            } else if let priceNum = order["average_price"] as? Double {
                averagePrice = priceNum
            } else if let priceNum = order["average_price"] as? Int {
                averagePrice = Double(priceNum)
            }

            if averagePrice == 0.0 {
                if let priceStr = order["average_filled_price"] as? String {
                    averagePrice = Double(priceStr) ?? 0.0
                } else if let priceNum = order["average_filled_price"] as? Double {
                    averagePrice = priceNum
                } else if let priceNum = order["average_filled_price"] as? Int {
                    averagePrice = Double(priceNum)
                }
            }

            if averagePrice == 0.0 {
                if let limitPriceStr = order["limit_price"] as? String {
                    averagePrice = Double(limitPriceStr) ?? 0.0
                } else if let limitPriceNum = order["limit_price"] as? Double {
                    averagePrice = limitPriceNum
                }
            }

            logger.debug(component: component, event: "parsed_order", data: [
                "id": id,
                "quantity": String(quantity),
                "price": String(averagePrice),
                "asset": asset
            ])

            var timestamp = Date()
            if let updatedAtStr = order["updated_at"] as? String {
                timestamp = dateFormatter.date(from: updatedAtStr) ?? Date()
            } else if let createdAtStr = order["created_at"] as? String {
                timestamp = dateFormatter.date(from: createdAtStr) ?? Date()
            }

            let transactionType: Core.TransactionType = side == .buy ? .buy : .sell

            let transaction = Core.Transaction(
                id: id,
                type: transactionType,
                asset: asset,
                quantity: quantity,
                price: averagePrice,
                timestamp: timestamp
            )

            transactions.append(transaction)
        }

        return transactions.sorted { $0.timestamp > $1.timestamp }
    }

    public func placeOrder(
        symbol: String,
        side: Core.OrderSide,
        type: Core.OrderType,
        quantity: Double,
        price: Double
    ) async throws -> Core.Order {
        guard let credentials = configuration.credentials else {
            throw ArbitrageError.connection(.authenticationFailed(
                exchange: name,
                reason: "No credentials provided"
            ))
        }

        let orderId = UUID().uuidString
        var body: [String: Any] = [
            "client_order_id": orderId,
            "side": side == .buy ? "buy" : "sell",
            "type": type == .market ? "market" : "limit",
            "symbol": symbol
        ]

        // Configure order based on type
        if type == .market {
            body["market_order_config"] = [
                "asset_quantity": String(format: "%.8f", quantity)
            ]
        } else {
            // Limit order requires price and quantity
            body["limit_order_config"] = [
                "asset_quantity": String(format: "%.8f", quantity),
                "limit_price": String(format: "%.8f", price)
            ]
        }

        let endpoint = "/api/v1/crypto/trading/orders/"
        let response = try await makeAuthenticatedRequest(
            method: "POST",
            endpoint: endpoint,
            body: body,
            credentials: credentials
        )

        guard let orderId = response["id"] as? String else {
            throw ArbitrageError.data(.invalidFormat(
                exchange: name,
                reason: "Missing order ID in response"
            ))
        }

        return Core.Order(
            id: orderId,
            symbol: symbol,
            side: side,
            type: type,
            quantity: quantity,
            price: price,
            status: .pending,
            timestamp: Date()
        )
    }

    /// Fetch crypto holdings from Robinhood
    public func getHoldings(assetCode: String? = nil) async throws -> [RobinhoodHolding] {
        guard let apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"],
              let privateKeyBase64 = ProcessInfo.processInfo.environment["ROBINHOOD_PRIVATE_KEY"] else {
            throw ArbitrageError.connection(.authenticationFailed(
                exchange: name,
                reason: "ROBINHOOD_API_KEY and ROBINHOOD_PRIVATE_KEY environment variables required"
            ))
        }

        guard let privateKey = Data(base64Encoded: privateKeyBase64) else {
            throw ArbitrageError.connection(.authenticationFailed(
                exchange: name,
                reason: "Invalid ROBINHOOD_PRIVATE_KEY format (must be base64)"
            ))
        }

        var endpoint = "/api/v1/crypto/trading/holdings/"
        if let assetCode = assetCode {
            endpoint += "?asset_code=\(assetCode)"
        }

        let response = try await makeAuthenticatedRequestWithCredentials(
            method: "GET",
            endpoint: endpoint,
            apiKey: apiKey,
            privateKey: privateKey
        )

        guard let results = response["results"] as? [[String: Any]] else {
            logger.info(
                component: component,
                event: "no_holdings_results",
                data: ["response_keys": Array(response.keys).joined(separator: ",")]
            )
            return []
        }

        logger.info(
            component: component,
            event: "holdings_parsed",
            data: ["count": String(results.count)]
        )

        // Parse all holdings, even those with zero quantity
        let holdings = results.compactMap { holdingDict in
            try? parseHolding(from: holdingDict)
        }

        logger.info(
            component: component,
            event: "holdings_converted",
            data: ["count": String(holdings.count)]
        )

        return holdings
    }

    /// Fetch account details from Robinhood
    public func getAccountDetails() async throws -> RobinhoodAccount {
        guard let apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"],
              let privateKeyBase64 = ProcessInfo.processInfo.environment["ROBINHOOD_PRIVATE_KEY"] else {
            throw ArbitrageError.connection(.authenticationFailed(
                exchange: name,
                reason: "ROBINHOOD_API_KEY and ROBINHOOD_PRIVATE_KEY environment variables required"
            ))
        }

        guard let privateKey = Data(base64Encoded: privateKeyBase64) else {
            throw ArbitrageError.connection(.authenticationFailed(
                exchange: name,
                reason: "Invalid ROBINHOOD_PRIVATE_KEY format (must be base64)"
            ))
        }

        let endpoint = "/api/v1/crypto/trading/accounts/"
        let response = try await makeAuthenticatedRequestWithCredentials(
            method: "GET",
            endpoint: endpoint,
            apiKey: apiKey,
            privateKey: privateKey
        )

        return try parseAccount(from: response)
    }

    // MARK: - Private Helpers

    private func makeAuthenticatedRequestWithCredentials(
        method: String,
        endpoint: String,
        apiKey: String,
        privateKey: Data
    ) async throws -> [String: Any] {
        // Rate limiting
        if let rateLimiter = configuration.rateLimiter {
            try await rateLimiter.waitIfNeeded()
        }

        let timestamp = String(Int(Date().timeIntervalSince1970))

        // Create message to sign: api_key + timestamp + endpoint + method + body
        let message = "\(apiKey)\(timestamp)\(endpoint)\(method)"
        let messageData = message.data(using: .utf8)!

        // Sign message with Ed25519
        let signature = try signMessage(messageData, privateKey: privateKey)
        let signatureBase64 = signature.base64EncodedString()

        // Build request
        let url = configuration.baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(signatureBase64, forHTTPHeaderField: "x-signature")
        request.setValue(timestamp, forHTTPHeaderField: "x-timestamp")
        request.timeoutInterval = configuration.requestTimeout

        // Make request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ArbitrageError.connection(.failedToConnect(
                exchange: name,
                reason: "Invalid response"
            ))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorString = String(data: data.prefix(500), encoding: .utf8) ?? "Unable to decode error"
            logger.error(
                component: component,
                event: "api_error",
                data: ["status": String(httpResponse.statusCode), "response": errorString]
            )

            // Try to parse error details from JSON response
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = errorJson["errors"] as? [[String: Any]],
               let firstError = errors.first,
               let detail = firstError["detail"] as? String {
                throw ArbitrageError.connection(.authenticationFailed(
                    exchange: name,
                    reason: "HTTP \(httpResponse.statusCode): \(detail)"
                ))
            }

            throw ArbitrageError.connection(.authenticationFailed(
                exchange: name,
                reason: "HTTP \(httpResponse.statusCode) - \(errorString)"
            ))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ArbitrageError.data(.invalidJSON(
                exchange: name,
                reason: "Failed to parse JSON response"
            ))
        }

        return json
    }

    private func makeRequestWithAPIKeyOnly(
        method: String,
        endpoint: String,
        apiKey: String
    ) async throws -> [String: Any] {
        // For read-only operations, try without signature first
        // Some endpoints might work with just API key

        // Rate limiting
        if let rateLimiter = configuration.rateLimiter {
            try await rateLimiter.waitIfNeeded()
        }

        let timestamp = String(Int(Date().timeIntervalSince1970))

        // Build request
        let url = configuration.baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(timestamp, forHTTPHeaderField: "x-timestamp")
        request.timeoutInterval = configuration.requestTimeout

        // Make request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ArbitrageError.connection(.failedToConnect(
                exchange: name,
                reason: "Invalid response"
            ))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorString = String(data: data.prefix(200), encoding: .utf8) ?? "Unable to decode error"
            logger.error(
                component: component,
                event: "api_error",
                data: [
                    "status": String(httpResponse.statusCode),
                    "response": errorString
                ]
            )
            throw ArbitrageError.connection(.authenticationFailed(
                exchange: name,
                reason: "HTTP \(httpResponse.statusCode) - \(errorString)"
            ))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ArbitrageError.data(.invalidJSON(
                exchange: name,
                reason: "Failed to parse JSON response"
            ))
        }

        return json
    }

    private func makeAuthenticatedRequest(
        method: String,
        endpoint: String,
        body: [String: Any]?,
        credentials: Configuration.Credentials
    ) async throws -> [String: Any] {
        // Rate limiting
        if let rateLimiter = configuration.rateLimiter {
            try await rateLimiter.waitIfNeeded()
        }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let bodyString = body != nil ? try JSONSerialization.data(withJSONObject: body!).base64EncodedString() : ""

        // Create message to sign
        let message = "\(credentials.apiKey)\(timestamp)\(endpoint)\(method)\(bodyString)"
        let messageData = message.data(using: .utf8)!

        // Sign message with Ed25519
        let signature = try signMessage(messageData, privateKey: credentials.privateKey)
        let signatureBase64 = signature.base64EncodedString()

        // Build request
        let url = configuration.baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(signatureBase64, forHTTPHeaderField: "x-signature")
        request.setValue(timestamp, forHTTPHeaderField: "x-timestamp")
        request.timeoutInterval = configuration.requestTimeout

        // Add body if present
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        // Make request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ArbitrageError.connection(.failedToConnect(
                exchange: name,
                reason: "Invalid response"
            ))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorString = String(data: data.prefix(200), encoding: .utf8) ?? "Unable to decode error"
            logger.error(
                component: component,
                event: "api_error",
                data: ["status": String(httpResponse.statusCode), "response": errorString]
            )
            throw ArbitrageError.connection(.authenticationFailed(
                exchange: name,
                reason: "HTTP \(httpResponse.statusCode)"
            ))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ArbitrageError.data(.invalidJSON(
                exchange: name,
                reason: "Failed to parse JSON response"
            ))
        }

        return json
    }

    private func signMessage(_ message: Data, privateKey: Data) throws -> Data {
        // Use Python nacl library for Ed25519 signing since macOS Security framework
        // doesn't support Ed25519 directly

        // Get the path to the signer script
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let scriptPath = "\(currentDirectory)/scripts/sign_robinhood_request.py"

        // Check if script exists
        guard fileManager.fileExists(atPath: scriptPath) else {
            throw RobinhoodError.signingFailed("Signing script not found at \(scriptPath)")
        }

        // Encode the message and private key as base64 strings to pass to Python
        let messageBase64 = message.base64EncodedString()
        let privateKeyBase64 = privateKey.base64EncodedString()

        // Create a temporary process to run Python script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/python3")
        process.arguments = [scriptPath, "--message", messageBase64, "--private-key", privateKeyBase64]

        // Capture output
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Run the process synchronously
        try process.run()
        process.waitUntilExit()

        // Read the output first to see error messages
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Check exit code
        guard process.terminationStatus == 0 else {
            throw RobinhoodError.signingFailed("Python signing script failed with exit code \(process.terminationStatus). Output: \(output)")
        }

        // Get the signature from output
        let signatureBase64 = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signatureBase64.isEmpty else {
            throw RobinhoodError.signingFailed("Failed to read signature from Python script. Output: \(output)")
        }

        // Decode the signature
        guard let signature = Data(base64Encoded: signatureBase64) else {
            throw RobinhoodError.signingFailed("Invalid base64 signature from Python script")
        }

        return signature
    }

    private func parseHolding(from dict: [String: Any]) throws -> RobinhoodHolding {
        guard let assetCode = dict["asset_code"] as? String else {
            throw ArbitrageError.data(.missingField(
                exchange: name,
                field: "asset_code"
            ))
        }

        // Robinhood API uses "total_quantity" for the total and "quantity_available_for_trading" for available
        // Try both as number or string
        func getQuantity(key: String) -> Double? {
            if let str = dict[key] as? String {
                return Double(str)
            } else if let num = dict[key] as? Double {
                return num
            } else if let num = dict[key] as? Int {
                return Double(num)
            }
            return nil
        }

        guard let totalQuantity = getQuantity(key: "total_quantity") else {
            throw ArbitrageError.data(.missingField(
                exchange: name,
                field: "total_quantity"
            ))
        }

        let availableQuantity = getQuantity(key: "quantity_available_for_trading") ?? totalQuantity

        return RobinhoodHolding(
            assetCode: assetCode,
            quantity: totalQuantity,
            available: availableQuantity,
            pending: 0.0,
            staked: 0.0
        )
    }

    private func parseAccount(from dict: [String: Any]) throws -> RobinhoodAccount {
        // Parse account details - structure depends on Robinhood API response
        // For now, return a basic account
        return RobinhoodAccount(
            id: dict["id"] as? String ?? UUID().uuidString,
            accountNumber: dict["account_number"] as? String,
            cryptoBuyingPower: dict["crypto_buying_power"] as? String,
            updatedAt: Date()
        )
    }
}

// MARK: - Supporting Types

public enum RobinhoodError: Error {
    case invalidPrivateKey
    case signingFailed(String)
    case invalidCredentials
}

public struct RobinhoodHolding {
    public let assetCode: String
    public let quantity: Double
    public let available: Double
    public let pending: Double
    public let staked: Double

    public init(
        assetCode: String,
        quantity: Double,
        available: Double,
        pending: Double,
        staked: Double
    ) {
        self.assetCode = assetCode
        self.quantity = quantity
        self.available = available
        self.pending = pending
        self.staked = staked
    }
}

public struct RobinhoodAccount {
    public let id: String
    public let accountNumber: String?
    public let cryptoBuyingPower: String?
    public let updatedAt: Date

    public init(
        id: String,
        accountNumber: String?,
        cryptoBuyingPower: String?,
        updatedAt: Date
    ) {
        self.id = id
        self.accountNumber = accountNumber
        self.cryptoBuyingPower = cryptoBuyingPower
        self.updatedAt = updatedAt
    }
}

// MARK: - Rate Limiter

actor RateLimiter {
    private var tokens: Int
    private let maxCapacity: Int
    private let refillAmount: Int
    private let refillInterval: TimeInterval

    init(maxCapacity: Int, refillAmount: Int, refillInterval: TimeInterval) {
        self.tokens = maxCapacity
        self.maxCapacity = maxCapacity
        self.refillAmount = refillAmount
        self.refillInterval = refillInterval
    }

    func waitIfNeeded() async throws {
        if tokens > 0 {
            tokens -= 1
            return
        }

        // Wait for refill
        try await Task.sleep(nanoseconds: UInt64(refillInterval * 1_000_000_000))
        tokens = min(maxCapacity, tokens + refillAmount)
        if tokens > 0 {
            tokens -= 1
        }
    }
}
