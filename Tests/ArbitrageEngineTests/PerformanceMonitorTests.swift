import Testing
import Foundation
@testable import Core
@testable import Utils

@Suite("PerformanceMonitor Tests")
struct PerformanceMonitorTests {

    @Test("Configuration has correct default values")
    func defaultConfiguration() {
        let config = PerformanceMonitor.Configuration()
        #expect(config.reportingInterval == 60.0)
        #expect(config.enableSystemMetrics == true)
    }

    @Test("Configuration accepts custom values")
    func customConfiguration() {
        let config = PerformanceMonitor.Configuration(
            reportingInterval: 30.0,
            enableSystemMetrics: false
        )
        #expect(config.reportingInterval == 30.0)
        #expect(config.enableSystemMetrics == false)
    }

    @Test("Records spread calculated events")
    func recordSpreadCalculated() async {
        let logger = StructuredLogger()
        let monitor = PerformanceMonitor(logger: logger)

        await monitor.recordSpreadCalculated(latencyMs: 10.5)
        await monitor.recordSpreadCalculated(latencyMs: 15.2)
        await monitor.recordSpreadCalculated(latencyMs: 12.8)

        let report = await monitor.generateReport()

        #expect(report.spreadCalculatedMetrics != nil)
        #expect(report.spreadCalculatedMetrics?.count == 3)
        #expect(report.spreadCalculatedMetrics?.minLatencyMs == 10.5)
        #expect(report.spreadCalculatedMetrics?.maxLatencyMs == 15.2)

        let avgLatency = report.spreadCalculatedMetrics?.averageLatencyMs ?? 0
        #expect(abs(avgLatency - 12.833) < 0.01)
    }

    @Test("Records trade simulated events")
    func recordTradeSimulated() async {
        let logger = StructuredLogger()
        let monitor = PerformanceMonitor(logger: logger)

        await monitor.recordTradeSimulated(latencyMs: 5.0)
        await monitor.recordTradeSimulated(latencyMs: 8.0)

        let report = await monitor.generateReport()

        #expect(report.tradeSimulatedMetrics != nil)
        #expect(report.tradeSimulatedMetrics?.count == 2)
        #expect(report.tradeSimulatedMetrics?.minLatencyMs == 5.0)
        #expect(report.tradeSimulatedMetrics?.maxLatencyMs == 8.0)
        #expect(report.tradeSimulatedMetrics?.averageLatencyMs == 6.5)
    }

    @Test("Records reconnection events")
    func recordReconnections() async {
        let logger = StructuredLogger()
        let monitor = PerformanceMonitor(logger: logger)

        await monitor.recordReconnection()
        await monitor.recordReconnection()
        await monitor.recordReconnection()

        let report = await monitor.generateReport()
        #expect(report.reconnectionCount == 3)
    }

    @Test("Generates report with no events")
    func emptyReport() async {
        let logger = StructuredLogger()
        let monitor = PerformanceMonitor(logger: logger)

        let report = await monitor.generateReport()

        #expect(report.spreadCalculatedMetrics == nil)
        #expect(report.tradeSimulatedMetrics == nil)
        #expect(report.reconnectionCount == 0)
    }

    @Test("Calculates p95 latency correctly")
    func p95Calculation() async {
        let logger = StructuredLogger()
        let monitor = PerformanceMonitor(logger: logger)

        for i in 1...100 {
            await monitor.recordSpreadCalculated(latencyMs: Double(i))
        }

        let report = await monitor.generateReport()

        #expect(report.spreadCalculatedMetrics != nil)
        #expect(report.spreadCalculatedMetrics?.count == 100)
        #expect(report.spreadCalculatedMetrics?.p95LatencyMs == 95.0)
    }

    @Test("Reset clears all metrics")
    func resetMetrics() async {
        let logger = StructuredLogger()
        let monitor = PerformanceMonitor(logger: logger)

        await monitor.recordSpreadCalculated(latencyMs: 10.0)
        await monitor.recordTradeSimulated(latencyMs: 5.0)
        await monitor.recordReconnection()

        var report = await monitor.generateReport()
        #expect(report.spreadCalculatedMetrics?.count == 1)
        #expect(report.tradeSimulatedMetrics?.count == 1)
        #expect(report.reconnectionCount == 1)

        await monitor.reset()

        report = await monitor.generateReport()
        #expect(report.spreadCalculatedMetrics == nil)
        #expect(report.tradeSimulatedMetrics == nil)
        #expect(report.reconnectionCount == 0)
    }

    @Test("Report includes timestamp")
    func reportTimestamp() async {
        let fixedDate = Date(timeIntervalSince1970: 1000000)
        let clock: @Sendable () -> Date = { fixedDate }

        let logger = StructuredLogger()
        let monitor = PerformanceMonitor(logger: logger, clock: clock)

        await monitor.recordSpreadCalculated(latencyMs: 10.0)

        let report = await monitor.generateReport()
        #expect(report.timestamp == fixedDate)
    }

    @Test("System metrics are included when enabled")
    func systemMetricsEnabled() async {
        let config = PerformanceMonitor.Configuration(
            reportingInterval: 60,
            enableSystemMetrics: true
        )

        let logger = StructuredLogger()
        let monitor = PerformanceMonitor(config: config, logger: logger)

        await monitor.recordSpreadCalculated(latencyMs: 10.0)

        let report = await monitor.generateReport()

        #expect(report.cpuUsagePercent != nil || report.memoryUsageMB != nil)
    }

    @Test("System metrics are excluded when disabled")
    func systemMetricsDisabled() async {
        let config = PerformanceMonitor.Configuration(
            reportingInterval: 60,
            enableSystemMetrics: false
        )

        let logger = StructuredLogger()
        let monitor = PerformanceMonitor(config: config, logger: logger)

        await monitor.recordSpreadCalculated(latencyMs: 10.0)

        let report = await monitor.generateReport()

        #expect(report.cpuUsagePercent == nil)
        #expect(report.memoryUsageMB == nil)
    }

    @Test("Periodic reporting can be started and stopped")
    func periodicReporting() async {
        let config = PerformanceMonitor.Configuration(
            reportingInterval: 0.1,
            enableSystemMetrics: false
        )

        let logger = StructuredLogger()
        let monitor = PerformanceMonitor(config: config, logger: logger)

        await monitor.recordSpreadCalculated(latencyMs: 10.0)
        await monitor.startPeriodicReporting()

        try? await Task.sleep(for: .milliseconds(250))

        await monitor.stopPeriodicReporting()

        let reportAfterReset = await monitor.generateReport()
        #expect(reportAfterReset.spreadCalculatedMetrics == nil)
    }

    @Test("Multiple calls to start periodic reporting are safe")
    func multipleStartCalls() async {
        let config = PerformanceMonitor.Configuration(
            reportingInterval: 0.1,
            enableSystemMetrics: false
        )

        let logger = StructuredLogger()
        let monitor = PerformanceMonitor(config: config, logger: logger)

        await monitor.startPeriodicReporting()
        await monitor.startPeriodicReporting()
        await monitor.startPeriodicReporting()

        try? await Task.sleep(for: .milliseconds(50))
        await monitor.stopPeriodicReporting()
    }

    @Test("EventMetrics equality")
    func eventMetricsEquality() {
        let metrics1 = PerformanceMonitor.EventMetrics(
            eventType: "test",
            count: 10,
            averageLatencyMs: 5.0,
            minLatencyMs: 1.0,
            maxLatencyMs: 10.0,
            p95LatencyMs: 9.0
        )

        let metrics2 = PerformanceMonitor.EventMetrics(
            eventType: "test",
            count: 10,
            averageLatencyMs: 5.0,
            minLatencyMs: 1.0,
            maxLatencyMs: 10.0,
            p95LatencyMs: 9.0
        )

        #expect(metrics1 == metrics2)
    }

    @Test("PerformanceReport equality")
    func performanceReportEquality() {
        let timestamp = Date(timeIntervalSince1970: 1000000)

        let metrics = PerformanceMonitor.EventMetrics(
            eventType: "test",
            count: 10,
            averageLatencyMs: 5.0,
            minLatencyMs: 1.0,
            maxLatencyMs: 10.0,
            p95LatencyMs: 9.0
        )

        let report1 = PerformanceMonitor.PerformanceReport(
            reportInterval: 60,
            spreadCalculatedMetrics: metrics,
            tradeSimulatedMetrics: nil,
            reconnectionCount: 5,
            cpuUsagePercent: 25.0,
            memoryUsageMB: 100.0,
            timestamp: timestamp
        )

        let report2 = PerformanceMonitor.PerformanceReport(
            reportInterval: 60,
            spreadCalculatedMetrics: metrics,
            tradeSimulatedMetrics: nil,
            reconnectionCount: 5,
            cpuUsagePercent: 25.0,
            memoryUsageMB: 100.0,
            timestamp: timestamp
        )

        #expect(report1 == report2)
    }
}
