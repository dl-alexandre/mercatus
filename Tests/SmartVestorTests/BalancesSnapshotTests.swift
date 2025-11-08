import Foundation
import Testing
@testable import SmartVestor

@Suite("Balances Panel Snapshot Tests")
struct BalancesSnapshotTests {
    @Test
    func balances_legacy_80x24() async throws {
        unsetenv("SMARTVESTOR_TUI_BALANCES_DECLARATIVE")
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        defer {
            unsetenv("SMARTVESTOR_TUI_BALANCES_DECLARATIVE")
            unsetenv("SMARTVESTOR_TUI_BUFFER")
        }

        let update = makeBalancesUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 15)
        let colorManager = ColorManager()
        let renderer = BalancePanelRenderer()
        let prices = ["BTC": 45000.0, "ETH": 3000.0, "USDC": 1.0]

        let renderedPanel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false,
            prices: prices
        )

        let adapter = PanelAdapter(
            panelType: .balances,
            renderedLines: renderedPanel.lines,
            layout: layout
        )

        let size = Size(width: 80, height: 24)
        var buffer = TerminalBuffer.empty(size: size)
        adapter.render(into: &buffer, at: .zero)

        assertSnapshot(buffer: buffer, named: "legacy_balances_80x24", testIdentifier: "balances_legacy_80x24")
    }

    @Test
    func balances_declarative_80x24() async throws {
        setenv("SMARTVESTOR_TUI_BALANCES_DECLARATIVE", "1", 1)
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        defer {
            unsetenv("SMARTVESTOR_TUI_BALANCES_DECLARATIVE")
            unsetenv("SMARTVESTOR_TUI_BUFFER")
        }

        let update = makeBalancesUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 15)
        let colorManager = ColorManager()
        let prices = ["BTC": 45000.0, "ETH": 3000.0, "USDC": 1.0]

        let balancesView = BalancesView(
            update: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false,
            prices: prices
        )
        balancesView.buildRows()

        let size = Size(width: 80, height: 24)
        var buffer = TerminalBuffer.empty(size: size)
        balancesView.render(into: &buffer, at: .zero)

        assertSnapshot(buffer: buffer, named: "decl_balances_80x24", testIdentifier: "balances_declarative_80x24")
    }

    @Test
    func balances_equivalence_check() async throws {
        let update = makeBalancesUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 15)
        let colorManager = ColorManager()
        let prices = ["BTC": 45000.0, "ETH": 3000.0, "USDC": 1.0]
        let size = Size(width: 80, height: 24)

        unsetenv("SMARTVESTOR_TUI_BALANCES_DECLARATIVE")
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        let renderer = BalancePanelRenderer()
        let renderedPanel = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false,
            prices: prices
        )
        let adapter = PanelAdapter(
            panelType: .balances,
            renderedLines: renderedPanel.lines,
            layout: layout
        )
        var legacyBuffer = TerminalBuffer.empty(size: size)
        adapter.render(into: &legacyBuffer, at: .zero)

        setenv("SMARTVESTOR_TUI_BALANCES_DECLARATIVE", "1", 1)
        let balancesView = BalancesView(
            update: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false,
            prices: prices
        )
        balancesView.buildRows()
        var declBuffer = TerminalBuffer.empty(size: size)
        balancesView.render(into: &declBuffer, at: .zero)

        let legacyNormalized = normalizeBufferOutput(legacyBuffer).serializeUTF8()
        let declNormalized = normalizeBufferOutput(declBuffer).serializeUTF8()

        let diff = legacyNormalized != declNormalized
        if diff {
            let legacyPath = snapshotPath(named: "legacy_balances_actual")
            let declPath = snapshotPath(named: "decl_balances_actual")
            try? legacyNormalized.write(to: legacyPath)
            try? declNormalized.write(to: declPath)
            Issue.record("Balances panel equivalence check failed. See .actual files for details.")
        }

        #expect(!diff, "Declarative and legacy should produce equivalent output")
    }

    @Test
    func balances_empty_state() async throws {
        setenv("SMARTVESTOR_TUI_BALANCES_DECLARATIVE", "1", 1)
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        defer {
            unsetenv("SMARTVESTOR_TUI_BALANCES_DECLARATIVE")
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

        let balancesView = BalancesView(
            update: emptyUpdate,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true
        )
        balancesView.buildRows()

        let size = Size(width: 80, height: 24)
        var buffer = TerminalBuffer.empty(size: size)
        balancesView.render(into: &buffer, at: .zero)

        assertSnapshot(buffer: buffer, named: "decl_balances_empty_80x24", testIdentifier: "balances_empty_state")
    }
}

private func makeBalancesUpdate() -> TUIUpdate {
    let balances = [
        Holding(
            id: UUID(),
            exchange: "test",
            asset: "BTC",
            available: 0.5,
            pending: 0.0,
            staked: 0.0,
            updatedAt: Date()
        ),
        Holding(
            id: UUID(),
            exchange: "test",
            asset: "ETH",
            available: 5.0,
            pending: 0.0,
            staked: 0.0,
            updatedAt: Date()
        ),
        Holding(
            id: UUID(),
            exchange: "test",
            asset: "USDC",
            available: 10000.0,
            pending: 0.0,
            staked: 0.0,
            updatedAt: Date()
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
            recentTrades: [],
            balances: balances,
            circuitBreakerOpen: false,
            lastExecutionTime: Date(),
            nextExecutionTime: Date().addingTimeInterval(60),
            totalPortfolioValue: 50000.0,
            errorCount: 0
        ),
        sequenceNumber: 100
    )
}
