import Foundation

public final class BalanceRowCache: @unchecked Sendable {
    private var cache: [String: (row: BalanceRow, width: Int, hash: UInt64)] = [:]
    private let lock = NSLock()
    private var hits: Int = 0
    private var misses: Int = 0

    func getOrCreate(
        asset: String,
        model: BalanceRowViewModel,
        width: Int,
        colorManager: ColorManagerProtocol,
        borderRenderer: PanelBorderRenderer,
        sparklineStr: String = "",
        spacing: Int = 2
    ) -> BalanceRow {
        lock.lock()
        defer { lock.unlock() }

        let hash = model.roundedHash
        if let cached = cache[asset],
           cached.width == width,
           cached.hash == hash {
            hits += 1
            return cached.row
        }

        misses += 1
        let row = BalanceRow(
            model: model,
            width: width,
            colorManager: colorManager,
            borderRenderer: borderRenderer,
            sparklineStr: sparklineStr,
            spacing: spacing
        )

        cache[asset] = (row: row, width: width, hash: hash)
        return row
    }

    func getStats() -> (hits: Int, misses: Int, hitRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        let total = hits + misses
        let rate = total > 0 ? Double(hits) / Double(total) : 0.0
        return (hits, misses, rate)
    }

    func resetStats() {
        lock.lock()
        defer { lock.unlock() }
        hits = 0
        misses = 0
    }

    func invalidate(asset: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: asset)
    }

    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}

public final class BalancesView: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    private let update: TUIUpdate
    private let layout: PanelLayout
    private let colorManager: ColorManagerProtocol
    private let borderStyle: BorderStyle
    private let unicodeSupported: Bool
    private let isFocused: Bool
    private let prices: [String: Double]?
    private let sparklineConfig: SparklineConfig?
    private let historyTracker: SparklineHistoryTracker?
    private var rows: [BalanceRow]
    private var _measuredSize: Size?
    public var measuredSize: Size? { _measuredSize }
    private var _dirtyReasons: DirtyReason = [.state]
    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { true }
    private static let cache = BalanceRowCache()

    public static func getStats() -> (hits: Int, misses: Int, hitRate: Double) {
        return cache.getStats()
    }

    public init(
        update: TUIUpdate,
        layout: PanelLayout,
        colorManager: ColorManagerProtocol,
        borderStyle: BorderStyle,
        unicodeSupported: Bool,
        isFocused: Bool = false,
        prices: [String: Double]? = nil,
        sparklineConfig: SparklineConfig? = nil,
        historyTracker: SparklineHistoryTracker? = nil,
        id: AnyHashable? = nil
    ) {
        self.update = update
        self.layout = layout
        self.colorManager = colorManager
        self.borderStyle = borderStyle
        self.unicodeSupported = unicodeSupported
        self.isFocused = isFocused
        self.prices = prices
        self.sparklineConfig = sparklineConfig
        self.historyTracker = historyTracker
        self.id = id ?? AnyHashable(PanelType.balances.rawValue)
        self.nodeID = NodeID()
        self.rows = []
        self._dirtyReasons = [.state]
    }

    public func buildRows() {
        let borderRenderer = PanelBorderRenderer(
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported
        )

        let width = layout.width
        let balances = update.data.balances.filter { $0.available > 0 }

        guard !balances.isEmpty else {
            rows = []
            return
        }

        let sortedBalances = balances.sorted { $0.available > $1.available }

        let sparklineWidth = (sparklineConfig?.enabled == true && sparklineConfig?.showAssetTrends == true) ? (sparklineConfig?.sparklineWidth ?? 0) : 0

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
        let maxRows = max(1, layout.height - headerLines - footerLines - 1)
        let displayBalances = Array(sortedBalances.prefix(maxRows))

        var builtRows: [BalanceRow] = []

        for holding in displayBalances {
            let price = calculatedPrices[holding.asset] ?? 0
            let value = calculatedValues[holding.asset] ?? 0
            let weight = totalValue > 0 ? (value / effectiveTotal * 100) : 0

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

            var sparklineStr = ""
            if sparklineWidth > 0, let historyTracker = historyTracker {
                let assetHistory = historyTracker.getAssetHistory(holding.asset)
                if !assetHistory.isEmpty {
                    let config = sparklineConfig ?? SparklineConfig.default
                    let scaler: GraphScaler = {
                        switch config.scalingMode {
                        case .auto:
                            return AutoScaler()
                        case .fixed:
                            let min = config.fixedMin ?? assetHistory.min() ?? 0
                            let max = config.fixedMax ?? assetHistory.max() ?? 1
                            return FixedScaler(min: min, max: max)
                        case .sync:
                            let min = config.fixedMin ?? assetHistory.min() ?? 0
                            let max = config.fixedMax ?? assetHistory.max() ?? 1
                            return SyncScaler(sharedRange: min...max)
                        }
                    }()
                    let renderer = SparklineRenderer(
                        unicodeSupported: unicodeSupported,
                        graphMode: config.graphMode,
                        scaler: scaler
                    )
                    let sparkline = renderer.render(
                        values: assetHistory,
                        width: sparklineWidth,
                        minHeight: config.minHeight,
                        maxHeight: config.maxHeight
                    )
                    sparklineStr = sparkline.padding(toLength: sparklineWidth, withPad: " ", startingAt: 0)
                } else {
                    sparklineStr = String(repeating: " ", count: sparklineWidth)
                }
            }

            let model = BalanceRowViewModel(
                asset: holding.asset,
                value: value,
                qty: holding.available,
                price: price,
                weight: weight,
                timestamp: holding.updatedAt,
                intensityLevel: intensityLevel
            )

            let row = Self.cache.getOrCreate(
                asset: holding.asset,
                model: model,
                width: width,
                colorManager: colorManager,
                borderRenderer: borderRenderer,
                sparklineStr: sparklineStr,
                spacing: 2
            )

            builtRows.append(row)
        }

        rows = builtRows

        if ProcessInfo.processInfo.environment["TUI_DEBUG_CACHE"] == "1" {
            let stats = Self.cache.getStats()
            print("[TUI PERF] BalanceRowCache hits:\(stats.hits) misses:\(stats.misses) hitRate:\(String(format: "%.1f", stats.hitRate * 100))%")
        }
    }

    public func measure(in size: Size) -> Size {
        if let cached = _measuredSize, cached == size {
            return cached
        }
        return Size(width: layout.width, height: rows.count + 4)
    }

    public func markDirty(_ reasons: DirtyReason) {
        _dirtyReasons.formUnion(reasons)
        _measuredSize = nil
    }

    public func clearDirty() {
        _dirtyReasons = []
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
        hasher.combine(id)
        hasher.combine(layout.width)
        hasher.combine(layout.height)
        hasher.combine(isFocused)
    }

    public func markDirty() {
        markDirty(.state)
    }

    public func onFocusChange(_ focused: Bool) {
        // No-op for BalancesView
    }

    public func render(into buf: inout TerminalBuffer, at origin: Point) {
        let borderRenderer = PanelBorderRenderer(
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported
        )

        let width = layout.width
        let effectiveHeight = max(8, layout.height)
        let balances = update.data.balances.filter { $0.available > 0 }

        let title = "Balances"
        let borderLines = borderRenderer.renderBorder(
            width: width,
            height: effectiveHeight,
            title: title,
            isFocused: isFocused,
            colorManager: colorManager
        )

        guard borderLines.count >= 2 else {
            return
        }

        var currentY = origin.y

        if currentY < buf.size.height {
            buf.write(borderLines[0], at: Point(x: origin.x, y: currentY))
        }
        currentY += 1

        if sparklineConfig?.enabled == true && sparklineConfig?.showPortfolioHistory == true,
           let historyTracker = historyTracker {
            let portfolioHistory = historyTracker.getPortfolioHistory()
            if !portfolioHistory.isEmpty {
                let config = sparklineConfig ?? SparklineConfig.default
                let scaler: GraphScaler = {
                    switch config.scalingMode {
                    case .auto:
                        return AutoScaler()
                    case .fixed:
                        let min = config.fixedMin ?? portfolioHistory.min() ?? 0
                        let max = config.fixedMax ?? portfolioHistory.max() ?? 1
                        return FixedScaler(min: min, max: max)
                    case .sync:
                        let min = config.fixedMin ?? portfolioHistory.min() ?? 0
                        let max = config.fixedMax ?? portfolioHistory.max() ?? 1
                        return SyncScaler(sharedRange: min...max)
                    }
                }()
                let renderer = SparklineRenderer(
                    unicodeSupported: unicodeSupported,
                    graphMode: config.graphMode,
                    scaler: scaler
                )
                let sparkline = renderer.render(
                    values: portfolioHistory,
                    width: min(config.sparklineWidth, width - 4),
                    minHeight: config.minHeight,
                    maxHeight: config.maxHeight
                )
                let portfolioLabel = colorManager.blue("Portfolio:")
                let currentValue = String(format: "$%.2f", update.data.totalPortfolioValue)
                let portfolioLine = "\(portfolioLabel) \(currentValue) \(sparkline)"
                let rendered = borderRenderer.renderContentLine(content: portfolioLine, width: width, padding: 1)
                if currentY < buf.size.height {
                    buf.write(rendered, at: Point(x: origin.x, y: currentY))
                }
                currentY += 1
            }
        }

        if balances.isEmpty {
            let emptyLine = borderRenderer.renderContentLine(
                content: colorManager.dim("No balances found"),
                width: width,
                padding: 1
            )
            if currentY < buf.size.height {
                buf.write(emptyLine, at: Point(x: origin.x, y: currentY))
            }
            currentY += 1
        } else {
            let sparklineWidth = (sparklineConfig?.enabled == true && sparklineConfig?.showAssetTrends == true) ? (sparklineConfig?.sparklineWidth ?? 0) : 0

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
            let headerContent = borderRenderer.renderContentLine(content: headerLine, width: width, padding: 1)
            if currentY < buf.size.height {
                buf.write(headerContent, at: Point(x: origin.x, y: currentY))
            }
            currentY += 1

            let separatorLength = width - 4
            let separatorContent = borderRenderer.renderContentLine(
                content: String(repeating: "-", count: separatorLength),
                width: width,
                padding: 1
            )
            if currentY < buf.size.height {
                buf.write(separatorContent, at: Point(x: origin.x, y: currentY))
            }
            currentY += 1

            if rows.isEmpty {
                buildRows()
            }

            let headerLines = 3
            let footerLines = 1
            let maxRows = max(1, effectiveHeight - headerLines - footerLines - 1)

            for row in rows.prefix(maxRows) {
                if currentY >= origin.y + effectiveHeight - footerLines {
                    break
                }
                row.render(into: &buf, at: Point(x: origin.x, y: currentY))
                currentY += 1
            }
        }

        while currentY < origin.y + effectiveHeight - 1 {
            if currentY < buf.size.height {
                let rendered = borderRenderer.renderContentLine(content: "", width: width, padding: 1)
                buf.write(rendered, at: Point(x: origin.x, y: currentY))
            }
            currentY += 1
        }

        if effectiveHeight > 1 && borderLines.count > 1 && currentY < buf.size.height {
            buf.write(borderLines[borderLines.count - 1], at: Point(x: origin.x, y: currentY))
        }
    }

    public func children() -> [TUIRenderable] {
        return rows
    }
}
