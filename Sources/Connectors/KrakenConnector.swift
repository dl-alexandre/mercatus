import Foundation
import Utils
import Core

/// WebSocket connector for Kraken best bid/offer (ticker) updates.
public final class KrakenConnector: ExchangeConnector, @unchecked Sendable {
    public struct RateLimitConfiguration: Sendable, Equatable {
        public let maxMessages: Int
        public let interval: TimeInterval

        public init(maxMessages: Int = 15, interval: TimeInterval = 10) {
            precondition(maxMessages > 0, "maxMessages must be greater than zero")
            precondition(interval > 0, "interval must be greater than zero")
            self.maxMessages = maxMessages
            self.interval = interval
        }

        public static let `default` = RateLimitConfiguration()
    }

    private enum KrakenConnectorError: Error, LocalizedError {
        case unableToEncodeSubscription
        case binaryPayloadNotUTF8

        var errorDescription: String? {
            switch self {
            case .unableToEncodeSubscription:
                return "Unable to encode Kraken subscription payload."
            case .binaryPayloadNotUTF8:
                return "Received binary payload that could not be decoded as UTF-8."
            }
        }
    }

    private final actor State {
        private let configuration: RateLimitConfiguration
        private var symbolToKraken: [String: String] = [:]
        private var krakenToSymbol: [String: String] = [:]
        private var sendTimestamps: [Date] = []

        init(configuration: RateLimitConfiguration) {
            self.configuration = configuration
        }

        func updateMappings(for symbols: [String]) -> [String] {
            var invalid: [String] = []

            for symbol in symbols {
                guard let krakenPair = KrakenConnector.krakenPair(for: symbol) else {
                    invalid.append(symbol)
                    continue
                }

                symbolToKraken[symbol] = krakenPair
                krakenToSymbol[krakenPair] = symbol
            }

            return invalid
        }

        func krakenPairs(for originals: Set<String>) -> [String] {
            originals.compactMap { symbolToKraken[$0] }
        }

        func originalSymbol(for krakenPair: String) -> String? {
            krakenToSymbol[krakenPair]
        }

        func registerSend(at date: Date) -> TimeInterval {
            pruneStaleEntries(currentDate: date)

            if sendTimestamps.count < configuration.maxMessages {
                sendTimestamps.append(date)
                return 0
            }

            guard let earliest = sendTimestamps.first else {
                sendTimestamps.append(date)
                return 0
            }

            return max(0, configuration.interval - date.timeIntervalSince(earliest))
        }

        private func pruneStaleEntries(currentDate: Date) {
            let cutoff = currentDate.addingTimeInterval(-configuration.interval)
            sendTimestamps.removeAll { $0 < cutoff }
        }
    }

    public let name = "Kraken"
    private let component = "connector.kraken"
    private let logger: StructuredLogger
    private let state: State
    private let session: URLSession
    private let backoffConfiguration: BaseExchangeConnector.BackoffConfiguration

    private lazy var baseConnector: BaseExchangeConnector = {
        BaseExchangeConnector(
            name: "Kraken",
            logger: logger,
            session: session,
            backoffConfiguration: backoffConfiguration,
            requestBuilder: { _ in
                var request = URLRequest(url: URL(string: "wss://ws.kraken.com/")!)
                request.timeoutInterval = 30
                return request
            },
            messageHandler: { [weak self] connector, message in
                guard let self else { return }
                try await self.handleIncoming(message: message, connector: connector)
            },
            subscriptionHandler: { [weak self] _, pairs, task in
                guard let self else { return }
                try await self.handleSubscription(pairs: pairs, task: task)
            },
            connectedHandler: { [weak self] _, _ in
                guard let self else { return }
                self.logger.info(
                    component: self.component,
                    event: "websocket_connected"
                )
            },
            disconnectedHandler: { [weak self] _, code, reason in
                guard let self else { return }
                var data: [String: String] = ["code": "\(code?.rawValue ?? URLSessionWebSocketTask.CloseCode.invalid.rawValue)"]
                if let reason, let message = String(data: reason, encoding: .utf8), !message.isEmpty {
                    data["reason"] = message
                }
                self.logger.warn(
                    component: self.component,
                    event: "websocket_disconnected",
                    data: data
                )
            }
        )
    }()

    public var priceUpdates: AsyncStream<RawPriceData> { baseConnector.priceUpdates }
    public var connectionEvents: AsyncStream<ConnectionEvent> { baseConnector.connectionEvents }

    public init(
        logger: StructuredLogger,
        session: URLSession = URLSession(configuration: .default),
        backoffConfiguration: BaseExchangeConnector.BackoffConfiguration = .default,
        rateLimitConfiguration: RateLimitConfiguration = .default
    ) {
        self.logger = logger
        self.state = State(configuration: rateLimitConfiguration)
        self.session = session
        self.backoffConfiguration = backoffConfiguration
    }

    public var connectionStatus: ConnectionStatus {
        get async {
            await baseConnector.connectionStatus
        }
    }

    public func connect() async throws {
        try await baseConnector.connect()
    }

    public func disconnect() async {
        await baseConnector.disconnect()
    }

    public func subscribeToPairs(_ pairs: [String]) async throws {
        let sanitized = pairs.map(Self.normalizeSymbol)
        let invalid = await state.updateMappings(for: sanitized)

        if !invalid.isEmpty {
            logger.warn(
                component: component,
                event: "invalid_pairs_filtered",
                data: ["pairs": invalid.joined(separator: ",")]
            )
        }

        try await baseConnector.subscribeToPairs(sanitized)
    }

    private func handleSubscription(
        pairs: Set<String>,
        task: URLSessionWebSocketTask
    ) async throws {
        let krakenPairs = await state.krakenPairs(for: pairs)

        guard !krakenPairs.isEmpty else {
            logger.warn(
                component: component,
                event: "subscription_skipped",
                data: ["reason": "no_valid_pairs"]
            )
            return
        }

        try await enforceRateLimit()

        let payload: [String: Any] = [
            "event": "subscribe",
            "pair": krakenPairs,
            "subscription": [
                "name": "ticker"
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let text = String(data: data, encoding: .utf8) else {
            throw KrakenConnectorError.unableToEncodeSubscription
        }

        try await task.send(.string(text))

        logger.info(
            component: component,
            event: "subscription_sent",
            data: ["pairs": krakenPairs.joined(separator: ",")]
        )
    }

    private func enforceRateLimit() async throws {
        while true {
            let now = Date()
            let delay = await state.registerSend(at: now)
            if delay == 0 {
                return
            }

            logger.warn(
                component: component,
                event: "outbound_rate_limited",
                data: [
                    "delay": String(format: "%.3f", delay)
                ]
            )

            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func handleIncoming(
        message: URLSessionWebSocketTask.Message,
        connector: BaseExchangeConnector
    ) async throws {
        switch message {
        case .string(let text):
            try await parseMessage(text, connector: connector)
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                logger.error(
                    component: component,
                    event: "payload_decode_failed",
                    data: ["reason": KrakenConnectorError.binaryPayloadNotUTF8.localizedDescription]
                )
                return
            }
            try await parseMessage(text, connector: connector)
        @unknown default:
            logger.warn(
                component: component,
                event: "payload_unhandled_type"
            )
        }
    }

    private func parseMessage(
        _ text: String,
        connector: BaseExchangeConnector
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("{") {
            try await handleEventPayload(trimmed, connector: connector)
        } else if trimmed.hasPrefix("[") {
            try await handleDataPayload(trimmed, connector: connector)
        } else {
            logger.debug(
                component: component,
                event: "payload_unrecognized",
                data: ["payload": trimmed]
            )
        }
    }

    private func handleEventPayload(
        _ text: String,
        connector: BaseExchangeConnector
    ) async throws {
        guard
            let data = text.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            let event = json["event"] as? String
        else {
            logger.warn(
                component: component,
                event: "event_payload_malformed"
            )
            return
        }

        switch event {
        case "heartbeat":
            await connector.emitEvent(.receivedHeartbeat(Date()))
        case "subscriptionStatus":
            handleSubscriptionStatus(json)
        case "systemStatus":
            handleSystemStatus(json)
        case "error":
            let message = (json["errorMessage"] as? String) ?? "unknown"
            logger.error(
                component: component,
                event: "kraken_error_event",
                data: ["reason": message]
            )
        default:
            logger.debug(
                component: component,
                event: "event_ignored",
                data: ["type": event]
            )
        }
    }

    private func handleSubscriptionStatus(_ payload: [String: Any]) {
        let status = (payload["status"] as? String) ?? "unknown"
        let pair = (payload["pair"] as? String) ?? "unknown"

        var data: [String: String] = [
            "status": status,
            "pair": pair
        ]

        if let message = payload["errorMessage"] as? String {
            data["reason"] = message
        }

        if status == "subscribed" {
            logger.info(
                component: component,
                event: "subscription_acknowledged",
                data: data
            )
        } else {
            logger.warn(
                component: component,
                event: "subscription_status",
                data: data
            )
        }
    }

    private func handleSystemStatus(_ payload: [String: Any]) {
        var data: [String: String] = [:]

        if let status = payload["status"] as? String {
            data["status"] = status
        }

        if let version = payload["version"] as? String {
            data["version"] = version
        }

        logger.info(
            component: component,
            event: "system_status",
            data: data
        )
    }

    private func handleDataPayload(
        _ text: String,
        connector: BaseExchangeConnector
    ) async throws {
        guard
            let data = text.data(using: .utf8),
            let array = try JSONSerialization.jsonObject(with: data, options: []) as? [Any]
        else {
            logger.warn(
                component: component,
                event: "data_payload_malformed"
            )
            return
        }

        if array.count >= 2, let heartbeat = array[1] as? String, heartbeat == "heartbeat" {
            await connector.emitEvent(.receivedHeartbeat(Date()))
            return
        }

        guard
            array.count >= 4,
            let values = array[1] as? [String: Any],
            let channel = array[2] as? String,
            channel == "ticker",
            let pair = array[3] as? String
        else {
            logger.debug(
                component: component,
                event: "data_payload_ignored",
                data: ["payload": text]
            )
            return
        }

        guard
            let askArray = values["a"] as? [Any],
            let bidArray = values["b"] as? [Any],
            let askPriceString = askArray.first as? String,
            let bidPriceString = bidArray.first as? String,
            let askPrice = Decimal(string: askPriceString),
            let bidPrice = Decimal(string: bidPriceString)
        else {
            logger.warn(
                component: component,
                event: "quote_parse_failed",
                data: ["payload": text]
            )
            return
        }

        guard askPrice >= bidPrice else {
            logger.debug(
                component: component,
                event: "quote_filtered",
                data: ["reason": "ask_lt_bid", "pair": pair]
            )
            return
        }

        let symbol = await state.originalSymbol(for: pair) ?? pair.replacingOccurrences(of: "/", with: "-")

        let raw = RawPriceData(
            exchange: name,
            symbol: symbol,
            bid: bidPrice,
            ask: askPrice,
            timestamp: Date()
        )

        await connector.emitPriceUpdate(raw)

        var logData: [String: String] = [
            "symbol": symbol,
            "pair": pair,
            "bid": "\(bidPrice)",
            "ask": "\(askPrice)"
        ]

        if let askVolume = askArray.dropFirst().first as? String {
            logData["ask_volume"] = askVolume
        }

        if let bidVolume = bidArray.dropFirst().first as? String {
            logData["bid_volume"] = bidVolume
        }

        logger.debug(
            component: component,
            event: "quote_received",
            data: logData
        )
    }

    private static func normalizeSymbol(_ symbol: String) -> String {
        symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private static func krakenPair(for symbol: String) -> String? {
        let sanitized = symbol.replacingOccurrences(of: " ", with: "")
        let components = sanitized.split(whereSeparator: { $0 == "-" || $0 == "/" })
        guard components.count == 2 else { return nil }

        let base = mapAsset(String(components[0]))
        let quote = mapAsset(String(components[1]))

        guard !base.isEmpty, !quote.isEmpty else { return nil }
        return "\(base)/\(quote)"
    }

    private static func mapAsset(_ asset: String) -> String {
        let normalized = asset.uppercased()
        switch normalized {
        case "BTC": return "XBT"
        case "DOGE": return "XDG"
        case "USDT": return "USDT"
        case "USDC": return "USDC"
        default:
            return normalized
        }
    }
}
