import Foundation
import Testing
@testable import SmartVestor

@Suite("Golden Frame Tests")
struct GoldenFrameTests {
    @Test
    func all_panels_120x40() async throws {
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        defer { unsetenv("SMARTVESTOR_TUI_BUFFER") }

        let reconciler = DefaultTUIReconciler(terminalSize: TerminalSize(cols: 120, rows: 40))
        let root = await makeAllPanelsTree()

        let ansi = try await renderToANSI(reconciler: reconciler, root: root, policy: .coalesced)
        assertANSISnapshot(ansi, named: "all_panels_120x40_first_frame", testIdentifier: "all_panels_120x40")
    }

    @Test
    func status_only_80x24() async throws {
        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        defer { unsetenv("SMARTVESTOR_TUI_BUFFER") }

        let reconciler = DefaultTUIReconciler(terminalSize: TerminalSize(cols: 80, rows: 24))
        let root = await makeStatusOnlyTree()

        let ansi = try await renderToANSI(reconciler: reconciler, root: root, policy: .coalesced)
        assertANSISnapshot(ansi, named: "status_only_80x24_first_frame", testIdentifier: "status_only_80x24")
    }
}

func renderToANSI(reconciler: DefaultTUIReconciler, root: TUIRenderable, policy: FlushPolicy) async throws -> Data {
    await reconciler.present(root, policy: policy)

    var differ = HybridBufferDiffer()
    let size = Size(width: 120, height: 40)

    var buffer = TerminalBuffer.empty(size: size)
    TUIRendererCore.render(root, into: &buffer, at: .zero)

    let ops = differ.diff(prev: nil, next: buffer, size: size)
    var output = Data()

    let esc = "\u{001B}["
    for op in ops.ops {
        switch op {
        case .setAttr(let attr):
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
                output.append("\(esc)\(codes.joined(separator: ";"))m".data(using: .utf8)!)
            } else {
                output.append("\(esc)0m".data(using: .utf8)!)
            }
        case .moveCursor(let x, let y):
            output.append("\(esc)\(y + 1);\(x + 1)H".data(using: .utf8)!)
        case .writeBytes(let bytes):
            output.append(bytes, count: bytes.count)
        case .clearLine:
            output.append("\(esc)K".data(using: .utf8)!)
        case .clearScreen:
            output.append("\(esc)2J\(esc)H".data(using: .utf8)!)
        }
    }

    return output
}

func assertANSISnapshot(_ ansi: Data, named: String, testIdentifier: String = #function) {
    let normalized = normalizeANSIData(ansi)
    let safeName = "\(testIdentifier)_ansi_\(named)"
    let path = snapshotPath(named: safeName)
    let shouldAutoApprove = ProcessInfo.processInfo.environment["CREATE_SNAPSHOTS"] == "1"

    if !FileManager.default.fileExists(atPath: path.path) {
        try! normalized.write(to: path)
        if !shouldAutoApprove {
            Issue.record("ANSI snapshot created: \(safeName). Verify and re-run.")
        }
        return
    }

    let expected = try! Data(contentsOf: path)
    let normalizedExpected = normalizeANSIData(expected)

    if normalizedExpected != normalized {
        let diffPath = failureArtifactPath(named: "\(safeName).actual")
        try? normalized.write(to: diffPath)
        Issue.record("ANSI snapshot mismatch: \(safeName). Wrote .actual for inspection at \(diffPath.path).")
    }
}

private func normalizeANSIData(_ data: Data) -> Data {
    var bytes = Array(data)
    bytes = stripANSIResetCodes(bytes)

    var result: [UInt8] = []
    var i = 0
    while i < bytes.count {
        if bytes[i] == 0x0A {
            while result.last == 0x20 {
                result.removeLast()
            }
        }
        result.append(bytes[i])
        i += 1
    }

    while result.last == 0x20 || result.last == 0x0A {
        result.removeLast()
    }

    return Data(result)
}

private func stripANSIResetCodes(_ bytes: [UInt8]) -> [UInt8] {
    var result: [UInt8] = []
    var i = 0
    while i < bytes.count {
        if i + 2 < bytes.count && bytes[i] == 0x1B && bytes[i+1] == 0x5B {
            if bytes[i+2] == 0x30 {
                var j = i + 3
                while j < bytes.count && bytes[j] != 0x6D {
                    j += 1
                }
                if j < bytes.count && bytes[j] == 0x6D {
                    i = j + 1
                    continue
                }
            } else {
                var j = i + 2
                while j < bytes.count && bytes[j] != 0x6D && bytes[j] != 0x48 {
                    j += 1
                }
                if j < bytes.count {
                    i = j + 1
                    continue
                }
            }
        }
        result.append(bytes[i])
        i += 1
    }
    return result
}


private func failureArtifactPath(named: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(named)
}
