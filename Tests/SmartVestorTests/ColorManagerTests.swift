import Testing
import Foundation
@testable import SmartVestor
import Utils

@Suite("Color Manager Tests")
struct ColorManagerTests {

    @Test("ColorManager should detect color support from TERM environment variable")
    func testColorDetectionFromTerm() {
        let originalTerm = ProcessInfo.processInfo.environment["TERM"]
        defer {
            if let term = originalTerm {
                setenv("TERM", term, 1)
            } else {
                unsetenv("TERM")
            }
        }

        setenv("TERM", "xterm-256color", 1)
        unsetenv("NO_COLOR")
        unsetenv("COLORTERM")
        let manager = ColorManager(monochrome: false)
        #expect(manager.supportsColor == true)
    }

    @Test("ColorManager should detect color support from COLORTERM environment variable")
    func testColorDetectionFromColorTerm() {
        let originalColorTerm = ProcessInfo.processInfo.environment["COLORTERM"]
        defer {
            if let colorTerm = originalColorTerm {
                setenv("COLORTERM", colorTerm, 1)
            } else {
                unsetenv("COLORTERM")
            }
        }

        unsetenv("TERM")
        setenv("COLORTERM", "truecolor", 1)
        unsetenv("NO_COLOR")
        let manager = ColorManager(monochrome: false)
        #expect(manager.supportsColor == true)
    }

    @Test("ColorManager should respect NO_COLOR environment variable")
    func testNoColorEnvironmentVariable() {
        let originalNoColor = ProcessInfo.processInfo.environment["NO_COLOR"]
        defer {
            if let noColor = originalNoColor {
                setenv("NO_COLOR", noColor, 1)
            } else {
                unsetenv("NO_COLOR")
            }
        }

        unsetenv("TERM")
        unsetenv("COLORTERM")
        unsetenv("NO_COLOR")
        setenv("NO_COLOR", "1", 1)
        let manager = ColorManager(monochrome: false)
        #expect(manager.supportsColor == false)
    }

    @Test("ColorManager should support various terminal types")
    func testTerminalTypeDetection() {
        let testTerms = [
            "xterm",
            "xterm-256color",
            "xterm-color",
            "screen",
            "screen-256color",
            "screen-color",
            "tmux",
            "tmux-256color",
            "vt100",
            "vt220",
            "ansi",
            "color",
            "linux",
            "rxvt",
            "rxvt-unicode"
        ]

        let originalTerm = ProcessInfo.processInfo.environment["TERM"]
        let originalNoColor = ProcessInfo.processInfo.environment["NO_COLOR"]
        defer {
            if let term = originalTerm {
                setenv("TERM", term, 1)
            } else {
                unsetenv("TERM")
            }
            if let noColor = originalNoColor {
                setenv("NO_COLOR", noColor, 1)
            } else {
                unsetenv("NO_COLOR")
            }
        }

        unsetenv("NO_COLOR")
        unsetenv("COLORTERM")

        for term in testTerms {
            setenv("TERM", term, 1)
            let manager = ColorManager(monochrome: false)
            #expect(manager.supportsColor == true, "Terminal type '\(term)' should support color")
        }
    }

    @Test("ColorManager should detect Unicode support from LC_ALL")
    func testUnicodeDetectionFromLcAll() {
        let originalLcAll = ProcessInfo.processInfo.environment["LC_ALL"]
        defer {
            if let lcAll = originalLcAll {
                setenv("LC_ALL", lcAll, 1)
            } else {
                unsetenv("LC_ALL")
            }
        }

        setenv("LC_ALL", "en_US.UTF-8", 1)
        unsetenv("LANG")
        unsetenv("CHARSET")
        let manager = ColorManager(monochrome: false)
        #expect(manager.supportsUnicode == true)
    }

    @Test("ColorManager should detect Unicode support from LANG")
    func testUnicodeDetectionFromLang() {
        let originalLang = ProcessInfo.processInfo.environment["LANG"]
        defer {
            if let lang = originalLang {
                setenv("LANG", lang, 1)
            } else {
                unsetenv("LANG")
            }
        }

        unsetenv("LC_ALL")
        setenv("LANG", "C.UTF8", 1)
        unsetenv("CHARSET")
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

        unsetenv("LC_ALL")
        unsetenv("LANG")
        setenv("CHARSET", "UTF-8", 1)
        let manager = ColorManager(monochrome: false)
        #expect(manager.supportsUnicode == true)
    }

    @Test("ColorManager should fallback to plain text in monochrome mode")
    func testMonochromeModeFallback() {
        let manager = ColorManager(monochrome: true)
        #expect(manager.supportsColor == false)
        #expect(manager.supportsUnicode == false)

        let testText = "Hello World"
        let greenText = manager.green(testText)
        #expect(greenText == testText)

        let redText = manager.red(testText)
        #expect(redText == testText)

        let boldText = manager.bold(testText)
        #expect(boldText == testText)

        let dimText = manager.dim(testText)
        #expect(dimText == testText)
    }

    @Test("ColorManager should apply colors when color is supported")
    func testColorApplication() {
        let originalTerm = ProcessInfo.processInfo.environment["TERM"]
        defer {
            if let term = originalTerm {
                setenv("TERM", term, 1)
            } else {
                unsetenv("TERM")
            }
        }

        setenv("TERM", "xterm-256color", 1)
        unsetenv("NO_COLOR")
        let manager = ColorManager(monochrome: false)

        guard manager.supportsColor else {
            #expect(Bool(), "Color should be supported in test environment")
            return
        }

        let testText = "Test"
        let greenText = manager.green(testText)
        #expect(greenText != testText)
        #expect(greenText.contains(testText))
        #expect(greenText.contains("\u{001B}"))

        let redText = manager.red(testText)
        #expect(redText != testText)
        #expect(redText.contains(testText))

        let blueText = manager.blue(testText)
        #expect(blueText != testText)
        #expect(blueText.contains(testText))

        let yellowText = manager.yellow(testText)
        #expect(yellowText != testText)
        #expect(yellowText.contains(testText))
    }

    @Test("ColorManager should apply styles when color is supported")
    func testStyleApplication() {
        let originalTerm = ProcessInfo.processInfo.environment["TERM"]
        defer {
            if let term = originalTerm {
                setenv("TERM", term, 1)
            } else {
                unsetenv("TERM")
            }
        }

        setenv("TERM", "xterm-256color", 1)
        unsetenv("NO_COLOR")
        let manager = ColorManager(monochrome: false)

        guard manager.supportsColor else {
            #expect(Bool(), "Color should be supported in test environment")
            return
        }

        let testText = "Test"
        let boldText = manager.bold(testText)
        #expect(boldText != testText)
        #expect(boldText.contains(testText))
        #expect(boldText.contains("\u{001B}"))

        let dimText = manager.dim(testText)
        #expect(dimText != testText)
        #expect(dimText.contains(testText))
    }


    @Test("ColorManager should reset colors correctly")
    func testColorReset() {
        let originalTerm = ProcessInfo.processInfo.environment["TERM"]
        defer {
            if let term = originalTerm {
                setenv("TERM", term, 1)
            } else {
                unsetenv("TERM")
            }
        }

        setenv("TERM", "xterm-256color", 1)
        unsetenv("NO_COLOR")
        let manager = ColorManager(monochrome: false)

        guard manager.supportsColor else {
            #expect(Bool(), "Color should be supported in test environment")
            return
        }

        let resetSequence = manager.reset()
        #expect(resetSequence.contains("\u{001B}"))

        let monochromeManager = ColorManager(monochrome: true)
        let monochromeReset = monochromeManager.reset()
        #expect(monochromeReset.isEmpty)
    }

    @Test("ColorManager should handle ANSIColor enum correctly")
    func testANSIColorEnum() {
        #expect(ANSIColor.red.code == 31)
        #expect(ANSIColor.green.code == 32)
        #expect(ANSIColor.yellow.code == 33)
        #expect(ANSIColor.blue.code == 34)
        #expect(ANSIColor.magenta.code == 35)
        #expect(ANSIColor.cyan.code == 36)
        #expect(ANSIColor.white.code == 37)
        #expect(ANSIColor.black.code == 30)
        #expect(ANSIColor.gray.code == 90)
    }

    @Test("ColorManager should handle ANSIStyle enum correctly")
    func testANSIStyleEnum() {
        #expect(ANSIStyle.reset.code == 0)
        #expect(ANSIStyle.bold.code == 1)
        #expect(ANSIStyle.dim.code == 2)
        #expect(ANSIStyle.italic.code == 3)
        #expect(ANSIStyle.underline.code == 4)
    }
}
