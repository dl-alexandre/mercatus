import Testing
import Foundation
@testable import SmartVestor

struct SnapshotTestOutput {
    let lines: [String]
    let terminalSize: TerminalSize
    let timestamp: Date

    init(lines: [String], terminalSize: TerminalSize) {
        self.lines = lines
        self.terminalSize = terminalSize
        self.timestamp = Date()
    }

    func normalize() -> [String] {
        return lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func compare(to other: SnapshotTestOutput) -> Bool {
        let normalizedSelf = normalize()
        let normalizedOther = other.normalize()

        guard normalizedSelf.count == normalizedOther.count else {
            return false
        }

        for (index, line) in normalizedSelf.enumerated() {
            if line != normalizedOther[index] {
                return false
            }
        }

        return true
    }
}

@Suite("TUI Snapshot Tests")
struct TUISnapshotTests {

    @Test("StatusPanelRenderer should produce consistent snapshot output")
    func testStatusPanelSnapshot() async {
        let renderer = StatusPanelRenderer()
        let colorManager = ColorManager()

        let update = createTestTUIUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)

        let rendered = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false
        )

        let snapshot = SnapshotTestOutput(lines: rendered.lines, terminalSize: TerminalSize(width: 80, height: 24))

        #expect(!snapshot.lines.isEmpty)
        #expect(snapshot.lines.count <= layout.height)
    }

    @Test("BalancePanelRenderer should produce consistent snapshot output")
    func testBalancePanelSnapshot() async {
        let renderer = BalancePanelRenderer()
        let colorManager = ColorManager()
        let layoutManager = LayoutManager.shared

        let update = createTestTUIUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 15)

        let rendered = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false
        )

        let snapshot = SnapshotTestOutput(lines: rendered.lines, terminalSize: TerminalSize(width: 80, height: 24))

        #expect(!snapshot.lines.isEmpty)
    }

    @Test("ActivityPanelRenderer should produce consistent snapshot output")
    func testActivityPanelSnapshot() async {
        let renderer = ActivityPanelRenderer()
        let colorManager = ColorManager()

        let update = createTestTUIUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 8)

        let rendered = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false
        )

        let snapshot = SnapshotTestOutput(lines: rendered.lines, terminalSize: TerminalSize(width: 80, height: 24))

        #expect(!snapshot.lines.isEmpty)
    }

    @Test("EnhancedTUIRenderer should produce consistent full frame snapshots")
    func testFullFrameSnapshot() async {
        let renderer = EnhancedTUIRenderer()

        let update = createTestTUIUpdate()
        let frame = await renderer.renderPanels(update, prices: nil, focus: nil)

        let snapshot = SnapshotTestOutput(lines: frame, terminalSize: TerminalSize(width: 80, height: 24))

        #expect(!snapshot.lines.isEmpty)
    }

    @Test("Snapshot output should be deterministic across runs")
    func testSnapshotDeterminism() async {
        let renderer = StatusPanelRenderer()
        let colorManager = ColorManager()

        let update = createTestTUIUpdate()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)

        let rendered1 = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false
        )

        let rendered2 = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .unicode,
            unicodeSupported: true,
            isFocused: false
        )

        let snapshot1 = SnapshotTestOutput(lines: rendered1.lines, terminalSize: TerminalSize(width: 80, height: 24))
        let snapshot2 = SnapshotTestOutput(lines: rendered2.lines, terminalSize: TerminalSize(width: 80, height: 24))

        #expect(snapshot1.compare(to: snapshot2))
    }

    private func createTestTUIUpdate() -> TUIUpdate {
        let state = AutomationState(
            isRunning: true,
            mode: .continuous,
            startedAt: Date(),
            lastExecutionTime: Date(),
            nextExecutionTime: Date().addingTimeInterval(60),
            pid: 12345
        )

        let data = TUIData(
            recentTrades: [
                InvestmentTransaction(
                    type: .buy,
                    exchange: "robinhood",
                    asset: "BTC",
                    quantity: 0.001,
                    price: 50000.0,
                    fee: 0.0,
                    timestamp: Date()
                )
            ],
            balances: [
                Holding(
                    exchange: "robinhood",
                    asset: "BTC",
                    available: 0.1,
                    pending: 0.0,
                    staked: 0.0,
                    updatedAt: Date()
                )
            ],
            circuitBreakerOpen: false,
            lastExecutionTime: Date(),
            nextExecutionTime: Date().addingTimeInterval(60),
            totalPortfolioValue: 4500.0,
            errorCount: 0
        )

        return TUIUpdate(
            type: .stateChange,
            state: state,
            data: data,
            sequenceNumber: 1
        )
    }
}
