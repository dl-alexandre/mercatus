import Testing
import Foundation
@testable import SmartVestor

@Suite("TUI Accessibility and Compatibility Tests")
struct TUIAccessibilityTests {

    @Test("ColorManager should fallback to monochrome when colors not supported")
    func testMonochromeFallback() {
        let colorManager = ColorManager(monochrome: true)

        let redText = colorManager.red("Test")
        let greenText = colorManager.green("Test")

        #expect(redText == "Test")
        #expect(greenText == "Test")
    }

    @Test("ColorManager should fallback to ASCII when Unicode not supported")
    func testASCIIFallback() {
        let colorManager = ColorManager(monochrome: false)

        let borderChars = BorderStyle.ascii.characters(unicodeSupported: false)

        #expect(borderChars.topLeft == "+")
        #expect(borderChars.topRight == "+")
        #expect(borderChars.bottomLeft == "+")
        #expect(borderChars.bottomRight == "+")
        #expect(borderChars.horizontal == "-")
        #expect(borderChars.vertical == "|")
    }

    @Test("LayoutManager should handle minimum size constraints")
    func testMinimumSizeHandling() {
        let layoutManager = LayoutManager.shared

        let smallSize = TerminalSize(width: 40, height: 10)
        let layouts = layoutManager.calculateLayout(terminalSize: smallSize)

        #expect(!layouts.isEmpty)

        for (_, layout) in layouts {
            #expect(layout.width >= 40)
            #expect(layout.height >= 1)
        }
    }

    @Test("Panel renderers should work in monochrome mode")
    func testMonochromeRendering() async {
        let colorManager = ColorManager(monochrome: true)

        let renderer = StatusPanelRenderer()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 10)
        let update = createTestTUIUpdate()

        let rendered = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .ascii,
            unicodeSupported: false,
            isFocused: false
        )

        #expect(!rendered.lines.isEmpty)
    }

    @Test("EnhancedTUIRenderer should handle SSH session compatibility")
    func testSSHCompatibility() async {
        let colorManager = ColorManager(monochrome: true)

        let renderer = EnhancedTUIRenderer(colorManager: colorManager)
        let update = createTestTUIUpdate()

        let frame = await renderer.renderPanels(update, prices: nil, focus: nil)

        #expect(!frame.isEmpty)

        for line in frame {
            #expect(!line.contains("\u{001B}"))
        }
    }

    @Test("AlertBannerRenderer should work in monochrome mode")
    func testAlertBannerMonochrome() {
        let colorManager = ColorManager(monochrome: true)

        let renderer = AlertBannerRenderer(colorManager: colorManager)
        let alert = renderer.renderAlert(message: "Test message", severity: .error, width: 80)

        #expect(!alert.isEmpty)
    }

    @Test("Text should be readable in ASCII-only mode")
    func testASCIIReadability() async {
        let colorManager = ColorManager(monochrome: false)

        let renderer = BalancePanelRenderer()
        let layout = PanelLayout(x: 0, y: 0, width: 80, height: 15)
        let update = createTestTUIUpdate()

        let rendered = await renderer.render(
            input: update,
            layout: layout,
            colorManager: colorManager,
            borderStyle: .ascii,
            unicodeSupported: false,
            isFocused: false
        )

        for line in rendered.lines {
            for char in line {
                let scalar = char.unicodeScalars.first
                if let scalar = scalar {
                    #expect(scalar.value < 0x80 || scalar.value == 0x0A)
                }
            }
        }
    }

    private func createTestTUIUpdate() -> TUIUpdate {
        let state = AutomationState(
            isRunning: true,
            mode: .continuous,
            startedAt: Date(),
            lastExecutionTime: Date(),
            nextExecutionTime: Date().addingTimeInterval(60),
            pid: nil
        )

        let data = TUIData(
            recentTrades: [],
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
            type: .heartbeat,
            state: state,
            data: data,
            sequenceNumber: 1
        )
    }
}
