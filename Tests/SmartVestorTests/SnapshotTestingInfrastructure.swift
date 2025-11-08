import Testing
import Foundation
@testable import SmartVestor

final class SnapshotCapturer {
    private var capturedOutput: [String] = []
    private var outputStream: OutputStream?

    init() {
        let pipe = Pipe()
        outputStream = OutputStream(toMemory: ())
    }

    func capture(_ lines: [String]) -> String {
        let normalized = lines.map { normalizeANSI($0) }.joined(separator: "\n")
        capturedOutput.append(normalized)
        return normalized
    }

    private func normalizeANSI(_ text: String) -> String {
        let ansiEscape = "\u{001B}["
        var result = text

        var range: Range<String.Index>?
        while let found = result.range(of: ansiEscape) {
            if let end = result[found.upperBound...].firstIndex(where: { $0 == "m" || $0.isLetter }) {
                let fullRange = found.lowerBound..<result.index(after: end)
                result.removeSubrange(fullRange)
                range = fullRange
            } else {
                break
            }
        }

        return result
    }

    func getSnapshot() -> String {
        return capturedOutput.joined(separator: "\n")
    }

    func compare(with expected: String) -> (matches: Bool, diff: String) {
        let actual = getSnapshot()
        if actual == expected {
            return (true, "")
        }

        let actualLines = actual.components(separatedBy: "\n")
        let expectedLines = expected.components(separatedBy: "\n")

        var diff = "Snapshot mismatch:\n"
        let maxLines = max(actualLines.count, expectedLines.count)

        for i in 0..<maxLines {
            let actualLine = i < actualLines.count ? actualLines[i] : "<missing>"
            let expectedLine = i < expectedLines.count ? expectedLines[i] : "<missing>"

            if actualLine != expectedLine {
                diff += "Line \(i + 1):\n"
                diff += "  Expected: \(expectedLine)\n"
                diff += "  Actual:   \(actualLine)\n"
            }
        }

        return (false, diff)
    }
}

final class TerminalSizeFixture {
    static let small = TerminalSize(width: 80, height: 24)
    static let medium = TerminalSize(width: 120, height: 40)
    static let large = TerminalSize(width: 200, height: 60)
    static let wide = TerminalSize(width: 250, height: 30)
    static let tall = TerminalSize(width: 80, height: 80)
}

final class TUISnapshotTestHelper {
    static func createTestUpdate(
        isRunning: Bool = true,
        mode: AutomationMode = .continuous,
        errorCount: Int = 0,
        circuitBreakerOpen: Bool = false,
        balances: [Holding] = [],
        trades: [InvestmentTransaction] = [],
        totalPortfolioValue: Double = 1000.0,
        sequenceNumber: Int64 = 1
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
            sequenceNumber: sequenceNumber
        )
    }

    static func createTestHolding(
        asset: String = "BTC",
        available: Double = 0.5,
        pending: Double = 0.0,
        staked: Double = 0.0,
        updatedAt: Date = Date()
    ) -> Holding {
        return Holding(
            id: UUID(),
            exchange: "robinhood",
            asset: asset,
            available: available,
            pending: pending,
            staked: staked,
            updatedAt: updatedAt
        )
    }

    static func createTestTrade(
        asset: String = "BTC",
        type: TransactionType = .buy,
        quantity: Double = 0.1,
        price: Double = 45000.0,
        fee: Double = 0.0,
        exchange: String = "robinhood"
    ) -> InvestmentTransaction {
        return InvestmentTransaction(
            id: UUID(),
            type: type,
            exchange: exchange,
            asset: asset,
            quantity: quantity,
            price: price,
            fee: fee,
            timestamp: Date()
        )
    }

    static func captureSnapshot(
        renderer: EnhancedTUIRendererProtocol,
        update: TUIUpdate,
        prices: [String: Double]? = nil,
        focus: PanelFocus? = nil
    ) async -> [String] {
        return await renderer.renderPanels(update, prices: prices, focus: focus)
    }
}

@Suite("Snapshot Testing Infrastructure")
struct SnapshotTestingInfrastructureTests {

    @Test("SnapshotCapturer should capture ANSI output")
    func testSnapshotCapture() async {
        let capturer = SnapshotCapturer()
        let output = [
            "\u{001B}[1mSmartVestor\u{001B}[0m  \u{001B}[32mRUNNING\u{001B}[0m",
            "as of 2025-01-15T10:00:00Z"
        ]

        let captured = capturer.capture(output)
        let snapshot = capturer.getSnapshot()

        #expect(snapshot.contains("SmartVestor"))
        #expect(snapshot.contains("RUNNING"))
        #expect(!snapshot.contains("\u{001B}["))
    }

    @Test("SnapshotCapturer should normalize ANSI codes")
    func testANSINormalization() {
        let capturer = SnapshotCapturer()
        let withANSI = "\u{001B}[1mBold\u{001B}[0m \u{001B}[32mGreen\u{001B}[0m"
        let normalized = capturer.capture([withANSI])

        #expect(normalized == "Bold Green")
        #expect(!normalized.contains("\u{001B}"))
    }

    @Test("Snapshot comparison should detect differences")
    func testSnapshotComparison() {
        let capturer = SnapshotCapturer()
        capturer.capture(["Line 1", "Line 2"])

        let (matches, diff) = capturer.compare(with: "Line 1\nLine 3")
        #expect(matches == false)
        #expect(!diff.isEmpty)
        #expect(diff.contains("Line 2"))
        #expect(diff.contains("Line 3"))
    }

    @Test("TerminalSize fixtures should provide standard sizes")
    func testTerminalSizeFixtures() {
        #expect(TerminalSizeFixture.small.width == 80)
        #expect(TerminalSizeFixture.small.height == 24)
        #expect(TerminalSizeFixture.medium.width == 120)
        #expect(TerminalSizeFixture.large.width == 200)
    }

    @Test("TUISnapshotTestHelper should create test updates")
    func testTestHelperCreation() {
        let update = TUISnapshotTestHelper.createTestUpdate(
            isRunning: false,
            totalPortfolioValue: 5000.0
        )

        #expect(update.state.isRunning == false)
        #expect(update.data.totalPortfolioValue == 5000.0)
    }

    @Test("TUISnapshotTestHelper should create test holdings")
    func testTestHoldingCreation() {
        let holding = TUISnapshotTestHelper.createTestHolding(
            asset: "ETH",
            available: 2.0
        )

        #expect(holding.asset == "ETH")
        #expect(holding.available == 2.0)
        #expect(holding.exchange == "robinhood")
    }
}
