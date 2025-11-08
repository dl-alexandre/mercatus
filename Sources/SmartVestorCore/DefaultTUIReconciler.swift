import Foundation
import Core

public enum FlushPolicy: Sendable {
    case immediate
    case coalesced
}

public final class DefaultTUIReconciler: TUIReconciler, @unchecked Sendable {
    private let diffRenderer: DiffRenderer
    private var bufferDiffer: HybridBufferDiffer?
    private var previousBuffer: TerminalBuffer?
    private let terminalSize: TerminalSize
    private let outputActor: OutputActor
    private let useBuffer: Bool
    private var frameCount: Int = 0
    private let writeToken: UInt64
    private let renderGraph: RenderGraph
    private let renderCache: RenderCache
    private var currentEnv: TerminalEnv

    private actor OutputActor {
        var lastBytesWritten: Int = 0

        func write(_ buffer: TerminalBuffer, diffRenderer: DiffRenderer, previous: TerminalBuffer?) {
            if let prev = previous {
                diffRenderer.renderDiff(from: prev, to: buffer)
            } else {
                diffRenderer.renderFull(buffer)
            }
        }

        func writeBufferDiff(_ ops: DiffOps, token: UInt64) {
            let before = DiffOpRenderer.lastBytesWritten
            DiffOpRenderer.render(ops, token: token)
            let after = DiffOpRenderer.lastBytesWritten
            lastBytesWritten = after - before
        }
    }

    public init(terminalSize: TerminalSize) {
        self.diffRenderer = DiffRenderer()
        self.terminalSize = terminalSize
        self.outputActor = OutputActor()
        self.useBuffer = TUIFeatureFlags.isBufferEnabled
        if useBuffer {
            self.bufferDiffer = HybridBufferDiffer()
        } else {
            self.bufferDiffer = nil
        }
        self.writeToken = TUIWriteGuard.createToken()
        self.renderGraph = RenderGraph()
        self.renderCache = RenderCache()
        self.currentEnv = TerminalEnv.detect()
    }

    deinit {
        TUIWriteGuard.releaseToken(writeToken)
    }

    public func submit(intent: RenderIntent) async {
        await present(intent.root, policy: .coalesced)
    }

    public func present(_ root: TUIRenderable, policy: FlushPolicy) async {
        frameCount += 1
        diffRenderer.resetFrame()
        await TUIMetrics.shared.recordFrame()

        let perfLog = ProcessInfo.processInfo.environment["TUI_PERF_DETAILED"] == "1"
        var t0: ContinuousClock.Instant = .now
        var t1: ContinuousClock.Instant = .now
        var t2: ContinuousClock.Instant = .now
        var t3: ContinuousClock.Instant = .now
        var t4: ContinuousClock.Instant = .now
        var t5: ContinuousClock.Instant = .now

        t0 = .now
        let size = Size(width: terminalSize.width, height: terminalSize.height)

        let env = TerminalEnv.detect()
        if env != currentEnv {
            await renderCache.invalidateByEnv(env)
            currentEnv = env
        }

        let dirtySubtree = TUIFeatureFlags.isDirtyGraphEnabled
            ? renderGraph.getDirtySubtree(root.nodeID)
            : Set([root.nodeID])

        var buffer: TerminalBuffer
        if let prev = previousBuffer {
            buffer = prev
            buffer.prepare(size: size)
        } else {
            buffer = TerminalBuffer(size: size)
            buffer.clear()
        }

        t1 = .now
        var nodesWalked = 0
        var nodesPainted = 0
        await renderDirtySubtree(root, into: &buffer, dirtyNodes: dirtySubtree, at: .zero, in: size, env: env, nodesWalked: &nodesWalked, nodesPainted: &nodesPainted)
        await TUIMetrics.shared.recordNodesWalked(nodesWalked)
        await TUIMetrics.shared.recordNodesPainted(nodesPainted)
        t2 = .now
        let layoutMs = t0.duration(to: t1).timeInterval * 1000
        let renderMs = t1.duration(to: t2).timeInterval * 1000
        await TUIMetrics.shared.recordRenderPhase("layout", timeMs: layoutMs)
        await TUIMetrics.shared.recordRenderPhase("render", timeMs: renderMs)

        let previous = previousBuffer
        var opsCount = 0
        var bytesWritten = 0

        if var differ = bufferDiffer, useBuffer {
            t3 = .now
            let ops = differ.diff(prev: previous, next: buffer, size: size)
            opsCount = ops.ops.count
            self.bufferDiffer = differ
            t4 = .now
            previousBuffer = buffer
            await outputActor.writeBufferDiff(ops, token: writeToken)
            t5 = .now
            bytesWritten = await outputActor.lastBytesWritten
        } else {
            previousBuffer = buffer
            await outputActor.write(buffer, diffRenderer: diffRenderer, previous: previous)
        }

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
            if ansiMs > 5.0 {
                print("[TUI PERF] WARNING: ANSI build exceeded 5ms: \(ansiMs)ms")
            }
            if diffMs > 10.0 {
                print("[TUI PERF] WARNING: Diff exceeded 10ms: \(diffMs)ms")
            }
        }

        if TUIFeatureFlags.isDebugMetricsEnabled && frameCount % 60 == 0 {
            let metrics = await TUIMetrics.shared.getMetrics()
            print(metrics.format())
        }

        if TUIFeatureFlags.isDirtyGraphEnabled {
            renderGraph.clearAll()
        }
    }

    private func renderDirtySubtree(_ node: TUIRenderable, into buffer: inout TerminalBuffer, dirtyNodes: Set<NodeID>, at origin: Point, in size: Size, env: TerminalEnv, nodesWalked: inout Int, nodesPainted: inout Int) async {
        nodesWalked += 1

        let measured = node.measure(in: size)
        let bounds = Rect(origin: origin, size: measured)
        let viewport = Viewport(rect: Rect(origin: .zero, size: size))

        // Viewport culling: skip if completely outside viewport
        guard viewport.intersection(bounds) != nil else {
            return
        }

        guard dirtyNodes.contains(node.nodeID) || node.dirtyReasons.contains(.env) else {
            if let cached = await renderCache.lookup(node.nodeID, computeHash(node), env) {
                await TUIMetrics.shared.recordCacheLookupHit()
                blitSurface(cached, into: &buffer, at: origin)
            }
            return
        }

        var hasher = Hasher()
        node.structuralHash(into: &hasher)
        let hash = UInt64(hasher.finalize())

        if let cached = await renderCache.lookup(node.nodeID, hash, env) {
            await TUIMetrics.shared.recordCacheLookupHit()
            blitSurface(cached, into: &buffer, at: origin)
            return
        }

        nodesPainted += 1
        node.render(into: &buffer, at: origin)

        var currentY = origin.y
        for child in node.children() {
            let childSize = child.measure(in: Size(width: size.width - origin.x, height: size.height - currentY))
            let childOrigin = Point(x: origin.x, y: currentY)
            let childBounds = Rect(origin: childOrigin, size: childSize)

            // Only render children that intersect viewport
            if viewport.intersection(childBounds) != nil {
                await renderDirtySubtree(child, into: &buffer, dirtyNodes: dirtyNodes, at: childOrigin, in: size, env: env, nodesWalked: &nodesWalked, nodesPainted: &nodesPainted)
            }
            currentY += childSize.height
        }

        let surface = Surface(
            lines: Array(buffer.lines[bounds.origin.y..<min(bounds.origin.y + bounds.size.height, buffer.lines.count)]),
            bounds: bounds,
            lastVisibleRect: viewport.intersection(bounds),
            env: env
        )

        await renderCache.store(node.nodeID, hash, surface, bounds, viewport.intersection(bounds), env)
        await TUIMetrics.shared.recordCacheStore()
    }

    private func computeHash(_ node: TUIRenderable) -> UInt64 {
        var hasher = Hasher()
        node.structuralHash(into: &hasher)
        return UInt64(hasher.finalize())
    }

    private func blitSurface(_ surface: Surface, into buffer: inout TerminalBuffer, at origin: Point) {
        for (index, line) in surface.lines.enumerated() {
            let y = origin.y + index
            if y >= 0 && y < buffer.size.height {
                let text = String(decoding: line.utf8, as: UTF8.self)
                buffer.write(text, at: Point(x: origin.x, y: y))
            }
        }
    }
}
