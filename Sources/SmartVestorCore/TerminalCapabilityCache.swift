import Foundation

#if os(macOS) || os(Linux)
import Darwin
#endif

public actor TerminalCapabilityCache {
    public static let shared = TerminalCapabilityCache()

    private var supportsUTF8: Bool?
    private var supportsTrueColor: Bool?
    private var supportsUnicodeBoxDrawing: Bool?
    private var supportsBraille: Bool?
    private var supportsEmojiWidth: Bool?
    private var colorDepth: Int?
    private var terminalWidth: Int?
    private var terminalHeight: Int?
    private var isProbed: Bool = false

    private init() {
        #if os(macOS) || os(Linux)
        signal(SIGWINCH) { _ in
            NotificationCenter.default.post(name: NSNotification.Name("TerminalResize"), object: nil)
        }
        #endif

        Task {
            await setupResizeNotification()
        }
    }

    public func probe() async {
        await probeCapabilities()
    }

    public func getUTF8Support() async -> Bool {
        if !isProbed {
            await probeCapabilities()
        }
        return supportsUTF8 ?? false
    }

    public func getTrueColorSupport() async -> Bool {
        if !isProbed {
            await probeCapabilities()
        }
        return supportsTrueColor ?? false
    }

    public func getUnicodeBoxDrawingSupport() async -> Bool {
        if !isProbed {
            await probeCapabilities()
        }
        return supportsUnicodeBoxDrawing ?? false
    }

    public func getBrailleSupport() async -> Bool {
        if !isProbed {
            await probeCapabilities()
        }
        return supportsBraille ?? false
    }

    public func getEmojiWidthSupport() async -> Bool {
        if !isProbed {
            await probeCapabilities()
        }
        return supportsEmojiWidth ?? false
    }

    public func getColorDepth() async -> Int {
        if !isProbed {
            await probeCapabilities()
        }
        return colorDepth ?? 256
    }

    public func getTerminalWidth() async -> Int {
        if !isProbed {
            await probeCapabilities()
        }
        return terminalWidth ?? 80
    }

    public func getTerminalHeight() async -> Int {
        if !isProbed {
            await probeCapabilities()
        }
        return terminalHeight ?? 24
    }

    public func invalidate() async {
        supportsUTF8 = nil
        supportsTrueColor = nil
        supportsUnicodeBoxDrawing = nil
        supportsBraille = nil
        supportsEmojiWidth = nil
        colorDepth = nil
        terminalWidth = nil
        terminalHeight = nil
        isProbed = false
    }

    private func probeCapabilities() async {
        #if os(macOS) || os(Linux)
        let lang = ProcessInfo.processInfo.environment["LANG"] ?? ""
        supportsUTF8 = lang.contains("UTF-8") || lang.contains("utf8")

        let term = ProcessInfo.processInfo.environment["TERM"] ?? ""
        let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? ""

        supportsTrueColor = term.contains("truecolor") ||
                           termProgram.contains("iTerm") ||
                           termProgram.contains("vscode") ||
                           ProcessInfo.processInfo.environment["COLORTERM"]?.contains("truecolor") == true

        supportsUnicodeBoxDrawing = supportsUTF8 == true &&
                                   (term.contains("xterm") ||
                                    term.contains("screen") ||
                                    term.contains("tmux") ||
                                    termProgram.contains("iTerm") ||
                                    termProgram.contains("vscode"))

        supportsBraille = supportsUTF8 == true

        supportsEmojiWidth = supportsUTF8 == true

        if let colorterm = ProcessInfo.processInfo.environment["COLORTERM"] {
            if colorterm.contains("truecolor") || colorterm.contains("24bit") {
                colorDepth = 16777216
            } else if colorterm.contains("256") {
                colorDepth = 256
            } else {
                colorDepth = 16
            }
        } else {
            colorDepth = supportsTrueColor == true ? 16777216 : 256
        }

        var winsize = winsize(ws_row: 0, ws_col: 0, ws_xpixel: 0, ws_ypixel: 0)
        let TIOCGWINSZ: UInt = 0x40087468
        let result = ioctl(STDOUT_FILENO, TIOCGWINSZ, &winsize)
        if result == 0 {
            terminalWidth = Int(winsize.ws_col)
            terminalHeight = Int(winsize.ws_row)
        } else {
            if let columns = ProcessInfo.processInfo.environment["COLUMNS"],
               let rows = ProcessInfo.processInfo.environment["LINES"],
               let cols = Int(columns),
               let rowsInt = Int(rows) {
                terminalWidth = cols
                terminalHeight = rowsInt
            } else {
                terminalWidth = 80
                terminalHeight = 24
            }
        }
        #else
        supportsUTF8 = true
        supportsTrueColor = true
        supportsUnicodeBoxDrawing = true
        supportsBraille = true
        supportsEmojiWidth = true
        colorDepth = 16777216
        terminalWidth = 80
        terminalHeight = 24
        #endif

        isProbed = true
    }

    public func setupResizeNotification() async {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TerminalResize"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleResize()
            }
        }
    }

    private func handleResize() async {
        await invalidate()
        await probeCapabilities()
    }
}
