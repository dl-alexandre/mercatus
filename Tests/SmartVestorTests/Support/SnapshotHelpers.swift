import Foundation
import Testing
@testable import SmartVestor

func assertSnapshot(buffer: TerminalBuffer, named: String, testIdentifier: String = #function) {
    let normalized = normalizeBufferOutput(buffer)
    let bytes = normalized.serializeUTF8()
    let safeName = "\(testIdentifier)_\(named)"
    let path = snapshotPath(named: safeName)
    let shouldAutoApprove = ProcessInfo.processInfo.environment["CREATE_SNAPSHOTS"] == "1"

    if !FileManager.default.fileExists(atPath: path.path) {
        try! bytes.write(to: path)
        if !shouldAutoApprove {
            Issue.record("Snapshot created: \(safeName). Verify and re-run.")
        }
        return
    }

    let expected = try! Data(contentsOf: path)
    let normalizedExpected = normalizeSnapshotData(expected)
    let normalizedActual = normalizeSnapshotData(bytes)

    if normalizedExpected != normalizedActual {
        let diffPath = failureArtifactPath(named: safeName + ".actual")
        try? bytes.write(to: diffPath)
        Issue.record("Snapshot mismatch: \(safeName). Wrote .actual for inspection at \(diffPath.path).")
    }
}

func normalizeBufferOutput(_ buffer: TerminalBuffer) -> TerminalBuffer {
    var normalized = TerminalBuffer(size: buffer.size)
    normalized.setCursor(buffer.cursor)
    for (i, line) in buffer.lines.enumerated() {
        let normalizedBytes = normalizeLineBytes(Array(line.utf8))
        if let text = String(bytes: normalizedBytes, encoding: .utf8) {
            normalized.write(text, at: Point(x: 0, y: i))
        }
    }
    return normalized
}

private func normalizeLineBytes(_ bytes: [UInt8]) -> [UInt8] {
    var result = bytes

    result = stripANSIResetCodes(result)
    result = stripTrailingSpaces(result)

    return result
}

private func stripANSIResetCodes(_ bytes: [UInt8]) -> [UInt8] {
    var result: [UInt8] = []
    var i = 0
    while i < bytes.count {
        if i + 2 < bytes.count && bytes[i] == 0x1B && bytes[i+1] == 0x5B && bytes[i+2] == 0x30 {
            var j = i + 3
            while j < bytes.count && bytes[j] != 0x6D {
                j += 1
            }
            if j < bytes.count && bytes[j] == 0x6D {
                i = j + 1
                continue
            }
        }
        result.append(bytes[i])
        i += 1
    }
    return result
}

private func stripTrailingSpaces(_ bytes: [UInt8]) -> [UInt8] {
    var result = bytes
    while result.last == 0x20 {
        result.removeLast()
    }
    return result
}

private func normalizeSnapshotData(_ data: Data) -> Data {
    var bytes = Array(data)
    bytes = stripANSIResetCodes(bytes)
    bytes = stripTrailingSpaces(bytes)
    return Data(bytes)
}

func snapshotPath(named: String) -> URL {
    let testFileURL = URL(fileURLWithPath: #filePath)
    return testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("__snapshots__")
        .appendingPathComponent(named + ".utf8")
}

private func failureArtifactPath(named: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(named)
}

extension TerminalBuffer {
    static func empty(size: Size) -> TerminalBuffer {
        var buffer = TerminalBuffer(size: size)
        buffer.clear()
        return buffer
    }

    func serializeUTF8() -> Data {
        var d = Data()
        for line in lines {
            d.append(contentsOf: line.utf8)
            d.append(0x0A)
        }
        return d
    }
}
