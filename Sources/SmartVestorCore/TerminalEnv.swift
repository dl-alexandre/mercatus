import Foundation

#if os(macOS) || os(Linux)
import Darwin
#endif

public struct TerminalEnv: Hashable, Sendable {
    public let cjk: Bool
    public let wcwidthVariant: Int
    public let tab: Int
    public let supportsUTF8: Bool
    public let supportsTrueColor: Bool
    public let supportsUnicodeBoxDrawing: Bool
    public let supportsBraille: Bool
    public let colorDepth: Int
    public let isTTY: Bool
    public let isLowColor: Bool

    public init(
        cjk: Bool = false,
        wcwidthVariant: Int = 0,
        tab: Int = 8,
        supportsUTF8: Bool = true,
        supportsTrueColor: Bool = true,
        supportsUnicodeBoxDrawing: Bool = true,
        supportsBraille: Bool = true,
        colorDepth: Int = 256,
        isTTY: Bool = false,
        isLowColor: Bool = false
    ) {
        self.cjk = cjk
        self.wcwidthVariant = wcwidthVariant
        self.tab = tab
        self.supportsUTF8 = supportsUTF8
        self.supportsTrueColor = supportsTrueColor
        self.supportsUnicodeBoxDrawing = supportsUnicodeBoxDrawing
        self.supportsBraille = supportsBraille
        self.colorDepth = colorDepth
        self.isTTY = isTTY
        self.isLowColor = isLowColor
    }

    public static func detect() -> TerminalEnv {
        #if os(macOS) || os(Linux)
        let isTTY = isatty(STDOUT_FILENO) != 0

        let cjk = detectCJK()

        let lang = ProcessInfo.processInfo.environment["LANG"] ?? ""
        let supportsUTF8 = lang.contains("UTF-8") || lang.contains("utf8")

        let term = ProcessInfo.processInfo.environment["TERM"] ?? ""
        let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? ""

        let supportsTrueColor = term.contains("truecolor") ||
                               termProgram.contains("iTerm") ||
                               termProgram.contains("vscode") ||
                               ProcessInfo.processInfo.environment["COLORTERM"]?.contains("truecolor") == true

        let supportsUnicodeBoxDrawing = supportsUTF8 &&
                                       (term.contains("xterm") ||
                                        term.contains("screen") ||
                                        term.contains("tmux") ||
                                        termProgram.contains("iTerm") ||
                                        termProgram.contains("vscode"))

        let supportsBraille = supportsUTF8

        let colorDepth: Int
        if let colorterm = ProcessInfo.processInfo.environment["COLORTERM"] {
            if colorterm.contains("truecolor") || colorterm.contains("24bit") {
                colorDepth = 16777216
            } else if colorterm.contains("256") {
                colorDepth = 256
            } else {
                colorDepth = 16
            }
        } else {
            colorDepth = supportsTrueColor ? 16777216 : 256
        }

        let isLowColor = colorDepth <= 256 && !supportsTrueColor

        return TerminalEnv(
            cjk: cjk,
            wcwidthVariant: 0,
            tab: 8,
            supportsUTF8: supportsUTF8,
            supportsTrueColor: supportsTrueColor,
            supportsUnicodeBoxDrawing: supportsUnicodeBoxDrawing,
            supportsBraille: supportsBraille,
            colorDepth: colorDepth,
            isTTY: isTTY,
            isLowColor: isLowColor
        )
        #else
        return TerminalEnv(
            cjk: false,
            wcwidthVariant: 0,
            tab: 8,
            supportsUTF8: true,
            supportsTrueColor: true,
            supportsUnicodeBoxDrawing: true,
            supportsBraille: true,
            colorDepth: 16777216,
            isTTY: true,
            isLowColor: false
        )
        #endif
    }

    private static func detectCJK() -> Bool {
        return ProcessInfo.processInfo.environment["LANG"]?.contains("zh") == true ||
               ProcessInfo.processInfo.environment["LANG"]?.contains("ja") == true ||
               ProcessInfo.processInfo.environment["LANG"]?.contains("ko") == true
    }

    public static func detectWithCache() async -> TerminalEnv {
        let cache = TerminalCapabilityCache.shared
        await cache.probe()

        let supportsUTF8 = await cache.getUTF8Support()
        let supportsTrueColor = await cache.getTrueColorSupport()
        let supportsUnicodeBoxDrawing = await cache.getUnicodeBoxDrawingSupport()
        let supportsBraille = await cache.getBrailleSupport()
        let colorDepth = await cache.getColorDepth()

        #if os(macOS) || os(Linux)
        let isTTY = isatty(STDOUT_FILENO) != 0
        #else
        let isTTY = true
        #endif

        let isLowColor = colorDepth <= 256 && !supportsTrueColor

        return TerminalEnv(
            cjk: detectCJK(),
            wcwidthVariant: 0,
            tab: 8,
            supportsUTF8: supportsUTF8,
            supportsTrueColor: supportsTrueColor,
            supportsUnicodeBoxDrawing: supportsUnicodeBoxDrawing,
            supportsBraille: supportsBraille,
            colorDepth: colorDepth,
            isTTY: isTTY,
            isLowColor: isLowColor
        )
    }
}
