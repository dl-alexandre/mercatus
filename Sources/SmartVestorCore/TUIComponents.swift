import Foundation

public struct Text: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    public let content: String
    private var _measuredSize: Size?
    public var measuredSize: Size? { _measuredSize }
    private var _dirtyReasons: DirtyReason = []
    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { false }

    static let widthCache = CharacterWidthCache()

    public init(_ content: String, id: AnyHashable? = nil) {
        self.content = content
        self.id = id ?? AnyHashable(content)
        self.nodeID = NodeID()
    }

    public func measure(in size: Size) -> Size {
        if let cached = _measuredSize, cached.width <= size.width && cached.height <= size.height {
            return cached
        }
        let env = TerminalEnv.detect()
        let lines = content.components(separatedBy: .newlines)
        var maxWidth = 0

        for line in lines {
            var lineWidth = 0
            var startIndex = line.startIndex
            while startIndex < line.endIndex {
                let graphemeRange = line.rangeOfComposedCharacterSequence(at: startIndex)
                let grapheme = line[graphemeRange]
                let width = try! TaskBlocking.runBlocking {
                    await Self.widthCache.width(of: grapheme, env: env)
                }
                lineWidth += width
                startIndex = graphemeRange.upperBound
            }
            maxWidth = max(maxWidth, lineWidth)
        }

        return Size(width: min(maxWidth, size.width), height: lines.count)
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
        hasher.combine(content)
    }

    public mutating func markDirty(_ reasons: DirtyReason) {
        _dirtyReasons.formUnion(reasons)
        _measuredSize = nil
    }

    public mutating func clearDirty() {
        _dirtyReasons = []
    }

    public func render(into buffer: inout TerminalBuffer, at origin: Point) {
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let y = origin.y + index
            if y < buffer.size.height && y >= 0 {
                buffer.write(line, at: Point(x: origin.x, y: y))
            }
        }
    }

    public func children() -> [TUIRenderable] {
        []
    }

    public func onFocusChange(_ focused: Bool) {
        // No-op
    }

    @inline(__always)
    private func calculateGraphemeWidth(_ grapheme: Substring, env: TerminalEnv) -> Int {
        return try! TaskBlocking.runBlocking {
            await Self.widthCache.width(of: grapheme, env: env)
        }
    }

    @inline(__always)
    private func _old_calculateGraphemeWidth(_ grapheme: Substring, env: TerminalEnv) -> Int {
        let string = String(grapheme)
        if string.isEmpty { return 0 }
        // Fast path for ASCII
        if string.utf8.allSatisfy({ $0 < 128 }) { return string.count }

        var width = 0
        for scalar in string.unicodeScalars {
            let codePoint = scalar.value
            if codePoint == 0 { continue }
            if (0x0001...0x001F).contains(codePoint) || (0x007F...0x009F).contains(codePoint) { continue }
            if (0x0300...0x036F).contains(codePoint) { continue }
            if (0x200B...0x200D).contains(codePoint) { continue }
            if (0xFE00...0xFE0F).contains(codePoint) { continue }

            if env.cjk {
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
                    width += 2
                    continue
                }
            }
            width += 1
        }
        return width
    }
}

public struct VStack: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    public let spacing: Int
    public let alignment: HorizontalAlignment
    public let content: [TUIRenderable]
    public let flexLayout: FlexLayout?
    private var _dirtyReasons: DirtyReason = []
    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { false }

    public enum HorizontalAlignment: Sendable {
        case leading
        case center
        case trailing
    }

    public init(
        spacing: Int = 0,
        alignment: HorizontalAlignment = .leading,
        flexLayout: FlexLayout? = nil,
        id: AnyHashable? = nil,
        @TUIViewBuilder content: () -> [TUIRenderable] = { [] }
    ) {
        self.spacing = spacing
        self.alignment = alignment
        self.flexLayout = flexLayout
        self.content = content()
        self.id = id ?? AnyHashable(UUID())
        self.nodeID = NodeID()
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
        hasher.combine(spacing)
        hasher.combine(alignment)
        if let flexLayout = flexLayout {
            hasher.combine(flexLayout.direction)
            hasher.combine(flexLayout.justifyContent)
            hasher.combine(flexLayout.alignItems)
            hasher.combine(flexLayout.gap)
        }
        hasher.combine(content.count)
        for child in content {
            var childHasher = Hasher()
            child.structuralHash(into: &childHasher)
            hasher.combine(childHasher.finalize())
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

    public func measure(in size: Size) -> Size {
        if let flexLayout = flexLayout {
            return LayoutEngine.measureFlex(self, flexLayout: flexLayout, in: size)
        }

        guard !content.isEmpty else {
            return Size(width: 0, height: 0)
        }

        let childSizes = content.map { $0.measure(in: size) }
        let maxWidth = childSizes.map { $0.width }.max() ?? 0
        let totalHeight = childSizes.reduce(0) { $0 + $1.height } + spacing * max(0, content.count - 1)

        return Size(width: min(maxWidth, size.width), height: min(totalHeight, size.height))
    }

    public func render(into buffer: inout TerminalBuffer, at origin: Point) {
        if let flexLayout = flexLayout {
            LayoutEngine.layoutFlex(self, flexLayout: flexLayout, in: buffer.size, at: origin, into: &buffer)
            return
        }

        var currentY = origin.y
        let maxChildWidth = content.map { $0.measure(in: buffer.size).width }.max() ?? 0

        for child in content {
            let childSize = child.measure(in: buffer.size)
            var childOrigin = Point(x: origin.x, y: currentY)

            switch alignment {
            case .leading:
                childOrigin.x = origin.x
            case .center:
                childOrigin.x = origin.x + (maxChildWidth - childSize.width) / 2
            case .trailing:
                childOrigin.x = origin.x + maxChildWidth - childSize.width
            }

            child.render(into: &buffer, at: childOrigin)
            currentY += childSize.height + spacing
        }
    }

    public func children() -> [TUIRenderable] {
        content
    }
}

public struct HStack: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    public let spacing: Int
    public let alignment: VerticalAlignment
    public let content: [TUIRenderable]
    public let flexLayout: FlexLayout?
    private var _dirtyReasons: DirtyReason = []
    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { false }

    public enum VerticalAlignment: Sendable {
        case top
        case center
        case bottom
    }

    public init(
        spacing: Int = 0,
        alignment: VerticalAlignment = .top,
        flexLayout: FlexLayout? = nil,
        id: AnyHashable? = nil,
        @TUIViewBuilder content: () -> [TUIRenderable] = { [] }
    ) {
        self.spacing = spacing
        self.alignment = alignment
        self.flexLayout = flexLayout
        self.content = content()
        self.id = id ?? AnyHashable(UUID())
        self.nodeID = NodeID()
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
        hasher.combine(spacing)
        hasher.combine(alignment)
        if let flexLayout = flexLayout {
            hasher.combine(flexLayout.direction)
            hasher.combine(flexLayout.justifyContent)
            hasher.combine(flexLayout.alignItems)
            hasher.combine(flexLayout.gap)
        }
        hasher.combine(content.count)
        for child in content {
            var childHasher = Hasher()
            child.structuralHash(into: &childHasher)
            hasher.combine(childHasher.finalize())
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

    public func measure(in size: Size) -> Size {
        if let flexLayout = flexLayout {
            return LayoutEngine.measureFlex(self, flexLayout: flexLayout, in: size)
        }

        guard !content.isEmpty else {
            return Size(width: 0, height: 0)
        }

        let childSizes = content.map { $0.measure(in: size) }
        let totalWidth = childSizes.reduce(0) { $0 + $1.width } + spacing * max(0, content.count - 1)
        let maxHeight = childSizes.map { $0.height }.max() ?? 0

        return Size(width: min(totalWidth, size.width), height: min(maxHeight, size.height))
    }

    public func render(into buffer: inout TerminalBuffer, at origin: Point) {
        if let flexLayout = flexLayout {
            LayoutEngine.layoutFlex(self, flexLayout: flexLayout, in: buffer.size, at: origin, into: &buffer)
            return
        }

        var currentX = origin.x
        let maxChildHeight = content.map { $0.measure(in: buffer.size).height }.max() ?? 0

        for child in content {
            let childSize = child.measure(in: buffer.size)
            var childOrigin = Point(x: currentX, y: origin.y)

            switch alignment {
            case .top:
                childOrigin.y = origin.y
            case .center:
                childOrigin.y = origin.y + (maxChildHeight - childSize.height) / 2
            case .bottom:
                childOrigin.y = origin.y + maxChildHeight - childSize.height
            }

            child.render(into: &buffer, at: childOrigin)
            currentX += childSize.width + spacing
        }
    }

    public func children() -> [TUIRenderable] {
        content
    }
}

public struct EmptyView: @unchecked Sendable, TUIRenderable {
    public let id: AnyHashable
    public let nodeID: NodeID
    private var _dirtyReasons: DirtyReason = []
    public var dirtyReasons: DirtyReason { _dirtyReasons }
    public var canReceiveFocus: Bool { false }

    public init(id: AnyHashable? = nil) {
        self.id = id ?? AnyHashable(UUID())
        self.nodeID = NodeID()
    }

    public func measure(in size: Size) -> Size {
        Size(width: 0, height: 0)
    }

    public func render(into buffer: inout TerminalBuffer, at origin: Point) {
    }

    public func children() -> [TUIRenderable] {
        []
    }

    public func structuralHash(into hasher: inout Hasher) {
        hasher.combine(nodeID)
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
