import Testing
import Foundation
@testable import SmartVestor

@Suite("Sparkline Integration Tests")
struct SparklineIntegrationTests {

    @Test("SparklineConfig should have sensible defaults")
    func testSparklineConfigDefaults() {
        let config = SparklineConfig.default
        #expect(config.enabled == true)
        #expect(config.showPortfolioHistory == true)
        #expect(config.showAssetTrends == true)
        #expect(config.historyLength >= 10 && config.historyLength <= 1000)
        #expect(config.sparklineWidth >= 5 && config.sparklineWidth <= 100)
        #expect(config.minHeight >= 1 && config.minHeight <= 8)
        #expect(config.maxHeight >= config.minHeight && config.maxHeight <= 8)
    }

    @Test("SparklineConfig should validate historyLength bounds")
    func testSparklineConfigHistoryLengthBounds() {
        let configTooSmall = SparklineConfig(historyLength: 5)
        #expect(configTooSmall.historyLength == 10)

        let configTooLarge = SparklineConfig(historyLength: 2000)
        #expect(configTooLarge.historyLength == 1000)

        let configValid = SparklineConfig(historyLength: 100)
        #expect(configValid.historyLength == 100)
    }

    @Test("SparklineConfig should validate sparklineWidth bounds")
    func testSparklineConfigWidthBounds() {
        let configTooSmall = SparklineConfig(sparklineWidth: 3)
        #expect(configTooSmall.sparklineWidth == 5)

        let configTooLarge = SparklineConfig(sparklineWidth: 200)
        #expect(configTooLarge.sparklineWidth == 100)

        let configValid = SparklineConfig(sparklineWidth: 20)
        #expect(configValid.sparklineWidth == 20)
    }

    @Test("SparklineConfig should validate height bounds")
    func testSparklineConfigHeightBounds() {
        let configInvalidMin = SparklineConfig(minHeight: 0, maxHeight: 4)
        #expect(configInvalidMin.minHeight == 1)

        let configInvalidMax = SparklineConfig(minHeight: 1, maxHeight: 10)
        #expect(configInvalidMax.maxHeight == 8)

        let configReversed = SparklineConfig(minHeight: 5, maxHeight: 3)
        #expect(configReversed.maxHeight >= configReversed.minHeight)
    }

    @Test("SparklineConfig disabled should disable all features")
    func testSparklineConfigDisabled() {
        let config = SparklineConfig.disabled
        #expect(config.enabled == false)
        #expect(config.showPortfolioHistory == false)
        #expect(config.showAssetTrends == false)
    }

    @Test("SparklineHistoryTracker should track portfolio values")
    func testHistoryTrackerPortfolioTracking() {
        let config = SparklineConfig(historyLength: 10)
        let tracker = SparklineHistoryTracker(config: config)

        tracker.updatePortfolioValue(1000.0)
        tracker.updatePortfolioValue(1100.0)
        tracker.updatePortfolioValue(1200.0)

        let history = tracker.getPortfolioHistory()
        #expect(history.count == 3)
        #expect(history[0] == 1000.0)
        #expect(history[1] == 1100.0)
        #expect(history[2] == 1200.0)
    }

    @Test("SparklineHistoryTracker should track asset prices")
    func testHistoryTrackerAssetTracking() {
        let config = SparklineConfig(historyLength: 10)
        let tracker = SparklineHistoryTracker(config: config)

        tracker.updateAssetPrice("BTC", price: 50000.0)
        tracker.updateAssetPrice("BTC", price: 51000.0)
        tracker.updateAssetPrice("ETH", price: 3000.0)

        let btcHistory = tracker.getAssetHistory("BTC")
        #expect(btcHistory.count == 2)
        #expect(btcHistory[0] == 50000.0)
        #expect(btcHistory[1] == 51000.0)

        let ethHistory = tracker.getAssetHistory("ETH")
        #expect(ethHistory.count == 1)
        #expect(ethHistory[0] == 3000.0)
    }

    @Test("SparklineHistoryTracker should prune history when exceeding length")
    func testHistoryTrackerPruning() {
        let targetLength = 10
        let config = SparklineConfig(historyLength: targetLength)
        let tracker = SparklineHistoryTracker(config: config)

        let effectiveLength = config.historyLength
        let itemsToAdd = effectiveLength + 5

        for i in 1...itemsToAdd {
            tracker.updatePortfolioValue(Double(i) * 100.0)
        }

        let history = tracker.getPortfolioHistory()
        #expect(history.count == effectiveLength)

        let expectedEnd = Double(itemsToAdd)
        #expect(history.last! == expectedEnd * 100.0)

        let expectedStart = Double(itemsToAdd - effectiveLength + 1)
        #expect(history.first! == expectedStart * 100.0)
    }

    @Test("SparklineHistoryTracker should respect enabled flag for portfolio")
    func testHistoryTrackerEnabledFlagPortfolio() {
        let config = SparklineConfig(enabled: false, showPortfolioHistory: true)
        let tracker = SparklineHistoryTracker(config: config)

        tracker.updatePortfolioValue(1000.0)

        let history = tracker.getPortfolioHistory()
        #expect(history.isEmpty)
    }

    @Test("SparklineHistoryTracker should respect enabled flag for assets")
    func testHistoryTrackerEnabledFlagAssets() {
        let config = SparklineConfig(enabled: false, showAssetTrends: true)
        let tracker = SparklineHistoryTracker(config: config)

        tracker.updateAssetPrice("BTC", price: 50000.0)

        let history = tracker.getAssetHistory("BTC")
        #expect(history.isEmpty)
    }

    @Test("SparklineHistoryTracker should respect showPortfolioHistory flag")
    func testHistoryTrackerShowPortfolioFlag() {
        let config = SparklineConfig(enabled: true, showPortfolioHistory: false)
        let tracker = SparklineHistoryTracker(config: config)

        tracker.updatePortfolioValue(1000.0)

        let history = tracker.getPortfolioHistory()
        #expect(history.isEmpty)
    }

    @Test("SparklineHistoryTracker should respect showAssetTrends flag")
    func testHistoryTrackerShowAssetTrendsFlag() {
        let config = SparklineConfig(enabled: true, showAssetTrends: false)
        let tracker = SparklineHistoryTracker(config: config)

        tracker.updateAssetPrice("BTC", price: 50000.0)

        let history = tracker.getAssetHistory("BTC")
        #expect(history.isEmpty)
    }

    @Test("SparklineHistoryTracker clear should remove all history")
    func testHistoryTrackerClear() {
        let tracker = SparklineHistoryTracker()

        tracker.updatePortfolioValue(1000.0)
        tracker.updateAssetPrice("BTC", price: 50000.0)

        #expect(!tracker.getPortfolioHistory().isEmpty)
        #expect(!tracker.getAssetHistory("BTC").isEmpty)

        tracker.clear()

        #expect(tracker.getPortfolioHistory().isEmpty)
        #expect(tracker.getAssetHistory("BTC").isEmpty)
    }

    @Test("BalancePanelRenderer should display portfolio sparkline when enabled")
    func testBalancePanelPortfolioSparkline() async {
        let config = SparklineConfig(showPortfolioHistory: true)
        let tracker = SparklineHistoryTracker(config: config)

        tracker.updatePortfolioValue(1000.0)
        tracker.updatePortfolioValue(1100.0)
        tracker.updatePortfolioValue(1200.0)

        let colorManager = ColorManager(monochrome: false)
        let renderer = BalancePanelRenderer(
            sparklineConfig: config,
            historyTracker: tracker
        )

        let update = createTestTUIUpdate(totalPortfolioValue: 1300.0)
        let layout = PanelLayout(x: 0, y: 0, width: 100, height: 15)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(rendered.contains("Portfolio:"))
    }

    @Test("BalancePanelRenderer should not display portfolio sparkline when disabled")
    func testBalancePanelNoPortfolioSparkline() async {
        let config = SparklineConfig(showPortfolioHistory: false)
        let tracker = SparklineHistoryTracker(config: config)

        let colorManager = ColorManager(monochrome: false)
        let renderer = BalancePanelRenderer(
            sparklineConfig: config,
            historyTracker: tracker
        )

        let update = createTestTUIUpdate(totalPortfolioValue: 1000.0)
        let layout = PanelLayout(x: 0, y: 0, width: 100, height: 15)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(!rendered.contains("Portfolio:"))
    }

    @Test("BalancePanelRenderer should display asset sparklines when enabled")
    func testBalancePanelAssetSparklines() async {
        let config = SparklineConfig(showAssetTrends: true, sparklineWidth: 10)
        let tracker = SparklineHistoryTracker(config: config)

        tracker.updateAssetPrice("BTC", price: 50000.0)
        tracker.updateAssetPrice("BTC", price: 51000.0)

        let colorManager = ColorManager(monochrome: false)
        let renderer = BalancePanelRenderer(
            sparklineConfig: config,
            historyTracker: tracker
        )

        let balances = [createTestHolding(asset: "BTC", available: 0.5)]
        let update = createTestTUIUpdate(balances: balances)
        let layout = PanelLayout(x: 0, y: 0, width: 120, height: 15)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(rendered.contains("TREND"))
    }

    @Test("BalancePanelRenderer should not display asset sparklines when disabled")
    func testBalancePanelNoAssetSparklines() async {
        let config = SparklineConfig(showAssetTrends: false)
        let tracker = SparklineHistoryTracker(config: config)

        let colorManager = ColorManager(monochrome: false)
        let renderer = BalancePanelRenderer(
            sparklineConfig: config,
            historyTracker: tracker
        )

        let balances = [createTestHolding(asset: "BTC", available: 0.5)]
        let update = createTestTUIUpdate(balances: balances)
        let layout = PanelLayout(x: 0, y: 0, width: 100, height: 15)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(!rendered.contains("TREND"))
    }

    @Test("BalancePanelRenderer should handle empty history gracefully")
    func testBalancePanelEmptyHistory() async {
        let config = SparklineConfig(showPortfolioHistory: true, showAssetTrends: true)
        let tracker = SparklineHistoryTracker(config: config)

        let colorManager = ColorManager(monochrome: false)
        let renderer = BalancePanelRenderer(
            sparklineConfig: config,
            historyTracker: tracker
        )

        let balances = [createTestHolding(asset: "BTC", available: 0.5)]
        let update = createTestTUIUpdate(balances: balances)
        let layout = PanelLayout(x: 0, y: 0, width: 100, height: 15)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        #expect(panel.lines.count > 0)
    }

    @Test("BalancePanelRenderer should work with ASCII sparklines")
    func testBalancePanelASCIISparklines() async {
        let config = SparklineConfig(showAssetTrends: true, sparklineWidth: 10)
        let tracker = SparklineHistoryTracker(config: config)

        tracker.updateAssetPrice("BTC", price: 50000.0)
        tracker.updateAssetPrice("BTC", price: 51000.0)

        let colorManager = ColorManager(monochrome: false)
        let renderer = BalancePanelRenderer(
            sparklineConfig: config,
            historyTracker: tracker
        )

        let balances = [createTestHolding(asset: "BTC", available: 0.5)]
        let update = createTestTUIUpdate(balances: balances)
        let layout = PanelLayout(x: 0, y: 0, width: 120, height: 15)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: false
        )

        let rendered = panel.render()
        #expect(rendered.contains("TREND"))
    }

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
}
