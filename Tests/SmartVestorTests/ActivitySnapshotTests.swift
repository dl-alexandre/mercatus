import Foundation
import Testing
@testable import SmartVestor

@Suite("Activity Panel Snapshot Tests")
struct ActivitySnapshotTests {
    @Test
    func activity_legacy_80x24() async throws {
        unsetenv("SMARTVESTOR_TUI_ACTIVITY_DECLARATIVE")
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        defer {
            unsetenv("SMARTVESTOR_TUI_ACTIVITY_DECLARATIVE")
            unsetenv("SMARTVESTOR_TUI_BUFFER")
        }

        let update = makeActivityUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 15)
        let colorManager = ColorManager()
        let renderer = ActivityPanelRenderer()

        let renderedPanel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false
        )

        let adapter = PanelAdapter(
            panelType: .activity,
            renderedLines: renderedPanel.lines,
            layout: layout
        )

        let size = Size(width: 80, height: 24)
        var buffer = TerminalBuffer.empty(size: size)
        adapter.render(into: &buffer, at: .zero)

        assertSnapshot(buffer: buffer, named: "legacy_activity_80x24", testIdentifier: "activity_legacy_80x24")
    }

    @Test
    func activity_declarative_80x24() async throws {
        setenv("SMARTVESTOR_TUI_ACTIVITY_DECLARATIVE", "1", 1)
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        defer {
            unsetenv("SMARTVESTOR_TUI_ACTIVITY_DECLARATIVE")
            unsetenv("SMARTVESTOR_TUI_BUFFER")
        }

        let update = makeActivityUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 15)
        let colorManager = ColorManager()

        let activityView = ActivityView(
            update: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false
        )
        activityView.buildRows()

        let size = Size(width: 80, height: 24)
        var buffer = TerminalBuffer.empty(size: size)
        activityView.render(into: &buffer, at: .zero)

        assertSnapshot(buffer: buffer, named: "decl_activity_80x24", testIdentifier: "activity_declarative_80x24")
    }

    @Test
    func activity_equivalence_check() async throws {
        let update = makeActivityUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 15)
        let colorManager = ColorManager()
        let size = Size(width: 80, height: 24)

        unsetenv("SMARTVESTOR_TUI_ACTIVITY_DECLARATIVE")
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        let renderer = ActivityPanelRenderer()
        let renderedPanel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false
        )
        let adapter = PanelAdapter(
            panelType: .activity,
            renderedLines: renderedPanel.lines,
            layout: layout
        )
        var legacyBuffer = TerminalBuffer.empty(size: size)
        adapter.render(into: &legacyBuffer, at: .zero)

        setenv("SMARTVESTOR_TUI_ACTIVITY_DECLARATIVE", "1", 1)
        let activityView = ActivityView(
            update: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false
        )
        activityView.buildRows()
        var declBuffer = TerminalBuffer.empty(size: size)
        activityView.render(into: &declBuffer, at: .zero)

        let legacyNormalized = normalizeBufferOutput(legacyBuffer).serializeUTF8()
        let declNormalized = normalizeBufferOutput(declBuffer).serializeUTF8()

        let diff = legacyNormalized != declNormalized
        if diff {
            let legacyPath = snapshotPath(named: "legacy_activity_actual")
            let declPath = snapshotPath(named: "decl_activity_actual")
            try? legacyNormalized.write(to: legacyPath)
            try? declNormalized.write(to: declPath)
            Issue.record("Activity panel equivalence check failed. See .actual files for details.")
        }

        #expect(!diff, "Declarative and legacy should produce equivalent output")
    }

    @Test
    func activity_empty_state() async throws {
        setenv("SMARTVESTOR_TUI_ACTIVITY_DECLARATIVE", "1", 1)
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        defer {
            unsetenv("SMARTVESTOR_TUI_ACTIVITY_DECLARATIVE")
            unsetenv("SMARTVESTOR_TUI_BUFFER")
        }

        let emptyUpdate = TUIUpdate(
            type: .heartbeat,
            state: AutomationState(
                isRunning: false,
                mode: .continuous,
                startedAt: nil,
                lastExecutionTime: nil,
                nextExecutionTime: nil,
                pid: nil
            ),
            data: TUIData(
                recentTrades: [],
                balances: [],
                circuitBreakerOpen: false,
                lastExecutionTime: nil,
                nextExecutionTime: nil,
                totalPortfolioValue: 0,
                errorCount: 0
            ),
            sequenceNumber: 0
        )

        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 15)
        let colorManager = ColorManager()

        let activityView = ActivityView(
            update: emptyUpdate,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )
        activityView.buildRows()

        let size = Size(width: 80, height: 24)
        var buffer = TerminalBuffer.empty(size: size)
        activityView.render(into: &buffer, at: .zero)

        assertSnapshot(buffer: buffer, named: "decl_activity_empty_80x24", testIdentifier: "activity_empty_state")
    }
}

private func makeActivityUpdate() -> TUIUpdate {
    let now = Date()
    let transactions = [
        InvestmentTransaction(
            id: UUID(),
            type: .buy,
            exchange: "robinhood",
            asset: "BTC",
            quantity: 0.01,
            price: 45000.0,
            fee: 0.5,
            timestamp: now.addingTimeInterval(-3600)
        ),
        InvestmentTransaction(
            id: UUID(),
            type: .sell,
            exchange: "robinhood",
            asset: "ETH",
            quantity: 0.5,
            price: 3000.0,
            fee: 0.3,
            timestamp: now.addingTimeInterval(-7200)
        ),
        InvestmentTransaction(
            id: UUID(),
            type: .deposit,
            exchange: "robinhood",
            asset: "USDC",
            quantity: 1000.0,
            price: 1.0,
            fee: 0.0,
            timestamp: now.addingTimeInterval(-10800)
        )
    ]

    return TUIUpdate(
        type: .heartbeat,
        state: AutomationState(
            isRunning: true,
            mode: .continuous,
            startedAt: Date(),
            lastExecutionTime: Date(),
            nextExecutionTime: Date().addingTimeInterval(60),
            pid: nil
        ),
        data: TUIData(
            recentTrades: transactions,
            balances: [],
            circuitBreakerOpen: false,
            lastExecutionTime: Date(),
            nextExecutionTime: Date().addingTimeInterval(60),
            totalPortfolioValue: 50000.0,
            errorCount: 0
        ),
        sequenceNumber: 100
    )
}
