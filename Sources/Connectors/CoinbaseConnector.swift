import Foundation
import CryptoKit
import Utils
import Core

/// Coinbase exchange connector that streams ticker updates from the Coinbase WebSocket API.
public final class CoinbaseConnector: ExchangeConnector, @unchecked Sendable {
    public struct Configuration: Sendable {
        public struct Credentials: Sendable {
            public let apiKey: String
            public let apiSecret: String
            public let passphrase: String?

            public init(apiKey: String, apiSecret: String, passphrase: String? = nil) {
                self.apiKey = apiKey
                self.apiSecret = apiSecret
                self.passphrase = passphrase
            }
        }

        public enum Environment: Sendable {
            case production
            case sandbox
            case custom(URL)

            fileprivate var url: URL {
                switch self {
                case .production:
                    return URL(string: "wss://ws-feed.exchange.coinbase.com")!
                case .sandbox:
                    return URL(string: "wss://ws-feed-public.sandbox.exchange.coinbase.com")!
                case .custom(let value):
                    return value
                }
            }
        }

        public let environment: Environment
        public let credentials: Credentials?
        public let requestTimeout: TimeInterval

        public init(
            environment: Environment = .production,
            credentials: Credentials? = nil,
            requestTimeout: TimeInterval = 30
        ) {
            self.environment = environment
            self.credentials = credentials
            self.requestTimeout = max(5, requestTimeout)
        }
    }

    public let name: String = "Coinbase"
    public var priceUpdates: AsyncStream<RawPriceData> { baseConnector.priceUpdates }
    public var connectionEvents: AsyncStream<ConnectionEvent> { baseConnector.connectionEvents }

    public var connectionStatus: ConnectionStatus {
        get async { await baseConnector.connectionStatus }
    }

    private let session: URLSession
    private lazy var baseConnector: BaseExchangeConnector = Self.makeBaseConnector(
        owner: self,
        logger: logger,
        session: session,
        configuration: configuration
    )
    private let logger: StructuredLogger
    private let configuration: Configuration
    private let authenticator: Authenticator?
    private let iso8601: ISO8601DateFormatter
    private let component = "connector.coinbase"

    public init(
        logger: StructuredLogger,
        configuration: Configuration = Configuration(),
        session: URLSession = URLSession(configuration: .default)
    ) {
        self.session = session
        self.logger = logger
        self.configuration = configuration

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601 = formatter

        if let credentials = configuration.credentials {
            self.authenticator = Authenticator(credentials: credentials, logger: logger)
        } else {
            self.authenticator = nil
        }

        _ = baseConnector
    }

    public func connect() async throws {
        try await baseConnector.connect()
    }

    private static func makeBaseConnector(
        owner: CoinbaseConnector,
        logger: StructuredLogger,
        session: URLSession,
        configuration: Configuration
    ) -> BaseExchangeConnector {
        let ownerBox = WeakBox(owner)

        let connector = BaseExchangeConnector(
            name: "Coinbase",
            logger: logger,
            session: session,
            requestBuilder: { _ in
                var request = URLRequest(url: configuration.environment.url)
                request.timeoutInterval = configuration.requestTimeout
                request.addValue("ArbitrageEngine/1.0", forHTTPHeaderField: "User-Agent")
                return request
            },
            messageHandler: { connector, message in
                guard let owner = ownerBox.value else { return }
                try await owner.handleMessage(message, connector: connector)
            },
            subscriptionHandler: { _, pairs, task in
                guard let owner = ownerBox.value else { return }
                try await owner.sendSubscription(for: pairs, using: task)
            },
            disconnectedHandler: { _, code, reason in
                guard let owner = ownerBox.value else { return }
                await owner.handleDisconnect(code: code, reason: reason)
            },
            statusHandler: { _, status in
                guard let owner = ownerBox.value else { return }
                await owner.handleStatusChange(status)
            }
        )

        ownerBox.value = owner
        return connector
    }

    public func disconnect() async {
        await baseConnector.disconnect()
    }

    public func subscribeToPairs(_ pairs: [String]) async throws {
        try await baseConnector.subscribeToPairs(pairs)
    }

    private func handleMessage(
        _ message: URLSessionWebSocketTask.Message,
        connector: BaseExchangeConnector
    ) async throws {
        let data: Data
        switch message {
        case .data(let payload):
            data = payload
        case .string(let string):
            guard let payload = string.data(using: .utf8) else {
                logger.warn(
                    component: component,
                    event: "invalid_payload_encoding",
                    data: ["reason": "Unable to encode string message as UTF-8"]
                )
                return
            }
            data = payload
        @unknown default:
            logger.warn(
                component: component,
                event: "unsupported_message_type"
            )
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warn(
                component: component,
                event: "json_parse_failed"
            )
            return
        }

        guard let type = json["type"] as? String else {
            logger.debug(
                component: component,
                event: "message_missing_type"
            )
            return
        }

        switch type {
        case "ticker":
            await handleTicker(json, connector: connector)
        case "subscriptions":
            logger.info(
                component: component,
                event: "subscriptions_ack",
                data: ["channels": describeChannels(json)]
            )
        case "heartbeat":
            await handleHeartbeat(json)
        case "error":
            logger.error(
                component: component,
                event: "coinbase_error",
                data: [
                    "message": (json["message"] as? String) ?? "unknown",
                    "reason": (json["reason"] as? String) ?? "n/a"
                ]
            )
        default:
            logger.debug(
                component: component,
                event: "message_ignored",
                data: ["type": type]
            )
        }
    }

    private func handleTicker(
        _ payload: [String: Any],
        connector: BaseExchangeConnector
    ) async {
        guard let quote = tickerQuote(from: payload) else { return }
        await connector.emitPriceUpdate(quote)
    }

    private func tickerQuote(from payload: [String: Any]) -> RawPriceData? {
        guard let productId = payload["product_id"] as? String else {
            logger.debug(
                component: component,
                event: "ticker_missing_product"
            )
            return nil
        }

        guard
            let bid = decimalValue(from: payload["best_bid"])
                ?? decimalValue(from: payload["bid"])
                ?? decimalValue(from: payload["price"]),
            let ask = decimalValue(from: payload["best_ask"])
                ?? decimalValue(from: payload["ask"])
                ?? decimalValue(from: payload["price"])
        else {
            logger.debug(
                component: component,
                event: "ticker_missing_prices",
                data: ["product_id": productId]
            )
            return nil
        }

        guard let timestamp = parseTimestamp(from: payload) else {
            logger.debug(
                component: component,
                event: "ticker_missing_time",
                data: ["product_id": productId]
            )
            return nil
        }

        return RawPriceData(
            exchange: name,
            symbol: productId,
            bid: bid,
            ask: ask,
            timestamp: timestamp
        )
    }

    private func handleHeartbeat(_ payload: [String: Any]) async {
        guard let timestamp = parseTimestamp(from: payload) else { return }
        await baseConnector.emitEvent(.receivedHeartbeat(timestamp))
    }

    private func sendSubscription(
        for pairs: Set<String>,
        using task: URLSessionWebSocketTask
    ) async throws {
        guard !pairs.isEmpty else {
            logger.warn(
                component: component,
                event: "subscription_empty_pairs"
            )
            return
        }

        var subscription: [String: Any] = [
            "type": "subscribe",
            "product_ids": pairs.sorted(),
            "channels": [
                [
                    "name": "ticker",
                    "product_ids": pairs.sorted()
                ]
            ]
        ]

        if let fields = try authenticator?.authenticationFields() {
            subscription.merge(fields) { _, new in new }
        }

        let data = try JSONSerialization.data(withJSONObject: subscription, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            logger.error(
                component: component,
                event: "subscription_encoding_failed"
            )
            return
        }

        try await task.send(.string(text))
        logger.info(
            component: component,
            event: "subscription_sent",
            data: ["pairs": pairs.sorted().joined(separator: ",")]
        )
    }

    private func handleDisconnect(
        code: URLSessionWebSocketTask.CloseCode?,
        reason: Data?
    ) async {
        var data: [String: String] = [:]
        if let code {
            data["code"] = "\(code.rawValue)"
        }
        if let reason, let text = String(data: reason, encoding: .utf8), !text.isEmpty {
            data["reason"] = text
        }

        if !data.isEmpty {
            logger.warn(
                component: component,
                event: "websocket_disconnected",
                data: data
            )
        }
    }

    private func handleStatusChange(_ status: ConnectionStatus) async {
        logger.debug(
            component: component,
            event: "status_updated",
            data: ["status": "\(status)"]
        )
    }

    private func parseTimestamp(from payload: [String: Any]) -> Date? {
        if let timeString = payload["time"] as? String {
            return iso8601.date(from: timeString)
        }

        if let millis = payload["timestamp"] as? Double {
            return Date(timeIntervalSince1970: millis)
        }

        if let millisString = payload["timestamp"] as? String, let value = Double(millisString) {
            return Date(timeIntervalSince1970: value)
        }

        return nil
    }

    private func decimalValue(from value: Any?) -> Decimal? {
        switch value {
        case let string as String:
            return Decimal(string: string)
        case let number as NSNumber:
            return Decimal(string: number.stringValue)
        default:
            return nil
        }
    }

    private func describeChannels(_ payload: [String: Any]) -> String {
        guard let channels = payload["channels"] as? [[String: Any]] else { return "[]" }
        let descriptors = channels.compactMap { channel -> String? in
            guard let name = channel["name"] as? String else { return nil }
            let products = (channel["product_ids"] as? [String])?.joined(separator: ",") ?? ""
            return products.isEmpty ? name : "\(name):\(products)"
        }
        return descriptors.joined(separator: "|")
    }
}

extension CoinbaseConnector {
    private struct Authenticator {
        private enum Method {
            case hmac(Data)
            case ecdsa(P256.Signing.PrivateKey)
        }

        private let method: Method
        private let credentials: Configuration.Credentials
        private let logger: StructuredLogger
        private let clock: @Sendable () -> Date

        init?(credentials: Configuration.Credentials, logger: StructuredLogger, clock: @escaping @Sendable () -> Date = Date.init) {
            self.credentials = credentials
            self.logger = logger
            self.clock = clock

            if let data = Data(base64Encoded: credentials.apiSecret) {
                self.method = .hmac(data)
                return
            }

            if credentials.apiSecret.contains("BEGIN EC PRIVATE KEY") {
                do {
                    let key = try P256.Signing.PrivateKey(pemRepresentation: credentials.apiSecret)
                    self.method = .ecdsa(key)
                    return
                } catch {
                    logger.warn(
                        component: "connector.coinbase.auth",
                        event: "invalid_pem_secret",
                        data: ["reason": error.localizedDescription]
                    )
                    return nil
                }
            }

            logger.warn(
                component: "connector.coinbase.auth",
                event: "unsupported_secret_format"
            )
            return nil
        }

        func authenticationFields() throws -> [String: Any] {
            let timestamp = String(format: "%.0f", clock().timeIntervalSince1970)
            let signingPayload = timestamp + "GET" + "/users/self/verify"
            let payloadData = Data(signingPayload.utf8)

            let signature: String
            switch method {
            case .hmac(let keyData):
                let key = SymmetricKey(data: keyData)
                let hmac = HMAC<SHA256>.authenticationCode(for: payloadData, using: key)
                signature = Data(hmac).base64EncodedString()
            case .ecdsa(let key):
                let signatureData = try key.signature(for: payloadData).derRepresentation
                signature = signatureData.base64EncodedString()
            }

            var fields: [String: Any] = [
                "signature": signature,
                "key": credentials.apiKey,
                "timestamp": timestamp
            ]

            if let passphrase = credentials.passphrase, !passphrase.isEmpty {
                fields["passphrase"] = passphrase
            }

            return fields
        }
    }
}

private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?

    init(_ value: T?) {
        self.value = value
    }
}
