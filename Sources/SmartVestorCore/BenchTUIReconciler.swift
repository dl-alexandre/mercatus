import Foundation
import Core

    public final class BenchTUIReconciler: TUIReconciler, @unchecked Sendable {
    private let diffRenderer: DiffRenderer
    private var bufferDiffer: HybridBufferDiffer
    private var previousBuffer: TerminalBuffer?
    private let terminalSize: TerminalSize
    private let outputActor: OutputActor
    private let telemetry: BenchTelemetryCollector
    private var frameCount: Int = 0
    private let writeToken: UInt64

    private actor OutputActor {
        private var totalBytes: Int = 0

        func writeFromOps(ops: DiffOps) -> Int {
            let bytes = estimateBytes(ops: ops)
            totalBytes += bytes
            return bytes
        }

        func reset() {
            totalBytes = 0
        }

        private func estimateBytes(ops: DiffOps) -> Int {
            var total = 0
            for op in ops.ops {
                switch op {
                case .writeBytes(let bytes):
                    total += bytes.count
                default:
                    total += 10
                }
            }
            return total
        }
    }

    public init(terminalSize: TerminalSize, telemetry: BenchTelemetryCollector) {
        self.diffRenderer = DiffRenderer()
        self.terminalSize = terminalSize
        self.outputActor = OutputActor()
        self.bufferDiffer = HybridBufferDiffer()
        self.telemetry = telemetry
        self.writeToken = TUIWriteGuard.createToken()
    }

    deinit {
        TUIWriteGuard.releaseToken(writeToken)
    }

    public func submit(intent: RenderIntent) async {
        await present(intent.root, policy: .coalesced)
    }

    public func present(_ root: TUIRenderable, policy: FlushPolicy) async {
        frameCount += 1
        let perfLog = ProcessInfo.processInfo.environment["TUI_PERF_DETAILED"] == "1"
        var t0: ContinuousClock.Instant = .now
        var t1: ContinuousClock.Instant = .now
        var t2: ContinuousClock.Instant = .now
        var t3: ContinuousClock.Instant = .now
        var t4: ContinuousClock.Instant = .now
        var t5: ContinuousClock.Instant = .now

        t0 = .now
        let size = Size(width: terminalSize.width, height: terminalSize.height)
        var buffer: TerminalBuffer
        if let prev = previousBuffer {
            buffer = prev
            buffer.prepare(size: size)
        } else {
            buffer = TerminalBuffer(size: size)
            buffer.clear()
        }

        t1 = .now
        TUIRendererCore.render(root, into: &buffer, at: .zero)
        t2 = .now

        let previous = previousBuffer

        t3 = .now
        let ops = bufferDiffer.diff(prev: previous, next: buffer, size: size)
        let opsCount = ops.ops.count
        t4 = .now
        assert(writeToken != 0, "Write token must be initialized")
        DiffOpRenderer.render(ops, token: writeToken)
        t5 = .now
        let bytesWritten = await outputActor.writeFromOps(ops: ops)

        previousBuffer = buffer

        await telemetry.recordRender(buffer: buffer, previous: previous)

        let buildMs = t0.duration(to: t1).timeInterval * 1000
        let diffMs = t2.duration(to: t3).timeInterval * 1000
        let ansiMs = t3.duration(to: t4).timeInterval * 1000
        let writeMs = t4.duration(to: t5).timeInterval * 1000

        var frameTelemetry = FrameTelemetry()
        frameTelemetry.timeInBridgeMs = buildMs
        frameTelemetry.timeInLayoutMs = 0.0
        frameTelemetry.timeInDiffMs = diffMs
        frameTelemetry.timeInWriteMs = ansiMs + writeMs
        frameTelemetry.bytesWritten = bytesWritten
        await telemetry.recordFrame(frameTelemetry)

        if perfLog && frameCount % 60 == 0 {
            let buildMs = t0.duration(to: t1).timeInterval * 1000
            let renderMs = t1.duration(to: t2).timeInterval * 1000
            let diffMs = t2.duration(to: t3).timeInterval * 1000
            let ansiMs = t3.duration(to: t4).timeInterval * 1000
            let writeMs = t4.duration(to: t5).timeInterval * 1000
            let totalMs = t0.duration(to: t5).timeInterval * 1000
            print("[TUI PERF] frame#\(frameCount) build:\(String(format: "%.2f", buildMs))ms render:\(String(format: "%.2f", renderMs))ms diff:\(String(format: "%.2f", diffMs))ms ansi:\(String(format: "%.2f", ansiMs))ms write:\(String(format: "%.2f", writeMs))ms total:\(String(format: "%.2f", totalMs))ms bytes:\(bytesWritten) ops:\(opsCount)")

            if opsCount > 2000 {
                print("[TUI PERF] WARNING: High ops count: \(opsCount), diff may be too granular")
            }
            if diffMs > 10.0 {
                print("[TUI PERF] WARNING: Diff exceeded 10ms: \(diffMs)ms")
            }
            if ansiMs > 5.0 {
                print("[TUI PERF] WARNING: ANSI build exceeded 5ms: \(ansiMs)ms")
            }
            if writeMs > 3.0 {
                print("[TUI PERF] WARNING: Write exceeded 3ms: \(writeMs)ms")
            }
        }
    }
}
