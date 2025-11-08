import Foundation
import Testing
@testable import SmartVestor

@Suite("Diff Ops Tests")
struct DiffOpsTests {
    @Test
    func diff_line_to_line() {
        let size = Size(width: 80, height: 5)
        var prev = TerminalBuffer.empty(size: size)
        var next = TerminalBuffer.empty(size: size)

        write(&prev, row: 0, "ABC")
        write(&next, row: 0, "ABX")

        var differ = HybridBufferDiffer()
        let ops = differ.diff(prev: prev, next: next, size: size)

        assertOpsSnapshot(ops, named: "line_change_abc_abx", testIdentifier: "diff_line_to_line")
    }

    @Test
    func resize_triggers_full_redraw() {
        let size1 = Size(width: 80, height: 10)
        let size2 = Size(width: 100, height: 10)
        var prev = TerminalBuffer.empty(size: size1)
        var next = TerminalBuffer.empty(size: size2)

        write(&prev, row: 1, "Hello")
        write(&next, row: 1, "Hello")

        var differ = HybridBufferDiffer()
        let ops = differ.diff(prev: prev, next: next, size: size2)

        assertOpsSnapshot(ops, named: "resize_full_redraw", testIdentifier: "resize_triggers_full_redraw")
    }

    @Test
    func no_changes_returns_empty_ops() {
        let size = Size(width: 80, height: 5)
        var buffer = TerminalBuffer.empty(size: size)
        write(&buffer, row: 1, "Hello")

        var differ = HybridBufferDiffer()
        let ops = differ.diff(prev: buffer, next: buffer, size: size)

        #expect(ops.ops.isEmpty || ops.ops.allSatisfy { op in
            if case .moveCursor = op {
                return true
            }
            return false
        })
    }
}

private func write(_ buf: inout TerminalBuffer, row: Int, _ s: String) {
    buf.write(s, at: Point(x: 0, y: row))
}

func assertOpsSnapshot(_ ops: DiffOps, named: String, testIdentifier: String = #function) {
    let text = ops.ops.map { op in
        switch op {
        case .setAttr(let attr):
            return "setAttr(\(attr.foreground?.description ?? "nil"),\(attr.background?.description ?? "nil"),bold:\(attr.bold))"
        case .moveCursor(let x, let y):
            return "moveCursor(\(x),\(y))"
        case .writeBytes(let bytes):
            return "writeBytes(\(bytes.count) bytes)"
        case .clearLine:
            return "clearLine"
        case .clearScreen:
            return "clearScreen"
        }
    }.joined(separator: "\n")

    let normalizedText = normalizeOpsText(text)
    let data = Data(normalizedText.utf8)
    let safeName = "\(testIdentifier)_ops_\(named)"
    let path = snapshotPath(named: safeName)
    let shouldAutoApprove = ProcessInfo.processInfo.environment["CREATE_SNAPSHOTS"] == "1"

    if !FileManager.default.fileExists(atPath: path.path) {
        try! data.write(to: path)
        if !shouldAutoApprove {
            Issue.record("Ops snapshot created: \(safeName). Verify and re-run.")
        }
        return
    }

    let expected = try! Data(contentsOf: path)
    let normalizedExpected = normalizeSnapshotData(expected)
    let normalizedActual = normalizeSnapshotData(data)

    if normalizedExpected != normalizedActual {
        let diffPath = failureArtifactPath(named: "\(safeName).actual.txt")
        try? data.write(to: diffPath)
        Issue.record("Ops snapshot mismatch: \(safeName). Wrote .actual for inspection at \(diffPath.path).")
    }
}

private func normalizeOpsText(_ text: String) -> String {
    text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
}

private func normalizeSnapshotData(_ data: Data) -> Data {
    if let text = String(data: data, encoding: .utf8) {
        let normalized = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return Data(normalized.utf8)
    }
    return data
}


private func failureArtifactPath(named: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(named)
}
