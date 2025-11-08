import Foundation

public struct BalanceRowViewModel: Sendable {
    let asset: String
    let value: Double
    let qty: Double
    let price: Double
    let weight: Double
    let timestamp: Date
    let intensityLevel: Int

    var roundedHash: UInt64 {
        var hasher = Hasher()
        hasher.combine(asset)
        hasher.combine(round(value * 100) / 100)
        hasher.combine(round(qty * 1_000_000) / 1_000_000)
        hasher.combine(round(price * 1_000_000) / 1_000_000)
        hasher.combine(round(weight * 10) / 10)
        let result = hasher.finalize()
        return UInt64(bitPattern: Int64(result))
    }
}

public struct BalanceRow: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    public let line: ContiguousArray<UInt8>
    public let runs: [AttrRun]
    public var measuredSize: Size?
    private var _dirtyReasons: DirtyReason = []
    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { false }

    public init(
        model: BalanceRowViewModel,
        width: Int,
        colorManager: ColorManagerProtocol,
        borderRenderer: PanelBorderRenderer,
        sparklineStr: String = "",
        spacing: Int = 2
    ) {
        self.id = AnyHashable(model.asset)
        self.nodeID = NodeID()

        let assetWidth = 8
        let valueWidth = 12
        let qtyWidth = 14
        let priceWidth = 12
        let pctWidth = 6
        let timestampWidth = 20

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: model.timestamp)

        let assetStrPadded = model.asset.leftPadding(toLength: assetWidth)

        let valueStrRaw: String
        if model.value > 0 {
            valueStrRaw = String(format: "$%.2f", model.value).rightPadding(toLength: valueWidth)
        } else {
            valueStrRaw = "-".rightPadding(toLength: valueWidth)
        }

        let qtyStrRaw = String(format: "%.6f", model.qty).rightPadding(toLength: qtyWidth)

        let priceStrRaw: String
        if model.price > 0 {
            priceStrRaw = String(format: "%.6f", model.price).rightPadding(toLength: priceWidth)
        } else {
            priceStrRaw = "loading...".leftPadding(toLength: priceWidth)
        }

        let pctStrRaw: String
        if model.weight > 0 {
            if model.weight < 0.05 {
                pctStrRaw = String(format: "%5.2f", model.weight).rightPadding(toLength: pctWidth)
            } else {
                pctStrRaw = String(format: "%5.1f", model.weight).rightPadding(toLength: pctWidth)
            }
        } else {
            pctStrRaw = "-".rightPadding(toLength: pctWidth)
        }

        let timestampStrPadded = timestamp.padding(toLength: timestampWidth, withPad: " ", startingAt: 0)
        let timestampStr = colorManager.dim(timestampStrPadded)

        let styledAsset = model.intensityLevel > 0 ? colorManager.bold(assetStrPadded) : assetStrPadded
        let styledValue = model.intensityLevel > 0 ? colorManager.bold(valueStrRaw) : valueStrRaw
        let styledQty = model.intensityLevel > 0 ? colorManager.bold(qtyStrRaw) : qtyStrRaw
        let styledPrice = model.intensityLevel > 0 ? colorManager.bold(priceStrRaw) : priceStrRaw
        let styledPct = model.intensityLevel > 0 ? colorManager.bold(pctStrRaw) : pctStrRaw

        var rowComponents = [styledAsset, styledValue, styledQty, styledPrice, styledPct, timestampStr]
        if !sparklineStr.isEmpty {
            rowComponents.append(sparklineStr)
        }

        let rowContent = rowComponents.joined(separator: String(repeating: " ", count: spacing))
        let renderedLine = borderRenderer.renderContentLine(content: rowContent, width: width, padding: 1)

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
        // No-op for BalanceRow
    }
}
