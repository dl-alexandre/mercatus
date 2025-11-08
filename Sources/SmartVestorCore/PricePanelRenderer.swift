import Foundation

public final class PricePanelRenderer: PanelRenderer, @unchecked Sendable {
    public let panelType: PanelType = .price
    public let identifier: String = "price"

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
        isFocused: Bool,
        prices: [String: Double]? = nil,
        scrollOffset: Int = 0,
        priceSortManager: PriceSortManager? = nil
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

        let title = "[4] Prices"
        let borderLines = borderRenderer.renderBorder(width: effectiveWidth, height: effectiveHeight, title: title, isFocused: isFocused, colorManager: colorManager)

        guard borderLines.count >= 2 else {
            return RenderedPanel(lines: [], width: effectiveWidth, height: effectiveHeight, hasBorder: borderStyle != .none)
        }

        lines.append(borderLines[0])

        let pricesToUse = prices ?? input.data.prices

        if TUIFeatureFlags.isDebugOverlayEnabled {
            let msg = "[PricePanel] pricesToUse count=\(pricesToUse.count) fromParam=\(prices != nil) fromInput=\(!input.data.prices.isEmpty)\n"
            msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            if !pricesToUse.isEmpty {
                let sample = Array(pricesToUse.prefix(3)).map { "\($0.key):\($0.value)" }.joined(separator: ", ")
                let sampleMsg = "[PricePanel] Sample prices: \(sample)\n"
                sampleMsg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            }
        }

        if pricesToUse.isEmpty {
            let emptyLine = borderRenderer.renderContentLine(
                content: colorManager.dim("No prices available"),
                width: effectiveWidth,
                padding: 1
            )
            lines.append(emptyLine)
        } else {
            let headerPadding = 1
            let leftBorderWidth = borderRenderer.measureVisibleWidth("│")
            let rightBorderWidth = borderRenderer.measureVisibleWidth("│")
            let paddingWidth = headerPadding * 2
            let availableContentWidth = effectiveWidth - leftBorderWidth - rightBorderWidth - paddingWidth
            let columnSpacing = 2

            let assetWidth = 10
            let priceWidth = 18
            let changeWidth = min(12, availableContentWidth - assetWidth - priceWidth - (columnSpacing * 2))

            let assetHeader = "SYMBOL".padding(toLength: assetWidth, withPad: " ", startingAt: 0)
            let priceHeader = "PRICE".padding(toLength: priceWidth, withPad: " ", startingAt: 0)
            let changeHeader = "24H CHANGE".padding(toLength: changeWidth, withPad: " ", startingAt: 0)

            let headerLine = "\(colorManager.blue(assetHeader))  \(colorManager.blue(priceHeader))  \(colorManager.blue(changeHeader))"
            let headerContent = borderRenderer.renderContentLine(
                content: headerLine,
                width: effectiveWidth,
                padding: headerPadding
            )
            lines.append(headerContent)

            let separatorLine = String(repeating: "-", count: max(1, availableContentWidth))
            let separatorContent = borderRenderer.renderContentLine(
                content: separatorLine,
                width: effectiveWidth,
                padding: headerPadding
            )
            lines.append(separatorContent)

            let sortedPrices: [(String, Double)]
            if let sortManager = priceSortManager {
                sortedPrices = await sortManager.sortPrices(pricesToUse)
            } else {
                sortedPrices = pricesToUse.sorted { $0.key < $1.key }
            }

            let headerLines = 3
            let footerLines = 1
            let maxRows = max(1, effectiveHeight - headerLines - footerLines)
            let maxStartIndex = max(0, sortedPrices.count - maxRows)
            let startIndex = max(0, min(scrollOffset, maxStartIndex))
            let endIndex = min(sortedPrices.count, startIndex + maxRows)
            let displayPrices = Array(sortedPrices[startIndex..<endIndex])

            for (symbol, price) in displayPrices {
                let symbolPadded = symbol.leftPadding(toLength: assetWidth)
                let priceStr = String(format: "$%.6f", price)
                let pricePadded = priceStr.rightPadding(toLength: priceWidth)
                let changeStr = "—".leftPadding(toLength: changeWidth)
                let changePadded = colorManager.dim(changeStr)

                let priceLine = "\(symbolPadded)  \(pricePadded)  \(changePadded)"

                if TUIFeatureFlags.isDebugOverlayEnabled {
                    let ansiPattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
                    let stripped = priceLine.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
                    let visibleWidth = borderRenderer.measureVisibleWidth(stripped)
                    let msg = "[PricePanel] Line for \(symbol): priceStr='\(priceStr)' pricePadded='\(pricePadded)' visibleWidth=\(visibleWidth)\n"
                    msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
                }

                let priceContent = borderRenderer.renderContentLine(
                    content: priceLine,
                    width: effectiveWidth,
                    padding: headerPadding
                )
                lines.append(priceContent)
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
