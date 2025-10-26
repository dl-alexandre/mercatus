import Foundation
import CryptoKit
import Utils
import Core

public final class GeminiConnector: ExchangeConnector, @unchecked Sendable {
    public struct Configuration: Sendable {
        public enum Environment: Sendable {
            case production
            case sandbox
            case custom(URL)

            fileprivate var baseUrl: URL {
                switch self {
                case .production:
                    return URL(string: "wss://api.gemini.com/v1/marketdata/")!
                case .sandbox:
                    return URL(string: "wss://api.sandbox.gemini.com/v1/marketdata/")!
                case .custom(let value):
                    return value
                }
            }
        }

        public struct Credentials: Sendable {
            public let apiKey: String
            public let apiSecret: String

            public init(apiKey: String, apiSecret: String) {
                self.apiKey = apiKey
                self.apiSecret = apiSecret
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

    public let name: String = "Gemini"
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
    private let component = "connector.gemini"

    private struct PriceState {
        var bid: Decimal?
        var ask: Decimal?
        var timestamp: Date
    }

    private final actor State {
        var currentSymbols: Set<String> = []
        var currentTask: URLSessionWebSocketTask?
        var priceStates: [String: PriceState] = [:]

        func setSymbols(_ symbols: Set<String>) {
            currentSymbols = symbols
        }

        func setTask(_ task: URLSessionWebSocketTask?) {
            currentTask = task
        }

        func getSymbols() -> Set<String> {
            currentSymbols
        }

        func updatePrice(symbol: String, bid: Decimal?, ask: Decimal?, timestamp: Date) -> (bid: Decimal, ask: Decimal)? {
            var state = priceStates[symbol] ?? PriceState(timestamp: timestamp)

            if let bid = bid {
                state.bid = bid
            }
            if let ask = ask {
                state.ask = ask
            }
            state.timestamp = timestamp

            priceStates[symbol] = state

            if let finalBid = state.bid, let finalAsk = state.ask {
                return (bid: finalBid, ask: finalAsk)
            }
            return nil
        }
    }

    private let state = State()

    public init(
        logger: StructuredLogger,
        configuration: Configuration = Configuration(),
        session: URLSession = URLSession(configuration: .default)
    ) {
        self.session = session
        self.logger = logger
        self.configuration = configuration

        _ = baseConnector
    }

    public func connect() async throws {
        try await baseConnector.connect()
    }

    private static func makeBaseConnector(
        owner: GeminiConnector,
        logger: StructuredLogger,
        session: URLSession,
        configuration: Configuration
    ) -> BaseExchangeConnector {
        let ownerBox = WeakBox(owner)

        let connector = BaseExchangeConnector(
            name: "Gemini",
            logger: logger,
            session: session,
            requestBuilder: { _ in
                guard ownerBox.value != nil else {
                    throw ArbitrageError.logic(.invalidState(
                        component: "Gemini",
                        expected: "owner present",
                        actual: "owner deallocated"
                    ))
                }
                var request = URLRequest(url: configuration.environment.baseUrl)
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
        await state.setSymbols(Set(pairs))
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

        if let type = json["type"] as? String {
            switch type {
            case "update":
                await handleUpdate(json, connector: connector)
            case "heartbeat":
                logger.debug(
                    component: component,
                    event: "heartbeat_received"
                )
            case "subscription_ack":
                if let subscriptionId = json["subscriptionId"] as? Int {
                    logger.info(
                        component: component,
                        event: "subscription_acknowledged",
                        data: ["subscription_id": "\(subscriptionId)"]
                    )
                }
            default:
                logger.debug(
                    component: component,
                    event: "message_ignored",
                    data: ["type": type]
                )
            }
        } else {
            logger.debug(
                component: component,
                event: "message_unknown_format"
            )
        }
    }

    private func handleUpdate(
        _ payload: [String: Any],
        connector: BaseExchangeConnector
    ) async {
        guard let events = payload["events"] as? [[String: Any]] else {
            logger.debug(
                component: component,
                event: "update_missing_events"
            )
            return
        }

        guard let symbol = payload["symbol"] as? String else {
            logger.debug(
                component: component,
                event: "update_missing_symbol"
            )
            return
        }

        let normalizedSymbol = normalizeGeminiSymbol(symbol)

        for event in events {
            if let type = event["type"] as? String, type == "change" {
                guard let side = event["side"] as? String else {
                    continue
                }

                guard side == "bid" || side == "ask" else {
                    continue
                }

                guard let price = decimalValue(from: event["price"]) else {
                    logger.debug(
                        component: component,
                        event: "update_missing_price",
                        data: ["symbol": symbol, "side": side]
                    )
                    continue
                }

                let bid = side == "bid" ? price : nil
                let ask = side == "ask" ? price : nil
                let timestamp = Date()

                if let prices = await state.updatePrice(symbol: normalizedSymbol, bid: bid, ask: ask, timestamp: timestamp) {
                    let quote = RawPriceData(
                        exchange: name,
                        symbol: normalizedSymbol,
                        bid: prices.bid,
                        ask: prices.ask,
                        timestamp: timestamp
                    )
                    await connector.emitPriceUpdate(quote)
                }
            }
        }
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

        await state.setTask(task)

        for pair in pairs {
            let geminiSymbol = pair.replacingOccurrences(of: "-", with: "").lowercased()

            let urlString = configuration.environment.baseUrl.absoluteString + geminiSymbol
            guard let url = URL(string: urlString) else {
                logger.error(
                    component: component,
                    event: "invalid_subscription_url",
                    data: ["pair": pair]
                )
                continue
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = configuration.requestTimeout
            request.addValue("ArbitrageEngine/1.0", forHTTPHeaderField: "User-Agent")

            let newTask = session.webSocketTask(with: request)
            await state.setTask(newTask)
            newTask.resume()

            logger.info(
                component: component,
                event: "subscription_created",
                data: ["pair": pair, "symbol": geminiSymbol]
            )

            Task { [weak self] in
                guard let self else { return }
                await self.receiveMessages(from: newTask, connector: baseConnector)
            }
        }

        logger.info(
            component: component,
            event: "subscriptions_sent",
            data: ["pairs": pairs.sorted().joined(separator: ",")]
        )
    }

    private func receiveMessages(from task: URLSessionWebSocketTask, connector: BaseExchangeConnector) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                try await handleMessage(message, connector: connector)
            } catch {
                if Task.isCancelled { return }
                logger.warn(
                    component: component,
                    event: "websocket_receive_error",
                    data: ["error": error.localizedDescription]
                )
                return
            }
        }
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

    private func normalizeGeminiSymbol(_ symbol: String) -> String {
        let upper = symbol.uppercased()

        let commonPairs = [
            ("USD", "-USD"),
            ("USDT", "-USDT"),
            ("BTC", "-BTC"),
            ("ETH", "-ETH"),
            ("DAI", "-DAI"),
            ("GUSD", "-GUSD")
        ]

        for (suffix, replacement) in commonPairs {
            if upper.hasSuffix(suffix) {
                let base = String(upper.dropLast(suffix.count))
                return base + replacement
            }
        }

        return upper
    }

    // MARK: - Trading Methods (Default implementations)

    public func getOrderBook(symbol: String) async throws -> OrderBook {
        // Default implementation - override in subclasses
        throw ArbitrageError.logic(.internalError(component: "GeminiConnector", reason: "getOrderBook not implemented for \(name)"))
    }

    public func getRecentTransactions(limit: Int) async throws -> [Transaction] {
        // Default implementation - override in subclasses
        throw ArbitrageError.logic(.internalError(component: "GeminiConnector", reason: "getRecentTransactions not implemented for \(name)"))
    }

    public func placeOrder(symbol: String, side: OrderSide, type: OrderType, quantity: Double, price: Double) async throws -> Order {
        // Default implementation - override in subclasses
        throw ArbitrageError.logic(.internalError(component: "GeminiConnector", reason: "placeOrder not implemented for \(name)"))
    }
}

private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?

    init(_ value: T?) {
        self.value = value
    }
}
