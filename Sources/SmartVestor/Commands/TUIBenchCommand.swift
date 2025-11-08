import Foundation
import ArgumentParser
import SmartVestor
import Core

#if os(macOS) || os(Linux)
import Darwin
#endif

typealias TradeTxnType = Core.TransactionType

struct TUIBenchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tui-bench",
        abstract: "Run TUI performance benchmarks."
    )

    @Option(name: .shortAndLong, help: "Terminal width (default 120).")
    var width: Int = 120

    @Option(name: .shortAndLong, help: "Terminal height (default 40).")
    var height: Int = 40

    @Option(name: .shortAndLong, help: "Duration seconds (default 30).")
    var duration: Int?

    private var effectiveDuration: Int {
        duration ?? 30
    }

    @Option(name: .shortAndLong, help: "Random seed for deterministic runs (default: system time).")
    var seed: Int?

    @Option(name: .long, help: "Benchmark scenario: price-10hz, activity-scroll, resize-and-input, or default.")
    var scenario: String = "default"

    mutating func run() async throws {
        #if os(macOS) || os(Linux)
        signal(SIGPIPE, SIG_IGN)
        #endif

        setenv("SMARTVESTOR_TUI_BUFFER", "1", 1)
        defer { unsetenv("SMARTVESTOR_TUI_BUFFER") }

        let terminalSize = TerminalSize(cols: width, rows: height)

        let registry = PanelRegistry()
        registry.register(StatusPanelRenderer())
        registry.register(BalancePanelRenderer())
        registry.register(ActivityPanelRenderer())
        registry.register(PricePanelRenderer())

        let bridge = TUIUpdateBridge(panelRegistry: registry)
        let treeCache = ComponentTreeCache()

        let layouts = [
            PanelType.status: PanelLayout(x: 0, y: 0, width: width, height: 8),
            PanelType.balance: PanelLayout(x: 0, y: 8, width: width, height: 10),
            PanelType.activity: PanelLayout(x: 0, y: 18, width: width, height: 10),
            PanelType.price: PanelLayout(x: 0, y: 28, width: width, height: 8),
            PanelType.swap: PanelLayout(x: 0, y: 36, width: width, height: 4)
        ]

        var ctx = BridgeContext(
            visiblePanels: [.status, .balance, .activity, .price],
            layouts: layouts,
            borderStyle: .unicode,
            unicodeSupported: true
        )

        let seedValue = seed ?? Int(Date().timeIntervalSince1970)
        let telemetry = BenchTelemetryCollector(skipInitialFrames: 1)
        let reconciler = BenchTUIReconciler(terminalSize: terminalSize, telemetry: telemetry)

        let startTime = ContinuousClock.now
        var frameCount = 0
        var priceUpdateCounter = 0
        var activityScrollOffset = 0
        var currentWidth = width

        var update = makeSampleUpdate(scenario: scenario, seed: seedValue)
        var prices = generateSyntheticPrices(seed: seedValue)

        let perfLog = ProcessInfo.processInfo.environment["TUI_PERF_DETAILED"] == "1"
        var lastCacheLogTime: Date = Date()

        let durationSeconds = effectiveDuration
        var shouldContinue = true
        while shouldContinue {
            let elapsed = startTime.duration(to: ContinuousClock.now)
            let elapsedSeconds = TimeInterval(elapsed.components.seconds) + TimeInterval(elapsed.components.attoseconds) / 1_000_000_000_000_000_000.0
            shouldContinue = elapsedSeconds < Double(durationSeconds)

            guard shouldContinue else { break }

            switch scenario {
            case "price-10hz":
                if frameCount % 6 == 0 {
                    priceUpdateCounter += 1
                    prices = generateSyntheticPrices(seed: seedValue + priceUpdateCounter)
                }
            case "activity-scroll":
                if frameCount % 3 == 0 {
                    activityScrollOffset = (activityScrollOffset + 1) % 1000
                    update = makeSampleUpdate(scenario: scenario, seed: seedValue, scrollOffset: activityScrollOffset)
                }
            case "resize-and-input":
                if frameCount == 100 {
                    currentWidth = 160
                    let newLayouts = [
                        PanelType.status: PanelLayout(x: 0, y: 0, width: currentWidth, height: 8),
                        PanelType.balance: PanelLayout(x: 0, y: 8, width: currentWidth, height: 10),
                        PanelType.activity: PanelLayout(x: 0, y: 18, width: currentWidth, height: 10),
                        PanelType.price: PanelLayout(x: 0, y: 28, width: currentWidth, height: 8),
                        PanelType.swap: PanelLayout(x: 0, y: 36, width: currentWidth, height: 4)
                    ]
                    ctx = BridgeContext(
                        visiblePanels: ctx.visiblePanels,
                        layouts: newLayouts,
                        borderStyle: ctx.borderStyle,
                        unicodeSupported: ctx.unicodeSupported
                    )
                } else if frameCount % 6 == 0 {
                    priceUpdateCounter += 1
                    prices = generateSyntheticPrices(seed: seedValue + priceUpdateCounter)
                }
            default:
                if frameCount % 6 == 0 {
                    priceUpdateCounter += 1
                    prices = generateSyntheticPrices(seed: seedValue + priceUpdateCounter)
                }
            }

            let root = await treeCache.getOrBuild(
                update: update,
                context: ctx,
                prices: prices,
                bridge: bridge
            )
            await reconciler.present(root, policy: .coalesced)

            frameCount += 1

            let now = Date()
            if perfLog && now.timeIntervalSince(lastCacheLogTime) >= 1.0 {
                logCacheStats(frameCount: frameCount, treeCache: treeCache)
                lastCacheLogTime = now
            }

            if frameCount % 60 == 0 {
                let elapsed = startTime.duration(to: ContinuousClock.now)
                let elapsedSeconds = TimeInterval(elapsed.components.seconds) + TimeInterval(elapsed.components.attoseconds) / 1_000_000_000_000_000_000.0
                if elapsedSeconds > 0 {
                    let fps = Double(frameCount) / elapsedSeconds
                    print("\rFrames: \(frameCount), FPS: \(String(format: "%.1f", fps))", terminator: "")
                    fflush(stdout)
                }
            }
        }

        print()
        await telemetry.reportSummary(frames: frameCount, duration: Double(durationSeconds))
    }

    private func logCacheStats(frameCount: Int, treeCache: ComponentTreeCache) {
        #if DEBUG
        _ = frameCount
        _ = treeCache
        #endif
    }

    private func makeSampleUpdate(scenario: String = "default", seed: Int = 0, scrollOffset: Int = 0) -> TUIUpdate {
        let state = AutomationState(
            isRunning: true,
            mode: .continuous,
            startedAt: Date(),
            lastExecutionTime: Date(),
            nextExecutionTime: Date().addingTimeInterval(60),
            pid: ProcessInfo.processInfo.processIdentifier
        )

        var balances: [Holding] = []
        var recentTrades: [InvestmentTransaction] = []

        if scenario == "default" || scenario == "price-10hz" {
            balances = makeSampleBalances(seed: seed)
        }

        if scenario == "activity-scroll" || scenario == "default" {
            recentTrades = makeSampleTrades(seed: seed, count: 1000, offset: scrollOffset)
        }

        let data = TUIData(
            recentTrades: recentTrades,
            balances: balances,
            circuitBreakerOpen: false,
            lastExecutionTime: Date(),
            nextExecutionTime: Date().addingTimeInterval(60),
            totalPortfolioValue: 100000.0,
            errorCount: 0
        )

        return TUIUpdate(
            timestamp: Date(),
            type: .heartbeat,
            state: state,
            data: data,
            sequenceNumber: 0
        )
    }

    private func generateSyntheticPrices(seed: Int) -> [String: Double] {
        var prices: [String: Double] = [:]
        let basePrices: [String: Double] = [
            "BTC": 45000.0,
            "ETH": 3000.0,
            "USDC": 1.0,
            "SOL": 100.0,
            "AVAX": 35.0
        ]

        var rng = SeededRandomNumberGenerator(seed: UInt64(seed))

        for (symbol, base) in basePrices {
            let variation = Double.random(in: -0.02...0.02, using: &rng)
            prices[symbol] = base * (1.0 + variation)
        }

        return prices
    }

    private func makeSampleBalances(seed: Int) -> [Holding] {
        var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
        let assets = ["BTC", "ETH", "USDC", "SOL", "AVAX"]
        var balances: [Holding] = []
        for asset in assets {
            let qty = Double.random(in: 0.1...10.0, using: &rng)
            balances.append(Holding(
                exchange: "robinhood",
                asset: asset,
                available: qty,
                pending: 0.0,
                staked: 0.0,
                updatedAt: Date()
            ))
        }
        return balances
    }

    private func makeSampleTrades(seed: Int, count: Int, offset: Int) -> [InvestmentTransaction] {
        var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
        var trades: [InvestmentTransaction] = []
        let tradeTypes: [TradeTxnType] = [.buy, .sell]
        let assets = ["BTC", "ETH", "USDC", "SOL", "AVAX"]

        @inline(__always)
        func fnv1a64(_ x: UInt64, _ y: UInt64) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325
            h ^= x; h = h &* 0x100000001b3
            h ^= y; h = h &* 0x100000001b3
            return h
        }

        func seededUUID(seed: UInt64, index: Int) -> UUID {
            let h1 = fnv1a64(seed, UInt64(index))
            let h2 = fnv1a64(~seed, UInt64(index) &* 0x9e3779b97f4a7c15)
            var bytes = [UInt8](repeating: 0, count: 16)
            withUnsafeBytes(of: h1.littleEndian) {
                let arr = Array($0)
                for i in 0..<min(8, arr.count) {
                    bytes[i] = arr[i]
                }
            }
            withUnsafeBytes(of: h2.littleEndian) {
                let arr = Array($0)
                for i in 0..<min(8, arr.count) {
                    bytes[8 + i] = arr[i]
                }
            }
            bytes[6] = (bytes[6] & 0x0F) | 0x40
            bytes[8] = (bytes[8] & 0x3F) | 0x80
            return UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
        }

        for i in offset..<(offset + count) {
            let type = tradeTypes[i % tradeTypes.count]
            let asset = assets[i % assets.count]
            let qty = Double.random(in: 0.001...1.0, using: &rng)
            let price = Double.random(in: 1000.0...100000.0, using: &rng)
            let txID = seededUUID(seed: UInt64(seed), index: i)
            let ledgerType: SmartVestor.TransactionType = (type == .buy) ? .buy : .sell
            trades.append(InvestmentTransaction(
                id: txID,
                type: ledgerType,
                exchange: "robinhood",
                asset: asset,
                quantity: qty,
                price: price,
                fee: qty * price * 0.001,
                timestamp: Date().addingTimeInterval(Double(i) * -60.0)
            ))
        }
        return trades
    }
}

struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 1103515245 &+ 12345
        return state
    }
}
