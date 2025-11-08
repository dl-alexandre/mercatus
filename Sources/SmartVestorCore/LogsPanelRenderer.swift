import Foundation

public final class LogsPanelRenderer: PanelRenderer, @unchecked Sendable {
    public let panelType: PanelType = .logs
    public let identifier: String = "logs"

    private var logEntries: [String]

    public init() {
        self.logEntries = []
    }

    public func setLogEntries(_ entries: [String]) {
        self.logEntries = entries
    }

    public func render(
        input: TUIUpdate,
        layout: PanelLayout,
        colorManager: ColorManagerProtocol,
        borderStyle: BorderStyle,
        unicodeSupported: Bool
    ) async -> RenderedPanel {
        return await render(
            input: input,
            layout: layout,
            colorManager: colorManager,
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported,
            isFocused: false
        )
    }

    public func render(
        input: TUIUpdate,
        layout: PanelLayout,
        colorManager: ColorManagerProtocol,
        borderStyle: BorderStyle,
        unicodeSupported: Bool,
        isFocused: Bool,
        scrollOffset: Int = 0
    ) async -> RenderedPanel {
        let borderRenderer = PanelBorderRenderer(
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported
        )

        let width = layout.width
        let availableHeight = layout.height
        let effectiveWidth = width
        let effectiveHeight = max(6, availableHeight)

        var lines: [String] = []

        let title = "[6] Logs"
        let borderLines = borderRenderer.renderBorder(width: effectiveWidth, height: effectiveHeight, title: title, isFocused: isFocused, colorManager: colorManager)

        guard borderLines.count >= 2 else {
            return RenderedPanel(lines: [], width: effectiveWidth, height: effectiveHeight, hasBorder: borderStyle != .none)
        }

        lines.append(borderLines[0])

        let headerPadding = 1
        let headerLines = 3
        let footerLines = 1
        let maxRows = max(1, effectiveHeight - headerLines - footerLines)

        if logEntries.isEmpty {
            let emptyLine = borderRenderer.renderContentLine(
                content: colorManager.dim("No logs available"),
                width: effectiveWidth,
                padding: headerPadding
            )
            lines.append(emptyLine)
        } else {
            let startIndex = max(0, min(scrollOffset, logEntries.count - maxRows))
            let endIndex = min(logEntries.count, startIndex + maxRows)
            let visibleLogs = Array(logEntries[startIndex..<endIndex])

            for logEntry in visibleLogs {
                let logLine = borderRenderer.renderContentLine(
                    content: logEntry,
                    width: effectiveWidth,
                    padding: headerPadding
                )
                lines.append(logLine)
            }
        }

        let contentLinesSoFar = lines.count
        let linesNeeded = effectiveHeight - 1
        let emptyLinesNeeded = max(0, linesNeeded - contentLinesSoFar)

        for _ in 0..<emptyLinesNeeded {
            let emptyLine = borderRenderer.renderContentLine(
                content: "",
                width: effectiveWidth,
                padding: 1
            )
            lines.append(emptyLine)
        }

        if borderLines.count > 1 {
            lines.append(borderLines[borderLines.count - 1])
        } else {
            let bottomBorder = borderRenderer.renderBottomBorder(width: effectiveWidth)
            lines.append(bottomBorder)
        }

        return RenderedPanel(
            lines: lines,
            width: effectiveWidth,
            height: lines.count,
            hasBorder: borderStyle != .none
        )
    }
}
