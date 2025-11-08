import Foundation

public final class StatusPanelRenderer: PanelRenderer, @unchecked Sendable {
    public let panelType: PanelType = .status
    public let identifier: String = "status"

    public init() {}

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
        isFocused: Bool
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

        let title = "[1] Status"
        let borderLines = borderRenderer.renderBorder(width: effectiveWidth, height: effectiveHeight, title: title, isFocused: isFocused, colorManager: colorManager)

        let state = input.state

        guard borderLines.count >= 2 else {
            var fallbackLines: [String] = []
            let topBorder = borderRenderer.renderTopBorder(width: effectiveWidth)
            fallbackLines.append(topBorder)
            let errorLine = borderRenderer.renderContentLine(
                content: colorManager.red("⚠️  Rendering failed: invalid border size"),
                width: effectiveWidth,
                padding: 1
            )
            fallbackLines.append(errorLine)
            let stateLine = borderRenderer.renderContentLine(
                content: "State: \(state.isRunning ? colorManager.green("RUNNING") : colorManager.red("STOPPED"))",
                width: effectiveWidth,
                padding: 1
            )
            fallbackLines.append(stateLine)
            while fallbackLines.count < effectiveHeight - 1 {
                fallbackLines.append(borderRenderer.renderContentLine(content: "", width: effectiveWidth, padding: 1))
            }
            if effectiveHeight > 1 {
                fallbackLines.append(borderRenderer.renderBottomBorder(width: effectiveWidth))
            }
            return RenderedPanel(lines: fallbackLines, width: effectiveWidth, height: fallbackLines.count, hasBorder: borderStyle != .none)
        }

        lines.append(borderLines[0])

        let data = input.data

        let isRunning = state.isRunning
        let hasErrors = data.errorCount > 0
        let circuitBreakerOpen = data.circuitBreakerOpen

        let statusColor: String

        if !isRunning {
            statusColor = colorManager.red("STOPPED")
        } else if hasErrors || circuitBreakerOpen {
            statusColor = colorManager.yellow("WARNING")
        } else {
            statusColor = colorManager.green("RUNNING")
        }

        let stateLine = borderRenderer.renderContentLine(
            content: "State: \(statusColor)",
            width: effectiveWidth,
            padding: 1
        )
        lines.append(stateLine)

        let mode = state.mode.rawValue
        let modeLine = borderRenderer.renderContentLine(
            content: "Mode: \(colorManager.blue(mode))",
            width: effectiveWidth,
            padding: 1
        )
        lines.append(modeLine)

        let seqLine = borderRenderer.renderContentLine(
            content: "Sequence: \(colorManager.dim(String(input.sequenceNumber)))",
            width: effectiveWidth,
            padding: 1
        )
        lines.append(seqLine)

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: input.timestamp)
        let tsLine = borderRenderer.renderContentLine(
            content: "Timestamp: \(colorManager.dim(timestamp))",
            width: effectiveWidth,
            padding: 1
        )
        lines.append(tsLine)

        if hasErrors || circuitBreakerOpen {
            var errorParts: [String] = []
            if data.errorCount > 0 {
                errorParts.append("\(data.errorCount) error\(data.errorCount == 1 ? "" : "s")")
            }
            if circuitBreakerOpen {
                errorParts.append("Circuit Breaker: \(colorManager.red("OPEN"))")
            } else {
                errorParts.append("Circuit Breaker: \(colorManager.green("CLOSED"))")
            }

            let errorSummary = errorParts.joined(separator: ", ")
            let errorLine = borderRenderer.renderContentLine(
                content: "Errors: \(errorSummary)",
                width: effectiveWidth,
                padding: 1
            )
            lines.append(errorLine)
        } else {
            let cbLine = borderRenderer.renderContentLine(
                content: "Circuit Breaker: \(colorManager.green("CLOSED"))",
                width: effectiveWidth,
                padding: 1
            )
            lines.append(cbLine)
        }

        if let lastExec = data.lastExecutionTime {
            let lastExecStr = formatter.string(from: lastExec)
            let lastExecLine = borderRenderer.renderContentLine(
                content: "Last Exec: \(colorManager.dim(lastExecStr))",
                width: effectiveWidth,
                padding: 1
            )
            lines.append(lastExecLine)
        }

        while lines.count < effectiveHeight - 1 {
            let emptyLine = borderRenderer.renderContentLine(
                content: "",
                width: effectiveWidth,
                padding: 1
            )
            lines.append(emptyLine)
        }

        if effectiveHeight > 1 && borderLines.count > 1 {
            lines.append(borderLines[borderLines.count - 1])
        } else if effectiveHeight > 1 {
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
