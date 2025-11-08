import Foundation

public struct TigerBeetleMetricLabels {
    public let operation: String
    public let exchange: String?
    public let asset: String?
    public let result: String

    public init(operation: String, exchange: String? = nil, asset: String? = nil, result: String) {
        self.operation = operation
        self.exchange = exchange
        self.asset = asset
        self.result = result
    }
}

public actor TigerBeetleExtendedMetrics {
    private var transferCount: Int64 = 0
    private var errorCounts: [String: Int64] = [:]
    private var idempotentHits: Int64 = 0
    private var latencies: [TimeInterval] = []
    private var batchSizes: [Int] = []
    private var backlogDepth: Int = 0

    public init() {}

    public func recordTransfer(labels: TigerBeetleMetricLabels) {
        transferCount += 1
        if labels.result != "success" {
            errorCounts[labels.result, default: 0] += 1
        }
    }

    public func recordIdempotentHit() {
        idempotentHits += 1
    }

    public func recordLatency(_ latency: TimeInterval) {
        latencies.append(latency)
        if latencies.count > 1000 {
            latencies.removeFirst(500)
        }
    }

    public func recordBatchSize(_ size: Int) {
        batchSizes.append(size)
        if batchSizes.count > 1000 {
            batchSizes.removeFirst(500)
        }
    }

    public func updateBacklog(_ depth: Int) {
        backlogDepth = depth
    }

    public func getMetrics() -> (
        transfersTotal: Int64,
        errorsTotal: [String: Int64],
        idempotentHitsTotal: Int64,
        p95Latency: TimeInterval,
        avgBatchSize: Double,
        backlogDepth: Int
    ) {
        let sortedLatencies = latencies.sorted()
        let p95Index = Int(Double(sortedLatencies.count) * 0.95)
        let p95Latency = p95Index < sortedLatencies.count ? sortedLatencies[p95Index] : 0

        let avgBatchSize = batchSizes.isEmpty ? 0 : Double(batchSizes.reduce(0, +)) / Double(batchSizes.count)

        return (
            transfersTotal: transferCount,
            errorsTotal: errorCounts,
            idempotentHitsTotal: idempotentHits,
            p95Latency: p95Latency,
            avgBatchSize: avgBatchSize,
            backlogDepth: backlogDepth
        )
    }

    public func reset() {
        transferCount = 0
        errorCounts = [:]
        idempotentHits = 0
        latencies = []
        batchSizes = []
        backlogDepth = 0
    }
}
