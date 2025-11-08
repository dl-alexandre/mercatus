import Foundation

public enum ANSIColor: Int {
    case black = 30
    case red = 31
    case green = 32
    case yellow = 33
    case blue = 34
    case magenta = 35
    case cyan = 36
    case white = 37
    case gray = 90

    var code: Int {
        return rawValue
    }
}

public enum ANSIStyle: Int {
    case reset = 0
    case bold = 1
    case dim = 2
    case italic = 3
    case underline = 4

    var code: Int {
        return rawValue
    }
}

public final class ColorManager: ColorManagerProtocol, @unchecked Sendable {
    public private(set) var supportsColor: Bool
    public private(set) var supportsUnicode: Bool

    private let esc = "\u{001B}["
    private let monochrome: Bool

    public init(monochrome: Bool = false) {
        self.monochrome = monochrome
        self.supportsColor = !monochrome && Self.detectColorSupport()
        self.supportsUnicode = !monochrome && Self.detectUnicodeSupport()
    }

    public func bold(_ text: String) -> String {
        return applyStyle(.bold, to: text)
    }

    public func dim(_ text: String) -> String {
        return applyStyle(.dim, to: text)
    }

    public func reset() -> String {
        if monochrome || !supportsColor {
            return ""
        }
        return "\(esc)\(ANSIStyle.reset.code)m"
    }

    public func green(_ text: String) -> String {
        return applyColor(.green, to: text)
    }

    public func red(_ text: String) -> String {
        return applyColor(.red, to: text)
    }

    public func yellow(_ text: String) -> String {
        return applyColor(.yellow, to: text)
    }

    public func blue(_ text: String) -> String {
        return applyColor(.blue, to: text)
    }

    public func applyColor(_ color: ANSIColor, to text: String) -> String {
        if monochrome || !supportsColor {
            return text
        }
        return "\(esc)\(color.code)m\(text)\(esc)\(ANSIStyle.reset.code)m"
    }

    public func applyStyle(_ style: ANSIStyle, to text: String) -> String {
        if monochrome || !supportsColor {
            return text
        }
        return "\(esc)\(style.code)m\(text)\(esc)\(ANSIStyle.reset.code)m"
    }

    public func applyColorAndStyle(_ color: ANSIColor, _ style: ANSIStyle, to text: String) -> String {
        if monochrome || !supportsColor {
            return text
        }
        return "\(esc)\(style.code);\(color.code)m\(text)\(esc)\(ANSIStyle.reset.code)m"
    }

    private static func detectColorSupport() -> Bool {
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil {
            return false
        }

        guard let term = ProcessInfo.processInfo.environment["TERM"] else {
            if ProcessInfo.processInfo.environment["COLORTERM"] != nil {
                return true
            }
            return false
        }

        let colorTerms = [
            "xterm", "xterm-256color", "xterm-color",
            "screen", "screen-256color", "screen-color",
            "tmux", "tmux-256color",
            "vt100", "vt220",
            "ansi", "color",
            "linux", "rxvt", "rxvt-unicode"
        ]

        let termLower = term.lowercased()
        if colorTerms.contains(where: { termLower.contains($0) }) {
            return true
        }

        if ProcessInfo.processInfo.environment["COLORTERM"] != nil {
            return true
        }

        return false
    }

    private static func detectUnicodeSupport() -> Bool {
        if let locale = ProcessInfo.processInfo.environment["LC_ALL"] ?? ProcessInfo.processInfo.environment["LANG"] {
            let localeUpper = locale.uppercased()
            if localeUpper.contains("UTF-8") || localeUpper.contains("UTF8") {
                return true
            }
        }

        if let charset = ProcessInfo.processInfo.environment["CHARSET"] {
            let charsetUpper = charset.uppercased()
            if charsetUpper.contains("UTF-8") || charsetUpper.contains("UTF8") {
                return true
            }
        }

        return false
    }
}
