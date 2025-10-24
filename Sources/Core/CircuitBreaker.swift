import Foundation

public actor CircuitBreaker {
    public enum State: Sendable, Equatable {
        case closed
        case open(openedAt: Date, failureCount: Int)
        case halfOpen

        public var failureCount: Int {
            switch self {
            case .closed, .halfOpen:
                return 0
            case .open(_, let count):
                return count
            }
        }
    }

    public struct Configuration: Sendable {
        public let failureThreshold: Int
        public let timeout: TimeInterval
        public let successThreshold: Int

        public init(
            failureThreshold: Int = 5,
            timeout: TimeInterval = 60.0,
            successThreshold: Int = 2
        ) {
            precondition(failureThreshold > 0, "failureThreshold must be > 0")
            precondition(timeout > 0, "timeout must be > 0")
            precondition(successThreshold > 0, "successThreshold must be > 0")

            self.failureThreshold = failureThreshold
            self.timeout = timeout
            self.successThreshold = successThreshold
        }

        public static let `default` = Configuration()
    }

    private let configuration: Configuration
    private let clock: @Sendable () -> Date
    private var state: State = .closed
    private var failureCount: Int = 0
    private var successCount: Int = 0

    public init(
        configuration: Configuration = .default,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.clock = clock
    }

    public var currentState: State {
        get {
            updateStateIfNeeded()
            return state
        }
    }

    public func recordSuccess() {
        updateStateIfNeeded()

        switch state {
        case .closed:
            failureCount = 0
        case .open:
            break
        case .halfOpen:
            successCount += 1
            if successCount >= configuration.successThreshold {
                transition(to: .closed)
                failureCount = 0
                successCount = 0
            }
        }
    }

    public func recordFailure() {
        updateStateIfNeeded()

        switch state {
        case .closed:
            failureCount += 1
            if failureCount >= configuration.failureThreshold {
                let now = clock()
                transition(to: .open(openedAt: now, failureCount: failureCount))
            }
        case .open:
            failureCount += 1
            if case .open(let openedAt, _) = state {
                transition(to: .open(openedAt: openedAt, failureCount: failureCount))
            }
        case .halfOpen:
            failureCount += 1
            successCount = 0
            let now = clock()
            transition(to: .open(openedAt: now, failureCount: failureCount))
        }
    }

    public func reset() {
        transition(to: .closed)
        failureCount = 0
        successCount = 0
    }

    public func canAttempt() -> Bool {
        updateStateIfNeeded()

        switch state {
        case .closed, .halfOpen:
            return true
        case .open:
            return false
        }
    }

    private func updateStateIfNeeded() {
        guard case .open(let openedAt, let count) = state else {
            return
        }

        let elapsed = clock().timeIntervalSince(openedAt)
        if elapsed >= configuration.timeout {
            transition(to: .halfOpen)
            successCount = 0
            failureCount = count
        }
    }

    private func transition(to newState: State) {
        state = newState
    }
}
