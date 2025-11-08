import Foundation

public struct TigerBeetleMetrics {
    public var operationCount: Int64 = 0
    public var errorCount: Int64 = 0
    public var totalLatencyNanos: Int64 = 0
    public var lastOperationTime: Date?

    public var averageLatencyNanos: Int64 {
        guard operationCount > 0 else { return 0 }
        return totalLatencyNanos / operationCount
    }

    public var errorRate: Double {
        guard operationCount > 0 else { return 0.0 }
        return Double(errorCount) / Double(operationCount)
    }
}

public actor TigerBeetleMetricsCollector {
    private var metrics = TigerBeetleMetrics()

    public init() {}

    public func recordOperation(latencyNanos: Int64, error: Error? = nil) {
        metrics.operationCount += 1
        metrics.totalLatencyNanos += latencyNanos
        metrics.lastOperationTime = Date()

        if error != nil {
            metrics.errorCount += 1
        }
    }

    public func getMetrics() -> TigerBeetleMetrics {
        return metrics
    }

    public func reset() {
        metrics = TigerBeetleMetrics()
    }
}

extension TigerBeetlePersistence {
    func measureOperation<T>(_ operation: () throws -> T) throws -> T {
        let startTime = DispatchTime.now()
        do {
            let result = try operation()
            let latency = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
            let collector = metricsCollector
            Task { @MainActor in
                await collector?.recordOperation(latencyNanos: Int64(latency))
            }
            return result
        } catch {
            let latency = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
            let collector = metricsCollector
            Task { @MainActor in
                await collector?.recordOperation(latencyNanos: Int64(latency), error: error)
            }
            throw error
        }
    }
}
