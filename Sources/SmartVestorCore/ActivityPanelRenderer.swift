import Foundation

public final class ActivityPanelRenderer: PanelRenderer, @unchecked Sendable {
    public let panelType: PanelType = .activity
    public let identifier: String = "activity"

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
        scrollOffset: Int = 0
    ) async -> RenderedPanel {
        let borderRenderer = PanelBorderRenderer(
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported
        )

        let width = layout.width
        let availableHeight = layout.height
        let effectiveWidth = width
        let effectiveHeight = max(7, availableHeight)

        var lines: [String] = []

        let title = "[3] Recent Activity"
        let borderLines = borderRenderer.renderBorder(width: effectiveWidth, height: effectiveHeight, title: title, isFocused: isFocused, colorManager: colorManager)

        guard borderLines.count >= 2 else {
            return RenderedPanel(lines: [], width: effectiveWidth, height: effectiveHeight, hasBorder: borderStyle != .none)
        }

        lines.append(borderLines[0])

        let now = Date()
        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60)

        if TUIFeatureFlags.isDebugOverlayEnabled {
            let msg = "[ActivityPanel] Total trades in input: \(input.data.recentTrades.count)\n"
            msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            if !input.data.recentTrades.isEmpty {
                let oldest = input.data.recentTrades.map { $0.timestamp }.min() ?? Date()
                let newest = input.data.recentTrades.map { $0.timestamp }.max() ?? Date()
                let ageMsg = "[ActivityPanel] Trade timestamps: oldest=\(oldest) newest=\(newest) cutoff=\(twentyFourHoursAgo)\n"
                ageMsg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            }
        }

        let recentTrades = input.data.recentTrades.filter { $0.timestamp >= twentyFourHoursAgo }
            .sorted { $0.timestamp > $1.timestamp }

        if TUIFeatureFlags.isDebugOverlayEnabled {
            let msg = "[ActivityPanel] Trades after 24h filter: \(recentTrades.count)\n"
            msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
        }

        if recentTrades.isEmpty {
            let placeholder = "No trades in the last 24 hours"
            let placeholderLine = borderRenderer.renderContentLine(
                content: colorManager.dim(placeholder),
                width: effectiveWidth,
                padding: 1
            )
            lines.append(placeholderLine)
        } else {
            let headerLines = 1
            let footerLines = 1
            let maxDisplayLines = max(1, effectiveHeight - headerLines - footerLines - 1)
            let maxStartIndex = max(0, recentTrades.count - maxDisplayLines)
            let startIndex = max(0, min(scrollOffset, maxStartIndex))
            let endIndex = min(recentTrades.count, startIndex + maxDisplayLines)
            let displayTrades = Array(recentTrades[startIndex..<endIndex])

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"

            for trade in displayTrades {
                let timeStr = dateFormatter.string(from: trade.timestamp)

                let typeColor: String
                let typeSymbol: String
                switch trade.type {
                case .buy:
                    typeColor = colorManager.green(trade.type.rawValue.uppercased())
                    typeSymbol = "+"
                case .sell:
                    typeColor = colorManager.red(trade.type.rawValue.uppercased())
                    typeSymbol = "-"
                case .deposit:
                    typeColor = colorManager.blue(trade.type.rawValue.uppercased())
                    typeSymbol = unicodeSupported ? "↑" : "^"
                case .withdrawal:
                    typeColor = colorManager.yellow(trade.type.rawValue.uppercased())
                    typeSymbol = unicodeSupported ? "↓" : "v"
                case .stake:
                    typeColor = colorManager.blue(trade.type.rawValue.uppercased())
                    typeSymbol = unicodeSupported ? "🔒" : "["
                case .unstake:
                    typeColor = colorManager.yellow(trade.type.rawValue.uppercased())
                    typeSymbol = unicodeSupported ? "🔓" : "]"
                case .reward:
                    typeColor = colorManager.green(trade.type.rawValue.uppercased())
                    typeSymbol = unicodeSupported ? "★" : "*"
                case .fee:
                    typeColor = colorManager.dim(trade.type.rawValue.uppercased())
                    typeSymbol = unicodeSupported ? "💰" : "$"
                }

                let asset = colorManager.bold(trade.asset)
                let quantity = String(format: "%.6f", trade.quantity)
                let price = String(format: "%.6f", trade.price)
                let exchange = colorManager.dim(trade.exchange)

                let availableWidth = effectiveWidth - 4
                let maxWidth = min(availableWidth, 100)

                let tradeLine: String
                if maxWidth >= 80 {
                    tradeLine = "\(colorManager.dim(timeStr))  \(typeSymbol) \(typeColor)  \(asset)  qty=\(quantity)  @ \(price)  ex=\(exchange)"
                } else if maxWidth >= 60 {
                    tradeLine = "\(colorManager.dim(timeStr))  \(typeColor)  \(asset)  qty=\(quantity)  @ \(price)"
                } else {
                    tradeLine = "\(colorManager.dim(timeStr))  \(typeColor)  \(asset)  qty=\(quantity)"
                }

                let ansiPattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
                let strippedTradeLine = tradeLine.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
                let visibleWidth = strippedTradeLine.count

                let contentLine: String
                if visibleWidth > maxWidth {
                    let truncatedStripped = String(strippedTradeLine.prefix(maxWidth - 3))
                    if let regex = try? NSRegularExpression(pattern: ansiPattern, options: []) {
                        let range = NSRange(tradeLine.startIndex..<tradeLine.endIndex, in: tradeLine)
                        let ansiMatches = regex.matches(in: tradeLine, options: [], range: range)
                        var codes = ""
                        for match in ansiMatches {
                            if let matchRange = Range(match.range, in: tradeLine) {
                                codes += String(tradeLine[matchRange])
                            }
                        }
                        contentLine = codes + truncatedStripped + "..."
                    } else {
                        contentLine = truncatedStripped + "..."
                    }
                } else {
                    contentLine = tradeLine
                }

                let formattedLine = borderRenderer.renderContentLine(
                    content: contentLine,
                    width: effectiveWidth,
                    padding: 1
                )
                lines.append(formattedLine)
            }
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
