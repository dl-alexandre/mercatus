import Foundation

public enum AlertSeverity: Sendable {
    case info
    case warning
    case error

    func getColor(colorManager: ColorManagerProtocol) -> (String) -> String {
        switch self {
        case .info:
            return colorManager.blue
        case .warning:
            return colorManager.yellow
        case .error:
            return colorManager.red
        }
    }

    func getIcon() -> String {
        switch self {
        case .info:
            return "ℹ"
        case .warning:
            return "⚠"
        case .error:
            return "✕"
        }
    }
}

public final class AlertBannerRenderer: @unchecked Sendable {
    private let colorManager: ColorManagerProtocol
    private let layoutManager: LayoutManagerProtocol

    public init(colorManager: ColorManagerProtocol = ColorManager(), layoutManager: LayoutManagerProtocol = LayoutManager.shared) {
        self.colorManager = colorManager
        self.layoutManager = layoutManager
    }

    public func renderAlert(message: String, severity: AlertSeverity, width: Int? = nil) -> [String] {
        let terminalSize = layoutManager.detectTerminalSize()
        let effectiveWidth = width ?? terminalSize.width
        let maxWidth = max(40, effectiveWidth - 4)

        let colorFunc = severity.getColor(colorManager: colorManager)
        let icon = severity.getIcon()
        let coloredIcon = colorFunc(icon)

        var lines: [String] = []

        let wrappedMessage = wrapText(message, maxWidth: maxWidth - 4)

        let borderChar = colorManager.supportsUnicode ? "═" : "="
        let topBorder = String(repeating: borderChar, count: maxWidth)
        let coloredTopBorder = colorFunc(topBorder)
        lines.append(coloredTopBorder)

        for (index, line) in wrappedMessage.enumerated() {
            let prefix = index == 0 ? "\(coloredIcon) " : "  "
            let paddedLine = line.padding(toLength: maxWidth - prefix.count, withPad: " ", startingAt: 0)
            lines.append("\(prefix)\(paddedLine)")
        }

        let bottomBorder = String(repeating: borderChar, count: maxWidth)
        let coloredBottomBorder = colorFunc(bottomBorder)
        lines.append(coloredBottomBorder)

        return lines
    }

    public func renderConnectionAlert(status: TUIConnectionStatus) -> [String] {
        switch status {
        case .connecting:
            return renderAlert(message: "Connecting to TUI server...", severity: .info)
        case .reconnecting:
            return renderAlert(message: "Reconnecting to TUI server...", severity: .warning)
        case .failed(let reason):
            return renderAlert(message: "Connection failed: \(reason)", severity: .error)
        case .connected:
            return []
        case .disconnected:
            return renderAlert(message: "Disconnected from TUI server", severity: .warning)
        }
    }

    private func wrapText(_ text: String, maxWidth: Int) -> [String] {
        var lines: [String] = []
        var currentLine = ""

        let words = text.split(separator: " ")

        for word in words {
            let wordStr = String(word)

            if currentLine.isEmpty {
                currentLine = wordStr
            } else if currentLine.count + 1 + wordStr.count <= maxWidth {
                currentLine += " \(wordStr)"
            } else {
                lines.append(currentLine)
                currentLine = wordStr
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.isEmpty ? [text] : lines
    }
}
