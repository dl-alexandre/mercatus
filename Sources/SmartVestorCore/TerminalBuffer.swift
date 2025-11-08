import Foundation

public struct Point: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public static let zero = Point(x: 0, y: 0)
}

public struct Size: Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static let zero = Size(width: 0, height: 0)

    public var isEmpty: Bool {
        return width <= 0 || height <= 0
    }
}

public struct AttrRun: Equatable, Sendable {
    public var start: Int
    public var length: Int
    public var foreground: UInt8?
    public var background: UInt8?
    public var bold: Bool
    public var dim: Bool
    public var italic: Bool
    public var underline: Bool
    public var reverse: Bool

    public init(
        start: Int,
        length: Int,
        foreground: UInt8? = nil,
        background: UInt8? = nil,
        bold: Bool = false,
        dim: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        reverse: Bool = false
    ) {
        self.start = start
        self.length = length
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.reverse = reverse
    }
}

public struct Line: Equatable, Sendable {
    public var utf8: ContiguousArray<UInt8>
    public var attrs: [AttrRun]

    public init(utf8: [UInt8] = [], attrs: [AttrRun] = []) {
        self.utf8 = ContiguousArray(utf8)
        self.attrs = attrs
    }

    public mutating func clear() {
        utf8.removeAll(keepingCapacity: true)
        attrs.removeAll(keepingCapacity: true)
    }

    public mutating func prepare(capacity: Int) {
        if utf8.capacity < capacity {
            utf8.reserveCapacity(capacity)
        }
    }
}

public struct TerminalBuffer: Sendable {
    public private(set) var lines: [Line]
    public private(set) var size: Size
    public private(set) var cursor: Point
    public private(set) var dirtyRange: ClosedRange<Int>?

    private nonisolated(unsafe) static var linePool: [Line] = []
    private nonisolated(unsafe) static var poolLock = NSLock()

    public init(size: Size) {
        self.size = size
        self.lines = Array(repeating: Line(), count: size.height)
        self.cursor = .zero
        self.dirtyRange = nil
    }

    public mutating func resize(to newSize: Size) {
        if newSize.width == size.width && newSize.height == size.height {
            return
        }

        let oldHeight = size.height
        size = newSize

        if newSize.height > oldHeight {
            lines.append(contentsOf: Array(repeating: Line(), count: newSize.height - oldHeight))
        } else if newSize.height < oldHeight {
            lines.removeLast(oldHeight - newSize.height)
        }

        for i in 0..<lines.count {
            if lines[i].utf8.count > newSize.width {
                lines[i].utf8.removeLast(lines[i].utf8.count - newSize.width)
            }
        }

        cursor.x = min(cursor.x, newSize.width - 1)
        cursor.y = min(cursor.y, newSize.height - 1)
        markDirty(0..<size.height)
    }

    public mutating func setCursor(_ point: Point) {
        cursor.x = max(0, min(point.x, size.width - 1))
        cursor.y = max(0, min(point.y, size.height - 1))
    }

    public mutating func write(_ text: String, at point: Point? = nil, attributes: AttrRun? = nil) {
        let pos = point ?? cursor
        guard pos.y >= 0 && pos.y < size.height else { return }

        let utf8Bytes = Array(text.utf8)
        guard !utf8Bytes.isEmpty else { return }

        var line = lines[pos.y]
        let endPos = min(pos.x + utf8Bytes.count, size.width)
        let writeLen = endPos - pos.x

        if pos.x >= line.utf8.count {
            line.utf8.append(contentsOf: Array(repeating: 32, count: pos.x - line.utf8.count))
        }

        let oldLen = line.utf8.count
        if writeLen > 0 {
            if pos.x + writeLen > oldLen {
                if pos.x < oldLen {
                    line.utf8.replaceSubrange(pos.x..<oldLen, with: utf8Bytes[0..<(oldLen - pos.x)])
                    line.utf8.append(contentsOf: utf8Bytes[(oldLen - pos.x)..<writeLen])
                } else {
                    line.utf8.append(contentsOf: Array(repeating: 32, count: pos.x - oldLen))
                    line.utf8.append(contentsOf: utf8Bytes[0..<writeLen])
                }
            } else {
                line.utf8.replaceSubrange(pos.x..<(pos.x + writeLen), with: utf8Bytes[0..<writeLen])
            }

            if line.utf8.count > size.width {
                line.utf8.removeLast(line.utf8.count - size.width)
            }

            if let attrs = attributes {
                var run = attrs
                run.start = pos.x
                run.length = writeLen
                line.attrs.append(run)
                line.attrs.sort { $0.start < $1.start }
            }
        }

        lines[pos.y] = line

        markDirty(pos.y...pos.y)
        setCursor(Point(x: endPos, y: pos.y))
    }

    public mutating func clearLine(_ row: Int) {
        guard row >= 0 && row < size.height else { return }
        lines[row].clear()
        markDirty(row...row)
    }

    public mutating func clear() {
        for i in 0..<lines.count {
            lines[i].clear()
        }
        cursor = .zero
        markDirty(0..<size.height)
    }

    public mutating func prepare(size: Size) {
        if self.size != size {
            resize(to: size)
        } else {
            for i in 0..<lines.count {
                lines[i].utf8.removeAll(keepingCapacity: true)
                lines[i].attrs.removeAll(keepingCapacity: true)
            }
            cursor = .zero
            markDirty(0..<size.height)
        }
    }

    public static func empty(size: Size) -> TerminalBuffer {
        var buf = TerminalBuffer(size: size)
        buf.clear()
        return buf
    }

    public mutating func markDirty(_ range: Range<Int>) {
        let clamped = max(0, min(range.lowerBound, size.height - 1))...max(0, min(range.upperBound - 1, size.height - 1))
        if let existing = dirtyRange {
            dirtyRange = min(existing.lowerBound, clamped.lowerBound)...max(existing.upperBound, clamped.upperBound)
        } else {
            dirtyRange = clamped
        }
    }

    public mutating func markDirty(_ range: ClosedRange<Int>) {
        markDirty(range.lowerBound..<(range.upperBound + 1))
    }

    public mutating func clearDirty() {
        dirtyRange = nil
    }

    public func getLine(_ index: Int) -> Line? {
        guard index >= 0 && index < lines.count else { return nil }
        return lines[index]
    }

    public func diff(from previous: TerminalBuffer) -> [(Int, Line)] {
        guard previous.size == size else {
            return Array(lines.enumerated())
        }

        var changes: [(Int, Line)] = []
        for i in 0..<min(lines.count, previous.lines.count) {
            if lines[i].utf8 != previous.lines[i].utf8 || lines[i].attrs != previous.lines[i].attrs {
                changes.append((i, lines[i]))
            }
        }

        if lines.count > previous.lines.count {
            for i in previous.lines.count..<lines.count {
                changes.append((i, lines[i]))
            }
        }

        return changes
    }

    public static func acquireLine() -> Line {
        poolLock.lock()
        defer { poolLock.unlock() }

        if let line = linePool.popLast() {
            var reused = line
            reused.clear()
            return reused
        }
        return Line()
    }

    public static func releaseLine(_ line: Line) {
        poolLock.lock()
        defer { poolLock.unlock() }

        if linePool.count < 100 {
            linePool.append(line)
        }
    }
}
