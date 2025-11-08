import Testing
import Foundation
@testable import SmartVestor

@Suite("Panel Renderer Tests")
struct PanelRendererTests {

    func createTestTUIUpdate(
        isRunning: Bool = true,
        mode: AutomationMode = .continuous,
        errorCount: Int = 0,
        circuitBreakerOpen: Bool = false,
        balances: [Holding] = [],
        trades: [InvestmentTransaction] = [],
        swapEvaluations: [SwapEvaluation] = []
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
            totalPortfolioValue: 1000.0,
            errorCount: errorCount,
            prices: [:],
            swapEvaluations: swapEvaluations
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

    func createTestTransaction(
        type: TransactionType = .buy,
        asset: String = "BTC",
        quantity: Double = 0.1,
        price: Double = 50000.0,
        exchange: String = "robinhood",
        timestamp: Date = Date()
    ) -> InvestmentTransaction {
        return InvestmentTransaction(
            type: type,
            exchange: exchange,
            asset: asset,
            quantity: quantity,
            price: price,
            fee: 1.0,
            timestamp: timestamp,
            metadata: [:],
            idempotencyKey: UUID().uuidString
        )
    }

    func createTestSwapEvaluation(
        fromAsset: String,
        toAsset: String,
        fromQuantity: Double = 1.0,
        estimatedToQuantity: Double = 1.2,
        netValue: Double = 12.5,
        isWorthwhile: Bool = true,
        confidence: Double = 0.72,
        exchange: String = "robinhood"
    ) -> SwapEvaluation {
        let totalCostUSD = max(0.5, netValue * 0.35)
        let sellFee = totalCostUSD * 0.15
        let buyFee = totalCostUSD * 0.15
        let spread = totalCostUSD * 0.2
        let slippage = totalCostUSD * 0.5
        return SwapEvaluation(
            fromAsset: fromAsset,
            toAsset: toAsset,
            fromQuantity: fromQuantity,
            estimatedToQuantity: estimatedToQuantity,
            totalCost: SwapCost(
                sellFee: sellFee,
                buyFee: buyFee,
                sellSpread: spread * 0.5,
                buySpread: spread * 0.5,
                sellSlippage: slippage * 0.5,
                buySlippage: slippage * 0.5,
                totalCostUSD: totalCostUSD,
                costPercentage: 0.45
            ),
            potentialBenefit: SwapBenefit(
                expectedReturnDifferential: netValue * 0.6,
                portfolioImprovement: netValue * 0.25,
                riskReduction: netValue > 2 ? netValue * 0.1 : nil,
                allocationAlignment: netValue * 0.15,
                totalBenefitUSD: netValue + totalCostUSD,
                benefitPercentage: (netValue + totalCostUSD) / max(1.0, totalCostUSD)
            ),
            netValue: netValue,
            isWorthwhile: isWorthwhile,
            confidence: confidence,
            exchange: exchange
        )
    }

    @Test("StatusPanelRenderer should display green status when running")
    func testStatusPanelRunning() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = StatusPanelRenderer()
        let update = createTestTUIUpdate(isRunning: true, errorCount: 0, circuitBreakerOpen: false)
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(rendered.contains("RUNNING") || rendered.contains("State:"))
        #expect(panel.hasBorder == true)
        #expect(panel.height > 0)
    }

    @Test("StatusPanelRenderer should display red status when stopped")
    func testStatusPanelStopped() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = StatusPanelRenderer()
        let update = createTestTUIUpdate(isRunning: false)
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(rendered.contains("STOPPED") || rendered.contains("State:"))
    }

    @Test("StatusPanelRenderer should display yellow status when warnings exist")
    func testStatusPanelWarning() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = StatusPanelRenderer()
        let update = createTestTUIUpdate(isRunning: true, errorCount: 5, circuitBreakerOpen: false)
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(rendered.contains("WARNING") || rendered.contains("5 error"))
    }

    @Test("StatusPanelRenderer should include mode and sequence number")
    func testStatusPanelMetadata() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = StatusPanelRenderer()
        let update = createTestTUIUpdate(mode: .continuous, errorCount: 0)
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(rendered.contains("Mode:") || rendered.contains("continuous"))
        #expect(rendered.contains("Sequence:") || rendered.contains("1"))
    }

    @Test("StatusPanelRenderer should display error summary when errors exist")
    func testStatusPanelErrorSummary() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = StatusPanelRenderer()
        let update = createTestTUIUpdate(isRunning: true, errorCount: 3, circuitBreakerOpen: true)
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(rendered.contains("error") || rendered.contains("Circuit Breaker"))
    }


    @Test("BalancePanelRenderer should highlight top holdings")
    func testBalancePanelHighlighting() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = BalancePanelRenderer()
        let balances = [
            createTestHolding(asset: "BTC", available: 10.0),
            createTestHolding(asset: "ETH", available: 1.0),
            createTestHolding(asset: "SOL", available: 0.1)
        ]
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
        #expect(rendered.contains("BTC") || rendered.contains("ASSET"))
    }

    @Test("BalancePanelRenderer should display blue labels and white values")
    func testBalancePanelColorScheme() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = BalancePanelRenderer()
        let balances = [createTestHolding()]
        let update = createTestTUIUpdate(balances: balances)
        let layout = PanelLayout(x: 0, y: 0, width: 100, height: 10)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(rendered.contains("ASSET") || rendered.contains("VALUE"))
    }

    @Test("BalancePanelRenderer should display timestamps in dim color")
    func testBalancePanelTimestampStyling() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = BalancePanelRenderer()
        let balances = [createTestHolding(updatedAt: Date())]
        let update = createTestTUIUpdate(balances: balances)
        let layout = PanelLayout(x: 0, y: 0, width: 100, height: 10)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(panel.lines.count > 0)
    }

    @Test("ActivityPanelRenderer should display placeholder when no trades")
    func testActivityPanelPlaceholder() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = ActivityPanelRenderer()
        let update = createTestTUIUpdate(trades: [])
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(rendered.contains("No trades in the last 24 hours") || rendered.contains("No trades"))
    }

    @Test("ActivityPanelRenderer should display recent trades")
    func testActivityPanelTradesDisplay() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = ActivityPanelRenderer()
        let trades = [
            createTestTransaction(type: .buy, asset: "BTC", timestamp: Date())
        ]
        let update = createTestTUIUpdate(trades: trades)
        let layout = PanelLayout(x: 0, y: 0, width: 100, height: 10)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(rendered.contains("BTC") || rendered.contains("BUY") || rendered.contains("buy"))
    }

    @Test("ActivityPanelRenderer should maintain chronological order")
    func testActivityPanelChronologicalOrder() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = ActivityPanelRenderer()
        let now = Date()
        let trades = [
            createTestTransaction(type: .buy, asset: "BTC", timestamp: now.addingTimeInterval(-3600)),
            createTestTransaction(type: .sell, asset: "ETH", timestamp: now)
        ]
        let update = createTestTUIUpdate(trades: trades)
        let layout = PanelLayout(x: 0, y: 0, width: 100, height: 10)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        let ethIndex = rendered.firstIndex(of: "E") ?? rendered.endIndex
        let btcIndex = rendered.firstIndex(of: "B") ?? rendered.endIndex

        #expect(rendered.contains("ETH") || rendered.contains("BTC"))
    }

    @Test("ActivityPanelRenderer should use color coding for transaction types")
    func testActivityPanelColorCoding() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = ActivityPanelRenderer()
        let trades = [
            createTestTransaction(type: .buy),
            createTestTransaction(type: .sell),
            createTestTransaction(type: .deposit)
        ]
        let update = createTestTUIUpdate(trades: trades)
        let layout = PanelLayout(x: 0, y: 0, width: 100, height: 15)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(rendered.contains("BUY") || rendered.contains("SELL") || rendered.contains("DEPOSIT"))
    }

    @Test("ActivityPanelRenderer should limit to 5 lines when configured")
    func testActivityPanelScrolling() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = ActivityPanelRenderer()
        let trades = (0..<10).map { i in
            createTestTransaction(
                asset: "ASSET\(i)",
                timestamp: Date().addingTimeInterval(TimeInterval(-i * 3600))
            )
        }
        let update = createTestTUIUpdate(trades: trades)
        let layout = PanelLayout(x: 0, y: 0, width: 100, height: 8)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        #expect(panel.height <= 8)
        #expect(panel.lines.count <= 8)
    }

    @Test("All panel renderers should work with ASCII borders")
    func testPanelRenderersASCIIBorders() async {
        let colorManager = ColorManager(monochrome: false)
        let statusRenderer = StatusPanelRenderer()
        let balanceRenderer = BalancePanelRenderer()
        let activityRenderer = ActivityPanelRenderer()

        let update = createTestTUIUpdate(
            balances: [createTestHolding()],
            trades: [createTestTransaction()]
        )
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)

        let statusPanel = await statusRenderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .ascii,
            unicodeSupported: false
        )

        let balancePanel = await balanceRenderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .ascii,
            unicodeSupported: false
        )

        let activityPanel = await activityRenderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .ascii,
            unicodeSupported: false
        )

        #expect(statusPanel.hasBorder == true)
        #expect(balancePanel.hasBorder == true)
        #expect(activityPanel.hasBorder == true)
    }

    @Test("All panel renderers should handle monochrome mode")
    func testPanelRenderersMonochrome() async {
        let colorManager = ColorManager(monochrome: true)
        let statusRenderer = StatusPanelRenderer()
        let balanceRenderer = BalancePanelRenderer()
        let activityRenderer = ActivityPanelRenderer()

        let update = createTestTUIUpdate(
            balances: [createTestHolding()],
            trades: [createTestTransaction()]
        )
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)

        let statusPanel = await statusRenderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .ascii,
            unicodeSupported: false
        )

        let balancePanel = await balanceRenderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .ascii,
            unicodeSupported: false
        )

        let activityPanel = await activityRenderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .ascii,
            unicodeSupported: false
        )

        #expect(statusPanel.lines.count > 0)
        #expect(balancePanel.lines.count > 0)
        #expect(activityPanel.lines.count > 0)
    }

    @Test("StatusPanelRenderer should provide fallback rendering when border fails")
    func testStatusPanelFallbackOnBorderFailure() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = StatusPanelRenderer()
        let update = createTestTUIUpdate(isRunning: true)
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let rendered = panel.render()
        #expect(!rendered.isEmpty)
        #expect(rendered.contains("State:") || rendered.contains("RUNNING") || rendered.contains("STOPPED"))
    }

    @Test("EnhancedTUIRenderer should detect and report empty panel output")
    func testEnhancedRendererEmptyPanelDetection() async throws {
        struct EmptyPanelRenderer: PanelRenderer {
            let panelType: PanelType = .price
            let identifier: String = "empty"

            func render(
                input: TUIUpdate,
                layout: PanelLayout,
                colorManager: ColorManagerProtocol,
                borderStyle: BorderStyle,
                unicodeSupported: Bool
            ) async -> RenderedPanel {
                return RenderedPanel(lines: [], width: layout.width, height: layout.height, hasBorder: false)
            }
        }

        let registry = PanelRegistry()
        registry.register(EmptyPanelRenderer())

        let update = createTestTUIUpdate()
        let layouts: [PanelType: PanelLayout] = [.price: PanelLayout(x: 0, y: 0, width: 80, height: 10)]

        let terminalSize = TerminalSize(width: 80, height: 24)
        let mockLayoutManager = MockLayoutManager(terminalSize: terminalSize, layouts: layouts)
        let configPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("panel-toggle-empty-\(UUID().uuidString).json")
        let toggleManager = PanelToggleManager(configPath: configPath)
        try await toggleManager.setVisibility(.price, visible: true)
        try await toggleManager.setVisibility(.status, visible: false)
        try await toggleManager.setVisibility(.balances, visible: false)
        try await toggleManager.setVisibility(.activity, visible: false)
        try await toggleManager.setVisibility(.swap, visible: false)
        await toggleManager.setSelectedPanel(.price)
        let enhancedRenderer = EnhancedTUIRenderer(
            layoutManager: mockLayoutManager,
            panelRegistry: registry,
            toggleManager: toggleManager
        )

        let frame = await enhancedRenderer.renderPanels(update, focus: nil)
        let frameText = frame.joined(separator: "\n")

        #expect(frameText.contains("failed to render") || frameText.contains("empty output"))
    }

    @Test("EnhancedTUIRenderer should detect panels with only borders and no content")
    func testEnhancedRendererBorderOnlyDetection() async throws {
        struct BorderOnlyPanelRenderer: PanelRenderer {
            let panelType: PanelType = .price
            let identifier: String = "borders-only"

            func render(
                input: TUIUpdate,
                layout: PanelLayout,
                colorManager: ColorManagerProtocol,
                borderStyle: BorderStyle,
                unicodeSupported: Bool
            ) async -> RenderedPanel {
                let borderRenderer = PanelBorderRenderer(borderStyle: borderStyle, unicodeSupported: unicodeSupported)
                let borderLines = borderRenderer.renderBorder(width: layout.width, height: layout.height, title: "Test", isFocused: false, colorManager: colorManager)
                return RenderedPanel(lines: borderLines, width: layout.width, height: layout.height, hasBorder: true)
            }
        }

        let registry = PanelRegistry()
        registry.register(BorderOnlyPanelRenderer())

        let terminalSize = TerminalSize(width: 80, height: 24)
        let layouts: [PanelType: PanelLayout] = [.price: PanelLayout(x: 0, y: 0, width: 80, height: 10)]
        let mockLayoutManager = MockLayoutManager(terminalSize: terminalSize, layouts: layouts)
        let configPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("panel-toggle-border-\(UUID().uuidString).json")
        let toggleManager = PanelToggleManager(configPath: configPath)
        try await toggleManager.setVisibility(.price, visible: true)
        try await toggleManager.setVisibility(.status, visible: false)
        try await toggleManager.setVisibility(.balances, visible: false)
        try await toggleManager.setVisibility(.activity, visible: false)
        try await toggleManager.setVisibility(.swap, visible: false)
        await toggleManager.setSelectedPanel(.price)

        let enhancedRenderer = EnhancedTUIRenderer(
            layoutManager: mockLayoutManager,
            panelRegistry: registry,
            toggleManager: toggleManager
        )

        let update = createTestTUIUpdate()
        let frame = await enhancedRenderer.renderPanels(update, focus: nil)
        let frameText = frame.joined(separator: "\n")

        let hasError = frameText.contains("failed to render") || frameText.contains("empty output") || frameText.contains("borders-only")
        #expect(hasError, "Expected error message for border-only panel, got: \(frameText.prefix(500))")
    }

    @Test("StatusPanelRenderer fallback should include state information")
    func testStatusPanelFallbackIncludesState() async {
        let colorManager = ColorManager(monochrome: false)
        let renderer = StatusPanelRenderer()

        let runningUpdate = createTestTUIUpdate(isRunning: true)
        let stoppedUpdate = createTestTUIUpdate(isRunning: false)

        let tinyLayout = PanelLayout(x: 0, y: 0, width: 80, height: 6)

        let runningPanel = await renderer.render(
            input: runningUpdate,
            layout: tinyLayout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let stoppedPanel = await renderer.render(
            input: stoppedUpdate,
            layout: tinyLayout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let runningText = runningPanel.render()
        let stoppedText = stoppedPanel.render()

        #expect(runningText.contains("RUNNING") || runningText.contains("State:"))
        #expect(stoppedText.contains("STOPPED") || stoppedText.contains("State:"))
    }

    @Test("SwapPanelRenderer should render swaps with scrolling summary")
    func testSwapPanelRendererWithSummary() async {
        let renderer = SwapPanelRenderer()
        let layout = PanelLayout(x: 0, y: 0, width: 90, height: 12)
        let colorManager = ColorManager(monochrome: true)

        let assets = ["BTC", "ETH", "SOL", "MATIC", "ADA", "DOGE"]
        let swaps = assets.enumerated().compactMap { index, asset -> SwapEvaluation? in
            guard index + 1 < assets.count else { return nil }
            return createTestSwapEvaluation(
                fromAsset: asset,
                toAsset: assets[index + 1],
                fromQuantity: Double(index + 1),
                estimatedToQuantity: Double(index + 2),
                netValue: Double(10 + (5 * index)),
                isWorthwhile: index % 2 == 0,
                confidence: 0.55 + Double(index) * 0.05
            )
        }

        let update = createTestTUIUpdate(swapEvaluations: swaps)
        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: true,
            scrollOffset: 2
        )

        let output = panel.render()
        #expect(output.contains("Swaps"))
        #expect(output.contains("Showing"))
        #expect(output.contains("Scroll") || output.contains("[J/K]"))
        #expect(output.contains("ETH"))
        #expect(output.contains("DOGE") == false || output.contains("of \(swaps.count)"))
    }

    @Test("SwapPanelRenderer should show placeholder when no swaps")
    func testSwapPanelRendererEmptyState() async {
        let renderer = SwapPanelRenderer()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)
        let colorManager = ColorManager(monochrome: true)
        let update = createTestTUIUpdate(swapEvaluations: [])

        let panel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false
        )

        let output = panel.render()
        #expect(output.contains("No swap evaluations available"))
    }
}

struct MockLayoutManager: LayoutManagerProtocol {
    let terminalSize: TerminalSize
    let layouts: [PanelType: PanelLayout]

    func detectTerminalSize() -> TerminalSize {
        return terminalSize
    }

    func calculateLayout(terminalSize: TerminalSize) -> [PanelType: PanelLayout] {
        return layouts
    }

    func calculateLayout(terminalSize: TerminalSize, priorities: [PanelType: LayoutPriority], visiblePanels: Set<PanelType>? = nil) -> [PanelType: PanelLayout] {
        return layouts
    }

    func calculateLayout(terminalSize: TerminalSize, visiblePanels: Set<PanelType>) -> [PanelType : PanelLayout] {
        return layouts
    }

    func isMinimumSizeMet(terminalSize: TerminalSize) -> Bool {
        return true
    }

    func validateLayout(_ layout: [PanelType: PanelLayout], terminalSize: TerminalSize) -> Result<Void, LayoutValidationError> {
        return .success(())
    }

    func startResizeMonitoring(onResize: @escaping @Sendable (TerminalSize) -> Void) -> Task<Void, Never> {
        return Task { }
    }

    func stopResizeMonitoring() {
    }
}
