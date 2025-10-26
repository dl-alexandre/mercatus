import Foundation
import Utils
import Core

/// Base implementation that manages the WebSocket lifecycle and emits connector events.
public actor BaseExchangeConnector: ExchangeConnector {
    public struct BackoffConfiguration: Sendable {
        public let initial: TimeInterval
        public let multiplier: Double
        public let maxDelay: TimeInterval

        public init(initial: TimeInterval = 1.0, multiplier: Double = 2.0, maxDelay: TimeInterval = 30.0) {
            self.initial = max(0.1, initial)
            self.multiplier = max(1.0, multiplier)
            self.maxDelay = max(self.initial, maxDelay)
        }

        public static let `default` = BackoffConfiguration()
    }

    private struct BackoffState {
        private let configuration: BackoffConfiguration
        private var currentDelay: TimeInterval

        init(configuration: BackoffConfiguration) {
            self.configuration = configuration
            self.currentDelay = configuration.initial
        }

        mutating func reset() {
            currentDelay = configuration.initial
        }

        mutating func nextDelay() -> TimeInterval {
            let delay = currentDelay
            currentDelay = min(configuration.maxDelay, currentDelay * configuration.multiplier)
            return delay
        }
    }

    public typealias RequestBuilder = @Sendable (BaseExchangeConnector) throws -> URLRequest
    public typealias MessageHandler = @Sendable (BaseExchangeConnector, URLSessionWebSocketTask.Message) async throws -> Void
    public typealias SubscriptionHandler = @Sendable (BaseExchangeConnector, Set<String>, URLSessionWebSocketTask) async throws -> Void
    public typealias ConnectedHandler = @Sendable (BaseExchangeConnector, URLSessionWebSocketTask) async throws -> Void
    public typealias DisconnectedHandler = @Sendable (BaseExchangeConnector, URLSessionWebSocketTask.CloseCode?, Data?) async -> Void
    public typealias StatusHandler = @Sendable (BaseExchangeConnector, ConnectionStatus) async -> Void

    public nonisolated let name: String
    public let logger: StructuredLogger

    private let component: String
    private let session: URLSession
    private let requestBuilder: RequestBuilder
    private let messageHandler: MessageHandler
    private let subscriptionHandler: SubscriptionHandler?
    private let connectedHandler: ConnectedHandler?
    private let disconnectedHandler: DisconnectedHandler?
    private let statusHandler: StatusHandler?

    private var status: ConnectionStatus = .disconnected
    private var manualDisconnectRequested: Bool = false
    private var subscriptions: Set<String> = []

    private var priceContinuation: AsyncStream<RawPriceData>.Continuation
    private let priceStreamStorage: AsyncStream<RawPriceData>

    private var eventContinuation: AsyncStream<ConnectionEvent>.Continuation
    private let eventStreamStorage: AsyncStream<ConnectionEvent>

    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?

    private var backoffState: BackoffState
    private let circuitBreaker: CircuitBreaker

    public nonisolated var priceUpdates: AsyncStream<RawPriceData> { priceStreamStorage }
    public nonisolated var connectionEvents: AsyncStream<ConnectionEvent> { eventStreamStorage }

    public init(
        name: String,
        logger: StructuredLogger,
        session: URLSession = URLSession(configuration: .default),
        backoffConfiguration: BackoffConfiguration = .default,
        circuitBreakerConfiguration: CircuitBreaker.Configuration = .default,
        requestBuilder: @escaping RequestBuilder,
        messageHandler: @escaping MessageHandler = { _, _ in },
        subscriptionHandler: SubscriptionHandler? = nil,
        connectedHandler: ConnectedHandler? = nil,
        disconnectedHandler: DisconnectedHandler? = nil,
        statusHandler: StatusHandler? = nil
    ) {
        self.name = name
        self.logger = logger
        self.session = session
        self.component = "connector.\(name.lowercased())"
        self.requestBuilder = requestBuilder
        self.messageHandler = messageHandler
        self.subscriptionHandler = subscriptionHandler
        self.connectedHandler = connectedHandler
        self.disconnectedHandler = disconnectedHandler
        self.statusHandler = statusHandler

        let priceStream = AsyncStream.makeStream(
            of: RawPriceData.self,
            bufferingPolicy: .bufferingNewest(100)
        )
        self.priceStreamStorage = priceStream.stream
        self.priceContinuation = priceStream.continuation

        let eventStream = AsyncStream.makeStream(
            of: ConnectionEvent.self,
            bufferingPolicy: .bufferingNewest(100)
        )
        self.eventStreamStorage = eventStream.stream
        self.eventContinuation = eventStream.continuation

        self.backoffState = BackoffState(configuration: backoffConfiguration)
        self.circuitBreaker = CircuitBreaker(configuration: circuitBreakerConfiguration)
    }

    deinit {
        priceContinuation.finish()
        eventContinuation.finish()
        receiveTask?.cancel()
        reconnectTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    public var connectionStatus: ConnectionStatus {
        get async { status }
    }

    public func connect() async throws {
        manualDisconnectRequested = false

        if case .connected = status {
            return
        }

        let correlationId = UUID().uuidString

        guard await circuitBreaker.canAttempt() else {
            let error = ArbitrageError.connection(.circuitBreakerOpen(
                exchange: name,
                failureCount: await circuitBreaker.currentState.failureCount
            ))
            logger.logError(error, component: component, correlationId: correlationId)
            throw error
        }

        do {
            try await startConnection(reconnecting: false, correlationId: correlationId)
            await circuitBreaker.recordSuccess()
        } catch {
            await circuitBreaker.recordFailure()
            throw error
        }
    }

    public func disconnect() async {
        manualDisconnectRequested = true
        reconnectTask?.cancel()
        reconnectTask = nil

        await closeSocket(code: .normalClosure, reason: nil)
        await setStatus(.disconnected)
        emitEvent(.disconnected(reason: nil))
    }

    public func subscribeToPairs(_ pairs: [String]) async throws {
        subscriptions = Set(pairs)

        guard case .connected = status, let task = webSocketTask else {
            let correlationId = UUID().uuidString
            let error = ArbitrageError.logic(.operationNotAllowed(
                component: name,
                operation: "subscribeToPairs",
                reason: "Not connected"
            ))
            logger.logError(error, component: component, correlationId: correlationId)
            throw error
        }

        do {
            if let subscriptionHandler {
                try await subscriptionHandler(self, subscriptions, task)
            }
        } catch {
            let correlationId = UUID().uuidString
            let wrappedError = ArbitrageError.connection(.subscriptionFailed(
                exchange: name,
                pairs: pairs,
                reason: error.localizedDescription
            ))
            logger.logError(wrappedError, component: component, correlationId: correlationId)
            throw wrappedError
        }
    }

    // MARK: - Protected helpers

    public func emitPriceUpdate(_ price: RawPriceData) {
        priceContinuation.yield(price)
    }

    public func emitEvent(_ event: ConnectionEvent) {
        eventContinuation.yield(event)
    }

    // MARK: - Internal lifecycle management

    private func startConnection(reconnecting: Bool, correlationId: String) async throws {
        guard webSocketTask == nil else { return }

        await setStatus(reconnecting ? .reconnecting : .connecting)

        do {
            let request = try requestBuilder(self)
            let task = session.webSocketTask(with: request)
            webSocketTask = task

            logger.info(
                component: component,
                event: reconnecting ? "websocket_reconnect_start" : "websocket_connect_start",
                data: ["url": request.url?.absoluteString ?? "unknown"],
                correlationId: correlationId
            )

            task.resume()
            if let connectedHandler {
                try await connectedHandler(self, task)
            }
            backoffState.reset()

            await setStatus(.connected)
            startReceiveLoop(using: task)

            if !subscriptions.isEmpty, let subscriptionHandler {
                try await subscriptionHandler(self, subscriptions, task)
            }
        } catch {
            let arbError = ArbitrageError.connection(.failedToConnect(
                exchange: name,
                reason: error.localizedDescription
            ))
            logger.logError(arbError, component: component, correlationId: correlationId)

            await handleConnectionFailure(error, correlationId: correlationId)
            throw arbError
        }
    }

    private func startReceiveLoop(using task: URLSessionWebSocketTask) {
        receiveTask?.cancel()

        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveMessages(from: task)
        }
    }

    private func receiveMessages(from task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                try await messageHandler(self, message)
            } catch {
                if Task.isCancelled { return }
                await handleReceiveFailure(error)
                return
            }
        }
    }

    private func handleReceiveFailure(_ error: Error) async {
        let correlationId = UUID().uuidString
        let arbError = ArbitrageError.connection(.connectionLost(
            exchange: name,
            reason: error.localizedDescription
        ))
        logger.logError(arbError, component: component, correlationId: correlationId)

        await closeSocket(code: .abnormalClosure, reason: nil)
        await setStatus(.failed(reason: error.localizedDescription))
        emitEvent(.disconnected(reason: error.localizedDescription))

        await circuitBreaker.recordFailure()
        await scheduleReconnect(after: error, correlationId: correlationId)
    }

    private func handleConnectionFailure(_ error: Error, correlationId: String) async {
        await closeSocket(code: .abnormalClosure, reason: nil)
        await setStatus(.failed(reason: error.localizedDescription))
        emitEvent(.disconnected(reason: error.localizedDescription))
        await circuitBreaker.recordFailure()
        await scheduleReconnect(after: error, correlationId: correlationId)
    }

    private func scheduleReconnect(after error: Error, correlationId: String) async {
        guard !manualDisconnectRequested else { return }

        guard await circuitBreaker.canAttempt() else {
            let cbError = ArbitrageError.connection(.circuitBreakerOpen(
                exchange: name,
                failureCount: await circuitBreaker.currentState.failureCount
            ))
            logger.logError(cbError, component: component, correlationId: correlationId)
            return
        }

        await setStatus(.reconnecting)

        let delay = backoffState.nextDelay()
        logger.warn(
            component: component,
            event: "websocket_reconnect_scheduled",
            data: [
                "delay": String(format: "%.2f", delay),
                "reason": error.localizedDescription
            ],
            correlationId: correlationId
        )

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self, correlationId] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }

            await self.reconnectIfNeeded(correlationId: correlationId)
        }
    }

    private func reconnectIfNeeded(correlationId: String) async {
        guard !manualDisconnectRequested else { return }
        webSocketTask = nil

        do {
            try await startConnection(reconnecting: true, correlationId: correlationId)
            await circuitBreaker.recordSuccess()
        } catch {
            await circuitBreaker.recordFailure()
            logger.error(
                component: component,
                event: "websocket_reconnect_failed",
                data: ["reason": error.localizedDescription],
                correlationId: correlationId
            )
        }
    }

    private func closeSocket(
        code: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) async {
        receiveTask?.cancel()
        receiveTask = nil

        if let task = webSocketTask {
            task.cancel(with: code, reason: reason)
            webSocketTask = nil
            if let disconnectedHandler {
                await disconnectedHandler(self, code, reason)
            }
        }
    }

    private func setStatus(_ newStatus: ConnectionStatus) async {
        guard status != newStatus else { return }

        status = newStatus
        emitEvent(.statusChanged(newStatus))

        logger.info(
            component: component,
            event: "status_changed",
            data: statusData(for: newStatus)
        )

        if let statusHandler {
            await statusHandler(self, newStatus)
        }
    }

    private func statusData(for status: ConnectionStatus) -> [String: String] {
        switch status {
        case .disconnected:
            return ["status": "disconnected"]
        case .connecting:
            return ["status": "connecting"]
        case .connected:
            return ["status": "connected"]
        case .reconnecting:
            return ["status": "reconnecting"]
        case .failed(let reason):
            return ["status": "failed", "reason": reason]
        }
    }

    // MARK: - Trading Methods (Default implementations)

    public func getOrderBook(symbol: String) async throws -> OrderBook {
        // Default implementation - override in subclasses
        throw ArbitrageError.logic(.internalError(component: "BaseExchangeConnector", reason: "getOrderBook not implemented for \(name)"))
    }

    public func getRecentTransactions(limit: Int) async throws -> [Transaction] {
        // Default implementation - override in subclasses
        throw ArbitrageError.logic(.internalError(component: "BaseExchangeConnector", reason: "getRecentTransactions not implemented for \(name)"))
    }

    public func placeOrder(symbol: String, side: OrderSide, type: OrderType, quantity: Double, price: Double) async throws -> Order {
        // Default implementation - override in subclasses
        throw ArbitrageError.logic(.internalError(component: "BaseExchangeConnector", reason: "placeOrder not implemented for \(name)"))
    }
}
