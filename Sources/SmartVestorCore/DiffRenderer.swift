import Foundation

#if os(macOS) || os(Linux)
import Darwin
#endif

public final class DiffRenderer: @unchecked Sendable {
    private let esc = "\u{001B}["
    private var outputBuffer: [UInt8] = []
    private let renderMutex = NSLock()
    private var writeCountThisFrame: Int = 0
    private var bytesWrittenThisFrame: Int = 0

    public init() {}

    public func resetFrame() {
        writeCountThisFrame = 0
        bytesWrittenThisFrame = 0
    }

    public func renderDiff(from previous: TerminalBuffer, to current: TerminalBuffer) {
        renderMutex.lock()
        defer { renderMutex.unlock() }

        guard previous.size == current.size else {
            renderFull(current)
            return
        }

        let changes = current.diff(from: previous)
        guard !changes.isEmpty else { return }

        outputBuffer.removeAll(keepingCapacity: true)

        let firstChanged = changes.first!.0
        let lastChanged = changes.last!.0

        if firstChanged > 0 {
            appendANSI("\(esc)\(firstChanged)A")
        }

        var currentLine = firstChanged
        for (lineIdx, newLine) in changes {
            if lineIdx > currentLine {
                appendANSI("\(esc)\(lineIdx - currentLine)B")
                currentLine = lineIdx
            }

            appendANSI("\(esc)K")

            if !newLine.utf8.isEmpty {
                outputBuffer.append(contentsOf: newLine.utf8)
            }

            if let attrs = newLine.attrs.first {
                applyAttributes(attrs)
            }

            appendANSI("\r\n")
        }

        let remainingLines = current.size.height - lastChanged - 1
        if remainingLines > 0 {
            for _ in 0..<remainingLines {
                appendANSI("\(esc)K\r\n")
            }
            appendANSI("\(esc)\(remainingLines)A")
        }

        writeOutput()
    }

    public func renderDamageRects(_ rects: [Rect], from previous: TerminalBuffer, to current: TerminalBuffer) {
        renderMutex.lock()
        defer { renderMutex.unlock() }

        guard previous.size == current.size else {
            renderFull(current)
            return
        }

        let merged = mergeRects(rects)

        for rect in merged {
            let startY = max(0, rect.origin.y)
            let endY = min(current.size.height, rect.origin.y + rect.size.height)
            let startX = max(0, rect.origin.x)
            let endX = min(current.size.width, rect.origin.x + rect.size.width)

            for y in startY..<endY {
                appendANSI("\(esc)\(y + 1);\(startX + 1)H")

                let clearWidth = endX - startX
                let clearSpaces = String(repeating: " ", count: clearWidth)
                outputBuffer.append(contentsOf: clearSpaces.utf8)

                appendANSI("\(esc)\(y + 1);\(startX + 1)H")

                if let line = current.getLine(y) {
                    let lineStart = min(startX, line.utf8.count)
                    let lineEnd = min(endX, line.utf8.count)
                    if lineStart < lineEnd {
                        let slice = Array(line.utf8[lineStart..<lineEnd])
                        outputBuffer.append(contentsOf: slice)
                    }
                }
            }
        }

        writeOutput()
    }

    @inline(__always)
    public func tryTailEdit(_ a: String, _ b: String) -> Bool {
        guard TUIFeatureFlags.isTailEditEnabled else { return false }

        let pa = a.utf8
        let pb = b.utf8
        let p = commonPrefixLen(pa, pb)

        if p >= min(pa.count, pb.count) * 9 / 10 {
            cursorForwardGraphemeAware(fromUTF8: p, in: a)
            writeBytes(pb.dropFirst(p))
            if pb.count < pa.count {
                eraseToEOL()
            }
            Task {
                await TUIMetrics.shared.recordTailFastPathHit()
            }
            return true
        }
        Task {
            await TUIMetrics.shared.recordTailFastPathMiss()
        }
        return false
    }

    private func commonPrefixLen(_ a: String.UTF8View, _ b: String.UTF8View) -> Int {
        let minLen = min(a.count, b.count)
        for i in 0..<minLen {
            if a[a.index(a.startIndex, offsetBy: i)] != b[b.index(b.startIndex, offsetBy: i)] {
                return i
            }
        }
        return minLen
    }

    private func cursorForwardGraphemeAware(fromUTF8: Int, in string: String) {
        if fromUTF8 <= 0 {
            return
        }
        let utf8Start = string.utf8.startIndex
        guard let utf8Index = string.utf8.index(utf8Start, offsetBy: fromUTF8, limitedBy: string.utf8.endIndex) else {
            appendANSI("\(esc)\(fromUTF8)C")
            return
        }
        var charIndex = string.startIndex
        var currentUTF8Offset = 0
        for char in string {
            let charUTF8Count = String(char).utf8.count
            if currentUTF8Offset + charUTF8Count > fromUTF8 {
                break
            }
            currentUTF8Offset += charUTF8Count
            charIndex = string.index(after: charIndex)
        }
        let graphemeRange = string.rangeOfComposedCharacterSequence(at: charIndex)
        let graphemeUTF8Offset = string.utf8.distance(from: string.utf8.startIndex, to: graphemeRange.lowerBound)
        appendANSI("\(esc)\(graphemeUTF8Offset)C")
    }

    private func writeBytes(_ bytes: String.UTF8View.SubSequence) {
        outputBuffer.append(contentsOf: Array(bytes))
    }

    private func eraseToEOL() {
        appendANSI("\(esc)K")
    }

    public func renderDiff(oldFrame: [String], newFrame: [String]) async {
        let oldLines = oldFrame.count
        let newLines = newFrame.count

        if oldFrame.isEmpty || oldLines != newLines {
            var output = "\(esc)?25l\(esc)H"
            for (idx, line) in newFrame.enumerated() {
                output += "\(esc)K\(line)"
                if idx < newLines - 1 {
                    output += "\r\n"
                }
            }
            output += "\(esc)0m\(esc)?25h"
            await Runtime.renderBus.write(output)
            return
        }

        var firstChanged: Int? = nil
        var lastChanged: Int? = nil

        for i in 0..<oldLines {
            if oldFrame[i] != newFrame[i] {
                if firstChanged == nil {
                    firstChanged = i
                }
                lastChanged = i
            }
        }

        guard let first = firstChanged, let last = lastChanged else {
            return
        }

        var output = "\(esc)?25l\(esc)\(first + 1);1H"

        for i in first...last {
            let newLine = newFrame[i]
            output += "\(esc)K\(newLine)"
            if i < last {
                output += "\r\n"
            }
        }

        output += "\(esc)0m\(esc)?25h"
        await Runtime.renderBus.write(output)
    }

    public func renderFull(_ buffer: TerminalBuffer) {
        renderMutex.lock()
        defer { renderMutex.unlock() }

        outputBuffer.removeAll(keepingCapacity: true)
        appendANSI("\(esc)H\(esc)J")

        for line in buffer.lines {
            if !line.utf8.isEmpty {
                outputBuffer.append(contentsOf: line.utf8)
            }
            if let attrs = line.attrs.first {
                applyAttributes(attrs)
            }
            appendANSI("\r\n")
        }

        writeOutput()
    }

    public func renderFull(newFrame: [String]) async {
        var output = "\(esc)H\(esc)J"
        for line in newFrame {
            output += line + "\n"
        }
        await Runtime.renderBus.write(output)
    }

    private func appendANSI(_ str: String) {
        outputBuffer.append(contentsOf: str.utf8)
    }

    private func applyAttributes(_ attrs: AttrRun) {
        var codes: [String] = []

        if attrs.bold { codes.append("1") }
        if attrs.dim { codes.append("2") }
        if attrs.italic { codes.append("3") }
        if attrs.underline { codes.append("4") }
        if attrs.reverse { codes.append("7") }
        if let fg = attrs.foreground {
            codes.append("38;5;\(fg)")
        }
        if let bg = attrs.background {
            codes.append("48;5;\(bg)")
        }

        if !codes.isEmpty {
            appendANSI("\(esc)\(codes.joined(separator: ";"))m")
        }
    }

    private func writeOutput() {
        TUIWriteGuard.assertWriteAllowed()

        guard !outputBuffer.isEmpty else {
            return
        }

        // Safety rail: enforce one write per frame
        assert(writeCountThisFrame == 0, "Multiple writes per frame detected!")
        writeCountThisFrame += 1

        let bufferString = String(bytes: outputBuffer, encoding: .utf8) ?? ""
        let bytesToWrite = outputBuffer.count
        outputBuffer.removeAll(keepingCapacity: true)

        // Safety rail: check bytes cap
        if bytesWrittenThisFrame + bytesToWrite > TUIFeatureFlags.bytesCap {
            // Fall back to simpler rendering for rest of frame
            return
        }
        bytesWrittenThisFrame += bytesToWrite

        #if os(macOS) || os(Linux)
        signal(SIGPIPE, SIG_IGN)
        #endif

        let data = bufferString.data(using: .utf8) ?? Data()
        data.withUnsafeBytes { bytes in
            let fd = FileHandle.standardOutput.fileDescriptor
            var written = 0
            var retries = 0
            let maxRetries = 10

            while written < bytes.count && retries < maxRetries {
                let ptr = bytes.baseAddress?.advanced(by: written)
                let count = bytes.count - written
                let result = write(fd, ptr, count)
                if result < 0 {
                    if errno == EAGAIN {
                        retries += 1
                        Task {
                            await TUIMetrics.shared.recordTTYWriteEAGAIN()
                        }
                        usleep(1000 * UInt32(retries))
                        continue
                    } else {
                        break
                    }
                } else {
                    written += result
                    retries = 0
                }
            }
        }

        // Record metrics
        Task {
            await TUIMetrics.shared.recordBytesPerFrame(bytesWrittenThisFrame)
        }
    }
}
