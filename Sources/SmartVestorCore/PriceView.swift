import Foundation

public struct PriceRowViewModel: Sendable {
    let symbol: String
    let price: Double
    let roundedPrice: Double

    init(symbol: String, price: Double) {
        self.symbol = symbol
        self.price = price
        self.roundedPrice = round(price * 1_000_000) / 1_000_000
    }

    var roundedHash: UInt64 {
        var hasher = Hasher()
        hasher.combine(symbol)
        hasher.combine(roundedPrice)
        let result = hasher.finalize()
        return UInt64(bitPattern: Int64(result))
    }
}

public struct PriceRow: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    public let line: ContiguousArray<UInt8>
    public let runs: [AttrRun]
    public var measuredSize: Size?
    private var _dirtyReasons: DirtyReason = []
    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { false }

    public init(
        model: PriceRowViewModel,
        width: Int,
        colorManager: ColorManagerProtocol,
        borderRenderer: PanelBorderRenderer,
        headerPadding: Int = 1
    ) {
        self.id = AnyHashable(model.symbol)
        self.nodeID = NodeID()

        let assetWidth = 10
        let priceWidth = 18

        let symbolPadded = model.symbol.leftPadding(toLength: assetWidth)
        let priceStr = String(format: "$%.6f", model.price)
        let pricePadded = priceStr.rightPadding(toLength: priceWidth)

        let priceLine = "\(symbolPadded)  \(pricePadded)  \(colorManager.dim("-"))"
        let renderedLine = borderRenderer.renderContentLine(content: priceLine, width: width, padding: headerPadding)

        self.line = ContiguousArray(renderedLine.utf8)
        self.runs = []
        self.measuredSize = Size(width: width, height: 1)
    }

    public func measure(in size: Size) -> Size {
        return measuredSize ?? Size(width: size.width, height: 1)
    }

    public func render(into buf: inout TerminalBuffer, at origin: Point) {
        guard origin.y >= 0 && origin.y < buf.size.height else { return }
        let text = String(decoding: line, as: UTF8.self)
        buf.write(text, at: origin)
    }

    public func children() -> [TUIRenderable] {
        return []
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
        hasher.combine(id)
        hasher.combine(line)
    }

    public mutating func markDirty(_ reasons: DirtyReason) {
        _dirtyReasons.formUnion(reasons)
    }

    public mutating func clearDirty() {
        _dirtyReasons = []
    }

    public mutating func markDirty() {
        markDirty(.state)
    }

    public func onFocusChange(_ focused: Bool) {
        // No-op
    }
}

public final class PriceRowCache: @unchecked Sendable {
    private var cache: [String: (row: PriceRow, width: Int, hash: UInt64)] = [:]
    private let lock = NSLock()
    private var hits: Int = 0
    private var misses: Int = 0

    func getOrCreate(
        symbol: String,
        model: PriceRowViewModel,
        width: Int,
        colorManager: ColorManagerProtocol,
        borderRenderer: PanelBorderRenderer,
        headerPadding: Int = 1
    ) -> PriceRow {
        lock.lock()
        defer { lock.unlock() }

        let hash = model.roundedHash
        if let cached = cache[symbol],
           cached.width == width,
           cached.hash == hash {
            hits += 1
            return cached.row
        }

        misses += 1
        let row = PriceRow(
            model: model,
            width: width,
            colorManager: colorManager,
            borderRenderer: borderRenderer,
            headerPadding: headerPadding
        )

        cache[symbol] = (row: row, width: width, hash: hash)
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

    func invalidate(symbol: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: symbol)
    }

    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}

public final class PriceRegion: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    private let prices: [String: Double]
    private let layout: PanelLayout
    private let colorManager: ColorManagerProtocol
    private let borderRenderer: PanelBorderRenderer
    private var rows: [PriceRow] = []
    private var _measuredSize: Size?
    public var measuredSize: Size? { _measuredSize }
    private var _dirtyReasons: DirtyReason = [.state]
    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { true }
    private static let cache = PriceRowCache()

    public static func getStats() -> (hits: Int, misses: Int, hitRate: Double) {
        return cache.getStats()
    }
    private nonisolated(unsafe) static var lastRenderedHash: UInt64 = 0
    private static let hashLock = NSLock()

    public init(
        prices: [String: Double],
        layout: PanelLayout,
        colorManager: ColorManagerProtocol,
        borderRenderer: PanelBorderRenderer,
        id: AnyHashable? = nil
    ) {
        self.prices = prices
        self.layout = layout
        self.colorManager = colorManager
        self.borderRenderer = borderRenderer
        self.id = id ?? AnyHashable("price-region")
        self.nodeID = NodeID()
        self._dirtyReasons = [.state]
    }

    public func buildRows() {
        let width = layout.width
        let effectiveHeight = max(6, layout.height)

        guard !prices.isEmpty else {
            rows = []
            return
        }

        let headerLines = 3
        let footerLines = 1
        let maxRows = max(1, effectiveHeight - headerLines - footerLines)
        let sortedPrices = prices.sorted { $0.key < $1.key }
        let displayPrices = Array(sortedPrices.prefix(maxRows))

        var builtRows: [PriceRow] = []

        for (symbol, price) in displayPrices {
            let model = PriceRowViewModel(symbol: symbol, price: price)

            let row = Self.cache.getOrCreate(
                symbol: symbol,
                model: model,
                width: width,
                colorManager: colorManager,
                borderRenderer: borderRenderer,
                headerPadding: 1
            )

            builtRows.append(row)
        }

        rows = builtRows

        let currentHash = computePricesHash(prices: prices)
        Self.hashLock.lock()
        let changed = Self.lastRenderedHash != currentHash
        if changed {
            Self.lastRenderedHash = currentHash
            _dirtyReasons.formUnion(.state)
        } else {
            _dirtyReasons = []
        }
        Self.hashLock.unlock()

        if ProcessInfo.processInfo.environment["TUI_DEBUG_CACHE"] == "1" {
            let stats = Self.cache.getStats()
            print("[TUI PERF] PriceRowCache hits:\(stats.hits) misses:\(stats.misses) hitRate:\(String(format: "%.1f", stats.hitRate * 100))% dirty:\(!_dirtyReasons.isEmpty)")
        }
    }

    private func computePricesHash(prices: [String: Double]) -> UInt64 {
        var hasher = Hasher()
        for (symbol, price) in prices.sorted(by: { $0.key < $1.key }) {
            hasher.combine(symbol)
            hasher.combine(round(price * 1_000_000) / 1_000_000)
        }
        let result = hasher.finalize()
        return UInt64(bitPattern: Int64(result))
    }

    public func measure(in size: Size) -> Size {
        if let cached = _measuredSize, cached == size {
            return cached
        }
        return Size(width: layout.width, height: rows.count + 3)
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
    }

    public func markDirty() {
        markDirty(.state)
    }

    public func onFocusChange(_ focused: Bool) {
        // No-op
    }

    public func render(into buf: inout TerminalBuffer, at origin: Point) {
        let headerPadding = 1
        let assetWidth = 10
        let priceWidth = 18
        let changeWidth = 12

        if prices.isEmpty {
            let emptyLine = borderRenderer.renderContentLine(
                content: colorManager.dim("No prices available"),
                width: layout.width,
                padding: 1
            )
            if origin.y < buf.size.height {
                buf.write(emptyLine, at: Point(x: origin.x, y: origin.y))
            }
            return
        }

        let assetHeader = "SYMBOL".padding(toLength: assetWidth, withPad: " ", startingAt: 0)
        let priceHeader = "PRICE".padding(toLength: priceWidth, withPad: " ", startingAt: 0)
        let changeHeader = "24H CHANGE".padding(toLength: changeWidth, withPad: " ", startingAt: 0)

        let headerLine = "\(colorManager.blue(assetHeader))  \(colorManager.blue(priceHeader))  \(colorManager.blue(changeHeader))"
        let headerContent = borderRenderer.renderContentLine(
            content: headerLine,
            width: layout.width,
            padding: headerPadding
        )

        var currentY = origin.y
        if currentY < buf.size.height {
            buf.write(headerContent, at: Point(x: origin.x, y: currentY))
        }
        currentY += 1

        let separatorContent = borderRenderer.renderContentLine(
            content: String(repeating: "-", count: layout.width - 4),
            width: layout.width,
            padding: headerPadding
        )
        if currentY < buf.size.height {
            buf.write(separatorContent, at: Point(x: origin.x, y: currentY))
        }
        currentY += 1

        if rows.isEmpty {
            buildRows()
        }

        let effectiveHeight = max(6, layout.height)
        let headerLines = 3
        let footerLines = 1
        let maxRows = max(1, effectiveHeight - headerLines - footerLines)

        for row in rows.prefix(maxRows) {
            if currentY >= origin.y + effectiveHeight - footerLines {
                break
            }
            row.render(into: &buf, at: Point(x: origin.x, y: currentY))
            currentY += 1
        }
    }

    public func children() -> [TUIRenderable] {
        return rows
    }
}

public final class PriceView: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    private let update: TUIUpdate
    private let layout: PanelLayout
    private let colorManager: ColorManagerProtocol
    private let borderStyle: BorderStyle
    private let unicodeSupported: Bool
    private let isFocused: Bool
    private let priceRegion: PriceRegion
    private var _measuredSize: Size?
    public var measuredSize: Size? { _measuredSize }
    private var _dirtyReasons: DirtyReason = [.state]
    public var dirtyReasons: DirtyReason { _dirtyReasons.union(priceRegion.dirtyReasons) }
    public var canReceiveFocus: Bool { false }

    public init(
        update: TUIUpdate,
        layout: PanelLayout,
        colorManager: ColorManagerProtocol,
        borderStyle: BorderStyle,
        unicodeSupported: Bool,
        isFocused: Bool = false,
        id: AnyHashable? = nil
    ) {
        self.update = update
        self.layout = layout
        self.colorManager = colorManager
        self.borderStyle = borderStyle
        self.unicodeSupported = unicodeSupported
        self.isFocused = isFocused
        self.id = id ?? AnyHashable(PanelType.price.rawValue)
        self.nodeID = NodeID()
        self._dirtyReasons = [.state]

        let borderRenderer = PanelBorderRenderer(
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported
        )

        self.priceRegion = PriceRegion(
            prices: update.data.prices,
            layout: layout,
            colorManager: colorManager,
            borderRenderer: borderRenderer
        )

        self._dirtyReasons = [.state]
    }

    public func measure(in size: Size) -> Size {
        if let cached = _measuredSize, cached == size {
            return cached
        }
        let effectiveHeight = max(6, layout.height)
        return Size(width: layout.width, height: effectiveHeight)
    }

    public func markDirty(_ reasons: DirtyReason) {
        _dirtyReasons.formUnion(reasons)
        _measuredSize = nil
        priceRegion.markDirty(reasons)
    }

    public func clearDirty() {
        _dirtyReasons = []
        priceRegion.clearDirty()
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
        // No-op
    }

    public func render(into buf: inout TerminalBuffer, at origin: Point) {
        let borderRenderer = PanelBorderRenderer(
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported
        )

        let width = layout.width
        let effectiveHeight = max(6, layout.height)

        let title = "Prices"
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

        priceRegion.buildRows()
        priceRegion.render(into: &buf, at: Point(x: origin.x, y: currentY))

        let headerLines = 1
        let footerLines = 1
        let regionHeight = 5
        currentY = origin.y + headerLines + regionHeight

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
        return [priceRegion]
    }
}
