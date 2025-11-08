import Testing
import Foundation
@testable import SmartVestor
@testable import Core

@Suite("Accessibility and Compatibility Tests")
struct AccessibilityCompatibilityTests {

    @Test("ColorManager should fallback to monochrome when NO_COLOR is set")
    func testMonochromeFallback() {
        let originalNoColor = ProcessInfo.processInfo.environment["NO_COLOR"]
        defer {
            if let noColor = originalNoColor {
                setenv("NO_COLOR", noColor, 1)
            } else {
                unsetenv("NO_COLOR")
            }
        }

        setenv("NO_COLOR", "1", 1)
        let manager = ColorManager(monochrome: false)

        #expect(manager.supportsColor == false)
        let styled = manager.bold("Test")
        #expect(styled == "Test")
        #expect(!styled.contains("\u{001B}["))
    }

    @Test("ColorManager should handle monochrome mode explicitly")
    func testExplicitMonochromeMode() {
        let manager = ColorManager(monochrome: true)

        #expect(manager.supportsColor == false)
        #expect(manager.supportsUnicode == false)

        let green = manager.green("Test")
        #expect(green == "Test")

        let red = manager.red("Test")
        #expect(red == "Test")

        let bold = manager.bold("Test")
        #expect(bold == "Test")
    }

    @Test("Enhanced TUI should render without colors in monochrome mode")
    func testMonochromeRendering() async {
        let colorManager = ColorManager(monochrome: true)
        let renderer = EnhancedTUIRenderer(colorManager: colorManager)

        let update = TUISnapshotTestHelper.createTestUpdate(
            isRunning: true,
            balances: [
                TUISnapshotTestHelper.createTestHolding(asset: "BTC", available: 0.5)
            ]
        )

        let frame = await renderer.renderPanels(update, prices: nil, focus: nil)
        let frameText = frame.joined(separator: "\n")

        #expect(!frameText.isEmpty)
        #expect(!frameText.contains("\u{001B}["))
    }

    @Test("Enhanced TUI should fallback to ASCII borders when Unicode not supported")
    func testASCIIBorderFallback() async {
        let colorManager = ColorManager(monochrome: true)
        #expect(colorManager.supportsUnicode == false)

        let renderer = EnhancedTUIRenderer(colorManager: colorManager)
        let update = TUISnapshotTestHelper.createTestUpdate()

        let frame = await renderer.renderPanels(update, prices: nil, focus: nil)
        let frameText = frame.joined(separator: "\n")

        #expect(!frameText.isEmpty)

        let hasUnicode = frameText.contains("─") || frameText.contains("│") ||
                         frameText.contains("┌") || frameText.contains("└") ||
                         frameText.contains("┐") || frameText.contains("┘") ||
                         frameText.contains("═") || frameText.contains("║") ||
                         frameText.contains("╔") || frameText.contains("╗") ||
                         frameText.contains("╚") || frameText.contains("╝")

        #expect(!hasUnicode)
    }

    @Test("ColorManager should detect Unicode support from locale")
    func testUnicodeDetectionFromLocale() {
        let originalLocale = ProcessInfo.processInfo.environment["LC_ALL"]
        defer {
            if let locale = originalLocale {
                setenv("LC_ALL", locale, 1)
            } else {
                unsetenv("LC_ALL")
            }
        }

        setenv("LC_ALL", "en_US.UTF-8", 1)
        let manager = ColorManager(monochrome: false)

        #expect(manager.supportsUnicode == true)
    }

    @Test("ColorManager should detect Unicode support from CHARSET")
    func testUnicodeDetectionFromCharset() {
        let originalCharset = ProcessInfo.processInfo.environment["CHARSET"]
        defer {
            if let charset = originalCharset {
                setenv("CHARSET", charset, 1)
            } else {
                unsetenv("CHARSET")
            }
        }

        setenv("CHARSET", "UTF-8", 1)
        let manager = ColorManager(monochrome: false)

        #expect(manager.supportsUnicode == true)
    }

    @Test("Enhanced TUI should work in SSH-like environment")
    func testSSHCompatibility() async {
        let originalTerm = ProcessInfo.processInfo.environment["TERM"]
        let originalColorTerm = ProcessInfo.processInfo.environment["COLORTERM"]

        defer {
            if let term = originalTerm {
                setenv("TERM", term, 1)
            } else {
                unsetenv("TERM")
            }

            if let colorTerm = originalColorTerm {
                setenv("COLORTERM", colorTerm, 1)
            } else {
                unsetenv("COLORTERM")
            }
        }

        setenv("TERM", "xterm", 1)
        unsetenv("COLORTERM")
        unsetenv("NO_COLOR")

        let colorManager = ColorManager(monochrome: false)
        let renderer = EnhancedTUIRenderer(colorManager: colorManager)

        let update = TUISnapshotTestHelper.createTestUpdate(
            balances: [
                TUISnapshotTestHelper.createTestHolding(asset: "BTC", available: 0.5)
            ]
        )

        let frame = await renderer.renderPanels(update, prices: nil, focus: nil)

        #expect(!frame.isEmpty)
        #expect(colorManager.supportsColor == true)
    }

    @Test("Enhanced TUI should handle missing environment variables gracefully")
    func testMissingEnvironmentVariables() async {
        let originalTerm = ProcessInfo.processInfo.environment["TERM"]
        let originalColorTerm = ProcessInfo.processInfo.environment["COLORTERM"]
        let originalLC = ProcessInfo.processInfo.environment["LC_ALL"]

        defer {
            if let term = originalTerm {
                setenv("TERM", term, 1)
            } else {
                unsetenv("TERM")
            }

            if let colorTerm = originalColorTerm {
                setenv("COLORTERM", colorTerm, 1)
            } else {
                unsetenv("COLORTERM")
            }

            if let lc = originalLC {
                setenv("LC_ALL", lc, 1)
            } else {
                unsetenv("LC_ALL")
            }
        }

        unsetenv("TERM")
        unsetenv("COLORTERM")
        unsetenv("LC_ALL")
        unsetenv("CHARSET")
        unsetenv("NO_COLOR")

        let colorManager = ColorManager(monochrome: false)
        let renderer = EnhancedTUIRenderer(colorManager: colorManager)

        let update = TUISnapshotTestHelper.createTestUpdate()
        let frame = await renderer.renderPanels(update, prices: nil, focus: nil)

        #expect(!frame.isEmpty)
    }

    @Test("Enhanced TUI should preserve functionality without Unicode support")
    func testFunctionalityWithoutUnicode() async {
        let colorManager = ColorManager(monochrome: true)
        let renderer = EnhancedTUIRenderer(colorManager: colorManager)

        let balances = [
            TUISnapshotTestHelper.createTestHolding(asset: "BTC", available: 0.5),
            TUISnapshotTestHelper.createTestHolding(asset: "ETH", available: 2.0)
        ]

        let update = TUISnapshotTestHelper.createTestUpdate(
            balances: balances,
            totalPortfolioValue: 50000.0
        )

        let frame = await renderer.renderPanels(update, prices: nil, focus: nil)

        #expect(!frame.isEmpty)
        let frameText = frame.joined(separator: "\n")
        #expect(frameText.contains("BTC") || frameText.contains("ETH"))
    }

    @Test("Enhanced TUI should handle all ANSI color codes correctly")
    func testANSIColorCodes() {
        let colorManager = ColorManager(monochrome: false)

        let green = colorManager.green("Test")
        #expect(green.contains("\u{001B}"))

        let red = colorManager.red("Test")
        #expect(red.contains("\u{001B}"))

        let yellow = colorManager.yellow("Test")
        #expect(yellow.contains("\u{001B}"))

        let blue = colorManager.blue("Test")
        #expect(blue.contains("\u{001B}"))
    }

    @Test("Enhanced TUI should render correctly with minimal terminal size")
    func testMinimalTerminalSize() async {
        let renderer = EnhancedTUIRenderer()
        let update = TUISnapshotTestHelper.createTestUpdate(
            balances: [
                TUISnapshotTestHelper.createTestHolding(asset: "BTC", available: 0.5)
            ]
        )

        let frame = await renderer.renderPanels(update, prices: nil, focus: nil)

        #expect(!frame.isEmpty)
        #expect(frame.count > 0)
    }
}
