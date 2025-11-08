import Foundation

public actor BackpressureThrottle {
    private var p99Latency: TimeInterval = 0
    private var backlogDepth: Int = 0
    private var isThrottled = false
    private let latencyThreshold: TimeInterval
    private let backlogThreshold: Int

    public init(
        latencyThreshold: TimeInterval = 0.1,
        backlogThreshold: Int = 1000
    ) {
        self.latencyThreshold = latencyThreshold
        self.backlogThreshold = backlogThreshold
    }

    public func updateMetrics(p99Latency: TimeInterval, backlogDepth: Int) {
        self.p99Latency = p99Latency
        self.backlogDepth = backlogDepth

        let shouldThrottle = p99Latency > latencyThreshold || backlogDepth > backlogThreshold
        if shouldThrottle && !isThrottled {
            isThrottled = true
        } else if !shouldThrottle && isThrottled {
            isThrottled = false
        }
    }

    public func canProceed() -> Bool {
        return !isThrottled
    }

    public func getState() -> (throttled: Bool, p99Latency: TimeInterval, backlogDepth: Int) {
        return (throttled: isThrottled, p99Latency: p99Latency, backlogDepth: backlogDepth)
    }
}

extension ExecutionEngine {
    func checkBackpressure(throttle: BackpressureThrottle?) async throws {
        guard let throttle = throttle else { return }

        let state = await throttle.getState()
        guard state.throttled else { return }

        throw SmartVestorError.executionError(
            "Backpressure throttle active: p99=\(state.p99Latency)s, backlog=\(state.backlogDepth)"
        )
    }
}
