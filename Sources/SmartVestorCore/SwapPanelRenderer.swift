import Foundation

public final class SwapPanelRenderer: PanelRenderer, @unchecked Sendable {
    public let panelType: PanelType = .swap
    public let identifier: String = "swap"

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
        let effectiveHeight = max(8, availableHeight)

        var lines: [String] = []

        let title = "[5] Swaps"
        let borderLines = borderRenderer.renderBorder(width: effectiveWidth, height: effectiveHeight, title: title, isFocused: isFocused, colorManager: colorManager)

        guard borderLines.count >= 2 else {
            return RenderedPanel(lines: [], width: effectiveWidth, height: effectiveHeight, hasBorder: borderStyle != .none)
        }

        lines.append(borderLines[0])

        let swapEvaluations = input.data.swapEvaluations

        if swapEvaluations.isEmpty {
            let emptyLine = borderRenderer.renderContentLine(
                content: colorManager.dim("No swap evaluations available"),
                width: effectiveWidth,
                padding: 1
            )
            lines.append(emptyLine)
        } else {
            let selectedIndex = min(max(0, scrollOffset), max(0, swapEvaluations.count - 1))
            let headerPadding = 1
            let fromWidth = 8
            let toWidth = 8
            let qtyWidth = 12
            let netWidth = 12
            let worthWidth = 6
            let confWidth = 8

            let fromHeader = "FROM".padding(toLength: fromWidth, withPad: " ", startingAt: 0)
            let toHeader = "TO".padding(toLength: toWidth, withPad: " ", startingAt: 0)
            let qtyHeader = "QTY".padding(toLength: qtyWidth, withPad: " ", startingAt: 0)
            let netHeader = "NET VALUE".padding(toLength: netWidth, withPad: " ", startingAt: 0)
            let worthHeader = "OK?".padding(toLength: worthWidth, withPad: " ", startingAt: 0)
            let confHeader = "CONF".padding(toLength: confWidth, withPad: " ", startingAt: 0)

            let headerLine = "\(colorManager.blue(fromHeader))  \(colorManager.blue(toHeader))  \(colorManager.blue(qtyHeader))  \(colorManager.blue(netHeader))  \(colorManager.blue(worthHeader))  \(colorManager.blue(confHeader))"
            let headerContent = borderRenderer.renderContentLine(
                content: headerLine,
                width: effectiveWidth,
                padding: headerPadding
            )
            lines.append(headerContent)

            let separatorContent = borderRenderer.renderContentLine(
                content: String(repeating: "-", count: effectiveWidth - 4),
                width: effectiveWidth,
                padding: headerPadding
            )
            lines.append(separatorContent)

            let headerLines = 3
            let footerLines = 2 // summary line + bottom border
            let maxRows = max(1, effectiveHeight - headerLines - footerLines)
            let maxStartIndex = max(0, swapEvaluations.count - maxRows)
            let startIndex = max(0, min(scrollOffset, maxStartIndex))
            let endIndex = min(swapEvaluations.count, startIndex + maxRows)
            let visibleEvaluations = Array(swapEvaluations[startIndex..<endIndex])

            for (index, evaluation) in visibleEvaluations.enumerated() {
                let actualIndex = startIndex + index
                let isSelected = actualIndex == selectedIndex

                let fromStr = evaluation.fromAsset.padding(toLength: fromWidth, withPad: " ", startingAt: 0)
                let toStr = evaluation.toAsset.padding(toLength: toWidth, withPad: " ", startingAt: 0)
                let qtyStr = String(format: "%.4f", evaluation.fromQuantity).padding(toLength: qtyWidth, withPad: " ", startingAt: 0)
                let netStr = String(format: "$%.2f", evaluation.netValue).padding(toLength: netWidth, withPad: " ", startingAt: 0)
                let worthStr = evaluation.isWorthwhile ? colorManager.green("YES") : colorManager.red("NO")
                let worthPadded = worthStr.padding(toLength: worthWidth, withPad: " ", startingAt: 0)
                let confStr = String(format: "%.0f%%", evaluation.confidence * 100).padding(toLength: confWidth, withPad: " ", startingAt: 0)

                var rowLine = "\(fromStr)  \(toStr)  \(qtyStr)  \(netStr)  \(worthPadded)  \(confStr)"

                if isSelected {
                    rowLine = colorManager.yellow(rowLine)
                }

                let rowContent = borderRenderer.renderContentLine(
                    content: rowLine,
                    width: effectiveWidth,
                    padding: headerPadding
                )
                lines.append(rowContent)
            }

            let summaryText: String = {
                let startDisplay = startIndex + 1
                let endDisplay = endIndex
                let rangeSummary = "\(startDisplay)-\(endDisplay) of \(swapEvaluations.count)"
                let indicatorPrefix = startIndex > 0 ? "↑ " : ""
                let indicatorSuffix = endIndex < swapEvaluations.count ? " ↓" : ""
                let base = "\(indicatorPrefix)\(rangeSummary)\(indicatorSuffix)"
                let instructions = "[J/K] Scroll  [Ctrl+J/K] Page  [E] Execute"
                let combined = "\(base)  \(instructions)"
                let maxContentWidth = max(0, effectiveWidth - 4)
                if combined.count <= maxContentWidth {
                    return combined
                }
                if instructions.count >= maxContentWidth {
                    return String(instructions.prefix(maxContentWidth))
                }
                let trimmedBaseCount = max(0, maxContentWidth - instructions.count - 2)
                let trimmedBase = String(base.prefix(trimmedBaseCount))
                return "\(trimmedBase)  \(instructions)"
            }()

            let summaryLine = borderRenderer.renderContentLine(
                content: colorManager.dim(summaryText),
                width: effectiveWidth,
                padding: headerPadding
            )
            lines.append(summaryLine)
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

extension String {
    func padding(toLength length: Int, withPad pad: String = " ", startingAt index: Int) -> String {
        let currentLength = self.count
        if currentLength >= length {
            return String(self.prefix(length))
        }
        let padding = String(repeating: pad, count: length - currentLength)
        return self + padding
    }
}
