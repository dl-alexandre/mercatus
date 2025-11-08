import Foundation

public struct ActivityRowViewModel: Sendable {
    let transactionId: UUID
    let formattedTime: String
    let typeColor: String
    let typeSymbol: String
    let asset: String
    let quantity: String
    let price: String
    let exchange: String
    let quantityValue: Double
    let priceValue: Double

    init(transaction: InvestmentTransaction, formattedTime: String, typeColor: String, typeSymbol: String, asset: String, quantity: String, price: String, exchange: String) {
        self.transactionId = transaction.id
        self.formattedTime = formattedTime
        self.typeColor = typeColor
        self.typeSymbol = typeSymbol
        self.asset = asset
        self.quantity = quantity
        self.price = price
        self.exchange = exchange
        self.quantityValue = transaction.quantity
        self.priceValue = transaction.price
    }

    var roundedHash: UInt64 {
        var hasher = Hasher()
        hasher.combine(transactionId)
        hasher.combine(round(quantityValue * 1_000_000) / 1_000_000)
        hasher.combine(round(priceValue * 1_000_000) / 1_000_000)
        let result = hasher.finalize()
        return UInt64(bitPattern: Int64(result))
    }
}

public struct ActivityRow: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    public let line: ContiguousArray<UInt8>
    public let runs: [AttrRun]
    public var measuredSize: Size?
    private var _dirtyReasons: DirtyReason = []
    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { false }

    public init(
        model: ActivityRowViewModel,
        width: Int,
        colorManager: ColorManagerProtocol,
        borderRenderer: PanelBorderRenderer,
        maxWidth: Int
    ) {
        self.id = AnyHashable(model.transactionId)
        self.nodeID = NodeID()

        let availableWidth = width - 4
        let effectiveMaxWidth = min(availableWidth, maxWidth)

        let asset = colorManager.bold(model.asset)

        let tradeLine: String
        if effectiveMaxWidth >= 80 {
            tradeLine = "\(colorManager.dim(model.formattedTime))  \(model.typeSymbol) \(model.typeColor)  \(asset)  qty=\(model.quantity)  @ \(model.price)  ex=\(colorManager.dim(model.exchange))"
        } else if effectiveMaxWidth >= 60 {
            tradeLine = "\(colorManager.dim(model.formattedTime))  \(model.typeColor)  \(asset)  qty=\(model.quantity)  @ \(model.price)"
        } else {
            tradeLine = "\(colorManager.dim(model.formattedTime))  \(model.typeColor)  \(asset)  qty=\(model.quantity)"
        }

        let contentLine = tradeLine.count > effectiveMaxWidth
            ? String(tradeLine.prefix(effectiveMaxWidth - 3)) + "..."
            : tradeLine

        let renderedLine = borderRenderer.renderContentLine(content: contentLine, width: width, padding: 1)

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
        // No-op for ActivityRow
    }
}
