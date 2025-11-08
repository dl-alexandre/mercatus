import Foundation
import Core

public final class ComponentTreeCache: @unchecked Sendable {
    // Two-tier caching: structureHash controls rebuilds, valueHash is informational only
    private var lastStructureHash: UInt64 = 0
    private var lastValueHash: UInt64 = 0
    private var lastTree: TUIRenderable?
    private var lastUpdate: Date = .distantPast
    private let maxStaleSeconds: TimeInterval = 10.0

    // Hit/miss metrics
    private var totalLookups: Int = 0
    private var hits: Int = 0
    private var misses: Int = 0

    public init() {}

    public func getOrBuild(
        update: TUIUpdate,
        context: BridgeContext,
        prices: [String: Double]?,
        bridge: TUIUpdateBridge
    ) async -> TUIRenderable {
        totalLookups &+= 1

        // Compute hashes
        let structureHash = computeStructureHash(context: context)
        let valueHash = computeStableValueHash(update: update, prices: prices)

        let now = Date()
        let isStale = now.timeIntervalSince(lastUpdate) > maxStaleSeconds

        // Reuse tree if structure unchanged and not stale
        if structureHash == lastStructureHash, !isStale, let cached = lastTree {
            hits &+= 1
            if ProcessInfo.processInfo.environment["TUI_PERF_DETAILED"] == "1" {
                let hitRate = Double(hits) / Double(max(1, totalLookups)) * 100.0
                print("[TUI PERF] TreeCache hit. hits:\(hits) misses:\(misses) lookups:\(totalLookups) hitRate:\(String(format: "%.1f", hitRate))% valueHashChanged:\(valueHash != lastValueHash)")
            }
            lastValueHash = valueHash
            return cached
        }
        misses &+= 1
        let tree = await bridge.createComponentTree(
            from: update,
            context: context,
            prices: prices
        )

        lastStructureHash = structureHash
        lastValueHash = valueHash
        lastTree = tree
        lastUpdate = now

        if ProcessInfo.processInfo.environment["TUI_PERF_DETAILED"] == "1" {
            let hitRate = Double(hits) / Double(max(1, totalLookups)) * 100.0
            print("[TUI PERF] TreeCache miss. hits:\(hits) misses:\(misses) lookups:\(totalLookups) hitRate:\(String(format: "%.1f", hitRate))%")
        }
        return tree
    }

    public func invalidate() {
        lastStructureHash = 0
        lastValueHash = 0
        lastTree = nil
        lastUpdate = .distantPast
        totalLookups = 0
        hits = 0
        misses = 0
    }

    public func getStats() -> (hits: Int, misses: Int, hitRate: Double) {
        let total = hits + misses
        let rate = total > 0 ? Double(hits) / Double(total) : 0.0
        return (hits, misses, rate)
    }

    public static func getStats() -> (hits: Int, misses: Int, hitRate: Double) {
        return (0, 0, 0.0)
    }

    // Fast, non-cryptographic FNV-1a based hash for stable structure
    private func computeStructureHash(context: BridgeContext) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325 // FNV offset basis
        func mix(_ v: UInt64) { h ^= v; h &*= 0x00000100000001B3 }
        for panel in context.visiblePanels.sorted(by: { $0.rawValue < $1.rawValue }) {
            mix(UInt64(bitPattern: Int64(panel.rawValue.hashValue)))
        }
        mix(UInt64(bitPattern: Int64(context.borderStyle.hashValue)))
        mix(context.unicodeSupported ? 1 : 0)
        for (type, layout) in context.layouts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            mix(UInt64(bitPattern: Int64(type.rawValue.hashValue)))
            mix(UInt64(layout.x)); mix(UInt64(layout.y)); mix(UInt64(layout.width)); mix(UInt64(layout.height))
        }
        return h
    }

    // Stable value hash excludes transient fields; rounds floats to display precision
    private func computeStableValueHash(update: TUIUpdate, prices: [String: Double]?) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) { h ^= v; h &*= 0x00000100000001B3 }
        mix(update.state.isRunning ? 1 : 0)
        mix(UInt64(bitPattern: Int64(update.state.mode.hashValue)))
        let roundedTotal = Int64((round(update.data.totalPortfolioValue * 100)))
        mix(UInt64(bitPattern: roundedTotal))
        mix(UInt64(update.data.errorCount))
        mix(update.data.circuitBreakerOpen ? 1 : 0)
        // balances: only symbols (structure), not quantities
        for symbol in update.data.balances.map({ $0.asset }).sorted() {
            mix(UInt64(bitPattern: Int64(symbol.hashValue)))
        }
        // recent trades: limit to IDs
        for id in update.data.recentTrades.prefix(10).map({ $0.id }) {
            mix(UInt64(bitPattern: Int64(id.hashValue)))
        }
        if let prices = prices {
            for (symbol, price) in prices.sorted(by: { $0.key < $1.key }) {
                mix(UInt64(bitPattern: Int64(symbol.hashValue)))
                let rp = Int64(round(price * 1_000_000))
                mix(UInt64(bitPattern: rp))
            }
        }
        return h
    }
}
