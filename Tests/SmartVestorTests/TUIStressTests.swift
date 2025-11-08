import Testing
import Foundation
import Darwin
@testable import SmartVestor
@testable import Core

@Suite("TUI Stress Tests")
struct TUIStressTests {

    @Test("Enhanced TUI should handle rapid updates without memory leaks")
    func testRapidUpdates() async throws {
        let renderer = EnhancedTUIRenderer()
        var memoryBaseline: mach_task_basic_info?

        func getMemoryUsage() -> UInt64? {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)

            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }

            guard result == KERN_SUCCESS else { return nil }
            return info.resident_size
        }

        let initialMemory = getMemoryUsage()

        let update = TUISnapshotTestHelper.createTestUpdate(
            balances: [
                TUISnapshotTestHelper.createTestHolding(asset: "BTC", available: 0.5),
                TUISnapshotTestHelper.createTestHolding(asset: "ETH", available: 2.0)
            ]
        )

        for i in 0..<1000 {
            let updateCopy = TUISnapshotTestHelper.createTestUpdate(
                balances: update.data.balances,
                sequenceNumber: Int64(i)
            )
            let _ = await renderer.renderPanels(updateCopy, prices: nil, focus: nil)

            if i % 100 == 0 {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        let finalMemory = getMemoryUsage()

        if let initial = initialMemory, let final = finalMemory {
            let memoryIncrease = final > initial ? final - initial : 0
            let memoryIncreaseMB = Double(memoryIncrease) / 1_000_000.0

            #expect(memoryIncreaseMB < 100.0, "Memory increased by \(memoryIncreaseMB)MB after 1000 renders")
        }
    }

    @Test("Enhanced TUI should maintain performance under load")
    func testPerformanceUnderLoad() async {
        let renderer = EnhancedTUIRenderer()
        let update = TUISnapshotTestHelper.createTestUpdate(
            balances: (0..<20).map { i in
                TUISnapshotTestHelper.createTestHolding(
                    asset: "ASSET\(i)",
                    available: Double(i) * 0.1
                )
            }
        )

        var renderTimes: [TimeInterval] = []

        for _ in 0..<100 {
            let startTime = Date()
            let _ = await renderer.renderPanels(update, prices: nil, focus: nil)
            let renderTime = Date().timeIntervalSince(startTime)
            renderTimes.append(renderTime)
        }

        let averageTime = renderTimes.reduce(0, +) / Double(renderTimes.count)
        let averageTimeMs = averageTime * 1000

        #expect(averageTimeMs < 100.0, "Average render time: \(averageTimeMs)ms")

        let p95Index = Int(Double(renderTimes.count) * 0.95)
        let sortedTimes = renderTimes.sorted()
        let p95Time = sortedTimes[min(p95Index, sortedTimes.count - 1)]
        let p95TimeMs = p95Time * 1000

        #expect(p95TimeMs < 200.0, "P95 render time: \(p95TimeMs)ms")
    }

    @Test("Enhanced TUI should handle large number of balances efficiently")
    func testLargeBalanceSet() async {
        let renderer = EnhancedTUIRenderer()
        var balances: [Holding] = []

        for i in 0..<100 {
            balances.append(TUISnapshotTestHelper.createTestHolding(
                asset: "ASSET\(i)",
                available: Double(i) * 0.01
            ))
        }

        let update = TUISnapshotTestHelper.createTestUpdate(
            balances: balances,
            totalPortfolioValue: 1000000.0
        )

        let startTime = Date()
        let frame = await renderer.renderPanels(update, prices: nil, focus: nil)
        let renderTime = Date().timeIntervalSince(startTime)

        #expect(!frame.isEmpty)
        #expect(renderTime < 1.0, "Render time: \(renderTime)s")
    }

    @Test("Enhanced TUI should handle concurrent renders safely")
    func testConcurrentRenders() async {
        let renderer = EnhancedTUIRenderer()
        let update = TUISnapshotTestHelper.createTestUpdate(
            balances: [
                TUISnapshotTestHelper.createTestHolding(asset: "BTC", available: 0.5)
            ]
        )

        await withTaskGroup(of: [String].self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await renderer.renderPanels(update, prices: nil, focus: nil)
                }
            }

            var results: [[String]] = []
            for await result in group {
                results.append(result)
            }

            #expect(results.count == 50)
            #expect(results.allSatisfy { !$0.isEmpty })
        }
    }

    @Test("Enhanced TUI should handle frequent price updates")
    func testFrequentPriceUpdates() async {
        let renderer = EnhancedTUIRenderer()
        let balances = [
            TUISnapshotTestHelper.createTestHolding(asset: "BTC", available: 0.5),
            TUISnapshotTestHelper.createTestHolding(asset: "ETH", available: 2.0)
        ]

        let update = TUISnapshotTestHelper.createTestUpdate(balances: balances)

        var renderTimes: [TimeInterval] = []

        for i in 0..<500 {
            let prices = [
                "BTC": 45000.0 + Double(i) * 10.0,
                "ETH": 3000.0 + Double(i) * 5.0
            ]

            let startTime = Date()
            let _ = await renderer.renderPanels(update, prices: prices, focus: nil)
            let renderTime = Date().timeIntervalSince(startTime)
            renderTimes.append(renderTime)
        }

        let averageTime = renderTimes.reduce(0, +) / Double(renderTimes.count)
        let averageTimeMs = averageTime * 1000

        #expect(averageTimeMs < 50.0, "Average render time with prices: \(averageTimeMs)ms")
    }

    @Test("Enhanced TUI should handle rapid focus changes")
    func testRapidFocusChanges() async {
        let renderer = EnhancedTUIRenderer()
        let update = TUISnapshotTestHelper.createTestUpdate()

        let panelTypes: [PanelType] = [.status, .balance, .activity]

        var renderTimes: [TimeInterval] = []

        for i in 0..<200 {
            let panelIndex = i % panelTypes.count
            let focus: PanelFocus = panelIndex == 0 ? .status : (panelIndex == 1 ? .balance : .activity)

            let startTime = Date()
            let _ = await renderer.renderPanels(update, prices: nil, focus: focus)
            let renderTime = Date().timeIntervalSince(startTime)
            renderTimes.append(renderTime)
        }

        let averageTime = renderTimes.reduce(0, +) / Double(renderTimes.count)
        let averageTimeMs = averageTime * 1000

        #expect(averageTimeMs < 50.0, "Average render time with focus: \(averageTimeMs)ms")
    }

    @Test("Enhanced TUI should handle state transitions efficiently")
    func testStateTransitions() async {
        let renderer = EnhancedTUIRenderer()

        var renderTimes: [TimeInterval] = []

        for i in 0..<100 {
            let isRunning = i % 2 == 0
            let update = TUISnapshotTestHelper.createTestUpdate(
                isRunning: isRunning,
                errorCount: i % 10 == 0 ? 5 : 0,
                circuitBreakerOpen: i % 20 == 0,
                sequenceNumber: Int64(i)
            )

            let startTime = Date()
            let _ = await renderer.renderPanels(update, prices: nil, focus: nil)
            let renderTime = Date().timeIntervalSince(startTime)
            renderTimes.append(renderTime)
        }

        let averageTime = renderTimes.reduce(0, +) / Double(renderTimes.count)
        let averageTimeMs = averageTime * 1000

        #expect(averageTimeMs < 50.0, "Average render time for state transitions: \(averageTimeMs)ms")
    }

    @Test("Enhanced TUI should handle mixed data scenarios")
    func testMixedDataScenarios() async {
        let renderer = EnhancedTUIRenderer()

        let scenarios: [(balances: Int, trades: Int, hasPrices: Bool)] = [
            (0, 0, false),
            (1, 0, false),
            (5, 3, true),
            (10, 5, true),
            (20, 10, true)
        ]

        for scenario in scenarios {
            var balances: [Holding] = []
            for i in 0..<scenario.balances {
                balances.append(TUISnapshotTestHelper.createTestHolding(
                    asset: "ASSET\(i)",
                    available: Double(i) * 0.1
                ))
            }

            var trades: [InvestmentTransaction] = []
            for i in 0..<scenario.trades {
                trades.append(TUISnapshotTestHelper.createTestTrade(
                    asset: "ASSET\(i % scenario.balances)",
                    type: i % 2 == 0 ? .buy : .sell
                ))
            }

            let update = TUISnapshotTestHelper.createTestUpdate(
                balances: balances,
                trades: trades
            )

            let prices = scenario.hasPrices ? [
                "BTC": 45000.0,
                "ETH": 3000.0
            ] : nil

            let startTime = Date()
            let frame = await renderer.renderPanels(update, prices: prices, focus: nil)
            let renderTime = Date().timeIntervalSince(startTime)

            #expect(!frame.isEmpty)
            #expect(renderTime < 0.5, "Render time for scenario: \(renderTime)s")
        }
    }
}
