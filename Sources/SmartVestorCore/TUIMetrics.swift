import Foundation

public actor TUIMetrics {
    public static let shared = TUIMetrics()

    // Counters
    private var renderNodesWalked: Int = 0
    private var renderNodesPainted: Int = 0
    private var damageRectsCount: Int = 0
    private var bytesPerFrame: [Int] = []
    private var framesPerSec: [Double] = []
    private var widthCacheHits: Int = 0
    private var widthCacheMisses: Int = 0
    private var tailFastPathHits: Int = 0
    private var tailFastPathMisses: Int = 0
    private var cacheLookupHits: Int = 0
    private var cacheStores: Int = 0
    private var cacheEvictions: Int = 0
    private var ttyWriteEAGAIN: Int = 0
    private var ttyWriteSIGPIPE: Int = 0

    private var graphRenderTimes: [Double] = []
    private var graphModeSelections: [String: Int] = [:]
    private var renderPhaseTimes: [String: [Double]] = [:]

    private var frameStartTime: ContinuousClock.Instant?
    private var frameCount: Int = 0
    private let metricsWindow: Int = 100

    private init() {}

    public func recordNodesWalked(_ count: Int) {
        renderNodesWalked += count
    }

    public func recordNodesPainted(_ count: Int) {
        renderNodesPainted += count
    }

    public func recordDamageRects(_ count: Int) {
        damageRectsCount += count
    }

    public func recordBytesPerFrame(_ bytes: Int) {
        bytesPerFrame.append(bytes)
        if bytesPerFrame.count > metricsWindow {
            bytesPerFrame.removeFirst()
        }
    }

    public func recordFrame() {
        frameCount += 1
        if let start = frameStartTime {
            let duration = start.duration(to: .now)
            let fps = 1.0 / max(duration.timeInterval, 0.001)
            framesPerSec.append(fps)
            if framesPerSec.count > metricsWindow {
                framesPerSec.removeFirst()
            }
        }
        frameStartTime = .now
    }

    public func recordWidthCacheHit() {
        widthCacheHits += 1
    }

    public func recordWidthCacheMiss() {
        widthCacheMisses += 1
    }

    public func recordTailFastPathHit() {
        tailFastPathHits += 1
    }

    public func recordTailFastPathMiss() {
        tailFastPathMisses += 1
    }

    public func recordCacheLookupHit() {
        cacheLookupHits += 1
    }

    public func recordCacheStore() {
        cacheStores += 1
    }

    public func recordCacheEviction() {
        cacheEvictions += 1
    }

    public func recordTTYWriteEAGAIN() {
        ttyWriteEAGAIN += 1
    }

    public func recordTTYWriteSIGPIPE() {
        ttyWriteSIGPIPE += 1
    }

    public func recordGraphRenderTime(_ timeMs: Double) {
        graphRenderTimes.append(timeMs)
        if graphRenderTimes.count > metricsWindow {
            graphRenderTimes.removeFirst()
        }
    }

    public func recordGraphModeSelection(_ mode: String) {
        graphModeSelections[mode, default: 0] += 1
    }

    public func recordRenderPhase(_ phase: String, timeMs: Double) {
        if renderPhaseTimes[phase] == nil {
            renderPhaseTimes[phase] = []
        }
        renderPhaseTimes[phase]?.append(timeMs)
        if let count = renderPhaseTimes[phase]?.count, count > metricsWindow {
            renderPhaseTimes[phase]?.removeFirst()
        }
    }

    public func getMetrics() -> MetricsSnapshot {
        let sortedBytes = bytesPerFrame.sorted()
        let sortedFPS = framesPerSec.sorted()

        let sortedGraphTimes = graphRenderTimes.sorted()
        let graphModeTotal = graphModeSelections.values.reduce(0, +)
        let graphModeRates = graphModeSelections.mapValues { Double($0) / Double(max(graphModeTotal, 1)) }

        var phaseStats: [String: MetricsSnapshot.PhaseStats] = [:]
        for (phase, times) in renderPhaseTimes {
            let sorted = times.sorted()
            phaseStats[phase] = MetricsSnapshot.PhaseStats(
                p50: percentile(sorted, 50),
                p95: percentile(sorted, 95)
            )
        }

        return MetricsSnapshot(
            renderNodesWalked: renderNodesWalked,
            renderNodesPainted: renderNodesPainted,
            damageRectsCount: damageRectsCount,
            bytesPerFrameP50: percentile(sortedBytes, 50),
            bytesPerFrameP95: percentile(sortedBytes, 95),
            framesPerSecP50: percentile(sortedFPS, 50),
            framesPerSecP95: percentile(sortedFPS, 95),
            widthCacheHitRate: widthCacheHits + widthCacheMisses > 0
                ? Double(widthCacheHits) / Double(widthCacheHits + widthCacheMisses)
                : 0.0,
            tailFastPathHitRate: tailFastPathHits + tailFastPathMisses > 0
                ? Double(tailFastPathHits) / Double(tailFastPathHits + tailFastPathMisses)
                : 0.0,
            cacheLookupHits: cacheLookupHits,
            cacheStores: cacheStores,
            cacheEvictions: cacheEvictions,
            ttyWriteEAGAIN: ttyWriteEAGAIN,
            ttyWriteSIGPIPE: ttyWriteSIGPIPE,
            graphRenderTimeP50: percentile(sortedGraphTimes, 50),
            graphRenderTimeP95: percentile(sortedGraphTimes, 95),
            graphModeRates: graphModeRates,
            renderPhaseStats: phaseStats
        )
    }

    public func reset() {
        renderNodesWalked = 0
        renderNodesPainted = 0
        damageRectsCount = 0
        bytesPerFrame.removeAll()
        framesPerSec.removeAll()
        widthCacheHits = 0
        widthCacheMisses = 0
        tailFastPathHits = 0
        tailFastPathMisses = 0
        cacheLookupHits = 0
        cacheStores = 0
        cacheEvictions = 0
        ttyWriteEAGAIN = 0
        ttyWriteSIGPIPE = 0
        graphRenderTimes.removeAll()
        graphModeSelections.removeAll()
        renderPhaseTimes.removeAll()
        frameCount = 0
        frameStartTime = nil
    }

    public func exportJSON() async -> Data? {
        let snapshot = await getMetrics()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(snapshot)
    }

    public func exportJSONToFile(_ path: String) async {
        if let data = await exportJSON() {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private func percentile<T: Comparable>(_ sorted: [T], _ p: Int) -> T? {
        guard !sorted.isEmpty else { return nil }
        let index = Int((Double(p) / 100.0) * Double(sorted.count - 1))
        return sorted[min(index, sorted.count - 1)]
    }
}

public struct MetricsSnapshot: Sendable, Codable {
    public let renderNodesWalked: Int
    public let renderNodesPainted: Int
    public let damageRectsCount: Int
    public let bytesPerFrameP50: Int?
    public let bytesPerFrameP95: Int?
    public let framesPerSecP50: Double?
    public let framesPerSecP95: Double?
    public let widthCacheHitRate: Double
    public let tailFastPathHitRate: Double
    public let cacheLookupHits: Int
    public let cacheStores: Int
    public let cacheEvictions: Int
    public let ttyWriteEAGAIN: Int
    public let ttyWriteSIGPIPE: Int
    public let graphRenderTimeP50: Double?
    public let graphRenderTimeP95: Double?
    public let graphModeRates: [String: Double]
    public let renderPhaseStats: [String: PhaseStats]

    public struct PhaseStats: Sendable, Codable {
        public let p50: Double?
        public let p95: Double?
    }

    public func format() -> String {
        var lines: [String] = []
        lines.append("TUI Metrics:")
        lines.append("  render.nodes.walked: \(renderNodesWalked)")
        lines.append("  render.nodes.painted: \(renderNodesPainted)")
        lines.append("  render.damage.rects: \(damageRectsCount)")
        if let p50 = bytesPerFrameP50, let p95 = bytesPerFrameP95 {
            lines.append("  render.bytes_per_frame P50: \(p50) P95: \(p95)")
        }
        if let p50 = framesPerSecP50, let p95 = framesPerSecP95 {
            lines.append("  render.frames_per_sec P50: \(String(format: "%.2f", p50)) P95: \(String(format: "%.2f", p95))")
        }
        lines.append("  widthcache.hit_rate: \(String(format: "%.2f", widthCacheHitRate * 100))%")
        lines.append("  diff.tail_fastpath.hit_rate: \(String(format: "%.2f", tailFastPathHitRate * 100))%")
        lines.append("  cache.render.lookup_hit: \(cacheLookupHits)")
        lines.append("  cache.render.store: \(cacheStores)")
        lines.append("  cache.render.evict: \(cacheEvictions)")
        lines.append("  tty.write.eagain: \(ttyWriteEAGAIN)")
        lines.append("  tty.write.sigpipe_ignored: \(ttyWriteSIGPIPE)")
        return lines.joined(separator: "\n")
    }
}
