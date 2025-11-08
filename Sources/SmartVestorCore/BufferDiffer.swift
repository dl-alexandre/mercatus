import Foundation

public struct DiffOps: Sendable {
    public var ops: [Op]

    public init(ops: [Op] = []) {
        self.ops = ops
    }
}

public enum Op: Sendable {
    case setAttr(Attr)
    case moveCursor(Int, Int)
    case writeBytes([UInt8])
    case clearLine
    case clearScreen
}

public struct Attr: Equatable, Sendable {
    public var foreground: UInt8?
    public var background: UInt8?
    public var bold: Bool
    public var dim: Bool
    public var italic: Bool
    public var underline: Bool
    public var reverse: Bool

    public init(
        foreground: UInt8? = nil,
        background: UInt8? = nil,
        bold: Bool = false,
        dim: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        reverse: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.reverse = reverse
    }

    public static let reset = Attr()
}

public protocol BufferDiffer: Sendable {
    mutating func diff(prev: TerminalBuffer?, next: TerminalBuffer, size: Size) -> DiffOps
}

public struct HybridBufferDiffer: BufferDiffer {
    private let charRunWindowSize: Int
    private let charFallbackEnabled: Bool
    private var tmpA: ContiguousArray<UInt8> = []
    private var tmpB: ContiguousArray<UInt8> = []

    public init(charRunWindowSize: Int = 100, charFallbackEnabled: Bool = true) {
        self.charRunWindowSize = charRunWindowSize
        self.charFallbackEnabled = ProcessInfo.processInfo.environment["SMARTVESTOR_TUI_CHARFALLBACK"] != "0"
        self.tmpA = ContiguousArray<UInt8>()
        self.tmpB = ContiguousArray<UInt8>()
        self.tmpA.reserveCapacity(256)
        self.tmpB.reserveCapacity(256)
    }

    public mutating func diff(prev: TerminalBuffer?, next: TerminalBuffer, size: Size) -> DiffOps {
        guard let prev = prev else {
            return DiffOps(ops: [.clearScreen] + renderFull(next))
        }

        guard prev.size == next.size else {
            return DiffOps(ops: [.clearScreen] + renderFull(next))
        }

        var ops: [Op] = []
        var firstChangedLine: Int? = nil
        var lastChangedLine: Int? = nil

        for i in 0..<min(prev.lines.count, next.lines.count) {
            if prev.lines[i] != next.lines[i] {
                if firstChangedLine == nil {
                    firstChangedLine = i
                }
                lastChangedLine = i
            }
        }

        if prev.lines.count != next.lines.count {
            if firstChangedLine == nil {
                firstChangedLine = min(prev.lines.count, next.lines.count)
            }
            lastChangedLine = max(prev.lines.count, next.lines.count) - 1
        }

        guard let first = firstChangedLine, let last = lastChangedLine else {
            return DiffOps(ops: [])
        }

        var currentLine = -1

        for lineIdx in first...min(last, next.lines.count - 1) {
            let prevLine = lineIdx < prev.lines.count ? prev.lines[lineIdx] : Line()
            let nextLine = next.lines[lineIdx]

            if prevLine != nextLine {
                if currentLine != lineIdx {
                    ops.append(.moveCursor(0, lineIdx))
                    currentLine = lineIdx
                }
                ops.append(.clearLine)

                let lenChange = abs(nextLine.utf8.count - prevLine.utf8.count)
                let changeSpan = max(prevLine.utf8.count, nextLine.utf8.count)

                if charFallbackEnabled && lenChange <= 6 && changeSpan <= 24 && nextLine.utf8.count <= charRunWindowSize {
                    let charOps = diffCharRun(prev: prevLine, next: nextLine)
                    if !charOps.isEmpty {
                        ops.append(contentsOf: charOps)
                    } else {
                        ops.append(.writeBytes(Array(nextLine.utf8)))
                    }
                } else {
                    ops.append(contentsOf: diffLineRun(prev: prevLine, next: nextLine))
                }
            }
        }

        if last < next.lines.count - 1 {
            let remainingStart = last + 1
            for remainingIdx in remainingStart..<next.lines.count {
                ops.append(.moveCursor(0, remainingIdx))
                ops.append(.clearLine)
            }
            ops.append(.moveCursor(0, last + 1))
        }

        return DiffOps(ops: ops)
    }

    private mutating func diffCharRun(prev: Line, next: Line) -> [Op] {
        let prevBytes = prev.utf8
        let nextBytes = next.utf8

        let lcp = commonPrefixLength(prevBytes, nextBytes)

        tmpA.removeAll(keepingCapacity: true)
        tmpB.removeAll(keepingCapacity: true)

        if prevBytes.count > lcp {
            tmpA.append(contentsOf: prevBytes[lcp...])
        }
        if nextBytes.count > lcp {
            tmpB.append(contentsOf: nextBytes[lcp...])
        }

        let lcs = commonSuffixLength(tmpA, tmpB)

        let changeStart = lcp
        let changeEnd = nextBytes.count - lcs

        var ops: [Op] = []

        if changeStart < changeEnd {
            let changedBytes = Array(nextBytes[changeStart..<changeEnd])
            if !changedBytes.isEmpty {
                let attr = getAttrForPosition(next, at: changeStart)
                if !attr.isDefault {
                    ops.append(.setAttr(attr))
                }
                ops.append(.writeBytes(changedBytes))
            }
        }

        return ops
    }

    @inline(__always)
    private func commonPrefixLength(_ a: ContiguousArray<UInt8>, _ b: ContiguousArray<UInt8>) -> Int {
        let minLen = min(a.count, b.count)
        var i = 0
        while i < minLen && a[i] == b[i] {
            i += 1
        }
        return i
    }

    @inline(__always)
    private func commonSuffixLength(_ a: ContiguousArray<UInt8>, _ b: ContiguousArray<UInt8>) -> Int {
        let minLen = min(a.count, b.count)
        var i = 0
        while i < minLen && a[a.count - 1 - i] == b[b.count - 1 - i] {
            i += 1
        }
        return i
    }

    private func diffLineRun(prev: Line, next: Line) -> [Op] {
        var ops: [Op] = []

        if prev.utf8 != next.utf8 {
            ops.append(.writeBytes(Array(next.utf8)))
        }

        if let attrRun = next.attrs.first, !isDefaultAttrRun(attrRun) {
            let attrObj = Attr(
                foreground: attrRun.foreground,
                background: attrRun.background,
                bold: attrRun.bold,
                dim: attrRun.dim,
                italic: attrRun.italic,
                underline: attrRun.underline,
                reverse: attrRun.reverse
            )
            ops.append(.setAttr(attrObj))
        }

        return ops
    }

    private func getAttrForPosition(_ line: Line, at offset: Int) -> Attr {
        for run in line.attrs {
            if offset >= run.start && offset < run.start + run.length {
                return Attr(
                    foreground: run.foreground,
                    background: run.background,
                    bold: run.bold,
                    dim: run.dim,
                    italic: run.italic,
                    underline: run.underline,
                    reverse: run.reverse
                )
            }
        }
        return .reset
    }

    private func renderFull(_ buffer: TerminalBuffer) -> [Op] {
        var ops: [Op] = []
        ops.append(.moveCursor(0, 0))

        for line in buffer.lines {
            ops.append(.clearLine)
            if !line.utf8.isEmpty {
                ops.append(.writeBytes(Array(line.utf8)))
            }
            if let attrRun = line.attrs.first, !isDefaultAttrRun(attrRun) {
                let attrObj = Attr(
                    foreground: attrRun.foreground,
                    background: attrRun.background,
                    bold: attrRun.bold,
                    dim: attrRun.dim,
                    italic: attrRun.italic,
                    underline: attrRun.underline,
                    reverse: attrRun.reverse
                )
                ops.append(.setAttr(attrObj))
            }
        }

        return ops
    }
}

private func isDefaultAttrRun(_ run: AttrRun) -> Bool {
    return run.foreground == nil && run.background == nil && !run.bold && !run.dim && !run.italic && !run.underline && !run.reverse
}

private extension Attr {
    var isDefault: Bool {
        return foreground == nil && background == nil && !bold && !dim && !italic && !underline && !reverse
    }
}
