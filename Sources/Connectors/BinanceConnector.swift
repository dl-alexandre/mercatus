import Foundation
import CryptoKit
import Utils
import Core

public final class BinanceConnector: ExchangeConnector, @unchecked Sendable {
    public struct Configuration: Sendable {
        public enum Environment: Sendable {
            case production
            case testnet
            case custom(URL)

            fileprivate var url: URL {
                switch self {
                case .production:
                    return URL(string: "wss://stream.binance.com:9443/ws")!
                case .testnet:
                    return URL(string: "wss://testnet.binance.vision/ws")!
                case .custom(let value):
                    return value
                }
            }
        }

        public let environment: Environment
        public let requestTimeout: TimeInterval

        public init(
            environment: Environment = .production,
            requestTimeout: TimeInterval = 30
        ) {
            self.environment = environment
            self.requestTimeout = max(5, requestTimeout)
        }
    }

    public let name: String = "Binance"
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
    private let component = "connector.binance"

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
        owner: BinanceConnector,
        logger: StructuredLogger,
        session: URLSession,
        configuration: Configuration
    ) -> BaseExchangeConnector {
        let ownerBox = WeakBox(owner)

        let connector = BaseExchangeConnector(
            name: "Binance",
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

        if let eventType = json["e"] as? String {
            switch eventType {
            case "bookTicker":
                await handleBookTicker(json, connector: connector)
            case "24hrTicker":
                await handle24hrTicker(json, connector: connector)
            default:
                logger.debug(
                    component: component,
                    event: "message_ignored",
                    data: ["event_type": eventType]
                )
            }
        } else if let result = json["result"] as? [String: Any] {
            logger.info(
                component: component,
                event: "subscription_result",
                data: ["status": result.isEmpty ? "success" : "pending"]
            )
        } else if let id = json["id"] as? Int {
            logger.debug(
                component: component,
                event: "subscription_ack",
                data: ["id": "\(id)"]
            )
        } else {
            logger.debug(
                component: component,
                event: "message_unknown_format"
            )
        }
    }

    private func handleBookTicker(
        _ payload: [String: Any],
        connector: BaseExchangeConnector
    ) async {
        guard let quote = bookTickerQuote(from: payload) else { return }
        await connector.emitPriceUpdate(quote)
    }

    private func handle24hrTicker(
        _ payload: [String: Any],
        connector: BaseExchangeConnector
    ) async {
        guard let quote = ticker24hrQuote(from: payload) else { return }
        await connector.emitPriceUpdate(quote)
    }

    private func bookTickerQuote(from payload: [String: Any]) -> RawPriceData? {
        guard let symbol = payload["s"] as? String else {
            logger.debug(
                component: component,
                event: "ticker_missing_symbol"
            )
            return nil
        }

        guard
            let bidPrice = decimalValue(from: payload["b"]),
            let askPrice = decimalValue(from: payload["a"])
        else {
            logger.debug(
                component: component,
                event: "ticker_missing_prices",
                data: ["symbol": symbol]
            )
            return nil
        }

        return RawPriceData(
            exchange: name,
            symbol: normalizeBinanceSymbol(symbol),
            bid: bidPrice,
            ask: askPrice,
            timestamp: Date()
        )
    }

    private func ticker24hrQuote(from payload: [String: Any]) -> RawPriceData? {
        guard let symbol = payload["s"] as? String else {
            logger.debug(
                component: component,
                event: "ticker_missing_symbol"
            )
            return nil
        }

        guard
            let bidPrice = decimalValue(from: payload["b"]),
            let askPrice = decimalValue(from: payload["a"])
        else {
            logger.debug(
                component: component,
                event: "ticker_missing_prices",
                data: ["symbol": symbol]
            )
            return nil
        }

        return RawPriceData(
            exchange: name,
            symbol: normalizeBinanceSymbol(symbol),
            bid: bidPrice,
            ask: askPrice,
            timestamp: Date()
        )
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

        let streams = pairs.map { pair in
            let binanceSymbol = pair.replacingOccurrences(of: "-", with: "").lowercased()
            return "\(binanceSymbol)@bookTicker"
        }

        let subscription: [String: Any] = [
            "method": "SUBSCRIBE",
            "params": streams,
            "id": Int.random(in: 1...999999)
        ]

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

    private func normalizeBinanceSymbol(_ symbol: String) -> String {
        let commonPairs = [
            ("USDT", "-USDT"),
            ("USDC", "-USDC"),
            ("BTC", "-BTC"),
            ("ETH", "-ETH"),
            ("BNB", "-BNB")
        ]

        for (suffix, replacement) in commonPairs {
            if symbol.hasSuffix(suffix) {
                let base = String(symbol.dropLast(suffix.count))
                return base + replacement
            }
        }

        return symbol
    }

    // MARK: - Trading Methods (Default implementations)

    public func getOrderBook(symbol: String) async throws -> OrderBook {
        // Default implementation - override in subclasses
        throw ArbitrageError.logic(.internalError(component: "BinanceConnector", reason: "getOrderBook not implemented for \(name)"))
    }

    public func getRecentTransactions(limit: Int) async throws -> [Transaction] {
        // Default implementation - override in subclasses
        throw ArbitrageError.logic(.internalError(component: "BinanceConnector", reason: "getRecentTransactions not implemented for \(name)"))
    }

    public func placeOrder(symbol: String, side: OrderSide, type: OrderType, quantity: Double, price: Double) async throws -> Order {
        // Default implementation - override in subclasses
        throw ArbitrageError.logic(.internalError(component: "BinanceConnector", reason: "placeOrder not implemented for \(name)"))
    }
}

private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?

    init(_ value: T?) {
        self.value = value
    }
}
