import Foundation

public struct Rect: Equatable, Hashable, Sendable {
    public var origin: Point
    public var size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.origin = Point(x: x, y: y)
        self.size = Size(width: width, height: height)
    }

    public var isEmpty: Bool {
        return size.isEmpty || origin.x < 0 || origin.y < 0
    }

    public func contains(_ point: Point) -> Bool {
        return point.x >= origin.x && point.x < origin.x + size.width &&
               point.y >= origin.y && point.y < origin.y + size.height
    }

    public func intersection(_ other: Rect) -> Rect {
        let minX = max(origin.x, other.origin.x)
        let minY = max(origin.y, other.origin.y)
        let maxX = min(origin.x + size.width, other.origin.x + other.size.width)
        let maxY = min(origin.y + size.height, other.origin.y + other.size.height)

        if maxX <= minX || maxY <= minY {
            return Rect(origin: .zero, size: .zero)
        }

        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public struct DirtyReason: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let state = DirtyReason(rawValue: 1 << 0)
    public static let layout = DirtyReason(rawValue: 1 << 1)
    public static let style = DirtyReason(rawValue: 1 << 2)
    public static let visibility = DirtyReason(rawValue: 1 << 3)
    public static let focus = DirtyReason(rawValue: 1 << 4)
    public static let env = DirtyReason(rawValue: 1 << 5)
}

public enum FlexDirection: Sendable, Hashable {
    case row
    case column
}

public enum JustifyContent: Sendable, Hashable {
    case flexStart
    case flexEnd
    case center
    case spaceBetween
    case spaceAround
    case spaceEvenly
}

public enum AlignItems: Sendable, Hashable {
    case flexStart
    case flexEnd
    case center
    case stretch
}

public struct FlexProperties: Sendable {
    public let flexGrow: Int
    public let flexShrink: Int
    public let flexBasis: Int?

    public init(flexGrow: Int = 0, flexShrink: Int = 1, flexBasis: Int? = nil) {
        self.flexGrow = max(0, flexGrow)
        self.flexShrink = max(0, flexShrink)
        self.flexBasis = flexBasis
    }

    public static let `default` = FlexProperties(flexGrow: 0, flexShrink: 1, flexBasis: nil)
}

public struct FlexLayout: Sendable {
    public let direction: FlexDirection
    public let justifyContent: JustifyContent
    public let alignItems: AlignItems
    public let gap: Int

    public init(
        direction: FlexDirection = .column,
        justifyContent: JustifyContent = .flexStart,
        alignItems: AlignItems = .flexStart,
        gap: Int = 0
    ) {
        self.direction = direction
        self.justifyContent = justifyContent
        self.alignItems = alignItems
        self.gap = max(0, gap)
    }

    public static let `default` = FlexLayout()
}

public protocol TUIRenderable: Sendable {
    var id: AnyHashable { get }

    var nodeID: NodeID { get }

    var dirty: Bool { get }

    var dirtyReasons: DirtyReason { get }

    var measuredSize: Size? { get }

    var canReceiveFocus: Bool { get }

    func measure(in size: Size) -> Size

    func render(into buf: inout TerminalBuffer, at origin: Point)

    func children() -> [TUIRenderable]

    func structuralHash(into hasher: inout Hasher)

    func markDirty(_ reasons: DirtyReason)

    func clearDirty()

    func onFocusChange(_ focused: Bool)
}

public extension TUIRenderable {
    func bounds(in size: Size, at origin: Point) -> Rect {
        let measured = measure(in: size)
        return Rect(origin: origin, size: measured)
    }

    var dirty: Bool { !dirtyReasons.isEmpty }

    var dirtyReasons: DirtyReason { [] }

    var measuredSize: Size? { nil }

    var canReceiveFocus: Bool { false }

    var flexProperties: FlexProperties { .default }

    var flexLayout: FlexLayout? { nil }

    func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
    }

    func markDirty(_ reasons: DirtyReason) {}

    func clearDirty() {}

    func onFocusChange(_ focused: Bool) {}
}

public struct LayoutEngine {
    public static func measure(_ root: TUIRenderable, in availableSize: Size) -> Size {
        if let flexLayout = root.flexLayout {
            return measureFlex(root, flexLayout: flexLayout, in: availableSize)
        }
        return root.measure(in: availableSize)
    }

    public static func layout(_ root: TUIRenderable, in availableSize: Size) -> Size {
        let measured = measure(root, in: availableSize)
        return Size(width: min(measured.width, availableSize.width),
                   height: min(measured.height, availableSize.height))
    }

    public static func layoutFlex(_ root: TUIRenderable, flexLayout: FlexLayout, in availableSize: Size, at origin: Point, into buffer: inout TerminalBuffer) {
        let children = root.children()
        guard !children.isEmpty else { return }

        let isRow = flexLayout.direction == .row
        let mainAxisSize = isRow ? availableSize.width : availableSize.height
        let crossAxisSize = isRow ? availableSize.height : availableSize.width

        var childSizes: [Size] = []
        var childFlexProps: [FlexProperties] = []

        for child in children {
            let constrainedSize = isRow
                ? Size(width: availableSize.width, height: crossAxisSize)
                : Size(width: crossAxisSize, height: availableSize.height)
            let measured = child.measure(in: constrainedSize)
            childSizes.append(measured)
            childFlexProps.append(child.flexProperties)
        }

        let totalGap = flexLayout.gap * max(0, children.count - 1)
        let totalMainAxisSize = isRow
            ? childSizes.reduce(0) { $0 + $1.width } + totalGap
            : childSizes.reduce(0) { $0 + $1.height } + totalGap

        var finalSizes = childSizes
        let remainingSpace = mainAxisSize - totalMainAxisSize

        if remainingSpace != 0 {
            let totalFlexGrow = childFlexProps.reduce(0) { $0 + $1.flexGrow }
            let totalFlexShrink = childFlexProps.reduce(0) { $0 + $1.flexShrink }

            if remainingSpace > 0 && totalFlexGrow > 0 {
                for i in 0..<children.count {
                    let flexGrow = childFlexProps[i].flexGrow
                    if flexGrow > 0 {
                        let growAmount = (remainingSpace * flexGrow) / totalFlexGrow
                        if isRow {
                            finalSizes[i] = Size(width: childSizes[i].width + growAmount, height: childSizes[i].height)
                        } else {
                            finalSizes[i] = Size(width: childSizes[i].width, height: childSizes[i].height + growAmount)
                        }
                    }
                }
            } else if remainingSpace < 0 && totalFlexShrink > 0 {
                let shrinkAmount = abs(remainingSpace)
                for i in 0..<children.count {
                    let flexShrink = childFlexProps[i].flexShrink
                    if flexShrink > 0 {
                        let shrink = (shrinkAmount * flexShrink) / totalFlexShrink
                        if isRow {
                            finalSizes[i] = Size(width: max(0, childSizes[i].width - shrink), height: childSizes[i].height)
                        } else {
                            finalSizes[i] = Size(width: childSizes[i].width, height: max(0, childSizes[i].height - shrink))
                        }
                    }
                }
            }
        }

        let finalMainAxisSize = isRow
            ? finalSizes.reduce(0) { $0 + $1.width } + totalGap
            : finalSizes.reduce(0) { $0 + $1.height } + totalGap

        let remainingSpaceForJustification = mainAxisSize - finalMainAxisSize

        var spacingBetweenItems: Int = flexLayout.gap
        var initialOffset: Int = 0

        switch flexLayout.justifyContent {
        case .flexStart:
            initialOffset = 0
            spacingBetweenItems = flexLayout.gap
        case .flexEnd:
            initialOffset = remainingSpaceForJustification
            spacingBetweenItems = flexLayout.gap
        case .center:
            initialOffset = remainingSpaceForJustification / 2
            spacingBetweenItems = flexLayout.gap
        case .spaceBetween:
            initialOffset = 0
            if children.count > 1 {
                spacingBetweenItems = flexLayout.gap + (remainingSpaceForJustification / max(1, children.count - 1))
            } else {
                spacingBetweenItems = flexLayout.gap
            }
        case .spaceAround:
            if children.count > 0 {
                let spacePerItem = remainingSpaceForJustification / max(1, children.count)
                initialOffset = spacePerItem / 2
                spacingBetweenItems = flexLayout.gap + spacePerItem
            } else {
                initialOffset = 0
                spacingBetweenItems = flexLayout.gap
            }
        case .spaceEvenly:
            if children.count > 0 {
                let spacePerGap = remainingSpaceForJustification / max(1, children.count + 1)
                initialOffset = spacePerGap
                spacingBetweenItems = flexLayout.gap + spacePerGap
            } else {
                initialOffset = 0
                spacingBetweenItems = flexLayout.gap
            }
        }

        var currentMainAxis = origin.x + (isRow ? initialOffset : 0)
        var currentCrossAxis = origin.y + (isRow ? 0 : initialOffset)

        for (index, child) in children.enumerated() {
            let finalSize = finalSizes[index]
            var childOrigin: Point

            if isRow {
                let crossAxisOffset: Int
                switch flexLayout.alignItems {
                case .flexStart:
                    crossAxisOffset = 0
                case .flexEnd:
                    crossAxisOffset = crossAxisSize - finalSize.height
                case .center:
                    crossAxisOffset = (crossAxisSize - finalSize.height) / 2
                case .stretch:
                    crossAxisOffset = 0
                }

                childOrigin = Point(x: currentMainAxis, y: origin.y + crossAxisOffset)
            } else {
                let crossAxisOffset: Int
                switch flexLayout.alignItems {
                case .flexStart:
                    crossAxisOffset = 0
                case .flexEnd:
                    crossAxisOffset = crossAxisSize - finalSize.width
                case .center:
                    crossAxisOffset = (crossAxisSize - finalSize.width) / 2
                case .stretch:
                    crossAxisOffset = 0
                }

                childOrigin = Point(x: origin.x + crossAxisOffset, y: currentCrossAxis)
            }

            let stretchedSize: Size
            if flexLayout.alignItems == .stretch {
                if isRow {
                    stretchedSize = Size(width: finalSize.width, height: crossAxisSize)
                } else {
                    stretchedSize = Size(width: crossAxisSize, height: finalSize.height)
                }
            } else {
                stretchedSize = finalSize
            }

            child.render(into: &buffer, at: childOrigin)

            if isRow {
                currentMainAxis += stretchedSize.width
                if index < children.count - 1 {
                    currentMainAxis += spacingBetweenItems
                }
            } else {
                currentCrossAxis += stretchedSize.height
                if index < children.count - 1 {
                    currentCrossAxis += spacingBetweenItems
                }
            }
        }
    }

    public static func measureFlex(_ root: TUIRenderable, flexLayout: FlexLayout, in availableSize: Size) -> Size {
        let children = root.children()
        guard !children.isEmpty else {
            return Size(width: 0, height: 0)
        }

        let isRow = flexLayout.direction == .row
        let crossAxisSize = isRow ? availableSize.height : availableSize.width

        var childSizes: [Size] = []
        for child in children {
            let constrainedSize = isRow
                ? Size(width: availableSize.width, height: crossAxisSize)
                : Size(width: crossAxisSize, height: availableSize.height)
            let measured = child.measure(in: constrainedSize)
            childSizes.append(measured)
        }

        let totalGap = flexLayout.gap * max(0, children.count - 1)

        if isRow {
            let totalWidth = childSizes.reduce(0) { $0 + $1.width } + totalGap
            let maxHeight = childSizes.map { $0.height }.max() ?? 0
            return Size(width: min(totalWidth, availableSize.width), height: min(maxHeight, availableSize.height))
        } else {
            let totalHeight = childSizes.reduce(0) { $0 + $1.height } + totalGap
            let maxWidth = childSizes.map { $0.width }.max() ?? 0
            return Size(width: min(maxWidth, availableSize.width), height: min(totalHeight, availableSize.height))
        }
    }

    public static func emitDamageRects(_ root: TUIRenderable, at origin: Point, in availableSize: Size) -> [DamageRect] {
        var rects: [DamageRect] = []
        collectDamageRects(root, at: origin, in: availableSize, into: &rects)
        return rects
    }

    private static func collectDamageRects(_ node: TUIRenderable, at origin: Point, in availableSize: Size, into rects: inout [DamageRect]) {
        if !node.dirtyReasons.isEmpty {
            let measured = node.measure(in: availableSize)
            let bounds = Rect(origin: origin, size: measured)
            rects.append(DamageRect(rect: bounds, nodeID: node.nodeID))
        }

        if let flexLayout = node.flexLayout {
            let children = node.children()
            guard !children.isEmpty else { return }

            let isRow = flexLayout.direction == .row
            var currentMainAxis = origin.x + (isRow ? 0 : 0)
            var currentCrossAxis = origin.y + (isRow ? 0 : 0)

            for child in children {
                let childSize = child.measure(in: availableSize)
                let childOrigin = Point(
                    x: isRow ? currentMainAxis : origin.x,
                    y: isRow ? origin.y : currentCrossAxis
                )
                collectDamageRects(child, at: childOrigin, in: availableSize, into: &rects)

                if isRow {
                    currentMainAxis += childSize.width + flexLayout.gap
                } else {
                    currentCrossAxis += childSize.height + flexLayout.gap
                }
            }
        } else {
            var currentY = origin.y
            for child in node.children() {
                let childSize = child.measure(in: Size(width: availableSize.width - origin.x, height: availableSize.height - currentY))
                let childOrigin = Point(x: origin.x, y: currentY)
                collectDamageRects(child, at: childOrigin, in: availableSize, into: &rects)
                currentY += childSize.height
            }
        }
    }
}

public struct EmptyComponent: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    private let fixedSize: Size
    private var _dirtyReasons: DirtyReason = []

    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { false }

    public init(id: AnyHashable = UUID().uuidString, size: Size = .zero) {
        self.id = id
        self.nodeID = NodeID()
        self.fixedSize = size
    }

    public func measure(in size: Size) -> Size {
        return fixedSize
    }

    public func render(into buf: inout TerminalBuffer, at origin: Point) {
    }

    public func children() -> [TUIRenderable] {
        return []
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
        hasher.combine(fixedSize)
    }

    public mutating func markDirty(_ reasons: DirtyReason) {
        _dirtyReasons.formUnion(reasons)
    }

    public mutating func clearDirty() {
        _dirtyReasons = []
    }

    public func onFocusChange(_ focused: Bool) {
        // No-op
    }
}

public struct TextComponent: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    private let text: String
    private let attributes: AttrRun?
    private var _dirtyReasons: DirtyReason = []

    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { false }

    public init(id: AnyHashable = UUID().uuidString, text: String, attributes: AttrRun? = nil) {
        self.id = id
        self.nodeID = NodeID()
        self.text = text
        self.attributes = attributes
    }

    public func measure(in size: Size) -> Size {
        let displayWidth = calculateDisplayWidth(text)
        return Size(width: min(displayWidth, size.width),
                   height: 1)
    }

    public func render(into buf: inout TerminalBuffer, at origin: Point) {
        buf.write(text, at: origin, attributes: attributes)
    }

    public func children() -> [TUIRenderable] {
        return []
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
        hasher.combine(text)
        if let attrs = attributes {
            hasher.combine(attrs.start)
            hasher.combine(attrs.length)
        }
    }

    public mutating func markDirty(_ reasons: DirtyReason) {
        _dirtyReasons.formUnion(reasons)
    }

    public mutating func clearDirty() {
        _dirtyReasons = []
    }

    public func onFocusChange(_ focused: Bool) {
        // No-op
    }

    private func calculateDisplayWidth(_ text: String) -> Int {
        let env = TerminalEnv.detect()
        var width = 0
        var startIndex = text.startIndex

        while startIndex < text.endIndex {
            let graphemeRange = text.rangeOfComposedCharacterSequence(at: startIndex)
            let grapheme = text[graphemeRange]
            width += try! TaskBlocking.runBlocking {
                await Text.widthCache.width(of: grapheme, env: env)
            }
            startIndex = graphemeRange.upperBound
        }

        return width
    }

    private func charWidth(_ scalar: Unicode.Scalar) -> Int {
        let codePoint = scalar.value

        if codePoint == 0 {
            return 0
        }

        if (0x0001...0x001F).contains(codePoint) || (0x007F...0x009F).contains(codePoint) {
            return 0
        }

        if (0x0300...0x036F).contains(codePoint) {
            return 0
        }

        if (0x200B...0x200D).contains(codePoint) {
            return 0
        }

        if (0xFE00...0xFE0F).contains(codePoint) {
            return 0
        }

        if codePoint >= 0x1100 {
            if ((0x1100...0x115F).contains(codePoint) ||
                (0x2329...0x232A).contains(codePoint) ||
                (0x2E80...0x2FFF).contains(codePoint) ||
                (0x3000...0x303F).contains(codePoint) ||
                (0x3040...0x4DBF).contains(codePoint) ||
                (0x4E00...0x9FFF).contains(codePoint) ||
                (0xA000...0xA4CF).contains(codePoint) ||
                (0xAC00...0xD7A3).contains(codePoint) ||
                (0xF900...0xFAFF).contains(codePoint) ||
                (0xFE30...0xFE4F).contains(codePoint) ||
                (0xFE50...0xFE6F).contains(codePoint) ||
                (0xFF00...0xFFEF).contains(codePoint) ||
                (0x20000...0x2FFFD).contains(codePoint) ||
                (0x30000...0x3FFFD).contains(codePoint)) {
                return 2
            }
        }

        return 1
    }
}

public final class ContainerComponent: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    private var _children: [TUIRenderable]
    private var _dirtyReasons: DirtyReason = []

    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { false }

    public init(id: AnyHashable = UUID().uuidString, children: [TUIRenderable] = []) {
        self.id = id
        self.nodeID = NodeID()
        self._children = children
    }

    public func measure(in size: Size) -> Size {
        var maxWidth = 0
        var totalHeight = 0

        for child in _children {
            let childSize = child.measure(in: size)
            maxWidth = max(maxWidth, childSize.width)
            totalHeight += childSize.height
        }

        return Size(width: min(maxWidth, size.width),
                   height: min(totalHeight, size.height))
    }

    public func render(into buf: inout TerminalBuffer, at origin: Point) {
        var currentY = origin.y
        for child in _children {
            let childSize = child.measure(in: Size(width: buf.size.width, height: buf.size.height - currentY))
            if currentY + childSize.height > buf.size.height {
                break
            }
            child.render(into: &buf, at: Point(x: origin.x, y: currentY))
            currentY += childSize.height
        }
    }

    public func children() -> [TUIRenderable] {
        return _children
    }

    public func setChildren(_ children: [TUIRenderable]) {
        _children = children
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
        hasher.combine(_children.count)
        for child in _children {
            var childHasher = Hasher()
            child.structuralHash(into: &childHasher)
            hasher.combine(childHasher.finalize())
        }
    }

    public func markDirty(_ reasons: DirtyReason) {
        _dirtyReasons.formUnion(reasons)
    }

    public func clearDirty() {
        _dirtyReasons = []
    }

    public func onFocusChange(_ focused: Bool) {
        // No-op
    }
}
