import Testing
import Foundation
@testable import SmartVestor
@testable import Core

@Suite("TUI Snapshot Tests")
struct SnapshotTests {

    @Test("Enhanced TUI should render consistent snapshot for small terminal")
    func testSmallTerminalSnapshot() async {
        let renderer = EnhancedTUIRenderer()
        let update = TUISnapshotTestHelper.createTestUpdate(
            isRunning: true,
            balances: [
                TUISnapshotTestHelper.createTestHolding(asset: "BTC", available: 0.5)
            ]
        )

        let frame = await TUISnapshotTestHelper.captureSnapshot(
            renderer: renderer,
            update: update
        )

        #expect(!frame.isEmpty)
        #expect(frame.contains { $0.contains("SmartVestor") || $0.contains("RUNNING") || $0.contains("STOPPED") })
    }

    @Test("Enhanced TUI should render consistent snapshot for medium terminal")
    func testMediumTerminalSnapshot() async {
        let renderer = EnhancedTUIRenderer()
        let balances = [
            TUISnapshotTestHelper.createTestHolding(asset: "BTC", available: 0.5),
            TUISnapshotTestHelper.createTestHolding(asset: "ETH", available: 2.0),
            TUISnapshotTestHelper.createTestHolding(asset: "SOL", available: 10.0)
        ]

        let update = TUISnapshotTestHelper.createTestUpdate(
            balances: balances,
            totalPortfolioValue: 50000.0
        )

        let frame = await TUISnapshotTestHelper.captureSnapshot(
            renderer: renderer,
            update: update
        )

        #expect(!frame.isEmpty)
    }

    @Test("Enhanced TUI should render consistent snapshot with prices")
    func testSnapshotWithPrices() async {
        let renderer = EnhancedTUIRenderer()
        let balances = [
            TUISnapshotTestHelper.createTestHolding(asset: "BTC", available: 0.5),
            TUISnapshotTestHelper.createTestHolding(asset: "ETH", available: 2.0)
        ]

        let update = TUISnapshotTestHelper.createTestUpdate(balances: balances)
        let prices = ["BTC": 45000.0, "ETH": 3000.0]

        let frame = await TUISnapshotTestHelper.captureSnapshot(
            renderer: renderer,
            update: update,
            prices: prices
        )

        #expect(!frame.isEmpty)
    }

    @Test("Enhanced TUI should render consistent snapshot for stopped state")
    func testStoppedStateSnapshot() async {
        let renderer = EnhancedTUIRenderer()
        let update = TUISnapshotTestHelper.createTestUpdate(
            isRunning: false,
            errorCount: 5,
            circuitBreakerOpen: true
        )

        let frame = await TUISnapshotTestHelper.captureSnapshot(
            renderer: renderer,
            update: update
        )

        #expect(!frame.isEmpty)
        let frameText = frame.joined(separator: "\n")
        #expect(frameText.contains("STOPPED") || frameText.contains("Stopped"))
    }

    @Test("Enhanced TUI should render consistent snapshot with trades")
    func testSnapshotWithTrades() async {
        let renderer = EnhancedTUIRenderer()
        let trades = [
            TUISnapshotTestHelper.createTestTrade(asset: "BTC", type: .buy, quantity: 0.1),
            TUISnapshotTestHelper.createTestTrade(asset: "ETH", type: .sell, quantity: 1.0)
        ]

        let update = TUISnapshotTestHelper.createTestUpdate(trades: trades)

        let frame = await TUISnapshotTestHelper.captureSnapshot(
            renderer: renderer,
            update: update
        )

        #expect(!frame.isEmpty)
    }

    @Test("Enhanced TUI should render consistent snapshot with empty data")
    func testEmptyDataSnapshot() async {
        let renderer = EnhancedTUIRenderer()
        let update = TUISnapshotTestHelper.createTestUpdate(
            balances: [],
            trades: [],
            totalPortfolioValue: 0.0
        )

        let frame = await TUISnapshotTestHelper.captureSnapshot(
            renderer: renderer,
            update: update
        )

        #expect(!frame.isEmpty)
    }

    @Test("Enhanced TUI should render consistent snapshot with many balances")
    func testManyBalancesSnapshot() async {
        let renderer = EnhancedTUIRenderer()
        var balances: [Holding] = []

        for (index, asset) in ["BTC", "ETH", "SOL", "ADA", "DOT", "LINK", "UNI", "AAVE"].enumerated() {
            balances.append(TUISnapshotTestHelper.createTestHolding(
                asset: asset,
                available: Double(index + 1) * 0.1
            ))
        }

        let update = TUISnapshotTestHelper.createTestUpdate(
            balances: balances,
            totalPortfolioValue: 100000.0
        )

        let frame = await TUISnapshotTestHelper.captureSnapshot(
            renderer: renderer,
            update: update
        )

        #expect(!frame.isEmpty)
    }

    @Test("Enhanced TUI should render consistent snapshot with focus state")
    func testFocusedPanelSnapshot() async {
        let renderer = EnhancedTUIRenderer()
        let update = TUISnapshotTestHelper.createTestUpdate()
        let focus: PanelFocus = .status

        let frame = await TUISnapshotTestHelper.captureSnapshot(
            renderer: renderer,
            update: update,
            prices: nil,
            focus: focus
        )

        #expect(!frame.isEmpty)
    }
}
