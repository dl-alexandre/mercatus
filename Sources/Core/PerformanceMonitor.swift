import Foundation
import Utils

public actor PerformanceMonitor {
    public struct Configuration: Sendable, Equatable {
        public let reportingInterval: TimeInterval
        public let enableSystemMetrics: Bool

        public init(
            reportingInterval: TimeInterval = 60.0,
            enableSystemMetrics: Bool = true
        ) {
            precondition(reportingInterval > 0, "reportingInterval must be > 0")
            self.reportingInterval = reportingInterval
            self.enableSystemMetrics = enableSystemMetrics
        }
    }

    public struct EventMetrics: Sendable, Equatable {
        public let eventType: String
        public let count: Int
        public let averageLatencyMs: Double
        public let minLatencyMs: Double
        public let maxLatencyMs: Double
        public let p95LatencyMs: Double

        public init(
            eventType: String,
            count: Int,
            averageLatencyMs: Double,
            minLatencyMs: Double,
            maxLatencyMs: Double,
            p95LatencyMs: Double
        ) {
            self.eventType = eventType
            self.count = count
            self.averageLatencyMs = averageLatencyMs
            self.minLatencyMs = minLatencyMs
            self.maxLatencyMs = maxLatencyMs
            self.p95LatencyMs = p95LatencyMs
        }
    }

    public struct PerformanceReport: Sendable, Equatable {
        public let reportInterval: TimeInterval
        public let spreadCalculatedMetrics: EventMetrics?
        public let tradeSimulatedMetrics: EventMetrics?
        public let reconnectionCount: Int
        public let cpuUsagePercent: Double?
        public let memoryUsageMB: Double?
        public let timestamp: Date

        public init(
            reportInterval: TimeInterval,
            spreadCalculatedMetrics: EventMetrics?,
            tradeSimulatedMetrics: EventMetrics?,
            reconnectionCount: Int,
            cpuUsagePercent: Double?,
            memoryUsageMB: Double?,
            timestamp: Date
        ) {
            self.reportInterval = reportInterval
            self.spreadCalculatedMetrics = spreadCalculatedMetrics
            self.tradeSimulatedMetrics = tradeSimulatedMetrics
            self.reconnectionCount = reconnectionCount
            self.cpuUsagePercent = cpuUsagePercent
            self.memoryUsageMB = memoryUsageMB
            self.timestamp = timestamp
        }
    }

    private struct EventRecord: Sendable {
        let timestamp: Date
        let latencyMs: Double
    }

    private let config: Configuration
    private let logger: StructuredLogger?
    private let clock: @Sendable () -> Date
    private let componentName = "PerformanceMonitor"

    private var spreadCalculatedEvents: [EventRecord] = []
    private var tradeSimulatedEvents: [EventRecord] = []
    private var reconnectionCount: Int = 0
    private var reportingTask: Task<Void, Never>?

    public init(
        config: Configuration = Configuration(),
        logger: StructuredLogger? = nil,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.config = config
        self.logger = logger
        self.clock = clock
    }

    public func recordSpreadCalculated(latencyMs: Double) {
        let record = EventRecord(timestamp: clock(), latencyMs: latencyMs)
        spreadCalculatedEvents.append(record)
    }

    public func recordTradeSimulated(latencyMs: Double) {
        let record = EventRecord(timestamp: clock(), latencyMs: latencyMs)
        tradeSimulatedEvents.append(record)
    }

    public func recordReconnection() {
        reconnectionCount += 1
    }

    public func startPeriodicReporting() {
        guard reportingTask == nil else { return }

        let selfReference = self
        reportingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(config.reportingInterval))
                guard !Task.isCancelled else { break }
                await selfReference.generateAndLogReport()
            }
        }
    }

    public func stopPeriodicReporting() {
        reportingTask?.cancel()
        reportingTask = nil
    }

    public func generateReport() -> PerformanceReport {
        let spreadMetrics = computeMetrics(for: spreadCalculatedEvents, eventType: "spread_calculated")
        let tradeMetrics = computeMetrics(for: tradeSimulatedEvents, eventType: "trade_simulated")

        var cpuUsage: Double? = nil
        var memoryUsage: Double? = nil

        if config.enableSystemMetrics {
            cpuUsage = getCPUUsage()
            memoryUsage = getMemoryUsage()
        }

        return PerformanceReport(
            reportInterval: config.reportingInterval,
            spreadCalculatedMetrics: spreadMetrics,
            tradeSimulatedMetrics: tradeMetrics,
            reconnectionCount: reconnectionCount,
            cpuUsagePercent: cpuUsage,
            memoryUsageMB: memoryUsage,
            timestamp: clock()
        )
    }

    public func reset() {
        spreadCalculatedEvents.removeAll()
        tradeSimulatedEvents.removeAll()
        reconnectionCount = 0
    }

    private func generateAndLogReport() {
        let report = generateReport()
        logReport(report)
        reset()
    }

    private func computeMetrics(for events: [EventRecord], eventType: String) -> EventMetrics? {
        guard !events.isEmpty else { return nil }

        let latencies = events.map { $0.latencyMs }
        let count = latencies.count
        let sum = latencies.reduce(0.0, +)
        let average = sum / Double(count)
        let minLatency = latencies.min() ?? 0.0
        let maxLatency = latencies.max() ?? 0.0

        let sortedLatencies = latencies.sorted()
        let p95Index = Int(Double(count - 1) * 0.95)
        let p95 = sortedLatencies[p95Index]

        return EventMetrics(
            eventType: eventType,
            count: count,
            averageLatencyMs: average,
            minLatencyMs: minLatency,
            maxLatencyMs: maxLatency,
            p95LatencyMs: p95
        )
    }

    private func getCPUUsage() -> Double? {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)

        guard result == KERN_SUCCESS, let threads = threadList else {
            return nil
        }

        var totalCPU: Double = 0.0

        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

            let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }

            if infoResult == KERN_SUCCESS {
                let cpuUsage = Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                totalCPU += cpuUsage
            }
        }

        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.stride))

        return totalCPU
    }

    private func getMemoryUsage() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        let memoryInBytes = Double(info.resident_size)
        let memoryInMB = memoryInBytes / (1024.0 * 1024.0)
        return memoryInMB
    }

    private func logReport(_ report: PerformanceReport) {
        var data: [String: String] = [
            "report_interval_seconds": String(format: "%.1f", report.reportInterval),
            "reconnection_count": String(report.reconnectionCount),
            "timestamp": ISO8601DateFormatter().string(from: report.timestamp)
        ]

        if let spreadMetrics = report.spreadCalculatedMetrics {
            data["spread_calculated_count"] = String(spreadMetrics.count)
            data["spread_calculated_avg_latency_ms"] = String(format: "%.3f", spreadMetrics.averageLatencyMs)
            data["spread_calculated_min_latency_ms"] = String(format: "%.3f", spreadMetrics.minLatencyMs)
            data["spread_calculated_max_latency_ms"] = String(format: "%.3f", spreadMetrics.maxLatencyMs)
            data["spread_calculated_p95_latency_ms"] = String(format: "%.3f", spreadMetrics.p95LatencyMs)
        } else {
            data["spread_calculated_count"] = "0"
        }

        if let tradeMetrics = report.tradeSimulatedMetrics {
            data["trade_simulated_count"] = String(tradeMetrics.count)
            data["trade_simulated_avg_latency_ms"] = String(format: "%.3f", tradeMetrics.averageLatencyMs)
            data["trade_simulated_min_latency_ms"] = String(format: "%.3f", tradeMetrics.minLatencyMs)
            data["trade_simulated_max_latency_ms"] = String(format: "%.3f", tradeMetrics.maxLatencyMs)
            data["trade_simulated_p95_latency_ms"] = String(format: "%.3f", tradeMetrics.p95LatencyMs)
        } else {
            data["trade_simulated_count"] = "0"
        }

        if let cpuUsage = report.cpuUsagePercent {
            data["cpu_usage_percent"] = String(format: "%.2f", cpuUsage)
        }

        if let memoryUsage = report.memoryUsageMB {
            data["memory_usage_mb"] = String(format: "%.2f", memoryUsage)
        }

        logger?.info(
            component: componentName,
            event: "performance_report",
            data: data
        )
    }
}
