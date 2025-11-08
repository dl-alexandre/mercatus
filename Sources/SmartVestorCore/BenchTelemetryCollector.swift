import Foundation
import Core

public struct BenchSummary: Sendable {
    public var frames: Int
    public var duration: Double
    public var renderLatencies: [Double]
    public var changedLines: [Double]
    public var bytesWritten: [Int]

    public var p95Latency: Double {
        guard !renderLatencies.isEmpty else { return 0 }
        let sorted = renderLatencies.sorted()
        let index = Int(Double(sorted.count) * 0.95)
        return sorted[min(index, sorted.count - 1)]
    }

    public var avgChangedLines: Double {
        guard !changedLines.isEmpty else { return 0 }
        let total = changedLines.reduce(0, +)
        return total / Double(changedLines.count)
    }

    public var renderLatencyP95: Double {
        return p95Latency
    }

    public var changedLinesMean: Double {
        return avgChangedLines
    }

    public var bytesPerSecond: Double {
        guard duration > 0 else { return 0 }
        let total = bytesWritten.reduce(0, +)
        return Double(total) / duration
    }

    public init(frames: Int = 0, duration: Double = 0) {
        self.frames = frames
        self.duration = duration
        self.renderLatencies = []
        self.changedLines = []
        self.bytesWritten = []
    }
}

public actor BenchTelemetryCollector: TUITelemetryCollector {
    private var summary = BenchSummary()
    private var renderLatencies: [Double] = []
    private var changedLinesPercent: [Double] = []
    private var bytesWritten: [Int] = []
    private var lastBuffer: TerminalBuffer?
    private var totalLines: Int = 0
    private var skipInitialFrames: Int = 2
    private var frameCount: Int = 0

    public init(skipInitialFrames: Int = 2) {
        self.skipInitialFrames = skipInitialFrames
    }

    public func recordFrame(_ telemetry: FrameTelemetry) async {
        frameCount += 1
        guard frameCount > skipInitialFrames else { return }
        renderLatencies.append(telemetry.timeInBridgeMs + telemetry.timeInLayoutMs + telemetry.timeInDiffMs + telemetry.timeInWriteMs)
        bytesWritten.append(telemetry.bytesWritten)
    }

    public func recordRender(buffer: TerminalBuffer, previous: TerminalBuffer?) async {
        let size = buffer.size
        totalLines = size.height

        guard frameCount > skipInitialFrames else {
            frameCount += 1
            lastBuffer = buffer
            return
        }

        if let prev = previous {
            let changes = buffer.diff(from: prev)
            let changedCount = changes.count
            let percent = totalLines > 0 ? (Double(changedCount) / Double(totalLines)) * 100.0 : 0.0
            changedLinesPercent.append(percent)
        } else {
            changedLinesPercent.append(100.0)
        }

        lastBuffer = buffer
    }

    public func reportSummary(frames: Int, duration: Double) async {
        summary.frames = frames
        summary.duration = duration
        summary.renderLatencies = renderLatencies
        summary.changedLines = changedLinesPercent
        summary.bytesWritten = bytesWritten

        let p95 = summary.p95Latency
        let avgChanged = summary.avgChangedLines
        let bytesPerSec = summary.bytesPerSecond

        print("Frames: \(frames)")
        print("P95 render latency: \(String(format: "%.1f", p95)) ms")
        print("Changed lines avg: \(String(format: "%.1f", avgChanged)) %")
        print("Bytes/s: \(String(format: "%.1f", bytesPerSec / 1024.0)) KB")

        if p95 > 50.0 {
            print("[TUI PERF] WARNING: P95 render latency exceeds 50 ms threshold: \(String(format: "%.1f", p95)) ms")
        }

        if avgChanged > 15.0 {
            print("[TUI PERF] WARNING: Changed lines percentage exceeds 15% threshold: \(String(format: "%.1f", avgChanged)) %")
        }

        let json = generateJSON(summary: summary)
        let jsonPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("bench_results.json")
        try? json.write(to: jsonPath, atomically: true, encoding: .utf8)

        let benchmarksDir = jsonPath.deletingLastPathComponent().appendingPathComponent("benchmarks")
        try? FileManager.default.createDirectory(at: benchmarksDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateTag = dateFormatter.string(from: Date())
        let datedPath = benchmarksDir.appendingPathComponent("bench_\(dateTag).json")
        try? json.write(to: datedPath, atomically: true, encoding: .utf8)

        print("Results written to: \(jsonPath.path)")
        print("Dated copy: \(datedPath.path)")
    }

    public func incrementCounter(_ key: CounterKey) async {
    }

    public func getCounters() async -> CounterTelemetry {
        return CounterTelemetry()
    }

    public func resetCounters() async {
    }

    private func estimateBytesWritten(ops: DiffOps) -> Int {
        var total = 0
        for op in ops.ops {
            switch op {
            case .writeBytes(let bytes):
                total += bytes.count
            case .setAttr, .moveCursor, .clearLine, .clearScreen:
                total += 10
            }
        }
        return total
    }

    private func generateJSON(summary: BenchSummary) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let dict: [String: Any] = [
            "frames": summary.frames,
            "duration": summary.duration,
            "p95_latency_ms": summary.p95Latency,
            "avg_changed_lines_percent": summary.avgChangedLines,
            "bytes_per_second": summary.bytesPerSecond,
            "render_latencies": summary.renderLatencies,
            "changed_lines": summary.changedLines,
            "bytes_written": summary.bytesWritten
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return json
    }
}
