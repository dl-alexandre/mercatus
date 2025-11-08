import Foundation

public enum AccessibilityMode: String, Sendable, Codable {
    case normal
    case highContrast
    case screenReader
}

public actor AccessibilityManager {
    private var mode: AccessibilityMode
    private var showKeyHints: Bool
    private var enhancedFocusBorders: Bool

    public init(
        mode: AccessibilityMode = .normal,
        showKeyHints: Bool = true,
        enhancedFocusBorders: Bool = true
    ) {
        self.mode = mode
        self.showKeyHints = showKeyHints
        self.enhancedFocusBorders = enhancedFocusBorders
    }

    public func getMode() -> AccessibilityMode {
        return mode
    }

    public func setMode(_ newMode: AccessibilityMode) {
        mode = newMode
    }

    public func shouldShowKeyHints() -> Bool {
        return showKeyHints && (mode == .normal || mode == .screenReader)
    }

    public func shouldUseEnhancedFocusBorders() -> Bool {
        return enhancedFocusBorders && (mode == .normal || mode == .highContrast)
    }

    public func getFocusBorderStyle() -> String {
        switch mode {
        case .normal:
            return enhancedFocusBorders ? "\u{001B}[7m" : "\u{001B}[4m"
        case .highContrast:
            return "\u{001B}[1m\u{001B}[7m"
        case .screenReader:
            return ""
        }
    }

    public func getResetStyle() -> String {
        return "\u{001B}[0m"
    }

    public func formatKeyHint(_ key: String, description: String) -> String {
        guard shouldShowKeyHints() else { return description }
        return "[\(key)] \(description)"
    }

    public func checkColorContrast(foreground: String, background: String) -> Bool {
        return true
    }
}
