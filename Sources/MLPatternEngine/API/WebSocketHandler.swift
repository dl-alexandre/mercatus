import Foundation
import Network
import Utils
import MLPatternEngine

public class WebSocketHandler: @unchecked Sendable {
    private let mlEngine: MLPatternEngine
    private let logger: StructuredLogger
    private let authManager: AuthManager
    private let rateLimiter: RateLimiter
    private var connections: [String: WebSocketConnection] = [:]
    private let maxConnections = 100
    private let lock = NSLock()
    private var heartbeatTask: Task<Void, Never>?
    private let heartbeatInterval: TimeInterval = 30.0

    public init(mlEngine: MLPatternEngine, logger: StructuredLogger, authManager: AuthManager, rateLimiter: RateLimiter) {
        self.mlEngine = mlEngine
        self.logger = logger
        self.authManager = authManager
        self.rateLimiter = rateLimiter
        startHeartbeat()
    }

    public func handleConnection(_ connection: WebSocketConnection) async {
        let connectionId = UUID().uuidString

        await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }

            guard connections.count < maxConnections else {
                continuation.resume(returning: ())
                return
            }
            connections[connectionId] = connection
            continuation.resume(returning: ())
        }

        if connections[connectionId] == nil {
            await connection.close(code: .policyViolation, reason: "Maximum connections exceeded")
            return
        }

        logger.info(component: "WebSocketHandler", event: "New WebSocket connection established", data: ["connectionId": connectionId])

        await handleMessages(for: connectionId, connection: connection)

        await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            connections.removeValue(forKey: connectionId)
            continuation.resume(returning: ())
        }

        logger.info(component: "WebSocketHandler", event: "WebSocket connection closed", data: ["connectionId": connectionId])
    }

    private func handleMessages(for connectionId: String, connection: WebSocketConnection) async {
        for await message in connection.messages {
            switch message {
            case .text(let text):
                await handleTextMessage(text, connectionId: connectionId, connection: connection)
            case .data(let data):
                await handleDataMessage(data, connectionId: connectionId, connection: connection)
            case .close:
                break
            case .ping:
                await connection.sendPong()
            case .pong:
                break
            }
        }
    }

    private func handleTextMessage(_ text: String, connectionId: String, connection: WebSocketConnection) async {
        do {
            let data = text.data(using: .utf8) ?? Data()
            let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)

            switch message.type {
            case "auth":
                await handleAuth(message, connectionId: connectionId, connection: connection)
            case "subscribe_predictions":
                await handleSubscribePredictions(message, connectionId: connectionId, connection: connection)
            case "subscribe_patterns":
                await handleSubscribePatterns(message, connectionId: connectionId, connection: connection)
            case "unsubscribe":
                await handleUnsubscribe(message, connectionId: connectionId, connection: connection)
            case "ping":
                await handlePing(connectionId: connectionId, connection: connection)
            default:
                await sendError("Unknown message type: \(message.type)", connectionId: connectionId, connection: connection)
            }
        } catch {
            logger.error(component: "WebSocketHandler", event: "Failed to parse WebSocket message: \(error)", data: ["connectionId": connectionId])
            await sendError("Invalid message format", connectionId: connectionId, connection: connection)
        }
    }

    private func handleDataMessage(_ data: Data, connectionId: String, connection: WebSocketConnection) async {
        // Handle binary data if needed
        logger.debug(component: "WebSocketHandler", event: "Received binary data", data: ["connectionId": connectionId, "size": "\(data.count)"])
    }

    private func handleAuth(_ message: WebSocketMessage, connectionId: String, connection: WebSocketConnection) async {
        guard let tokenValue = message.data["token"],
              let token = tokenValue.value as? String else {
            await sendError("Missing authentication token", connectionId: connectionId, connection: connection)
            return
        }

        if authManager.validateToken(token) {
            connection.authenticated = true
            await sendSuccess("Authentication successful", connectionId: connectionId, connection: connection)
        } else {
            await sendError("Invalid authentication token", connectionId: connectionId, connection: connection)
        }
    }

    private func handleSubscribePredictions(_ message: WebSocketMessage, connectionId: String, connection: WebSocketConnection) async {
        guard connection.authenticated else {
            await sendError("Authentication required", connectionId: connectionId, connection: connection)
            return
        }

        guard let symbolValue = message.data["symbol"],
              let symbol = symbolValue.value as? String else {
            await sendError("Missing symbol parameter", connectionId: connectionId, connection: connection)
            return
        }

        let timeHorizon = (message.data["timeHorizon"]?.value as? Double) ?? 300.0
        let modelType = (message.data["modelType"]?.value as? String) ?? "PRICE_PREDICTION"

        connection.subscriptions.insert(.predictions(symbol: symbol, timeHorizon: timeHorizon, modelType: modelType))

        await sendSuccess("Subscribed to predictions for \(symbol)", connectionId: connectionId, connection: connection)

        // Start streaming predictions
        await startPredictionStream(for: connectionId, connection: connection, symbol: symbol, timeHorizon: timeHorizon, modelType: modelType)
    }

    private func handleSubscribePatterns(_ message: WebSocketMessage, connectionId: String, connection: WebSocketConnection) async {
        guard connection.authenticated else {
            await sendError("Authentication required", connectionId: connectionId, connection: connection)
            return
        }

        guard let symbolValue = message.data["symbol"],
              let symbol = symbolValue.value as? String else {
            await sendError("Missing symbol parameter", connectionId: connectionId, connection: connection)
            return
        }

        connection.subscriptions.insert(.patterns(symbol: symbol))

        await sendSuccess("Subscribed to patterns for \(symbol)", connectionId: connectionId, connection: connection)

        // Start streaming patterns
        await startPatternStream(for: connectionId, connection: connection, symbol: symbol)
    }

    private func handleUnsubscribe(_ message: WebSocketMessage, connectionId: String, connection: WebSocketConnection) async {
        guard let typeValue = message.data["type"],
              let subscriptionType = typeValue.value as? String else {
            await sendError("Missing subscription type", connectionId: connectionId, connection: connection)
            return
        }

        if subscriptionType == "predictions" {
            connection.subscriptions = connection.subscriptions.filter { subscription in
                if case .predictions = subscription { return false }
                return true
            }
        } else if subscriptionType == "patterns" {
            connection.subscriptions = connection.subscriptions.filter { subscription in
                if case .patterns = subscription { return false }
                return true
            }
        }

        await sendSuccess("Unsubscribed from \(subscriptionType)", connectionId: connectionId, connection: connection)
    }

    private func handlePing(connectionId: String, connection: WebSocketConnection) async {
        await sendPong(connectionId: connectionId, connection: connection)
    }

    private func startPredictionStream(for connectionId: String, connection: WebSocketConnection, symbol: String, timeHorizon: TimeInterval, modelType: String) async {
        Task { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            while connection.subscriptions.contains(where: { subscription in
                if case .predictions(let subSymbol, _, _) = subscription {
                    return subSymbol == symbol
                }
                return false
            }) {
                do {
                    let modelTypeEnum = try parseModelType(modelType)
                    let prediction = try await mlEngine.getPrediction(
                        for: symbol,
                        timeHorizon: timeHorizon,
                        modelType: modelTypeEnum
                    )

                    let response = WebSocketResponse(
                        type: "prediction",
                        data: [
                            "symbol": AnyCodable(symbol),
                            "prediction": AnyCodable(prediction.prediction),
                            "confidence": AnyCodable(prediction.confidence),
                            "uncertainty": AnyCodable(prediction.uncertainty),
                            "modelVersion": AnyCodable(prediction.modelVersion),
                            "timestamp": AnyCodable(prediction.timestamp.timeIntervalSince1970)
                        ]
                    )

                    await sendResponse(response, connection: connection)

                    // Wait before next prediction
                    try await Task.sleep(nanoseconds: UInt64(timeHorizon * 1_000_000_000))
                } catch {
                    logger.error(component: "WebSocketHandler", event: "Prediction stream error: \(error)", data: ["connectionId": connectionId])
                    break
                }
            }
        }
    }

    private func startPatternStream(for connectionId: String, connection: WebSocketConnection, symbol: String) async {
        Task { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }

            while connection.subscriptions.contains(where: { subscription in
                if case .patterns(let subSymbol) = subscription {
                    return subSymbol == symbol
                }
                return false
            }) {
                do {
                    let patterns = try await mlEngine.detectPatterns(for: symbol)

                    let patternData = patterns.map { pattern in
                        [
                            "patternId": AnyCodable(pattern.patternId),
                            "patternType": AnyCodable(pattern.patternType.rawValue),
                            "symbol": AnyCodable(pattern.symbol),
                            "startTime": AnyCodable(pattern.startTime.timeIntervalSince1970),
                            "endTime": AnyCodable(pattern.endTime.timeIntervalSince1970),
                            "confidence": AnyCodable(pattern.confidence),
                            "completionScore": AnyCodable(pattern.completionScore),
                            "priceTarget": AnyCodable(pattern.priceTarget ?? 0),
                            "stopLoss": AnyCodable(pattern.stopLoss ?? 0)
                        ]
                    }

                    let response = WebSocketResponse(
                        type: "patterns",
                        data: [
                            "symbol": AnyCodable(symbol),
                            "patterns": AnyCodable(patternData),
                            "timestamp": AnyCodable(Date().timeIntervalSince1970)
                        ]
                    )

                    await sendResponse(response, connection: connection)

                    // Wait before next pattern detection
                    try await Task.sleep(nanoseconds: 60_000_000_000) // 1 minute
                } catch {
                    logger.error(component: "WebSocketHandler", event: "Pattern stream error: \(error)", data: ["connectionId": connectionId])
                    break
                }
            }
        }
    }

    private func parseModelType(_ modelTypeString: String) throws -> ModelInfo.ModelType {
        guard let modelType = ModelInfo.ModelType(rawValue: modelTypeString.uppercased()) else {
            throw APIError.invalidModelType(modelTypeString)
        }
        return modelType
    }

    private func sendResponse(_ response: WebSocketResponse, connection: WebSocketConnection) async {
        do {
            let data = try JSONEncoder().encode(response)
            let text = String(data: data, encoding: .utf8) ?? ""
            await connection.sendText(text)
        } catch {
            logger.error(component: "WebSocketHandler", event: "Failed to send response: \(error)")
        }
    }

    private func sendSuccess(_ message: String, connectionId: String, connection: WebSocketConnection) async {
        let response = WebSocketResponse(type: "success", data: ["message": AnyCodable(message)])
        await sendResponse(response, connection: connection)
    }

    private func sendError(_ message: String, connectionId: String, connection: WebSocketConnection) async {
        let response = WebSocketResponse(type: "error", data: ["message": AnyCodable(message)])
        await sendResponse(response, connection: connection)
    }

    private func sendPong(connectionId: String, connection: WebSocketConnection) async {
        let response = WebSocketResponse(type: "pong", data: ["timestamp": AnyCodable(Date().timeIntervalSince1970)])
        await sendResponse(response, connection: connection)
    }

    private func startHeartbeat() {
        heartbeatTask = Task { @Sendable in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
                await sendHeartbeatToAllConnections()
            }
        }
    }

    private func sendHeartbeatToAllConnections() async {
        let connectionsCopy = await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            continuation.resume(returning: connections)
        }

        for (_, connection) in connectionsCopy {
            let heartbeat = WebSocketResponse(
                type: "heartbeat",
                data: [
                    "timestamp": AnyCodable(Date().timeIntervalSince1970),
                    "server_time": AnyCodable(Date().timeIntervalSince1970)
                ]
            )
            await sendResponse(heartbeat, connection: connection)
        }
    }

    public func broadcastToSubscribers(subscription: Subscription, data: [String: AnyCodable]) async {
        let connectionsCopy = await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            continuation.resume(returning: connections)
        }

        for (_, connection) in connectionsCopy {
            if connection.subscriptions.contains(subscription) {
                let message = WebSocketResponse(type: "subscription_update", data: data)
                await sendResponse(message, connection: connection)
            }
        }
    }

    public func getConnectionStats() -> WebSocketStats {
        lock.lock()
        defer { lock.unlock() }

        var totalSubscriptions = 0
        var authenticatedConnections = 0

        for connection in connections.values {
            totalSubscriptions += connection.subscriptions.count
            if connection.authenticated {
                authenticatedConnections += 1
            }
        }

        return WebSocketStats(
            totalConnections: connections.count,
            authenticatedConnections: authenticatedConnections,
            totalSubscriptions: totalSubscriptions,
            maxConnections: maxConnections,
            timestamp: Date()
        )
    }

    public func shutdown() async {
        heartbeatTask?.cancel()

        let connectionsCopy = await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            continuation.resume(returning: connections)
        }

        for (_, connection) in connectionsCopy {
            await connection.close(code: .normal, reason: "Server shutdown")
        }

        await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            connections.removeAll()
            continuation.resume(returning: ())
        }
    }
}

// MARK: - WebSocket Models

public struct WebSocketMessage: Codable {
    public let type: String
    public let data: [String: AnyCodable]

    public init(type: String, data: [String: AnyCodable]) {
        self.type = type
        self.data = data
    }
}

public struct WebSocketResponse: Codable {
    public let type: String
    public let data: [String: AnyCodable]

    public init(type: String, data: [String: AnyCodable]) {
        self.type = type
        self.data = data
    }
}

public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else {
            throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

// MARK: - WebSocket Connection

public class WebSocketConnection: @unchecked Sendable {
    public var authenticated = false
    public var subscriptions: Set<Subscription> = []

    public init() {}

    public func sendText(_ text: String) async {
        // Implementation would depend on the WebSocket library used
    }

    public func sendPong() async {
        // Implementation would depend on the WebSocket library used
    }

    public func close(code: WebSocketCloseCode, reason: String) async {
        // Implementation would depend on the WebSocket library used
    }

    public var messages: AsyncStream<WebSocketMessageType> {
        AsyncStream { continuation in
            // Implementation would depend on the WebSocket library used
            continuation.finish()
        }
    }
}

public enum Subscription: Hashable {
    case predictions(symbol: String, timeHorizon: TimeInterval, modelType: String)
    case patterns(symbol: String)
}

public enum WebSocketMessageType {
    case text(String)
    case data(Data)
    case close
    case ping
    case pong
}

public enum WebSocketCloseCode {
    case normal
    case policyViolation
    case internalError
}

public struct WebSocketStats {
    public let totalConnections: Int
    public let authenticatedConnections: Int
    public let totalSubscriptions: Int
    public let maxConnections: Int
    public let timestamp: Date

    public init(totalConnections: Int, authenticatedConnections: Int, totalSubscriptions: Int, maxConnections: Int, timestamp: Date) {
        self.totalConnections = totalConnections
        self.authenticatedConnections = authenticatedConnections
        self.totalSubscriptions = totalSubscriptions
        self.maxConnections = maxConnections
        self.timestamp = timestamp
    }
}
