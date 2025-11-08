import Testing
import Foundation
import Darwin
@testable import SmartVestor
@testable import Core
@testable import Utils

@Suite("Rendering Performance Tests")
struct RenderingPerformanceTests {

    func createTestTUIUpdate(
        isRunning: Bool = true,
        mode: AutomationMode = .continuous,
        errorCount: Int = 0,
        circuitBreakerOpen: Bool = false,
        balances: [Holding] = [],
        trades: [InvestmentTransaction] = [],
        totalPortfolioValue: Double = 1000.0
    ) -> TUIUpdate {
        let state = AutomationState(
            isRunning: isRunning,
            mode: mode,
            startedAt: Date(),
            lastExecutionTime: Date(),
            nextExecutionTime: nil,
            pid: nil
        )
        let data = TUIData(
            recentTrades: trades,
            balances: balances,
            circuitBreakerOpen: circuitBreakerOpen,
            lastExecutionTime: Date(),
            nextExecutionTime: nil,
            totalPortfolioValue: totalPortfolioValue,
            errorCount: errorCount
        )
        return TUIUpdate(
            timestamp: Date(),
            type: .heartbeat,
            state: state,
            data: data,
            sequenceNumber: 1
        )
    }

    func createTestHolding(
        asset: String = "BTC",
        available: Double = 0.5,
        updatedAt: Date = Date()
    ) -> Holding {
        return Holding(
            exchange: "robinhood",
            asset: asset,
            available: available,
            pending: 0.0,
            staked: 0.0,
            updatedAt: updatedAt
        )
    }

    func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        } else {
            return 0
        }
    }

    @Test("Render time should be ≤ 16ms per frame")
    func testRenderTimeConstraints() async throws {
        let monitor = PerformanceMonitor()
        let renderer = EnhancedTUIRenderer(performanceMonitor: monitor)
        let update = createTestTUIUpdate(
            balances: [
                createTestHolding(asset: "BTC", available: 0.5),
                createTestHolding(asset: "ETH", available: 2.0),
                createTestHolding(asset: "SOL", available: 10.0)
            ]
        )

        var renderTimes: [Double] = []
        let frameCount = 100

        for _ in 0..<frameCount {
            let startTime = Date()
            let frame = await renderer.renderPanels(update, prices: nil, focus: nil)
            let renderTime = Date().timeIntervalSince(startTime) * 1000
            renderTimes.append(renderTime)
            _ = frame
        }

        let averageRenderTime = renderTimes.reduce(0, +) / Double(renderTimes.count)
        let p95RenderTime = renderTimes.sorted()[Int(Double(renderTimes.count) * 0.95)]
        let p99RenderTime = renderTimes.sorted()[Int(Double(renderTimes.count) * 0.99)]
        let maxRenderTime = renderTimes.max() ?? 0

        print("Average render time: \(String(format: "%.2f", averageRenderTime))ms")
        print("P95 render time: \(String(format: "%.2f", p95RenderTime))ms")
        print("P99 render time: \(String(format: "%.2f", p99RenderTime))ms")
        print("Max render time: \(String(format: "%.2f", maxRenderTime))ms")

        #expect(averageRenderTime <= 16.0)
        #expect(p95RenderTime <= 20.0)
        #expect(p99RenderTime <= 25.0)
        #expect(maxRenderTime <= 30.0)
    }

    @Test("Memory footprint should be ≤ 50MB")
    func testMemoryFootprintLimits() async throws {
        let monitor = PerformanceMonitor()
        let renderer = EnhancedTUIRenderer(performanceMonitor: monitor)

        let largeUpdate = createTestTUIUpdate(
            balances: (0..<50).map { createTestHolding(asset: "ASSET\($0)", available: Double.random(in: 0.1...100.0)) }
        )

        let memoryBefore = getCurrentMemoryUsage()

        for _ in 0..<100 {
            _ = await renderer.renderPanels(largeUpdate, prices: nil, focus: nil)
        }

        let memoryAfter = getCurrentMemoryUsage()
        let memoryDelta = memoryAfter - memoryBefore
        let memoryDeltaMB = Double(memoryDelta) / 1024.0 / 1024.0

        print("Memory delta: \(String(format: "%.2f", memoryDeltaMB))MB")
        print("Memory before: \(String(format: "%.2f", Double(memoryBefore) / 1024.0 / 1024.0))MB")
        print("Memory after: \(String(format: "%.2f", Double(memoryAfter) / 1024.0 / 1024.0))MB")

        #expect(memoryDeltaMB <= 50.0)
    }

    @Test("Diff-based rendering should be more efficient than full renders")
    func testDiffBasedRenderingEfficiency() async throws {
        let diffRenderer = DiffRenderer()

        let baseFrame = (0..<30).map { "Line \($0): Base content" }
        let smallChangeFrame = baseFrame.enumerated().map { index, line in
            if index == 15 {
                return "Line \(index): Changed content"
            }
            return line
        }
        let largeChangeFrame = (0..<30).map { "Line \($0): Completely new content" }

        var fullRenderTimes: [TimeInterval] = []
        var diffRenderTimes: [TimeInterval] = []
        let iterations = 100

        for _ in 0..<iterations {
            let fullStart = Date()
            await diffRenderer.renderFull(newFrame: baseFrame)
            fullRenderTimes.append(Date().timeIntervalSince(fullStart) * 1000)
        }

        for _ in 0..<iterations {
            let diffStart = Date()
            await diffRenderer.renderDiff(oldFrame: baseFrame, newFrame: smallChangeFrame)
            diffRenderTimes.append(Date().timeIntervalSince(diffStart) * 1000)
        }

        let avgFullRender = fullRenderTimes.reduce(0, +) / Double(fullRenderTimes.count)
        let avgDiffRender = diffRenderTimes.reduce(0, +) / Double(diffRenderTimes.count)

        print("Average full render: \(String(format: "%.3f", avgFullRender))ms")
        print("Average diff render: \(String(format: "%.3f", avgDiffRender))ms")
        print("Efficiency gain: \(String(format: "%.2f", avgFullRender / avgDiffRender))x")

        #expect(avgDiffRender < avgFullRender)

        var largeChangeFullTimes: [TimeInterval] = []
        var largeChangeDiffTimes: [TimeInterval] = []

        for _ in 0..<iterations {
            let fullStart = Date()
            await diffRenderer.renderFull(newFrame: largeChangeFrame)
            largeChangeFullTimes.append(Date().timeIntervalSince(fullStart) * 1000)
        }

        for _ in 0..<iterations {
            let diffStart = Date()
            await diffRenderer.renderDiff(oldFrame: baseFrame, newFrame: largeChangeFrame)
            largeChangeDiffTimes.append(Date().timeIntervalSince(diffStart) * 1000)
        }

        let avgLargeFull = largeChangeFullTimes.reduce(0, +) / Double(largeChangeFullTimes.count)
        let avgLargeDiff = largeChangeDiffTimes.reduce(0, +) / Double(largeChangeDiffTimes.count)

        print("Average large change full render: \(String(format: "%.3f", avgLargeFull))ms")
        print("Average large change diff render: \(String(format: "%.3f", avgLargeDiff))ms")

        #expect(avgLargeDiff <= avgLargeFull * 2.0)
    }

    @Test("Concurrent rendering should maintain performance")
    func testConcurrentRenderingPerformance() async throws {
        let monitor = PerformanceMonitor()
        let renderer = EnhancedTUIRenderer(performanceMonitor: monitor)

        let update = createTestTUIUpdate(
            balances: [
                createTestHolding(asset: "BTC", available: 0.5),
                createTestHolding(asset: "ETH", available: 2.0)
            ]
        )

        let concurrentStart = Date()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    _ = await renderer.renderPanels(update, prices: nil, focus: nil)
                }
            }
        }
        let concurrentTime = Date().timeIntervalSince(concurrentStart) * 1000

        let sequentialStart = Date()
        for _ in 0..<50 {
            _ = await renderer.renderPanels(update, prices: nil, focus: nil)
        }
        let sequentialTime = Date().timeIntervalSince(sequentialStart) * 1000

        print("Concurrent time: \(String(format: "%.2f", concurrentTime))ms")
        print("Sequential time: \(String(format: "%.2f", sequentialTime))ms")

        let avgConcurrent = concurrentTime / 50.0
        let avgSequential = sequentialTime / 50.0

        #expect(avgConcurrent <= 16.0)
        #expect(avgSequential <= 16.0)
    }

    @Test("Rendering with prices should maintain performance")
    func testRenderingWithPricesPerformance() async throws {
        let monitor = PerformanceMonitor()
        let renderer = EnhancedTUIRenderer(performanceMonitor: monitor)

        let update = createTestTUIUpdate(
            balances: [
                createTestHolding(asset: "BTC", available: 0.5),
                createTestHolding(asset: "ETH", available: 2.0),
                createTestHolding(asset: "SOL", available: 10.0),
                createTestHolding(asset: "DOGE", available: 1000.0),
                createTestHolding(asset: "ADA", available: 500.0)
            ]
        )

        let prices: [String: Double] = [
            "BTC": 45000.0,
            "ETH": 2500.0,
            "SOL": 100.0,
            "DOGE": 0.1,
            "ADA": 0.5
        ]

        var renderTimes: [Double] = []
        let frameCount = 50

        for _ in 0..<frameCount {
            let startTime = Date()
            _ = await renderer.renderPanels(update, prices: prices, focus: nil)
            let renderTime = Date().timeIntervalSince(startTime) * 1000
            renderTimes.append(renderTime)
        }

        let averageRenderTime = renderTimes.reduce(0, +) / Double(renderTimes.count)
        let maxRenderTime = renderTimes.max() ?? 0

        print("Average render time with prices: \(String(format: "%.2f", averageRenderTime))ms")
        print("Max render time with prices: \(String(format: "%.2f", maxRenderTime))ms")

        #expect(averageRenderTime <= 16.0)
        #expect(maxRenderTime <= 30.0)
    }
}
