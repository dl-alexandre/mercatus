import Foundation
import Core

public actor RenderLoop {
    private struct RenderState {
        var pendingIntent: RenderIntent?
        var lastFlush: ContinuousClock.Instant
        var currentBuffer: TerminalBuffer?
        var isInitialized: Bool = false
        var flushTask: Task<Void, Never>?

        mutating func reset() {
            pendingIntent = nil
            currentBuffer = nil
            isInitialized = false
            flushTask?.cancel()
            flushTask = nil
        }
    }

    private var renderState: RenderState
    private let maxFlushRate: TimeInterval = 1.0 / 60.0
    private let p95TargetMs: Double = 50.0
    private let writeThresholdMs: Double = 16.0
    private var debounceDelay: TimeInterval = 0.016
    private let performanceMonitor: Core.PerformanceMonitor?
    private let reconciler: TUIReconciler

    public init(
        reconciler: TUIReconciler,
        performanceMonitor: Core.PerformanceMonitor? = nil,
        refreshConfig: TUIConfig.RefreshConfig? = nil
    ) {
        self.reconciler = reconciler
        self.performanceMonitor = performanceMonitor
        let config = refreshConfig ?? TUIConfig.RefreshConfig.default
        self.debounceDelay = config.debounceDelay
        self.renderState = RenderState(lastFlush: .now)
    }

    nonisolated public func enqueue(_ intent: RenderIntent) {
        Task {
            await coalesce(intent)
        }
    }

    private func coalesce(_ intent: RenderIntent) {
        if let existing = renderState.pendingIntent {
            if intent.priority > existing.priority {
                renderState.pendingIntent = intent
                scheduleFlush()
            } else {
                renderState.pendingIntent = intent
            }
        } else {
            renderState.pendingIntent = intent
            scheduleFlush()
        }
    }

    private func scheduleFlush() {
        renderState.flushTask?.cancel()

        let now = ContinuousClock.Instant.now
        let elapsed = renderState.lastFlush.duration(to: now)
        let elapsedSeconds = TimeInterval(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000.0

        if elapsedSeconds >= maxFlushRate || renderState.pendingIntent?.priority == .input {
            Task {
                await flush()
            }
        } else {
            let timeToNextFlush = maxFlushRate - elapsedSeconds
            renderState.flushTask = Task {
                try? await Task.sleep(for: .seconds(timeToNextFlush))
                await flush()
            }
        }
    }

    private func flush() async {
        guard let intent = renderState.pendingIntent else { return }

        let startTime = ContinuousClock.Instant.now
        renderState.pendingIntent = nil

        await reconciler.submit(intent: intent)

        let endTime = ContinuousClock.Instant.now
        renderState.lastFlush = endTime
        let flushDuration = startTime.duration(to: endTime)
        let flushSeconds = TimeInterval(flushDuration.components.seconds) + Double(flushDuration.components.attoseconds) / 1_000_000_000_000_000_000.0
        let flushMs = flushSeconds * 1000

        if flushMs > writeThresholdMs && intent.priority == .telemetry {
            debounceDelay = min(debounceDelay * 1.5, 0.1)
        }

        if let monitor = performanceMonitor {
            await monitor.recordRenderLatency(latencyMs: flushMs)
        }

        await TUIMetrics.shared.recordRenderPhase("flush", timeMs: flushMs)

        Task {
            if let data = await TUIMetrics.shared.exportJSON() {
                try? data.write(to: URL(fileURLWithPath: "/tmp/tui_metrics.json"))
            }
        }

        if renderState.pendingIntent != nil {
            scheduleFlush()
        }
    }

    public func reset() {
        renderState.reset()
    }

    public func getConfiguration() -> (maxRefreshRate: Double, debounceDelay: Double) {
        return (maxRefreshRate: 1.0 / maxFlushRate, debounceDelay: debounceDelay)
    }

    public func updateConfiguration(_ config: TUIConfig.RefreshConfig) {
        debounceDelay = config.debounceDelay
    }
}

public enum RenderCommand: Sendable {
    case initialRender(TUIUpdate)
    case updateRender(TUIUpdate)
    case keyboardEvent(KeyEvent)
    case diffRender(changedLines: [Int: String])
}
