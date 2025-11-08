import Foundation

public final class ActivityRowCache: @unchecked Sendable {
    private var cache: [UUID: (row: ActivityRow, width: Int, hash: UInt64)] = [:]
    private let lock = NSLock()
    private var hits: Int = 0
    private var misses: Int = 0

    func getOrCreate(
        transaction: InvestmentTransaction,
        model: ActivityRowViewModel,
        width: Int,
        colorManager: ColorManagerProtocol,
        borderRenderer: PanelBorderRenderer,
        maxWidth: Int
    ) -> ActivityRow {
        lock.lock()
        defer { lock.unlock() }

        let hash = model.roundedHash
        if let cached = cache[transaction.id],
           cached.width == width,
           cached.hash == hash {
            hits += 1
            return cached.row
        }

        misses += 1
        let row = ActivityRow(
            model: model,
            width: width,
            colorManager: colorManager,
            borderRenderer: borderRenderer,
            maxWidth: maxWidth
        )

        cache[transaction.id] = (row: row, width: width, hash: hash)
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

    func invalidate(transactionId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: transactionId)
    }

    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    func prefill(
        transactions: [InvestmentTransaction],
        rows: [ActivityRow],
        width: Int,
        colorManager: ColorManagerProtocol,
        borderRenderer: PanelBorderRenderer,
        maxWidth: Int
    ) {
        lock.lock()
        defer { lock.unlock() }

        for (transaction, row) in zip(transactions, rows) {
            let cached = cache[transaction.id]
            if cached == nil || cached!.width != width {
                cache[transaction.id] = (row: row, width: width, hash: 0)
            }
        }
    }
}

public final class ActivityView: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    private let update: TUIUpdate
    private let layout: PanelLayout
    private let colorManager: ColorManagerProtocol
    private let borderStyle: BorderStyle
    private let unicodeSupported: Bool
    private let isFocused: Bool
    private var scrollOffset: Int = 0
    private var allRows: [ActivityRow] = []
    private var visibleRows: [ActivityRow] = []
    private var _measuredSize: Size?
    public var measuredSize: Size? { _measuredSize }
    private var _dirtyReasons: DirtyReason = [.state]
    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { true }
    private static let cache = ActivityRowCache()

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
        scrollOffset: Int = 0,
        id: AnyHashable? = nil
    ) {
        self.update = update
        self.layout = layout
        self.colorManager = colorManager
        self.borderStyle = borderStyle
        self.unicodeSupported = unicodeSupported
        self.isFocused = isFocused
        self.scrollOffset = scrollOffset
        self.id = id ?? AnyHashable(PanelType.activity.rawValue)
        self.nodeID = NodeID()
        self._dirtyReasons = [.state]
    }

    public func buildRows() {
        let borderRenderer = PanelBorderRenderer(
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported
        )

        let width = layout.width
        let now = Date()
        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60)

        let recentTrades = update.data.recentTrades
            .filter { $0.timestamp >= twentyFourHoursAgo }
            .sorted { $0.timestamp > $1.timestamp }

        guard !recentTrades.isEmpty else {
            allRows = []
            visibleRows = []
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"

        let availableWidth = width - 4
        let maxWidth = min(availableWidth, 100)

        var builtRows: [ActivityRow] = []

        for trade in recentTrades {
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

            let asset = trade.asset
            let quantity = String(format: "%.6f", trade.quantity)
            let price = String(format: "%.6f", trade.price)
            let exchange = trade.exchange

            let model = ActivityRowViewModel(
                transaction: trade,
                formattedTime: timeStr,
                typeColor: typeColor,
                typeSymbol: typeSymbol,
                asset: asset,
                quantity: quantity,
                price: price,
                exchange: exchange
            )

            let row = Self.cache.getOrCreate(
                transaction: trade,
                model: model,
                width: width,
                colorManager: colorManager,
                borderRenderer: borderRenderer,
                maxWidth: maxWidth
            )

            builtRows.append(row)
        }

        allRows = builtRows

        let headerLines = 1
        let footerLines = 1
        let maxVisibleRows = max(1, layout.height - headerLines - footerLines - 1)
        let start = min(scrollOffset, max(0, allRows.count - maxVisibleRows))
        let end = min(start + maxVisibleRows, allRows.count)
        visibleRows = Array(allRows[start..<end])

        if visibleRows.count > 0 && visibleRows.count <= maxVisibleRows {
            let visibleTransactions = Array(recentTrades[start..<min(end, recentTrades.count)])
            Self.cache.prefill(
                transactions: visibleTransactions,
                rows: visibleRows,
                width: width,
                colorManager: colorManager,
                borderRenderer: borderRenderer,
                maxWidth: maxWidth
            )
        }

        if ProcessInfo.processInfo.environment["TUI_DEBUG_CACHE"] == "1" {
            let stats = Self.cache.getStats()
            print("[TUI PERF] ActivityRowCache hits:\(stats.hits) misses:\(stats.misses) hitRate:\(String(format: "%.1f", stats.hitRate * 100))% visible:\(visibleRows.count)/\(allRows.count)")
        }
    }

    public func measure(in size: Size) -> Size {
        if let cached = _measuredSize, cached == size {
            return cached
        }
        return Size(width: layout.width, height: visibleRows.count + 2)
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
        // No-op for ActivityView
    }

    public func render(into buf: inout TerminalBuffer, at origin: Point) {
        let borderRenderer = PanelBorderRenderer(
            borderStyle: borderStyle,
            unicodeSupported: unicodeSupported
        )

        let width = layout.width
        let effectiveHeight = max(7, layout.height)

        let now = Date()
        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60)
        let recentTrades = update.data.recentTrades.filter { $0.timestamp >= twentyFourHoursAgo }
            .sorted { $0.timestamp > $1.timestamp }

        let title = "Recent Activity"
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

        if recentTrades.isEmpty {
            let placeholder = "No trades in the last 24 hours"
            let placeholderLine = borderRenderer.renderContentLine(
                content: colorManager.dim(placeholder),
                width: width,
                padding: 1
            )
            if currentY < buf.size.height {
                buf.write(placeholderLine, at: Point(x: origin.x, y: currentY))
            }
            currentY += 1
        } else {
            if visibleRows.isEmpty {
                buildRows()
            }

            let headerLines = 1
            let footerLines = 1
            let maxVisibleRows = max(1, effectiveHeight - headerLines - footerLines - 1)

            for row in visibleRows.prefix(maxVisibleRows) {
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
        return visibleRows
    }
}
