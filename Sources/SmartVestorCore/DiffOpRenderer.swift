import Foundation
#if os(macOS) || os(Linux)
import Darwin
#endif

public enum DiffOpRenderer {
    public nonisolated(unsafe) static var lastBytesWritten: Int = 4096
    private nonisolated(unsafe) static var lastBytesLock = NSLock()
    private nonisolated(unsafe) static var writeCount: Int = 0
    private nonisolated(unsafe) static var writeCountLock = NSLock()

    public static func render(_ ops: DiffOps, token: UInt64) {
        TUIWriteGuard.assertWriteAllowed(token: token)

        var outputBuffer = ContiguousArray<UInt8>()
        let capacity: Int
        lastBytesLock.lock()
        capacity = max(4096, lastBytesWritten + lastBytesWritten / 10)
        lastBytesLock.unlock()
        outputBuffer.reserveCapacity(capacity)

        let escBytes: [UInt8] = [0x1B, 0x5B]
        var currentAttr: Attr = .reset
        var pendingBytes: ContiguousArray<UInt8> = []

        func flushPendingBytes() {
            if !pendingBytes.isEmpty {
                outputBuffer.append(contentsOf: pendingBytes)
                pendingBytes.removeAll(keepingCapacity: true)
            }
        }

        func mergeWriteBytes(_ bytes: [UInt8]) {
            pendingBytes.append(contentsOf: bytes)
        }

        for op in ops.ops {
            switch op {
            case .setAttr(let attr):
                flushPendingBytes()

                if attr == currentAttr {
                    continue
                }

                var codes: [String] = []

                if attr.bold { codes.append("1") }
                if attr.dim { codes.append("2") }
                if attr.italic { codes.append("3") }
                if attr.underline { codes.append("4") }
                if attr.reverse { codes.append("7") }
                if let fg = attr.foreground {
                    codes.append("38;5;\(fg)")
                }
                if let bg = attr.background {
                    codes.append("48;5;\(bg)")
                }

                if !codes.isEmpty {
                    outputBuffer.append(contentsOf: escBytes)
                    let codesStr = codes.joined(separator: ";")
                    outputBuffer.append(contentsOf: codesStr.utf8)
                    outputBuffer.append(0x6D)
                } else {
                    outputBuffer.append(contentsOf: escBytes)
                    outputBuffer.append(0x30)
                    outputBuffer.append(0x6D)
                }

                currentAttr = attr

            case .moveCursor(let x, let y):
                flushPendingBytes()
                outputBuffer.append(contentsOf: escBytes)
                let yStr = String(y + 1)
                let xStr = String(x + 1)
                outputBuffer.append(contentsOf: yStr.utf8)
                outputBuffer.append(0x3B)
                outputBuffer.append(contentsOf: xStr.utf8)
                outputBuffer.append(0x48)

            case .writeBytes(let bytes):
                if !pendingBytes.isEmpty && pendingBytes.count + bytes.count <= 8192 {
                    pendingBytes.append(contentsOf: bytes)
                } else {
                    flushPendingBytes()
                    mergeWriteBytes(bytes)
                }

            case .clearLine:
                flushPendingBytes()
                outputBuffer.append(contentsOf: escBytes)
                outputBuffer.append(0x4B)

            case .clearScreen:
                flushPendingBytes()
                outputBuffer.append(contentsOf: escBytes)
                outputBuffer.append(0x32)
                outputBuffer.append(0x4A)
                outputBuffer.append(contentsOf: escBytes)
                outputBuffer.append(0x48)
            }
        }

        flushPendingBytes()

        if !outputBuffer.isEmpty {
            lastBytesLock.lock()
            lastBytesWritten = outputBuffer.count
            lastBytesLock.unlock()

            writeCountLock.lock()
            writeCount += 1
            let currentWriteCount = writeCount
            writeCountLock.unlock()

            assert(currentWriteCount == 1, "Multiple writes per frame detected: \(currentWriteCount)")

            if ProcessInfo.processInfo.environment["TUI_PERF_DETAILED"] == "1" {
                writeCountLock.lock()
                let count = writeCount
                writeCountLock.unlock()
                assert(count == 1, "Write guard violation: writeCount=\(count), expected 1")
            }

            let bufferString = String(bytes: outputBuffer, encoding: .utf8) ?? ""
            Task {
                await Runtime.renderBus.write(bufferString)
            }

            writeCountLock.lock()
            writeCount = 0
            writeCountLock.unlock()
        }
    }
}
