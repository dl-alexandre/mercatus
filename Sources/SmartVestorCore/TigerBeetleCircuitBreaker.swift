import Foundation

public enum CircuitState: Sendable {
    case closed
    case open
    case halfOpen
}

public actor TigerBeetleCircuitBreaker {
    private var state: CircuitState = .closed
    private var failureCount: Int = 0
    private var lastFailureTime: Date?
    private var consecutiveSuccesses: Int = 0

    private let failureThreshold: Int
    private let recoveryTimeout: TimeInterval
    private let halfOpenMaxSuccesses: Int

    public init(
        failureThreshold: Int = 10,
        recoveryTimeout: TimeInterval = 60,
        halfOpenMaxSuccesses: Int = 3
    ) {
        self.failureThreshold = failureThreshold
        self.recoveryTimeout = recoveryTimeout
        self.halfOpenMaxSuccesses = halfOpenMaxSuccesses
    }

    public func recordSuccess() {
        consecutiveSuccesses += 1

        if state == .halfOpen && consecutiveSuccesses >= halfOpenMaxSuccesses {
            state = .closed
            failureCount = 0
            consecutiveSuccesses = 0
        } else if state == .closed {
            failureCount = 0
        }
    }

    public func recordFailure(_ error: Error) {
        failureCount += 1
        lastFailureTime = Date()
        consecutiveSuccesses = 0

        if failureCount >= failureThreshold {
            state = .open
        }
    }

    public func canAttempt() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) >= recoveryTimeout {
                state = .halfOpen
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }

    public func getState() -> CircuitState {
        return state
    }

    public func reset() {
        state = .closed
        failureCount = 0
        consecutiveSuccesses = 0
        lastFailureTime = nil
    }
}

extension TigerBeetlePersistence {
    func executeWithCircuitBreaker<T>(_ operation: () throws -> T, circuitBreaker: TigerBeetleCircuitBreaker?) async throws -> T {
        guard let breaker = circuitBreaker else {
            return try operation()
        }

        guard await breaker.canAttempt() else {
            throw SmartVestorError.persistenceError("Circuit breaker is open")
        }

        do {
            let result = try operation()
            await breaker.recordSuccess()
            return result
        } catch {
            await breaker.recordFailure(error)
            throw error
        }
    }
}
