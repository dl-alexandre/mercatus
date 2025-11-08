import Foundation
import NIOCore
import NIOPosix
import Utils

public enum TUIConnectionStatus: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(reason: String)
}

public struct BackoffConfiguration: Sendable {
    public let initial: TimeInterval
    public let multiplier: Double
    public let maxDelay: TimeInterval
    public let maxRetries: Int

    public init(initial: TimeInterval = 1.0, multiplier: Double = 2.0, maxDelay: TimeInterval = 30.0, maxRetries: Int = 10) {
        self.initial = max(0.1, initial)
        self.multiplier = max(1.0, multiplier)
        self.maxDelay = max(self.initial, maxDelay)
        self.maxRetries = max(0, maxRetries)
    }

    public static let `default` = BackoffConfiguration()
}

public actor TUIConnectionManager {
    private struct BackoffState {
        private let configuration: BackoffConfiguration
        private var currentDelay: TimeInterval
        private var retryCount: Int = 0

        init(configuration: BackoffConfiguration) {
            self.configuration = configuration
            self.currentDelay = configuration.initial
        }

        mutating func reset() {
            currentDelay = configuration.initial
            retryCount = 0
        }

        mutating func nextDelay() -> TimeInterval? {
            guard retryCount < configuration.maxRetries else {
                return nil
            }

            let delay = currentDelay
            currentDelay = min(configuration.maxDelay, currentDelay * configuration.multiplier)
            retryCount += 1
            return delay
        }

        func canRetry() -> Bool {
            return retryCount < configuration.maxRetries
        }

        func getRetryCount() -> Int {
            return retryCount
        }
    }

    private let socketPath: String
    private let backoffConfig: BackoffConfiguration
    private let logger: StructuredLogger
    private var backoffState: BackoffState
    private var connectionStatus: TUIConnectionStatus = .disconnected
    private var reconnectTask: Task<Void, Never>?
    private var lastSuccessfulFrame: [String]?
    private let statusContinuation: AsyncStream<TUIConnectionStatus>.Continuation

    private let _connectionStatusStream: AsyncStream<TUIConnectionStatus>

    public nonisolated var connectionStatusStream: AsyncStream<TUIConnectionStatus> {
        _connectionStatusStream
    }

    public init(socketPath: String, backoffConfig: BackoffConfiguration = .default, logger: StructuredLogger = StructuredLogger()) {
        self.socketPath = socketPath
        self.backoffConfig = backoffConfig
        self.logger = logger
        self.backoffState = BackoffState(configuration: backoffConfig)

        let (stream, continuation) = AsyncStream.makeStream(of: TUIConnectionStatus.self)
        self._connectionStatusStream = stream
        self.statusContinuation = continuation
    }

    public func scheduleReconnect() async {
        guard backoffState.canRetry() else {
            connectionStatus = .failed(reason: "Maximum retry attempts exceeded")
            statusContinuation.yield(.failed(reason: "Maximum retry attempts exceeded"))
            logger.error(component: "TUIConnectionManager", event: "Maximum retries exceeded", data: [
                "maxRetries": String(backoffConfig.maxRetries)
            ])
            return
        }

        guard let delay = backoffState.nextDelay() else {
            return
        }

        connectionStatus = .reconnecting
            statusContinuation.yield(.reconnecting)

        let retryCount = backoffState.getRetryCount()
        logger.warn(component: "TUIConnectionManager", event: "Scheduling reconnect", data: [
            "retryCount": String(retryCount),
            "delay": String(format: "%.2f", delay),
            "socketPath": socketPath
        ])

        reconnectTask?.cancel()
        reconnectTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
        }
    }

    public func cacheFrame(_ frame: [String]) {
        lastSuccessfulFrame = frame
    }

    public func getCachedFrame() -> [String]? {
        return lastSuccessfulFrame
    }

    public func getStatus() -> TUIConnectionStatus {
        return connectionStatus
    }

    public func setStatus(_ status: TUIConnectionStatus) {
        connectionStatus = status
        statusContinuation.yield(status)
    }

    public func reset() {
        reconnectTask?.cancel()
        reconnectTask = nil
        backoffState.reset()
        connectionStatus = .disconnected
        statusContinuation.yield(.disconnected)
    }

    public func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    deinit {
        statusContinuation.finish()
    }
}
