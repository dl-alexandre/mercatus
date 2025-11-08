import Foundation

extension String {
func rightPadding(toLength length: Int, withPad pad: String = " ") -> String {
let paddingLength = max(0, length - self.count)
return String(repeating: pad, count: paddingLength) + self
}

    func leftPadding(toLength length: Int, withPad pad: String = " ") -> String {
        let paddingLength = max(0, length - self.count)
        return self + String(repeating: pad, count: paddingLength)
    }
}

public final class BalancePanelRenderer: PanelRenderer, @unchecked Sendable {
    public let panelType: PanelType = .balance
    public let identifier: String = "balance"

    private let sparklineConfig: SparklineConfig
    private let historyTracker: SparklineHistoryTracker?

    public init(
        sparklineConfig: SparklineConfig = .default,
        historyTracker: SparklineHistoryTracker? = nil
    ) {
        self.sparklineConfig = sparklineConfig
        self.historyTracker = historyTracker
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
        prices: [String: Double]? = nil,
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

        let title = "[2] Balances"
        let borderLines = borderRenderer.renderBorder(width: effectiveWidth, height: effectiveHeight, title: title, isFocused: isFocused, colorManager: colorManager)

        guard borderLines.count >= 2 else {
            return RenderedPanel(lines: [], width: effectiveWidth, height: effectiveHeight, hasBorder: borderStyle != .none)
        }

        lines.append(borderLines[0])

        let headerPadding = 1
        let borderChars = borderStyle != .none ? 2 : 0
        let availableContentWidth = effectiveWidth - (headerPadding * 2) - borderChars

        let contentLineAvailableWidth = effectiveWidth - (headerPadding * 2) - 2

        if sparklineConfig.enabled && sparklineConfig.showPortfolioHistory {
            if let historyTracker = historyTracker {
                let portfolioHistory = historyTracker.getPortfolioHistory()
                if !portfolioHistory.isEmpty {
                    let scaler: GraphScaler = {
                        switch sparklineConfig.scalingMode {
                        case .auto:
                            return AutoScaler()
                        case .fixed:
                            let min = sparklineConfig.fixedMin ?? portfolioHistory.min() ?? 0
                            let max = sparklineConfig.fixedMax ?? portfolioHistory.max() ?? 1
                            return FixedScaler(min: min, max: max)
                        case .sync:
                            let min = sparklineConfig.fixedMin ?? portfolioHistory.min() ?? 0
                            let max = sparklineConfig.fixedMax ?? portfolioHistory.max() ?? 1
                            return SyncScaler(sharedRange: min...max)
                        }
                    }()
                    let renderer = SparklineRenderer(
                        unicodeSupported: unicodeSupported,
                        graphMode: sparklineConfig.graphMode,
                        scaler: scaler
                    )
                    let sparkline = renderer.render(
                        values: portfolioHistory,
                        width: min(sparklineConfig.sparklineWidth, availableContentWidth),
                        minHeight: sparklineConfig.minHeight,
                        maxHeight: sparklineConfig.maxHeight
                    )
                    let portfolioLabel = colorManager.blue("Portfolio:")
                    let currentValue = String(format: "$%.2f", input.data.totalPortfolioValue)
                    let portfolioLine = "\(portfolioLabel) \(currentValue) \(sparkline)"
                    let portfolioContent = borderRenderer.renderContentLine(
                        content: portfolioLine,
                        width: effectiveWidth,
                        padding: 1
                    )
                    lines.append(portfolioContent)
                }
            }
        }

        let balances = input.data.balances.filter { $0.available > 0 }

        if balances.isEmpty {
            let emptyLine = borderRenderer.renderContentLine(
                content: colorManager.dim("No balances found"),
                width: effectiveWidth,
                padding: 1
            )
            lines.append(emptyLine)
        } else {
            let sortedBalances = balances.sorted { $0.available > $1.available }

            let sparklineWidth = sparklineConfig.enabled && sparklineConfig.showAssetTrends ? sparklineConfig.sparklineWidth : 0

            let assetWidth = 8
            let valueWidth = 12
            let qtyWidth = 14
            let priceWidth = 12
            let pctWidth = 6
            let timestampWidth = 20
            let spacing = 2

            let assetHeaderPadded = "ASSET".padding(toLength: assetWidth, withPad: " ", startingAt: 0)
            let valueHeaderPadded = "VALUE".padding(toLength: valueWidth, withPad: " ", startingAt: 0)
            let qtyHeaderPadded = "QTY".padding(toLength: qtyWidth, withPad: " ", startingAt: 0)
            let priceHeaderPadded = "PRICE".padding(toLength: priceWidth, withPad: " ", startingAt: 0)
            let pctHeaderPadded = "%".padding(toLength: pctWidth, withPad: " ", startingAt: 0)
            let timestampHeaderPadded = "UPDATED".padding(toLength: timestampWidth, withPad: " ", startingAt: 0)

            let assetHeader = colorManager.blue(assetHeaderPadded)
            let valueHeader = colorManager.blue(valueHeaderPadded)
            let qtyHeader = colorManager.blue(qtyHeaderPadded)
            let priceHeader = colorManager.blue(priceHeaderPadded)
            let pctHeader = colorManager.blue(pctHeaderPadded)
            let timestampHeader = colorManager.blue(timestampHeaderPadded)

            var headerComponents = [assetHeader, valueHeader, qtyHeader, priceHeader, pctHeader, timestampHeader]

            if sparklineWidth > 0 {
                let sparklineHeaderPadded = "TREND".padding(toLength: sparklineWidth, withPad: " ", startingAt: 0)
                let sparklineHeader = colorManager.blue(sparklineHeaderPadded)
                headerComponents.append(sparklineHeader)
            }

            let headerLine = headerComponents.joined(separator: String(repeating: " ", count: spacing))
            let headerContent = borderRenderer.renderContentLine(
                content: headerLine,
                width: effectiveWidth,
                padding: headerPadding
            )
            lines.append(headerContent)

            let separatorLength = contentLineAvailableWidth
            let separatorContent = borderRenderer.renderContentLine(
                content: String(repeating: "-", count: separatorLength),
                width: effectiveWidth,
                padding: headerPadding
            )
            lines.append(separatorContent)

            let formatter = ISO8601DateFormatter()

            var calculatedValues: [String: Double] = [:]
            var calculatedPrices: [String: Double] = [:]
            var totalValue: Double = 0

            for holding in sortedBalances {
                let price: Double
                if let providedPrice = prices?[holding.asset], providedPrice > 0 {
                    price = providedPrice
                } else if let pricesDict = prices {
                    var foundPrice: Double? = nil
                    for (key, value) in pricesDict {
                        if key.uppercased() == holding.asset.uppercased() && value > 0 {
                            foundPrice = value
                            break
                        }
                    }
                    price = foundPrice ?? 0.0
                } else {
                    price = 0.0
                }

                let value = holding.available * price
                calculatedValues[holding.asset] = value
                calculatedPrices[holding.asset] = price
                totalValue += value
            }

            let effectiveTotal = max(0.000001, totalValue)

            let headerLines = 3
            let footerLines = 1
            let maxRows = max(1, effectiveHeight - headerLines - footerLines - 1)
            let maxStartIndex = max(0, sortedBalances.count - maxRows)
            let startIndex = max(0, min(scrollOffset, maxStartIndex))
            let endIndex = min(sortedBalances.count, startIndex + maxRows)
            let displayBalances = Array(sortedBalances[startIndex..<endIndex])

            for holding in displayBalances {
                let price: Double
                if let cachedPrice = calculatedPrices[holding.asset] {
                    price = cachedPrice
                } else if let providedPrice = prices?[holding.asset], providedPrice > 0 {
                    price = providedPrice
                } else if let pricesDict = prices {
                    var foundPrice: Double? = nil
                    for (key, value) in pricesDict {
                        if key.uppercased() == holding.asset.uppercased() && value > 0 {
                            foundPrice = value
                            break
                        }
                    }
                    price = foundPrice ?? 0.0
                } else {
                    price = 0.0
                }
                let value = calculatedValues[holding.asset] ?? 0
                let weight = totalValue > 0 ? (value / effectiveTotal * 100) : 0

                // Left-align text columns, right-align numeric columns
                let assetStrPadded = holding.asset.leftPadding(toLength: assetWidth)

                let valueStrRaw: String
                if totalValue > 0 && value > 0 {
                    valueStrRaw = String(format: "$%.2f", value).rightPadding(toLength: valueWidth)
                } else {
                    valueStrRaw = "-".rightPadding(toLength: valueWidth)
                }

                let qtyStrRaw = String(format: "%.6f", holding.available).rightPadding(toLength: qtyWidth)

                let priceStrRaw: String
                if price > 0 {
                    priceStrRaw = String(format: "%.6f", price).rightPadding(toLength: priceWidth)
                } else {
                    priceStrRaw = "loading...".leftPadding(toLength: priceWidth)
                }

                let pctStrRaw: String
                if totalValue > 0 && value > 0 {
                    if weight < 0.05 {
                        pctStrRaw = String(format: "%5.2f", weight).rightPadding(toLength: pctWidth)
                    } else {
                        pctStrRaw = String(format: "%5.1f", weight).rightPadding(toLength: pctWidth)
                    }
                } else {
                    pctStrRaw = "-".rightPadding(toLength: pctWidth)
                }

                let timestamp = formatter.string(from: holding.updatedAt)
                let timestampStrPadded = timestamp.padding(toLength: timestampWidth, withPad: " ", startingAt: 0)
                let timestampStr = colorManager.dim(timestampStrPadded)

                let assetStr = assetStrPadded
                let valueStr = valueStrRaw
                let qtyStr = qtyStrRaw
                let priceStr = priceStrRaw
                let pctStr = pctStrRaw

                var sparklineStr = ""
                if sparklineWidth > 0, let historyTracker = historyTracker {
                    let assetHistory = historyTracker.getAssetHistory(holding.asset)
                    if !assetHistory.isEmpty {
                        let scaler: GraphScaler = {
                            switch sparklineConfig.scalingMode {
                            case .auto:
                                return AutoScaler()
                            case .fixed:
                                let min = sparklineConfig.fixedMin ?? assetHistory.min() ?? 0
                                let max = sparklineConfig.fixedMax ?? assetHistory.max() ?? 1
                                return FixedScaler(min: min, max: max)
                            case .sync:
                                let min = sparklineConfig.fixedMin ?? assetHistory.min() ?? 0
                                let max = sparklineConfig.fixedMax ?? assetHistory.max() ?? 1
                                return SyncScaler(sharedRange: min...max)
                            }
                        }()
                        let renderer = SparklineRenderer(
                            unicodeSupported: unicodeSupported,
                            graphMode: sparklineConfig.graphMode,
                            scaler: scaler
                        )
                        let sparkline = renderer.render(
                            values: assetHistory,
                            width: sparklineWidth,
                            minHeight: sparklineConfig.minHeight,
                            maxHeight: sparklineConfig.maxHeight
                        )
                        sparklineStr = sparkline.padding(toLength: sparklineWidth, withPad: " ", startingAt: 0)
                    } else {
                        sparklineStr = String(repeating: " ", count: sparklineWidth)
                    }
                }

                var intensityLevel: Int = 0
                if totalValue > 0 && value > 0 {
                    let topPercentage = 20.0
                    if weight >= topPercentage {
                        intensityLevel = 3
                    } else if weight >= topPercentage * 0.5 {
                        intensityLevel = 2
                    } else if weight >= topPercentage * 0.25 {
                        intensityLevel = 1
                    }
                }

                let styledAsset = intensityLevel > 0 ? colorManager.bold(assetStr) : assetStr
                let styledValue = intensityLevel > 0 ? colorManager.bold(valueStr) : valueStr
                let styledQty = intensityLevel > 0 ? colorManager.bold(qtyStr) : qtyStr
                let styledPrice = intensityLevel > 0 ? colorManager.bold(priceStr) : priceStr
                let styledPct = intensityLevel > 0 ? colorManager.bold(pctStr) : pctStr

                var rowComponents = [styledAsset, styledValue, styledQty, styledPrice, styledPct, timestampStr]
                if sparklineWidth > 0 {
                    rowComponents.append(sparklineStr)
                }

                let rowContent = rowComponents.joined(separator: String(repeating: " ", count: spacing))

                let rowLine = borderRenderer.renderContentLine(
                    content: rowContent,
                    width: effectiveWidth,
                    padding: headerPadding
                )
                lines.append(rowLine)
            }
        }

        let contentLinesSoFar = lines.count
        let totalLinesNeeded = effectiveHeight - 1
        let emptyLinesNeeded = max(0, totalLinesNeeded - contentLinesSoFar)

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
            height: effectiveHeight,
            hasBorder: borderStyle != .none
        )
    }
}
