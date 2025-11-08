import Foundation
import ArgumentParser
import SmartVestor
import Utils
import MLPatternEngine
import NIOCore
import NIOPosix
import Core
import Connectors

#if canImport(MLPatternEngineMLX) && os(macOS)
import Metal
import SmartVestorMLXAdapter
import MLPatternEngineMLX
import MLX

@_silgen_name("mlx_set_error_handler")
func mlx_set_error_handler(_ handler: @escaping @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void, _ data: UnsafeMutableRawPointer?, _ dtor: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?)

private let _forceMLXAdapterLoad: Void = {
    // Set custom error handler BEFORE any MLX operations to prevent exit()
    // This allows graceful fallback if Metal initialization fails
    mlx_set_error_handler({ msg, _ in
        if let msg = msg {
            let errorMsg = String(cString: msg)
            fputs("[MLX] Error (non-fatal, will fallback): \(errorMsg)\n", stderr)
        }
    }, nil, nil)

    // Check for explicit CPU mode requests via environment variables
    let mlxDevice = ProcessInfo.processInfo.environment["MLX_DEVICE"]
    let disableMetal = ProcessInfo.processInfo.environment["MLX_DISABLE_METAL"]

    if mlxDevice == "cpu" || disableMetal == "1" {
        // User explicitly requested CPU mode
        fputs("[MLX] CPU mode requested via environment variables\n", stderr)
    } else {
        // Try Metal - it will fall back gracefully if initialization fails
        fputs("[MLX] Attempting Metal initialization (will fall back to CPU if it fails)\n", stderr)
    }

    let _ = MLXAdapter.self
}()

private func setupMLXEnvironment() {
    if let bundleURL = Bundle.main.url(forResource: "ArbitrageEngine_SmartVestorMLXAdapter", withExtension: "bundle"),
       let bundle = Bundle(url: bundleURL),
       let metallibURL = bundle.url(forResource: "default", withExtension: "metallib") {
        let executablePath = ProcessInfo.processInfo.arguments.first ?? ""
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        let targetPath = (executableDir as NSString).appendingPathComponent("default.metallib")

        if !FileManager.default.fileExists(atPath: targetPath) {
            try? FileManager.default.copyItem(at: metallibURL, to: URL(fileURLWithPath: targetPath))
        }

        setenv("METAL_PATH", executableDir, 1)
    }
}
#endif

#if os(macOS) || os(Linux)
import Darwin
#endif


// MARK: - Constants

private let robinhoodSupportedCoins: Set<String> = [
    "BTC", "ETH", "DOGE", "LTC", "BCH", "ETC", "BSV", "USDC", "ADA", "DOT",
    "UNI", "LINK", "XLM", "MATIC", "SOL", "AVAX", "SHIB", "COMP", "AAVE",
    "YFI", "SUSHI", "MKR", "SNX", "CRV", "1INCH", "BAT", "LRC"
]

private let tuiHelpLines: [String] = [
    "                     SmartVestor TUI Help                  ",
    "",
    "Keyboard Shortcuts:",
    "──────────────────",
    "[S]tart     - Start automation (when stopped)",
    "[P]ause     - Pause automation (when running)",
    "[R]esume    - Resume automation",
    "re[F]resh   - Refresh display",
    "[H]elp      - Show this help screen",
    "[L]ogs      - Show automation logs",
    "[Q]uit      - Exit TUI",
    "",
    "Panel Toggles:",
    "──────────────",
    "[1]         - Toggle Status panel",
    "[2]         - Toggle Balances panel",
    "[3]         - Toggle Activity panel",
    "[4]         - Toggle Price panel",
    "[5]         - Toggle Swap panel",
    "[6]         - Toggle Logs panel",
    "[T]ab       - Cycle through visible panels",
    "",
    "Navigation:",
    "───────────",
    "j/k         - Scroll down/up in panels",
    "h/l         - Scroll left/right (future)",
    "Ctrl+J/K    - Page-wise scrolling",
    "",
    "Panel Actions:",
    "─────────────",
    "[O]rder     - Toggle price sort mode (Price panel)",
    "[E]xecute   - Execute selected swap (Swap panel)",
    "",
    "Other:",
    "─────",
    "Ctrl+C     - Exit TUI immediately",
    "Escape     - Exit TUI",
    "",
    "Press [H] again to close"
]

func createPersistence(config: SmartVestorConfig? = nil) throws -> PersistenceProtocol {
    if (config ?? (try? SmartVestorConfigurationManager().currentConfig)) != nil {
        let configManager = try SmartVestorConfigurationManager()
        return try configManager.createPersistence()
    }
    return SQLitePersistence(dbPath: "smartvestor.db")
}

@main
struct SmartVestorCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sv",
        abstract: "SmartVestor - Automated cryptocurrency investment management",
        version: "0.1.0",
                subcommands: [
                    StatusCommand.self,
                    CoinsCommand.self,
                    AllocateCommand.self,
                    ConnectTUICommand.self,
                    PricesCommand.self,
                    ListCoinsCommand.self,
                    PredictCommand.self,
                    TrainCommand.self,
                    RankCommand.self,
                    ModelsCommand.self,
                    UpdateModelCommand.self,
                    SwapCommand.self,
                    SyncCommand.self,
                    BalancesCommand.self,
                    ActivityCommand.self,
                    LogsCommand.self,
                    TUIBenchCommand.self,
                    TUIGraphTestCommand.self,
                    TUIDataCommand.self,
                    StartCommand.self,
                    StopCommand.self,
                    ExportLedgerCommand.self,
                    ExportBalancesCommand.self,
                    DiffLedgerCommand.self,
                    ReplayVerifyCommand.self,
                    ExecuteCutoverCommand.self,
                    RollbackCutoverCommand.self,
                    DiagCommand.self
                ]
    )

    func run() async throws {
        // MLX initialization moved to runMLBasedScoring to avoid crashes when not using ML
    }
}

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show system status and current holdings"
    )

    func run() async throws {
        let logger = StructuredLogger()
        let stateManager = AutomationStateManager(logger: logger)
        let config = try? SmartVestorConfigurationManager().currentConfig
        let persistence = try createPersistence(config: config)

        do {
            try persistence.initialize()
            try persistence.migrate()
        } catch {
            print("Warning: Could not initialize database: \(error.localizedDescription)")
        }

        var state = try? stateManager.load() ?? AutomationState(
            isRunning: false,
            mode: .continuous,
            startedAt: nil,
            lastExecutionTime: nil,
            nextExecutionTime: nil,
            pid: nil
        )

        // Verify if process is actually running
        if let currentState = state, currentState.isRunning, let pid = currentState.pid {
            #if os(macOS) || os(Linux)
            errno = 0
            let killResult = kill(pid, 0)
            let killErrno = errno
            // kill returns 0 if process exists, -1 with ESRCH if process doesn't exist, -1 with EPERM if we lack permission (but process exists)
            let isActuallyRunning = (killResult == 0) || (killResult == -1 && killErrno == EPERM)

            if !isActuallyRunning {
                // Process is not actually running, update state
                print("Warning: State file says RUNNING but process (PID: \(pid)) is not running")
                print("   Updating state to STOPPED...")
                try? stateManager.save(AutomationState(
                    isRunning: false,
                    mode: currentState.mode,
                    startedAt: currentState.startedAt,
                    lastExecutionTime: currentState.lastExecutionTime,
                    nextExecutionTime: currentState.nextExecutionTime,
                    pid: nil
                ))
                // Reload state
                state = try? stateManager.load()
            }
            #endif
        }

        var allBalances = (try? persistence.getAllAccounts()) ?? []
        allBalances = allBalances.filter { $0.total > 0 }
        let balances = allBalances
        let recentTrades = (try? persistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: 5)) ?? []

        var symbols = Array(Set(balances.map { $0.asset }))
        if !symbols.contains("USDC") && !symbols.contains("USD") {
            symbols.append("USDC")
        }

        let provider = MultiProviderMarketDataProvider(logger: logger)
        var prices: [String: Double] = [:]
        if !symbols.isEmpty {
            prices = (try? await provider.getCurrentPrices(symbols: symbols)) ?? [:]
        }

        if prices["USDC"] == nil && prices["USD"] == nil {
            prices["USDC"] = 1.0
            prices["USD"] = 1.0
        }

        let totalValue = balances.reduce(0.0) { acc, h in
            acc + h.total * (prices[h.asset] ?? 0.0)
        }

        print("SmartVestor Status")
        print("==================")
        print("")

        if let state = state {
            let statusText = state.isRunning ? "RUNNING" : "STOPPED"
            let statusColor = state.isRunning ? "\u{001B}[32m" : "\u{001B}[31m"
            let reset = "\u{001B}[0m"
            print("State: \(statusColor)\(statusText)\(reset)")
            print("Mode: \(state.mode.rawValue)")

            if let startedAt = state.startedAt {
                let formatter = ISO8601DateFormatter()
                print("Started: \(formatter.string(from: startedAt))")
            }

            if let lastExec = state.lastExecutionTime {
                let formatter = ISO8601DateFormatter()
                print("Last Execution: \(formatter.string(from: lastExec))")
            }

            if let pid = state.pid {
                #if os(macOS) || os(Linux)
                errno = 0
                let killResult = kill(pid, 0)
                let killErrno = errno
                // kill returns 0 if process exists, -1 with ESRCH if process doesn't exist, -1 with EPERM if we lack permission (but process exists)
                let isActuallyRunning = (killResult == 0) || (killResult == -1 && killErrno == EPERM)
                let pidStatus = isActuallyRunning ? "\u{001B}[32m[RUNNING]\u{001B}[0m" : "\u{001B}[31m[STOPPED]\u{001B}[0m"
                print("Process ID: \(pid) \(pidStatus)")
                if !isActuallyRunning && state.isRunning {
                    print("\u{001B}[33mWARNING: Process is marked as RUNNING but PID is not active!\u{001B}[0m")
                }
                #else
                print("Process ID: \(pid)")
                #endif
            }
        }

        print("")
        print("Portfolio")
        print("---------")
        print(String(format: "Total Value: $%.2f", totalValue))
        print("Holdings: \(balances.count)")
        print("")

        if !balances.isEmpty {
            print("Balances:")
            let separator = String(repeating: "-", count: 90)
            print(separator)

            let assetCol = "Asset".padding(toLength: 10, withPad: " ", startingAt: 0)
            let availCol = "Available".padding(toLength: 15, withPad: " ", startingAt: 0)
            let pendCol = "Pending".padding(toLength: 15, withPad: " ", startingAt: 0)
            let stakedCol = "Staked".padding(toLength: 15, withPad: " ", startingAt: 0)
            let totalCol = "Total".padding(toLength: 15, withPad: " ", startingAt: 0)
            let valueCol = "Value".padding(toLength: 15, withPad: " ", startingAt: 0)
            print("\(assetCol) \(availCol) \(pendCol) \(stakedCol) \(totalCol) \(valueCol)")
            print(separator)

            let sortedBalances = balances.sorted { (prices[$0.asset] ?? 0.0) * $0.total > (prices[$1.asset] ?? 0.0) * $1.total }

            for balance in sortedBalances {
                let value = (prices[balance.asset] ?? 0.0) * balance.total
                let assetStr = balance.asset.padding(toLength: 10, withPad: " ", startingAt: 0)
                let availStr = String(format: "%.8f", balance.available).padding(toLength: 15, withPad: " ", startingAt: 0)
                let pendStr = String(format: "%.8f", balance.pending).padding(toLength: 15, withPad: " ", startingAt: 0)
                let stakedStr = String(format: "%.8f", balance.staked).padding(toLength: 15, withPad: " ", startingAt: 0)
                let totalStr = String(format: "%.8f", balance.total).padding(toLength: 15, withPad: " ", startingAt: 0)
                let valueStr = String(format: "$%.2f", value).padding(toLength: 15, withPad: " ", startingAt: 0)
                print("\(assetStr) \(availStr) \(pendStr) \(stakedStr) \(totalStr) \(valueStr)")
            }
            print(separator)
        }

        if !recentTrades.isEmpty {
            print("")
            print("Recent Trades (last 5):")
            print(String(repeating: "-", count: 80))
            let formatter = ISO8601DateFormatter()
            for trade in recentTrades.prefix(5) {
                let dateStr = formatter.string(from: trade.timestamp)
                print("\(dateStr) - \(trade.type.rawValue): \(trade.quantity) \(trade.asset) @ \(trade.exchange)")
            }
        }
    }
}

struct CoinsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "coins",
        abstract: "Show recommended coins based on ML-powered scoring analysis"
    )

    @Option(name: .shortAndLong, help: "Number of top coins to show")
    var limit: Int = 10

    @Flag(name: .shortAndLong, help: "Show detailed scoring breakdown")
    var detailed: Bool = false

    @Option(name: .shortAndLong, help: "Filter by category (layer1, defi, gaming, etc.)")
    var category: String?

    @Flag(name: .customLong("all-coins"), help: "Show all coins (not just Robinhood-supported)")
    var allCoins: Bool = false

    func run() async throws {
        print("Starting")
        print("Using ML-based scoring")

        let _ = loadConfiguration()
        print("Config loaded")
        let logger = StructuredLogger(enabled: true)

        var coinScores: [CoinScore]

        do {
            coinScores = try await runMLBasedScoring(logger: logger)
        } catch {
            logger.error(component: "WorkingCLI", event: "scoring_failed", data: ["error": error.localizedDescription])
            coinScores = []
        }

        if !coinScores.isEmpty {
            print("\n=== MLX Prediction Verification ===")
            print("Showing top coins with predicted price changes:")
            for coin in coinScores.prefix(10) {
                let bullishScore = coin.momentumScore
                let isBullish = bullishScore > 0.5
                let direction = isBullish ? "↑ BULLISH" : "↓ BEARISH"
                print(String(format: "%@: score=%.3f, bullish=%.3f %@",
                    coin.symbol, coin.totalScore, bullishScore, direction))
            }
            print("")
        }

        print("Got scores: \(coinScores.count)")

        var filteredCoins = coinScores

        if !allCoins {
            filteredCoins = coinScores.filter { robinhoodSupportedCoins.contains($0.symbol) }
        }

        if let categoryFilter = category {
            if let coinCategory = CoinCategory(rawValue: categoryFilter) {
                filteredCoins = filteredCoins.filter { $0.category == coinCategory }
            } else {
            }
        }

        let topCoins = Array(filteredCoins.prefix(limit))

        if detailed {
            print("Detailed Coin Scores (Top \(limit)):")
            print("Method: ml_based")
            if let categoryFilter = category {
                print("Category: \(categoryFilter)")
            }
            if !allCoins {
                print("Filtered to Robinhood-supported coins")
            }
            print("")

            print("=== MLX Prediction Verification ===")
            for coin in topCoins {
                let bullishScore = coin.momentumScore
                let isBullish = bullishScore > 0.5
                let direction = isBullish ? "↑ BULLISH" : "↓ BEARISH"
                print(String(format: "%@: score=%.3f, bullish=%.3f %@",
                    coin.symbol, coin.totalScore, bullishScore, direction))
            }
            print("")

            for coin in topCoins {
                print("Symbol: \(coin.symbol)")
                print("  Total Score: \(String(format: "%.3f", coin.totalScore))")
                print("  Technical: \(String(format: "%.2f", coin.technicalScore))")
                print("  Fundamental: \(String(format: "%.2f", coin.fundamentalScore))")
                print("  Momentum: \(String(format: "%.2f", coin.momentumScore))")
                print("  Volatility: \(String(format: "%.2f", coin.volatilityScore))")
                print("  Liquidity: \(String(format: "%.2f", coin.liquidityScore))")
                print("  Market Cap: \(formatNumber(coin.marketCap))")
                print("  Category: \(coin.category)")
                print("")
            }
        }

        if !detailed {
            struct CoinsOutput: Codable {
                let coins: [CoinScore]
                let method: String
                let limit: Int
                let category: String?
                let robinhood_only: Bool
            }
            let output = CoinsOutput(
                coins: topCoins,
                method: "ml_based",
                limit: limit,
                category: category,
                robinhood_only: !allCoins
            )
            print("About to output")
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(output)
    print(String(data: data, encoding: .utf8)!)
        }

    }

    private func runMLBasedScoring(logger: StructuredLogger) async throws -> [CoinScore] {
        #if canImport(MLPatternEngineMLX) && os(macOS)
        // Configure MLX dtype FIRST, before any MLX types are created
        // Environment variables are set in _forceMLXAdapterLoad if CPU mode is requested
        MLXInitialization.configureMLX()
        setupMLXEnvironment()
        // Don't call MLXAdapter.ensureInitialized() here - let the factory handle it
        // Factory will attempt MLX initialization and fall back gracefully if it fails
        #endif

        logger.info(component: "WorkingCLI", event: "using_mlx_models")

        let useMLXModels = true

        let factory = MLPatternEngineFactory(logger: logger, useMLXModels: useMLXModels)
        let mlEngine = try await factory.createMLPatternEngine()

        try await mlEngine.start()

        let mlScoringEngine = MLScoringEngine(
            mlEngine: mlEngine,
            logger: logger
        )

        let coinScores = try await mlScoringEngine.scoreAllCoins()

        try await mlEngine.stop()

        return coinScores
    }


    private func loadConfiguration() -> SmartVestorConfig {
    let configPath = "config/smartvestor_config.json"

    guard let data = FileManager.default.contents(atPath: configPath) else {
    return SmartVestorConfig()
    }

    do {
            return try JSONDecoder().decode(SmartVestorConfig.self, from: data)
        } catch {
            print("Config load failed: \(error)")
            return SmartVestorConfig()
        }
    }

    private func formatNumber(_ number: Double) -> String {
        if number >= 1_000_000_000_000 {
            return String(format: "%.2fT", number / 1_000_000_000_000)
        } else if number >= 1_000_000_000 {
            return String(format: "%.1fB", number / 1_000_000_000)
        } else if number >= 1_000_000 {
            return String(format: "%.1fM", number / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", number / 1_000)
        } else {
            return String(format: "%.2f", number)
        }
    }
}

struct AllocateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "allocate",
        abstract: "Create allocation plan based on coin recommendations"
    )

    @Option(name: .shortAndLong, help: "Investment amount in USD")
    var amount: Double = 10000.0

    @Option(name: .shortAndLong, help: "Maximum number of positions")
    var maxPositions: Int = 12

    @Flag(name: .shortAndLong, help: "Use score-based allocation (no anchor coins)")
    var scoreBased: Bool = false

    func run() async throws {

        let config = try loadConfiguration()
        let persistence = try createPersistence(config: config)
        let marketDataProvider = MultiProviderMarketDataProvider(
            coinGeckoAPIKey: ProcessInfo.processInfo.environment["COINGECKO_API_KEY"],
            coinMarketCapAPIKey: ProcessInfo.processInfo.environment["COINMARKETCAP_API_KEY"]
        )

        if scoreBased {

            let coinScoringEngine = CoinScoringEngine(
                config: config,
                persistence: persistence,
                marketDataProvider: marketDataProvider
            )

            let scoreBasedAllocationManager = ScoreBasedAllocationManager(
                config: config,
                persistence: persistence,
                coinScoringEngine: coinScoringEngine,
                marketDataProvider: marketDataProvider
            )

            let allocationPlan = try await scoreBasedAllocationManager.createScoreBasedAllocation(
                amount: amount,
                maxPositions: maxPositions
            )


            for (_, allocation) in allocationPlan.allocations.enumerated() {
                _ = String(format: "%.1f", allocation.percentage * 100)
                _ = String(format: "%.0f", allocation.amount)
                _ = String(format: "%.3f", allocation.score)
            }


        } else {

            let allocationManager = AllocationManager(
                config: config,
                persistence: persistence
            )

            let allocationPlan = try await allocationManager.createAllocationPlan(amount: amount)


            for (_, altcoin) in allocationPlan.adjustedAllocation.altcoins.enumerated() {
                _ = String(format: "%.1f", altcoin.percentage * 100)
            }
        }

    }

    private func loadConfiguration() throws -> SmartVestorConfig {
        let configPath = "config/smartvestor_config.json"

        guard let data = FileManager.default.contents(atPath: configPath) else {
            return SmartVestorConfig()
        }

        return try JSONDecoder().decode(SmartVestorConfig.self, from: data)
    }
}

// MARK: - Mock Implementations

public class MockPersistence: PersistenceProtocol {
    public init() {}

    public func initialize() throws {}
    public func migrate() throws {}
    public func getCurrentVersion() throws -> Int { return 1 }
    public func setVersion(_ version: Int) throws {}

    public func saveAccount(_ account: Holding) throws {}
    public func getAccount(exchange: String, asset: String) throws -> Holding? { return nil }
    public func getAllAccounts() throws -> [Holding] { return [] }
    public func updateAccountBalance(exchange: String, asset: String, available: Double, pending: Double, staked: Double) throws {}

    public func saveTransaction(_ transaction: InvestmentTransaction) throws {}
    public func getTransactions(exchange: String?, asset: String?, type: SmartVestor.TransactionType?, limit: Int?) throws -> [InvestmentTransaction] { return [] }
    public func getTransaction(by idempotencyKey: String) throws -> InvestmentTransaction? { return nil }

    public func saveAllocationPlan(_ plan: AllocationPlan) throws {}
    public func getAllocationPlans(limit: Int?) throws -> [AllocationPlan] { return [] }
    public func getLatestAllocationPlan() throws -> AllocationPlan? { return nil }

    public func saveAuditEntry(_ entry: AuditEntry) throws {}
    public func getAuditEntries(component: String?, limit: Int?) throws -> [AuditEntry] { return [] }

    public func beginTransaction() throws {}
    public func commitTransaction() throws {}
    public func rollbackTransaction() throws {}
}

public class MockMarketDataProvider: MarketDataProviderProtocol {
    public init() {}

    public func getHistoricalData(startDate: Date, endDate: Date, symbols: [String]) async throws -> [String: [SmartVestor.MarketDataPoint]] {
        var data: [String: [SmartVestor.MarketDataPoint]] = [:]

        for symbol in symbols {
            let points = generateMockDataPoints(symbol: symbol, startDate: startDate, endDate: endDate)
            data[symbol] = points
        }

        return data
    }

    public func getCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        var prices: [String: Double] = [:]

        for symbol in symbols {
            prices[symbol] = generateMockPrice(for: symbol)
        }

        return prices
    }

    public func getVolumeData(symbols: [String]) async throws -> [String: Double] {
        var volumes: [String: Double] = [:]

        for symbol in symbols {
            // Create deterministic volume differences based on symbol characteristics
            let baseVolume: Double
            switch symbol {
            case "BTC": baseVolume = 35_000_000_000
            case "ETH": baseVolume = 18_000_000_000
            case "SOL": baseVolume = 3_000_000_000
            case "ADA": baseVolume = 1_200_000_000
            case "DOT": baseVolume = 800_000_000
            case "LINK": baseVolume = 1_500_000_000
            case "UNI": baseVolume = 600_000_000
            case "AAVE": baseVolume = 400_000_000
            case "COMP": baseVolume = 300_000_000
            case "MKR": baseVolume = 200_000_000
            case "AVAX": baseVolume = 800_000_000
            case "MATIC": baseVolume = 500_000_000
            case "ARB": baseVolume = 700_000_000
            case "OP": baseVolume = 600_000_000
            case "DOGE": baseVolume = 300_000_000
            case "SHIB": baseVolume = 200_000_000
            case "PEPE": baseVolume = 100_000_000
            case "BONK": baseVolume = 80_000_000
            case "WIF": baseVolume = 120_000_000
            default: baseVolume = 50_000_000
            }

            // Add deterministic symbol-specific variation
            let symbolHash = abs(symbol.hashValue)
            let variation = Double(symbolHash % 1000) / 1000.0 * 0.2 // 0-20% variation
            volumes[symbol] = baseVolume * (0.9 + variation)
        }

        return volumes
    }

    private func generateMockDataPoints(symbol: String, startDate: Date, endDate: Date) -> [SmartVestor.MarketDataPoint] {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1

        var points: [SmartVestor.MarketDataPoint] = []
        var currentDate = startDate
        var currentPrice = generateMockPrice(for: symbol)

        // Use deterministic seed based on symbol and date
        let symbolHash = abs(symbol.hashValue)
        let dateHash = Int(startDate.timeIntervalSince1970) % 1000

        for i in 0..<days {
            // Create deterministic price changes based on symbol and day
            let daySeed = (symbolHash + dateHash + i) % 1000
            let change = (Double(daySeed) / 1000.0 - 0.5) * 0.02 // -1% to +1% change
            currentPrice *= (1.0 + change)

            // Deterministic OHLC based on symbol and day
            let ohlcSeed = (symbolHash + i) % 1000
            let high = currentPrice * (1.0 + Double(ohlcSeed % 20) / 1000.0) // 0-2% high
            let low = currentPrice * (1.0 - Double((ohlcSeed + 100) % 20) / 1000.0) // 0-2% low
            let open = currentPrice * (1.0 + Double((ohlcSeed + 200) % 10) / 1000.0 - 0.005) // ±0.5% open
            let close = currentPrice

            // Deterministic volume based on symbol characteristics
            let baseVolume = getBaseVolumeForSymbol(symbol)
            let volumeSeed = (symbolHash + i * 7) % 1000
            let volume = baseVolume * (0.8 + Double(volumeSeed) / 1000.0 * 0.4) // ±20% volume variation

            let point = SmartVestor.MarketDataPoint(
                timestamp: currentDate,
                price: currentPrice,
                volume: volume,
                high: high,
                low: low,
                open: open,
                close: close
            )

            points.append(point)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? endDate
        }

        return points
    }

    private func getBaseVolumeForSymbol(_ symbol: String) -> Double {
        switch symbol {
        case "BTC": return 50_000_000
        case "ETH": return 30_000_000
        case "SOL": return 20_000_000
        case "ADA", "DOT", "LINK": return 15_000_000
        case "UNI", "AAVE", "COMP", "MKR": return 10_000_000
        case "AVAX", "MATIC", "ARB", "OP": return 12_000_000
        case "DOGE", "SHIB": return 8_000_000
        case "PEPE", "BONK", "WIF": return 5_000_000
        default: return 3_000_000
        }
    }

    private func generateMockPrice(for symbol: String) -> Double {
        // Create deterministic prices based on symbol characteristics
        let basePrice: Double
        switch symbol {
        case "BTC": basePrice = 45000
        case "ETH": basePrice = 3000
        case "ADA": basePrice = 0.5
        case "DOT": basePrice = 8
        case "LINK": basePrice = 15
        case "SOL": basePrice = 100
        case "AVAX": basePrice = 30
        case "MATIC": basePrice = 1.0
        case "ARB": basePrice = 2.0
        case "OP": basePrice = 2.5
        case "ATOM": basePrice = 10
        case "NEAR": basePrice = 4
        case "FTM": basePrice = 0.4
        case "ALGO": basePrice = 0.2
        case "ICP": basePrice = 10
        case "UNI": basePrice = 8
        case "AAVE": basePrice = 100
        case "COMP": basePrice = 50
        case "MKR": basePrice = 2500
        case "SNX": basePrice = 3
        case "GRT": basePrice = 0.2
        case "DOGE": basePrice = 0.1
        case "SHIB": basePrice = 0.00002
        case "PEPE": basePrice = 0.000002
        case "FLOKI": basePrice = 0.00002
        case "BONK": basePrice = 0.00002
        case "WIF": basePrice = 2.0
        case "BOME": basePrice = 0.015
        case "POPCAT": basePrice = 0.75
        case "MEW": basePrice = 0.03
        case "MYRO": basePrice = 0.2
        default: basePrice = 50
        }

        // Add deterministic symbol-specific variation
        let symbolHash = abs(symbol.hashValue)
        let variation = Double(symbolHash % 1000) / 1000.0 * 0.1 // 0-10% variation
        return basePrice * (0.95 + variation)
    }
}

struct ConnectTUICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tui",
        abstract: "Connect to the SmartVestor TUI server"
    )

    @Option(name: .shortAndLong, help: "Path to Unix domain socket")
    var socketPath: String = "/tmp/smartvestor-tui.sock"

    @Flag(name: .long, help: "Print raw JSON stream")
    var raw: Bool = false

    func run() async throws {
        if raw {
            // Raw mode: connect and print JSON stream
            let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

            do {
                let bootstrap = ClientBootstrap(group: group)
                    .channelInitializer { channel in
                        return channel.pipeline.addHandler(TUIClientPrintHandler())
                    }

                let channel = try await bootstrap.connect(unixDomainSocketPath: socketPath).get()

                var ping = channel.allocator.buffer(capacity: 5)
                ping.writeString("PING\n")
                channel.writeAndFlush(ping, promise: nil as EventLoopPromise<Void>?)

                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    channel.closeFuture.whenComplete { result in
                        switch result {
                        case .success:
                            continuation.resume()
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } catch {
                print("Failed to connect: \(error.localizedDescription)")
                throw error
            }

            try? await group.shutdownGracefully()
        } else {
            // TUI mode: interactive terminal interface
            await runInteractiveTUI()
        }
    }
}

final class TUIClientPrintHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let bytes = buffer.readBytes(length: buffer.readableBytes) {
            if let text = String(bytes: bytes, encoding: .utf8) {
                print(text, terminator: "")
            }
        }
    }
}

actor QuitFlag: TerminalSecurity.QuitFlagProtocol {
    private var _value = false
    func set() { _value = true }
    func isSet() -> Bool { _value }
}

actor LastUpdateStore {
    private var _update: TUIUpdate?
    func set(_ update: TUIUpdate) { _update = update }
    func get() -> TUIUpdate? { return _update }
}

actor ResizeMonitorTaskRef {
    private var task: Task<Void, Never>?
    func set(_ task: Task<Void, Never>) { self.task = task }
    func get() -> Task<Void, Never>? { return task }
}

actor UpdateContinuationRef {
    private var _continuation: AsyncStream<TUIUpdate>.Continuation?
    func set(_ continuation: AsyncStream<TUIUpdate>.Continuation) { _continuation = continuation }
    func get() -> AsyncStream<TUIUpdate>.Continuation? { return _continuation }
}

actor QuitConfirmationState {
    private var _pendingQuit = false
    private var _pendingSince: Date?

    func setPending() {
        _pendingQuit = true
        _pendingSince = Date()
    }

    func clearPending() {
        _pendingQuit = false
        _pendingSince = nil
    }

    func isPending() -> Bool {
        if _pendingQuit, let since = _pendingSince {
            let elapsed = Date().timeIntervalSince(since)
            if elapsed > 3.0 {
                clearPending()
                return false
            }
        }
        return _pendingQuit
    }
}

actor SwapConfirmationState {
    private var pendingSwap: SwapEvaluation?

    func setPending(_ swap: SwapEvaluation) {
        pendingSwap = swap
    }

    func clearPending() {
        pendingSwap = nil
    }

    func getPending() -> SwapEvaluation? {
        return pendingSwap
    }

    func isPending() -> Bool {
        return pendingSwap != nil
    }
}

actor HelpStateRef {
    private var _helpState = HelpState()

    func toggle() async {
        await _helpState.toggle()
    }

    func isVisible() async -> Bool {
        return await _helpState.isVisible()
    }

    func getScrollOffset() async -> Int {
        return await _helpState.getScrollOffset()
    }

    func scrollDown(maxLines: Int, visibleLines: Int) async {
        await _helpState.scrollDown(maxLines: maxLines, visibleLines: visibleLines)
    }

    func scrollUp() async {
        await _helpState.scrollUp()
    }

    func hide() async {
        await _helpState.hide()
    }
}

actor ChannelRef {
    private var _channel: Channel?
    func set(_ channel: Channel?) { _channel = channel }
    func get() -> Channel? { _channel }
}

actor ServerTaskRef {
    private var _task: Task<Void, Error>?
    func set(_ task: Task<Void, Error>?) { _task = task }
    func get() -> Task<Void, Error>? { _task }
}

final class TUIClientUpdateHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private var buffer = Data()
    private let updateContinuation: AsyncStream<TUIUpdate>.Continuation

    init(updateContinuation: AsyncStream<TUIUpdate>.Continuation) {
        self.updateContinuation = updateContinuation
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var byteBuffer = unwrapInboundIn(data)
        guard let bytes = byteBuffer.readBytes(length: byteBuffer.readableBytes) else { return }
        buffer.append(contentsOf: bytes)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var lines = buffer.split(separator: 10)
        if !buffer.isEmpty && buffer.last != 10 {
            buffer = Data(lines.removeLast())
        } else {
            buffer.removeAll()
        }

        for lineData in lines {
            do {
                let update = try decoder.decode(TUIUpdate.self, from: lineData)
                if !update.data.prices.isEmpty {
                    let priceKeys = Array(update.data.prices.keys).sorted()
                    let debugMsg = "Received TUI update with \(update.data.prices.count) prices: \(priceKeys.joined(separator: ", "))\n"
                    if let data = debugMsg.data(using: .utf8) {
                        try? FileHandle.standardError.write(contentsOf: data)
                    }
                }
                updateContinuation.yield(update)
            } catch {
                continue
            }
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        var ping = context.channel.allocator.buffer(capacity: 5)
        ping.writeString("PING\n")
        context.channel.writeAndFlush(ping, promise: nil)
    }
}

// MARK: - Interactive TUI Implementation

extension ConnectTUICommand {
    // Performance optimizations: Shared diff renderer
    private static let sharedDiffRenderer = DiffRenderer()

    func runInteractiveTUI() async {
        #if os(macOS) || os(Linux)
        signal(SIGPIPE, SIG_IGN)
        #endif

        _ = Runtime.renderBus

        let logger = StructuredLogger(enabled: false)
        let terminalSecurity = TerminalSecurity(logger: logger)
        let enhancedRenderer = EnhancedTUIRenderer()
        let existingLogPath = ProcessInfo.processInfo.environment["SMARTVESTOR_LOG_PATH"]
        if existingLogPath == nil || existingLogPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            setenv("SMARTVESTOR_LOG_PATH", "/tmp/smartvestor.log", 1)
        }

        #if os(macOS) || os(Linux)
        let isTTY = isatty(STDIN_FILENO) != 0
        let isOutputTTY = await Runtime.renderBus.isOutputTTY()
        #else
        let isTTY = true
        let isOutputTTY = await Runtime.renderBus.isOutputTTY()
        #endif

        if !isOutputTTY {
            let logger = StructuredLogger(enabled: true)
            logger.info(component: "TUI", event: "non_tty_output_detected", data: ["fallback": "file_logging"])
        }

        if !isTTY {
            await enhancedRenderer.renderInitialState()
            print("\nWarning: Interactive keyboard input not available in this environment.")
            print("   To use the interactive TUI:")
            print("   • Run in a proper terminal: sv tui")
            print("   • Start automation with TUI: sv start --tui")
            print("   • Use raw JSON mode: sv tui --raw")
            return
        }

        do {
            _ = try terminalSecurity.setupTerminal()
        } catch TerminalSecurityError.nonTTY {
            print("Non-TTY detected. Disabling TUI.")
            return
        } catch {
            print("Warning: Failed to setup terminal: \(error.localizedDescription)")
            return
        }

        let keyboardHandler = KeyboardHandler(logger: logger, terminalSecurity: terminalSecurity)
        let serverTaskRef = ServerTaskRef()
        let quitFlag = QuitFlag()
        terminalSecurity.setQuitFlag(quitFlag)

        let (updateStream, updateContinuation) = AsyncStream.makeStream(of: TUIUpdate.self)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let channelRef = ChannelRef()

        defer {
            terminalSecurity.restoreTerminalState()
        }

        let tryConnect: @Sendable () async -> Channel? = {
            do {
                let bootstrap = ClientBootstrap(group: group)
                    .channelInitializer { ch in
                        return ch.pipeline.addHandler(TUIClientUpdateHandler(updateContinuation: updateContinuation))
                    }

                return try await bootstrap.connect(unixDomainSocketPath: socketPath).get()
            } catch {
                return nil
            }
        }

        // Try to load initial data from persistence before rendering
        let initialPersistence = try? createPersistence()
        if let persistence = initialPersistence {
            do {
                try persistence.initialize()
                try persistence.migrate()
            } catch {
                // Continue without persistence if initialization fails
            }
        }
        await enhancedRenderer.renderInitialState(persistence: initialPersistence)

        try? await Task.sleep(nanoseconds: 100_000_000)

        let lastUpdateStore = LastUpdateStore()

        var channel = await tryConnect()
        await channelRef.set(channel)

        if channel == nil {
            await showCenteredStatus("Polling data directly (server not running)", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)

            _ = Task.detached { @Sendable in
                guard let persistence = try? createPersistence() else {
                    return
                }
                do {
                    try persistence.initialize()
                    try persistence.migrate()
                } catch {
                }

                let provider = MultiProviderMarketDataProvider()
                var sequenceNumber: Int64 = 0

                func sendUpdate() async {
                    do {
                        let balances = try persistence.getAllAccounts()
                        let recent = try persistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: 10)
                        var symbols = Array(Set(balances.map { $0.asset }))

                        if !symbols.contains("USDC") && !symbols.contains("USD") {
                            symbols.append("USDC")
                        }

                        var prices: [String: Double] = [:]
                        if !symbols.isEmpty {
                            prices = (try? await provider.getCurrentPrices(symbols: symbols)) ?? [:]
                        }

                        if prices["USDC"] == nil && prices["USD"] == nil {
                            prices["USDC"] = 1.0
                            prices["USD"] = 1.0
                        }

                        let totalValue = balances.reduce(0.0) { acc, h in
                            acc + h.total * (prices[h.asset] ?? 0.0)
                        }

                        let state = AutomationState(
                            isRunning: false,
                            mode: .continuous,
                            startedAt: nil,
                            lastExecutionTime: nil,
                            nextExecutionTime: nil,
                            pid: nil
                        )

                        let data = TUIData(
                            recentTrades: recent,
                            balances: balances,
                            circuitBreakerOpen: false,
                            lastExecutionTime: nil,
                            nextExecutionTime: nil,
                            totalPortfolioValue: totalValue,
                            errorCount: 0,
                            prices: prices,
                            swapEvaluations: []
                        )

                        let update = TUIUpdate(
                            type: .heartbeat,
                            state: state,
                            data: data,
                            sequenceNumber: sequenceNumber
                        )

                        sequenceNumber += 1
                        updateContinuation.yield(update)
                    } catch {
                    }
                }

                await sendUpdate()

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await sendUpdate()
                }
            }

            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                channel = await tryConnect()
                if channel != nil {
                    await channelRef.set(channel)
                    await showCenteredStatus("Server connected. Using server updates.", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                    break
                }
            }
        } else {
            try? await Task.sleep(nanoseconds: 100_000_000)
            await showCenteredStatus("Connected to server", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
        }

        defer {
            Task {
                let ch = await channelRef.get()
                try? await ch?.close()
                try? await group.shutdownGracefully()
            }
            Task {
                let task = await serverTaskRef.get()
                task?.cancel()
            }
        }

        do {
            let keyStream = try keyboardHandler.startReading()
            let lastUpdateStore = LastUpdateStore()
            let updateContinuationRef = UpdateContinuationRef()
            let quitConfirmationState = QuitConfirmationState()
            let helpStateRef = HelpStateRef()
            await updateContinuationRef.set(updateContinuation)

            let layoutManager = LayoutManager.shared
            let resizeMonitorTaskRef = ResizeMonitorTaskRef()

            let enhancedRendererForResize = enhancedRenderer
            let lastUpdateStoreForResize = lastUpdateStore
            let helpStateRefForResize = helpStateRef

            let resizeTask = layoutManager.startResizeMonitoring { @Sendable newSize in
                Task { @Sendable in
                    await enhancedRendererForResize.invalidateCachedTerminalSize()
                    // Check if help overlay is visible and preserve its state
                    let isHelpVisible = await helpStateRefForResize.isVisible()
                    let helpScrollOffset = isHelpVisible ? await helpStateRefForResize.getScrollOffset() : 0

                    // Trigger a re-render if we have an update
                    if let update = await lastUpdateStoreForResize.get() {
                        // If help was visible, restore it after rendering with the new size
                        if isHelpVisible {
                            await enhancedRendererForResize.renderUpdate(update)
                            await enhancedRendererForResize.showHelpOverlay(lines: tuiHelpLines, scrollOffset: helpScrollOffset)
                        } else {
                            await enhancedRendererForResize.renderUpdate(update)
                        }
                    }
                }
            }
            await resizeMonitorTaskRef.set(resizeTask)

            await withTaskGroup(of: Void.self) { group in
                group.addTask { @Sendable in
                    for await update in updateStream {
                        if await quitFlag.isSet() {
                            break
                        }
                        await lastUpdateStore.set(update)
                        // Always render - the renderer will handle the help overlay if it's visible
                        await enhancedRenderer.renderUpdate(update)
                    }
                    await quitFlag.set()
                    if let task = await resizeMonitorTaskRef.get() {
                        task.cancel()
                    }
                    layoutManager.stopResizeMonitoring()
                }

                group.addTask { @Sendable in
                    let toggleManager = await enhancedRenderer.getToggleManager()
                    let scrollState = await enhancedRenderer.getScrollState()
                    let priceSortManager = await enhancedRenderer.getPriceSortManager()
                    let keyDebouncer = KeyDebouncer(debounceInterval: 0.05)

                    func itemCount(for panel: PanelType, update: TUIUpdate) -> Int {
                        switch panel {
                        case .balances, .balance:
                            return update.data.balances.count
                        case .activity:
                            return update.data.recentTrades.count
                        case .price:
                            return update.data.prices.count
                        case .swap:
                            return update.data.swapEvaluations.count
                        case .logs:
                            // Logs panel handles its own scrolling internally
                            return 100 // Placeholder
                        case .status:
                            return 1
                        default:
                            return 0
                        }
                    }

                    let swapConfirmationState = SwapConfirmationState()

                    for await keyEvent in keyStream {
                        if await quitFlag.isSet() { break }

                        let shouldProcess = await keyDebouncer.shouldProcess(keyEvent)
                        guard shouldProcess else { continue }

                        let command = TUICommand.from(keyEvent: keyEvent)
                        let selectedPanel = await toggleManager.getSelectedPanel()

                        if await swapConfirmationState.isPending() {
                            if case .character(let char) = keyEvent {
                                let charLower = char.lowercased()
                                if charLower == "y" || charLower == "\r" {
                                    if let swap = await swapConfirmationState.getPending() {
                                        await swapConfirmationState.clearPending()
                                        await executeSwapWithManager(
                                            swap: swap,
                                            enhancedRenderer: enhancedRenderer,
                                            lastUpdateStore: lastUpdateStore
                                        )
                                    }
                                } else if charLower == "n" || charLower == "\u{001B}" {
                                    await swapConfirmationState.clearPending()
                                    await clearCenteredDialog(enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                                }
                            } else if case .escape = keyEvent {
                                await swapConfirmationState.clearPending()
                                await clearCenteredDialog(enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                            }
                            continue
                        }

                        if await quitConfirmationState.isPending() {
                            if case .character(let char) = keyEvent {
                                if char.lowercased() == "q" {
                                    await quitFlag.set()
                                    if let continuation = await updateContinuationRef.get() {
                                        continuation.finish()
                                    }
                                    keyboardHandler.stop()
                                    break
                                } else {
                                    await quitConfirmationState.clearPending()
                                }
                            } else {
                                await quitConfirmationState.clearPending()
                            }
                        }

                        switch keyEvent {
                        case .character(let char):
                            let charLower = char.lowercased()
                            switch charLower {
                            case "1":
                                do {
                                    try await toggleManager.toggle(.status)
                                    if await toggleManager.isVisible(.status) {
                                        await scrollState.resetScrollPosition(for: .status)
                                    }
                                    if let update = await lastUpdateStore.get() {
                                        await enhancedRenderer.renderUpdate(update)
                                    }
                                } catch {
                                    await showCenteredError("Error toggling panel: \(error.localizedDescription)", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                                }
                                continue
                            case "2":
                                do {
                                    try await toggleManager.toggle(.balances)
                                    if await toggleManager.isVisible(.balances) {
                                        await scrollState.resetScrollPosition(for: .balances)
                                    }
                                    if let update = await lastUpdateStore.get() {
                                        await enhancedRenderer.renderUpdate(update)
                                    }
                                } catch {
                                    await showCenteredError("Error toggling panel: \(error.localizedDescription)", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                                }
                                continue
                            case "3":
                                do {
                                    try await toggleManager.toggle(.activity)
                                    if await toggleManager.isVisible(.activity) {
                                        await scrollState.resetScrollPosition(for: .activity)
                                    }
                                    if let update = await lastUpdateStore.get() {
                                        await enhancedRenderer.renderUpdate(update)
                                    }
                                } catch {
                                    await showCenteredError("Error toggling panel: \(error.localizedDescription)", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                                }
                                continue
                            case "4":
                                do {
                                    try await toggleManager.toggle(.price)
                                    if await toggleManager.isVisible(.price) {
                                        await scrollState.resetScrollPosition(for: .price)
                                    }
                                    if let update = await lastUpdateStore.get() {
                                        await enhancedRenderer.renderUpdate(update)
                                    }
                                } catch {
                                    await showCenteredError("Error toggling panel: \(error.localizedDescription)", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                                }
                                continue
                            case "5":
                                do {
                                    try await toggleManager.toggle(.swap)
                                    if await toggleManager.isVisible(.swap) {
                                        await scrollState.resetScrollPosition(for: .swap)
                                    }
                                    if let update = await lastUpdateStore.get() {
                                        await enhancedRenderer.renderUpdate(update)
                                    }
                                } catch {
                                    await showCenteredError("Error toggling panel: \(error.localizedDescription)", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                                }
                                continue
                            case "6":
                                do {
                                    try await toggleManager.toggle(.logs)
                                    if await toggleManager.isVisible(.logs) {
                                        await scrollState.resetScrollPosition(for: .logs)
                                        let stateMgr = AutomationStateManager(logger: logger)
                                        let persistence: PersistenceProtocol? = try? createPersistence()
                                        let processor = CommandProcessor(
                                            stateManager: stateMgr,
                                            logger: logger,
                                            persistence: persistence
                                        )
                                        if let result = try? await processor.process(.logs, currentState: nil),
                                           let message = result.message {
                                            let logLines = message.components(separatedBy: .newlines).filter { !$0.isEmpty }
                                            if let logsRenderer = await enhancedRenderer.getLogsRenderer() {
                                                logsRenderer.setLogEntries(logLines)
                                            }
                                        }
                                    }
                                    if let update = await lastUpdateStore.get() {
                                        await enhancedRenderer.renderUpdate(update)
                                    }
                                } catch {
                                    await showCenteredError("Error toggling logs panel: \(error.localizedDescription)", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                                }
                                continue
                            case "j":
                                if await helpStateRef.isVisible() {
                                    // Calculate visible lines based on terminal size
                                    let terminalSize = await enhancedRenderer.getTerminalSize()
                                    let availableLines = max(terminalSize.height - 4, 1)
                                    let visibleLines = min(tuiHelpLines.count, availableLines)
                                    await helpStateRef.scrollDown(maxLines: tuiHelpLines.count, visibleLines: visibleLines)
                                    let scrollOffset = await helpStateRef.getScrollOffset()
                                    await presentHelpOverlay(
                                        enhancedRenderer: enhancedRenderer,
                                        lastUpdateStore: lastUpdateStore,
                                        scrollOffset: scrollOffset
                                    )
                                } else if let panel = selectedPanel, let update = await lastUpdateStore.get() {
                                    let items = itemCount(for: panel, update: update)
                                    guard items > 0 else { continue }
                                    _ = await scrollState.scrollDown(panelType: panel, maxItems: items)
                                    await enhancedRenderer.renderUpdate(update)
                                }
                                continue
                            case "k":
                                if await helpStateRef.isVisible() {
                                    await helpStateRef.scrollUp()
                                    let scrollOffset = await helpStateRef.getScrollOffset()
                                    await presentHelpOverlay(
                                        enhancedRenderer: enhancedRenderer,
                                        lastUpdateStore: lastUpdateStore,
                                        scrollOffset: scrollOffset
                                    )
                                } else if let panel = selectedPanel, let update = await lastUpdateStore.get() {
                                    _ = await scrollState.scrollUp(panelType: panel)
                                    await enhancedRenderer.renderUpdate(update)
                                }
                                continue
                            case "o":
                                if selectedPanel == .price {
                                    await priceSortManager.toggleSortMode()
                                    if let update = await lastUpdateStore.get() {
                                        await enhancedRenderer.renderUpdate(update)
                                    }
                                    continue
                                }
                                break
                            case "e":
                                if selectedPanel == .swap {
                                    if let update = await lastUpdateStore.get() {
                                        let swapEvaluations = update.data.swapEvaluations
                                        if !swapEvaluations.isEmpty {
                                            let scrollPos = await scrollState.getScrollPosition(for: .swap)
                                            let selectedIndex = max(0, min(scrollPos, swapEvaluations.count - 1))
                                            let selectedSwap = swapEvaluations[selectedIndex]

                                            if selectedSwap.isWorthwhile {
                                                await swapConfirmationState.setPending(selectedSwap)
                                                let confirmationMessage = "Execute swap: \(selectedSwap.fromAsset) -> \(selectedSwap.toAsset)?\nNet value: $\(String(format: "%.2f", selectedSwap.netValue))  [Y]es/[N]o"
                                                await showCenteredDialog(confirmationMessage)
                                            } else {
                                                await showStatusMessage("Swap not worthwhile (confidence: \(Int(selectedSwap.confidence * 100))%)")
                                            }
                                        } else {
                                            await showStatusMessage("No swaps available")
                                        }
                                    }
                                }
                                continue
                            default:
                                break
                            }
                        case .tab:
                            await toggleManager.cycleToNextVisiblePanel()
                            if let update = await lastUpdateStore.get() {
                                await enhancedRenderer.renderUpdate(update)
                            }
                            continue
                        case .control(let char):
                            let charLower = char.lowercased()
                            if let panel = selectedPanel {
                                if charLower == "j" {
                                    if let update = await lastUpdateStore.get() {
                                        let items = itemCount(for: panel, update: update)
                                        guard items > 0 else { continue }
                                        _ = await scrollState.scrollPageDown(panelType: panel, pageSize: 10, maxItems: items)
                                        await enhancedRenderer.renderUpdate(update)
                                    }
                                    continue
                                } else if charLower == "k" {
                                    if let update = await lastUpdateStore.get() {
                                        _ = await scrollState.scrollPageUp(panelType: panel, pageSize: 10)
                                        await enhancedRenderer.renderUpdate(update)
                                    }
                                    continue
                                }
                            }
                        default:
                            break
                        }

                        guard let cmd = command else { continue }

                        switch cmd {
                        case .quit:
                            await helpStateRef.hide()
                            await clearHelp()
                            let isPending = await quitConfirmationState.isPending()
                            if isPending {
                                await quitFlag.set()
                                if let continuation = await updateContinuationRef.get() {
                                    continuation.finish()
                                }
                                keyboardHandler.stop()
                                break
                            } else {
                                await quitConfirmationState.setPending()
                                await showCenteredDialog("Press 'q' again to quit")
                                Task.detached {
                                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                                    await quitConfirmationState.clearPending()
                                    if await quitFlag.isSet() == false {
                                        await clearCenteredDialog(enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                                    }
                                }
                            }
                            continue
                        case .logs:
                            do {
                                try await toggleManager.toggle(.logs)
                                if await toggleManager.isVisible(.logs) {
                                    await scrollState.resetScrollPosition(for: .logs)
                                    let stateMgr = AutomationStateManager(logger: logger)
                                    let persistence: PersistenceProtocol? = try? createPersistence()
                                    let processor = CommandProcessor(
                                        stateManager: stateMgr,
                                        logger: logger,
                                        persistence: persistence
                                    )
                                    if let result = try? await processor.process(.logs, currentState: nil),
                                       let message = result.message {
                                        let logLines = message.components(separatedBy: .newlines).filter { !$0.isEmpty }
                                        if let logsRenderer = await enhancedRenderer.getLogsRenderer() {
                                            logsRenderer.setLogEntries(logLines)
                                        }
                                    }
                                }
                                if let update = await lastUpdateStore.get() {
                                    await enhancedRenderer.renderUpdate(update)
                                }
                            } catch {
                                await showCenteredError("Error toggling logs panel: \(error.localizedDescription)", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                            }
                            continue
                        case .help:
                            await helpStateRef.toggle()
                            if await helpStateRef.isVisible() {
                                // Show help overlay
                                let scrollOffset = await helpStateRef.getScrollOffset()
                                await presentHelpOverlay(
                                    enhancedRenderer: enhancedRenderer,
                                    lastUpdateStore: lastUpdateStore,
                                    scrollOffset: scrollOffset
                                )
                            } else {
                                // Hide help overlay
                                await dismissHelpOverlay(
                                    enhancedRenderer: enhancedRenderer,
                                    lastUpdateStore: lastUpdateStore
                                )
                            }
                            continue
                        case .refresh:
                            await showCenteredStatus("Refreshing...", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                        case .start:
                            let stateMgr = AutomationStateManager(logger: logger)
                            if let currentState = try? stateMgr.load(), currentState.isRunning {
                                await showCenteredStatus("Server is already running", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                            } else {
                                await showCenteredStatus("Starting server...", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                                let task = await startAutomationServer(logger: logger)
                                await serverTaskRef.set(task)

                                for _ in 0..<10 {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    let newChannel = await tryConnect()
                                    if newChannel != nil {
                                        await channelRef.set(newChannel)
                                        await showStatusMessage("Server started")
                                        break
                                    }
                                }
                            }
                        case .pause, .resume:
                            let stateMgr = AutomationStateManager(logger: logger)
                            let persistence: PersistenceProtocol? = try? createPersistence()
                            if let currentState = try? stateMgr.load() {
                                let processor = CommandProcessor(
                                    stateManager: stateMgr,
                                    logger: logger,
                                    persistence: persistence
                                )
                                _ = try? await processor.process(cmd, currentState: currentState)
                            }
                        }
                    }
                }
            }
        } catch {
            logger.error(component: "TUI", event: "Error", data: ["error": error.localizedDescription])
        }

        updateContinuation.finish()
        keyboardHandler.stop()
        terminalSecurity.restoreTerminalState()
        print("\u{001B}[?25h", terminator: "")
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        fflush(stdout)
    }

    func startAutomationServer(logger: StructuredLogger) async -> Task<Void, Error> {
        return Task {
            let logPath = ProcessInfo.processInfo.environment["SMARTVESTOR_LOG_PATH"]
            let consoleLogger = StructuredLogger(logFilePath: logPath)
            let lockManager = ProcessLockManager(logger: consoleLogger)

            guard try lockManager.acquireLock() else {
                throw SmartVestorError.executionError("Server already running")
            }

            defer {
                try? lockManager.releaseLock()
            }

            var exchangeConnectors: [String: ExchangeConnectorProtocol] = [:]

            var apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"]
            var privateKeyBase64 = ProcessInfo.processInfo.environment["ROBINHOOD_PRIVATE_KEY"]

            if apiKey == nil || privateKeyBase64 == nil {
                let envPath = ".env"
                if let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) {
                    for line in envContent.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

                        let parts = trimmed.components(separatedBy: "=")
                        if parts.count >= 2 {
                            let key = parts[0].trimmingCharacters(in: .whitespaces)
                            let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)

                            if key == "ROBINHOOD_API_KEY" && apiKey == nil {
                                apiKey = value
                            } else if key == "ROBINHOOD_PRIVATE_KEY" && privateKeyBase64 == nil {
                                privateKeyBase64 = value
                            }
                        }
                    }
                }
            }

            if let apiKey = apiKey, let privateKeyBase64 = privateKeyBase64 {
                let sanitizedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                let sanitizedPrivateKey = privateKeyBase64
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    .filter { !$0.isWhitespace && $0 != "\n" && $0 != "\r" }

                if !sanitizedApiKey.isEmpty && !sanitizedPrivateKey.isEmpty {
                    setenv("ROBINHOOD_API_KEY", sanitizedApiKey, 1)
                    setenv("ROBINHOOD_PRIVATE_KEY", sanitizedPrivateKey, 1)

                    do {
                        let credentials = try RobinhoodConnector.Configuration.Credentials(
                            apiKey: sanitizedApiKey,
                            privateKeyBase64: sanitizedPrivateKey
                        )
                        let robinhoodConnector = RobinhoodConnector(
                            logger: consoleLogger,
                            configuration: RobinhoodConnector.Configuration(
                                credentials: credentials
                            )
                        )
                        exchangeConnectors["robinhood"] = robinhoodConnector
                    } catch {
                    }
                }
            }

            let components = try await AutomationBootstrapper.createComponents(
                configPath: nil,
                productionMode: false,
                exchangeConnectors: exchangeConnectors,
                logger: consoleLogger
            )

            let tuiServer = TUIServer()
            try await tuiServer.start()

            let stateManager = AutomationStateManager(logger: consoleLogger)
            let initialState = AutomationState(
                isRunning: true,
                mode: .continuous,
                startedAt: Date(),
                lastExecutionTime: nil,
                nextExecutionTime: nil,
                pid: ProcessInfo.processInfo.processIdentifier
            )
            try stateManager.save(initialState)

            if let runner = components.continuousRunner {
                runner.setTUI(server: tuiServer)
                try await runner.startContinuousMonitoring()
            }

            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }

            if let runner = components.continuousRunner {
                await runner.stopContinuousMonitoring()
            }
            await tuiServer.stop()
        }
    }

    func showLogs(message: String, enhancedRenderer: EnhancedTUIRenderer) async {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        print(message)
        print("\n(Press any key to return)")
        fflush(stdout)

        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        } catch {
        }
    }

    func renderTUI(enhancedRenderer: EnhancedTUIRenderer, commandBarRenderer: CommandBarRenderer, isRunning: Bool, mode: AutomationMode, lastFrame: [String]?) async -> [String] {
        let mockData = TUIData(
            recentTrades: [],
            balances: [],
            circuitBreakerOpen: false,
            lastExecutionTime: nil,
            nextExecutionTime: nil,
            totalPortfolioValue: 0,
            errorCount: 0
        )

        let mockState = AutomationState(
            isRunning: isRunning,
        mode: mode,
        startedAt: isRunning ? Date() : nil, // Only create Date when needed
        lastExecutionTime: nil,
        nextExecutionTime: nil,
        pid: nil
        )

        let update = TUIUpdate(
            type: .heartbeat,
            state: mockState,
            data: mockData,
            sequenceNumber: 0
        )

        // Use the EnhancedTUIRenderer to render the full TUI including command bar
        let frame = await enhancedRenderer.renderPanels(update, prices: nil, focus: nil)

        // Use diff rendering for better performance if we have a previous frame
        if let lastFrame = lastFrame, lastFrame.count == frame.count {
            // Use diff rendering - only update changed lines
            await Self.sharedDiffRenderer.renderDiff(oldFrame: lastFrame, newFrame: frame)
        } else {
            // Full render for initial or resized frames
            await Self.sharedDiffRenderer.renderFull(newFrame: frame)
        }

        return frame
    }

    func handleKeyEvent(_ event: KeyEvent, enhancedRenderer: EnhancedTUIRenderer, commandBarRenderer: CommandBarRenderer, isRunning: inout Bool, mode: AutomationMode, lastFrame: inout [String]?) async -> Bool {
        var highlightedKey: String?

        switch event {
        case .character(let char):
            let key = String(char).uppercased()
            highlightedKey = key

            switch char.lowercased() {
            case "q":
                return true // Exit
            case "h", "?":
                await showHelp(scrollOffset: 0)
                return false
            case "p":
                await handlePauseCommand(isRunning: &isRunning, mode: mode)
            case "r":
                await handleResumeCommand(isRunning: &isRunning, mode: mode)
            case "s":
                await handleStartCommand(isRunning: &isRunning, mode: mode)
            case "f":
                await refreshDisplay(enhancedRenderer: enhancedRenderer, commandBarRenderer: commandBarRenderer, isRunning: isRunning, mode: mode, lastFrame: &lastFrame)
            case "l":
                await showStatusMessage("Logs command sent (no server connected)")
            default:
                await showStatusMessage("Unknown command: \(char)")
            }
        case .escape:
            return true // Exit
        case .control(let char):
            if char == "c" {
                return true // Exit
            }
        default:
            break
        }

        // Update command bar highlighting
        await updateCommandBar(commandBarRenderer: commandBarRenderer, highlightedKey: highlightedKey, isRunning: isRunning)

        return false
    }

    func showHelp(scrollOffset: Int = 0) async {
        #if os(macOS) || os(Linux)
        var size = winsize()
        let TIOCGWINSZ: UInt = 0x40087468
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 {
            let rows = Int(size.ws_row)
            let cols = Int(size.ws_col)

            let helpText = """
╔═══════════════════════════════════════════════════════════╗
║                     SmartVestor TUI Help                     ║
╚═══════════════════════════════════════════════════════════╝

Keyboard Shortcuts:
──────────────────
[S]tart     - Start automation (when stopped)
[P]ause     - Pause automation (when running)
[R]esume    - Resume automation
re[F]resh   - Refresh display
[H]elp      - Show this help screen
[L]ogs      - Show automation logs
[Q]uit      - Exit TUI

Panel Toggles:
──────────────
[1]         - Toggle Status panel
[2]         - Toggle Balances panel
[3]         - Toggle Activity panel
[4]         - Toggle Price panel
[5]         - Toggle Swap panel
[6]         - Toggle Logs panel
[T]ab       - Cycle through visible panels

Navigation:
───────────
j/k         - Scroll down/up in panels
h/l         - Scroll left/right (future)
Ctrl+J/K    - Page-wise scrolling

Other:
─────
Ctrl+C     - Exit TUI immediately
Escape     - Exit TUI

Press [H] again o to close
"""

            let helpLines = helpText.components(separatedBy: .newlines)
            let maxVisibleLines = min(rows - 4, helpLines.count)
            let dialogWidth = min(70, cols - 4)
            let dialogHeight = min(maxVisibleLines + 4, rows - 4)
            let startRow = max(1, (rows - dialogHeight) / 2)
            let startCol = max(1, (cols - dialogWidth) / 2)

            let visibleStart = max(0, min(scrollOffset, helpLines.count - maxVisibleLines))
            let visibleEnd = min(helpLines.count, visibleStart + maxVisibleLines)
            let visibleLines = Array(helpLines[visibleStart..<visibleEnd])

            // Build the entire output string first for atomic rendering
            // Save cursor position so we can restore it later if needed
            var output = "\u{001B}[s"  // Save cursor position
            output += "\u{001B}[?25l"  // Hide cursor

            let borderTop = String(repeating: "═", count: dialogWidth - 2)
            let borderBottom = String(repeating: "═", count: dialogWidth - 2)
            let bottomRow = startRow + visibleLines.count + 1

            // First, completely clear the entire dialog rectangular area
            // For each row in the dialog area, clear from startCol to the end of the dialog width
            for row in startRow...bottomRow {
                output += "\u{001B}[\(row);\(startCol)H"
                // Clear exactly dialogWidth characters by writing spaces
                for _ in 0..<dialogWidth {
                    output += " "
                }
                // Move back to start of dialog area for this row
                output += "\u{001B}[\(row);\(startCol)H"
            }

            // Now draw the dialog on the cleared area
            // Top border row
            output += "\u{001B}[\(startRow);\(startCol)H"
            output += "╔\(borderTop)╗"

            // Content rows
            for (idx, line) in visibleLines.enumerated() {
                let row = startRow + idx + 1
                let trimmedLine = String(line.prefix(dialogWidth - 4))
                let paddedLine = trimmedLine.padding(toLength: dialogWidth - 4, withPad: " ", startingAt: 0)

                output += "\u{001B}[\(row);\(startCol)H"
                output += "║ \(paddedLine) ║"
            }

            // Bottom border row
            output += "\u{001B}[\(bottomRow);\(startCol)H"
            output += "╚\(borderBottom)╝"

            // Move cursor out of the way to avoid interfering
            output += "\u{001B}[\(rows);\(cols)H"

            // Output everything at once
            print(output, terminator: "")
            fflush(stdout)
        } else {
            print("Help: Press H to show/hide, Q or Escape to close")
        }
        #else
        print("Help: Press H to show/hide, Q or Escape to close")
        #endif
    }

    func clearHelp() async {
        // Clear help dialog by erasing the dialog area
        #if os(macOS) || os(Linux)
        var size = winsize()
        let TIOCGWINSZ: UInt = 0x40087468
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 {
            let rows = Int(size.ws_row)
            let cols = Int(size.ws_col)

            // Calculate the dialog area to clear (same as when we drew it)
            let helpText = """
╔═══════════════════════════════════════════════════════════╗
║                     SmartVestor TUI Help                     ║
╚═══════════════════════════════════════════════════════════╝

Keyboard Shortcuts:
──────────────────
[S]tart     - Start automation (when stopped)
[P]ause     - Pause automation (when running)
[R]esume    - Resume automation
re[F]resh   - Refresh display
[H]elp      - Show this help screen
[L]ogs      - Show automation logs
[Q]uit      - Exit TUI

Panel Toggles:
──────────────
[1]         - Toggle Status panel
[2]         - Toggle Balances panel
[3]         - Toggle Activity panel
[4]         - Toggle Price panel
[5]         - Toggle Swap panel
[6]         - Toggle Logs panel
[T]ab       - Cycle through visible panels

Navigation:
───────────
j/k         - Scroll down/up in panels
h/l         - Scroll left/right (future)
Ctrl+J/K    - Page-wise scrolling

Panel Actions:
─────────────
[O]rder     - Toggle price sort mode (Price panel)
[E]xecute   - Execute selected swap (Swap panel)

Other:
─────
Ctrl+C     - Exit TUI immediately
Escape     - Exit TUI

Press [H] again to close
"""

            let helpLines = helpText.components(separatedBy: .newlines)
            let maxVisibleLines = min(rows - 4, helpLines.count)
            let dialogWidth = min(70, cols - 4)
            let dialogHeight = min(maxVisibleLines + 4, rows - 4)
            let startRow = max(1, (rows - dialogHeight) / 2)
            let startCol = max(1, (cols - dialogWidth) / 2)
            let bottomRow = startRow + dialogHeight

            // Clear the dialog area by erasing lines from startCol onwards
            var clearOutput = ""
            for row in startRow...bottomRow {
                clearOutput += "\u{001B}[\(row);\(startCol)H"
                clearOutput += "\u{001B}[K"  // Clear from cursor to end of line
            }

            // Restore cursor position
            clearOutput += "\u{001B}[u"
            clearOutput += "\u{001B}[?25h"  // Show cursor

            print(clearOutput, terminator: "")
            fflush(stdout)
        }
        #endif
    }

    func showStatusMessage(_ message: String) async {
        // Move cursor to status line area and show message temporarily
        print("\u{001B}[s", terminator: "") // Save cursor position
        print("\u{001B}[10;1H", terminator: "") // Move to status area
        print("\u{001B}[K", terminator: "") // Clear line
        print("Status: \(message)", terminator: "")
        fflush(stdout)

        // Clear after 2 seconds
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        print("\u{001B}[u", terminator: "") // Restore cursor position
        print("\u{001B}[10;1H\u{001B}[K", terminator: "") // Clear the status line
        fflush(stdout)
    }

    func showCenteredDialog(_ message: String) async {
        #if os(macOS) || os(Linux)
        try? await Task.sleep(nanoseconds: 50_000_000)

        var size = winsize()
        let TIOCGWINSZ: UInt = 0x40087468
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 {
            let rows = Int(size.ws_row)
            let cols = Int(size.ws_col)

            let dialogWidth = min(max(message.count + 4, 40), cols - 4)
            let dialogHeight = 3
            let startRow = max(1, (rows - dialogHeight) / 2)
            let startCol = max(1, (cols - dialogWidth) / 2)

            print("\u{001B}[?25l", terminator: "")
            print("\u{001B}[s", terminator: "")
            fflush(stdout)

            let borderTop = String(repeating: "─", count: dialogWidth - 2)
            let borderBottom = String(repeating: "─", count: dialogWidth - 2)
            let messageLine = message.prefix(dialogWidth - 4).padding(toLength: dialogWidth - 4, withPad: " ", startingAt: 0)

            print("\u{001B}[\(startRow);\(startCol)H", terminator: "")
            print("┌\(borderTop)┐", terminator: "")
            print("\u{001B}[\(startRow + 1);\(startCol)H", terminator: "")
            print("│ \(messageLine) │", terminator: "")
            print("\u{001B}[\(startRow + 2);\(startCol)H", terminator: "")
            print("└\(borderBottom)┘", terminator: "")

            fflush(stdout)
        } else {
            print(message)
        }
        #else
        print(message)
        #endif
    }

    func showCenteredStatus(_ message: String, enhancedRenderer: EnhancedTUIRenderer? = nil, lastUpdateStore: LastUpdateStore? = nil) async {
        await showCenteredDialog(message)
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            await clearCenteredDialog(enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
        } catch {
            await clearCenteredDialog(enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
        }
    }

    func showCenteredError(_ message: String, enhancedRenderer: EnhancedTUIRenderer? = nil, lastUpdateStore: LastUpdateStore? = nil) async {
        await showCenteredDialog(message)
        do {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            await clearCenteredDialog(enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
        } catch {
            await clearCenteredDialog(enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
        }
    }

    func executeSwapWithManager(
        swap: SwapEvaluation,
        enhancedRenderer: EnhancedTUIRenderer,
        lastUpdateStore: LastUpdateStore
    ) async {
        await clearCenteredDialog(enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
        await showCenteredStatus("Executing swap: \(swap.fromAsset) -> \(swap.toAsset)...", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)

        Task.detached(priority: .userInitiated) { @Sendable in
            do {
                let config = try SmartVestorConfigurationManager().currentConfig
                let persistence = try createPersistence(config: config)
                let logger = StructuredLogger()

                let exchangeConnectors: [String: ExchangeConnectorProtocol] = [:]
                let executionEngine = ExecutionEngine(
                    config: config,
                    persistence: persistence,
                    exchangeConnectors: exchangeConnectors,
                    swapAnalyzer: nil
                )

                let swapManager = SwapExecutionManager(
                    executionEngine: executionEngine,
                    persistence: persistence,
                    logger: logger,
                    maxRetries: 3
                )

                let dryRun = ProcessInfo.processInfo.environment["SMARTVESTOR_DRY_RUN"] == "true"
                let result = await swapManager.executeSwap(swap, dryRun: dryRun, requireConfirmation: false)

                if result.success {
                    await showCenteredStatus("Swap executed successfully: \(swap.fromAsset) -> \(swap.toAsset)", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                } else {
                    let errorMsg = result.error?.localizedDescription ?? "Unknown error"
                    await showCenteredError("Swap execution failed: \(errorMsg)", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
                }

            } catch {
                await showCenteredError("Swap execution failed: \(error.localizedDescription)", enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
            }
        }
    }

    func clearCenteredDialog(enhancedRenderer: EnhancedTUIRenderer? = nil, lastUpdateStore: LastUpdateStore? = nil) async {
        #if os(macOS) || os(Linux)
        var size = winsize()
        let TIOCGWINSZ: UInt = 0x40087468
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 {
            let rows = Int(size.ws_row)
            let cols = Int(size.ws_col)

            let dialogHeight = 3
            let startRow = max(1, (rows - dialogHeight) / 2)
            let dialogWidth = min(80, cols - 4)
            let startCol = max(1, (cols - dialogWidth) / 2)

            for row in startRow..<(startRow + dialogHeight) {
                print("\u{001B}[\(row);\(startCol)H", terminator: "")
                print("\u{001B}[K", terminator: "")
            }

            print("\u{001B}[u", terminator: "")
            print("\u{001B}[?25h", terminator: "")
            fflush(stdout)
        }
        #endif

        if let renderer = enhancedRenderer, let updateStore = lastUpdateStore {
            if let update = await updateStore.get() {
                await renderer.renderUpdate(update)
            } else {
                await renderer.renderInitialState()
            }
        }
    }

    func refreshDisplay(enhancedRenderer: EnhancedTUIRenderer, commandBarRenderer: CommandBarRenderer, isRunning: Bool, mode: AutomationMode, lastFrame: inout [String]?) async {
        lastFrame = await renderTUI(enhancedRenderer: enhancedRenderer, commandBarRenderer: commandBarRenderer, isRunning: isRunning, mode: mode, lastFrame: lastFrame)
    }

    func updateCommandBar(commandBarRenderer: CommandBarRenderer, highlightedKey: String?, isRunning: Bool) async {
        // Calculate the command bar line position (should be near the bottom)
        // The TUI has approximately 22 lines total
        let commandBarLine = 22

        let newCommandBar = commandBarRenderer.renderDefaultCommands(isRunning: isRunning, highlightedKey: highlightedKey)

        // Move cursor to command bar line and update it
        print("\u{001B}[\(commandBarLine);1H", terminator: "") // Move to command bar line
        print("\u{001B}[K", terminator: "") // Clear line
        print(newCommandBar, terminator: "")
        fflush(stdout)

    // Clear highlight after a delay
    if highlightedKey != nil {
    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second - much more visible
    let normalCommandBar = commandBarRenderer.renderDefaultCommands(isRunning: isRunning)
        print("\u{001B}[\(commandBarLine);1H\u{001B}[K", terminator: "")
            print(normalCommandBar, terminator: "")
            fflush(stdout)
        }
    }

    func renderLatestFrame(
        enhancedRenderer: EnhancedTUIRenderer,
        lastUpdateStore: LastUpdateStore,
        cachedUpdate: TUIUpdate? = nil
    ) async {
        if let update = cachedUpdate {
            await enhancedRenderer.renderUpdate(update)
            return
        }

        if let update = await lastUpdateStore.get() {
            await enhancedRenderer.renderUpdate(update)
        } else {
            await enhancedRenderer.renderInitialState()
        }
    }

    func presentHelpOverlay(
        enhancedRenderer: EnhancedTUIRenderer,
        lastUpdateStore: LastUpdateStore,
        scrollOffset: Int
    ) async {
        await enhancedRenderer.showHelpOverlay(lines: tuiHelpLines, scrollOffset: scrollOffset)
        await renderLatestFrame(enhancedRenderer: enhancedRenderer, lastUpdateStore: lastUpdateStore)
    }

    func dismissHelpOverlay(
        enhancedRenderer: EnhancedTUIRenderer,
        lastUpdateStore: LastUpdateStore
    ) async {
        await enhancedRenderer.hideHelpOverlay()
        // Small delay to ensure state is cleared
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        // Trigger a full re-render so the overlay completely disappears and panels are restored
        if let update = await lastUpdateStore.get() {
            await enhancedRenderer.renderUpdate(update)
        } else {
            await enhancedRenderer.renderInitialState()
        }
    }

    func handleStartCommand(isRunning: inout Bool, mode: AutomationMode) async {
        if isRunning {
            await showStatusMessage("Automation is already running")
            return
        }

        isRunning = true
        await showStatusMessage("Starting automation in \(mode.rawValue) mode...")

        // In a real implementation, this would start the actual automation
        // For now, just simulate starting
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
        await showStatusMessage("Automation started successfully")
    }

    func handlePauseCommand(isRunning: inout Bool, mode: AutomationMode) async {
        if !isRunning {
            await showStatusMessage("Automation is not running")
            return
        }

        isRunning = false
        await showStatusMessage("Pausing automation...")

        // In a real implementation, this would pause the actual automation
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second delay
        await showStatusMessage("Automation paused")
    }

    func handleResumeCommand(isRunning: inout Bool, mode: AutomationMode) async {
        if isRunning {
            await showStatusMessage("Automation is already running")
            return
        }

        isRunning = true
        await showStatusMessage("Resuming automation...")

        // In a real implementation, this would resume the actual automation
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second delay
        await showStatusMessage("Automation resumed")
    }
}

struct PricesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prices",
        abstract: "Fetch current prices for cryptocurrency symbols"
    )

    @Argument(help: "Symbols to fetch prices for (e.g., BTC ETH). If omitted, shows all Robinhood coins.")
    var symbols: [String] = []

    private func findProjectRoot() -> String? {
        let fileManager = FileManager.default
        var currentPath = fileManager.currentDirectoryPath

        while !currentPath.isEmpty && currentPath != "/" {
            let packageSwiftPath = (currentPath as NSString).appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageSwiftPath) {
                return currentPath
            }
            currentPath = (currentPath as NSString).deletingLastPathComponent
        }

        return fileManager.currentDirectoryPath
    }

    func run() async throws {
        let logger = StructuredLogger()

        var apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"]
        var privateKeyBase64 = ProcessInfo.processInfo.environment["ROBINHOOD_PRIVATE_KEY"]

        if apiKey == nil || privateKeyBase64 == nil {
            let projectRoot = findProjectRoot() ?? FileManager.default.currentDirectoryPath
            let envPaths = [
                (projectRoot as NSString).appendingPathComponent(".env"),
                (projectRoot as NSString).appendingPathComponent("config/production.env")
            ]
            for envPath in envPaths {
                if let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) {
                    for line in envContent.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

                        let parts = trimmed.components(separatedBy: "=")
                        if parts.count >= 2 {
                            let key = parts[0].trimmingCharacters(in: .whitespaces)
                            let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)

                            if key == "ROBINHOOD_API_KEY" && apiKey == nil {
                                apiKey = value
                                setenv("ROBINHOOD_API_KEY", value, 1)
                            } else if key == "ROBINHOOD_PRIVATE_KEY" && privateKeyBase64 == nil {
                                privateKeyBase64 = value
                                setenv("ROBINHOOD_PRIVATE_KEY", value, 1)
                            }
                        }
                    }
                    if apiKey != nil && privateKeyBase64 != nil {
                        break
                    }
                }
            }
        }

        let provider = MultiProviderMarketDataProvider(logger: logger)

        let symbolsToFetch: [String]
        if symbols.isEmpty {
            let robinhoodCoins = await getAllRobinhoodCoins(logger: logger)
            if robinhoodCoins.isEmpty {
                print("Error: Could not fetch Robinhood coins list from API.")
                print("   Please ensure ROBINHOOD_API_KEY is set correctly.")
                print("   You can also specify coins manually: sv prices BTC ETH SOL")
                return
            }
            symbolsToFetch = robinhoodCoins
        } else {
            symbolsToFetch = symbols
        }

        print("Fetching prices for: \(symbolsToFetch.joined(separator: ", "))")
        print("")

        do {
            let prices = try await provider.getCurrentPrices(symbols: symbolsToFetch)

            if prices.isEmpty {
                print("No prices found")
                return
            }

            print("Prices:")
            print(String(repeating: "-", count: 50))

            for symbol in symbolsToFetch.sorted() {
                if let price = prices[symbol] {
                    print(String(format: "\(symbol): $%.6f", price))
                } else {
                    print("\(symbol): Not found")
                }
            }

            print("")
            print("Total symbols requested: \(symbolsToFetch.count)")
            print("Prices found: \(prices.count)")
        } catch {
            print("Error fetching prices: \(error.localizedDescription)")
            throw error
        }
    }

    private func getAllRobinhoodCoins(logger: StructuredLogger) async -> [String] {
        do {
            let apiSymbols = try await RobinhoodInstrumentsAPI.shared.fetchSupportedSymbols(logger: logger, forceRefresh: true)
            logger.info(component: "PricesCommand", event: "robinhood_symbols_fetched", data: ["count": String(apiSymbols.count)])

            if apiSymbols.isEmpty {
                logger.warn(component: "PricesCommand", event: "api_returned_empty", data: [
                    "message": "API returned empty list, using fallback symbols"
                ])
                return getFallbackRobinhoodCoins()
            }

            return apiSymbols
        } catch {
            logger.warn(component: "PricesCommand", event: "robinhood_api_failed", data: [
                "error": error.localizedDescription,
                "message": "Robinhood instruments API endpoint may not be available. Using fallback approach."
            ])
            print("Warning: Robinhood instruments API endpoint appears unavailable.")
            print("   Error: \(error.localizedDescription)")
            print("   Using fallback list of known Robinhood-supported coins.")
            print("")
            return getFallbackRobinhoodCoins()
        }
    }

    private func getFallbackRobinhoodCoins() -> [String] {
        return [
            "AAVE", "ADA", "ARB", "ASTER", "AVAX", "BCH", "BNB", "BONK",
            "BTC", "COMP", "CRV", "DOGE", "ETC", "ETH", "FLOKI", "HBAR",
            "HYPE", "LINK", "LTC", "MEW", "MOODENG", "ONDO", "OP", "PENGU",
            "PEPE", "PNUT", "POPCAT", "SHIB", "SOL", "SUI", "TON", "TRUMP",
            "UNI", "USDC", "XLM", "XPL", "XRP", "XTZ", "WLFI", "WIF",
            "VIRTUAL", "ZORA", "DOT", "MATIC", "BAT", "LRC", "YFI",
            "SUSHI", "MKR", "SNX", "1INCH", "BSV", "ALGO", "ATOM", "NEAR",
            "FTM", "ICP", "GRT", "FIL", "MANA", "SAND", "AXS", "ENJ"
        ]
    }
}

struct ListCoinsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-coins",
        abstract: "List all tradable coins on Robinhood"
    )

    @Flag(name: .shortAndLong, help: "Force refresh from API (bypass cache)")
    var refresh: Bool = false

    func run() async throws {
        let logger = StructuredLogger(enabled: true)

        let coins = try await getAllRobinhoodCoins(logger: logger, forceRefresh: refresh)

        if coins.isEmpty {
            print("No coins found.")
            return
        }

        print("Robinhood Tradable Coins (\(coins.count)):")
        print(String(repeating: "-", count: 50))

        for coin in coins.sorted() {
            print(coin)
        }

        print("")
        print("Total: \(coins.count) coins")
    }

    private func getAllRobinhoodCoins(logger: StructuredLogger, forceRefresh: Bool) async throws -> [String] {
        let apiSymbols = try await RobinhoodInstrumentsAPI.shared.fetchSupportedSymbols(logger: logger, forceRefresh: forceRefresh)
        logger.info(component: "ListCoinsCommand", event: "robinhood_symbols_fetched", data: ["count": String(apiSymbols.count)])
        return apiSymbols
    }
}

struct PredictCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "predict",
        abstract: "Get MLX-powered price prediction for a cryptocurrency"
    )

    @Argument(help: "Coin symbol (e.g., BTC, ETH, SOL)")
    var symbol: String

    @Option(name: .shortAndLong, help: "Time horizon in seconds (default: 3600 = 1 hour)")
    var timeHorizon: TimeInterval = 3600

    @Flag(name: .long, help: "Show detailed prediction breakdown")
    var detailed: Bool = false

    func run() async throws {
        let logger = StructuredLogger(enabled: true)

        print("Initializing MLX prediction engine...")

        #if canImport(MLPatternEngineMLX) && os(macOS)
        MLXInitialization.configureMLX()
        setupMLXEnvironment()

        do {
            try MLXAdapter.ensureInitialized()
        } catch {
            print("Warning: MLX initialization failed: \(error.localizedDescription)")
            print("Attempting to continue with fallback...")
        }
        #endif

        let factory = MLPatternEngineFactory(logger: logger, useMLXModels: true)
        let mlEngine = try await factory.createMLPatternEngine()

        try await mlEngine.start()

        let symbolWithUSD = symbol.uppercased().hasSuffix("-USD") ? symbol.uppercased() : "\(symbol.uppercased())-USD"

        print("Fetching prediction for \(symbolWithUSD)...")
        print("Time horizon: \(Int(timeHorizon)) seconds (\(Int(timeHorizon / 3600)) hours)")
        print("")

        var prediction: PredictionResponse?
        var lastError: Error?

        do {
            prediction = try await mlEngine.getPrediction(
                for: symbolWithUSD,
                timeHorizon: timeHorizon,
                modelType: .pricePrediction
            )
        } catch {
            lastError = error
        }

        guard let pred = prediction else {
            if let error = lastError {
                print("Error getting prediction: \(error.localizedDescription)")
            } else {
                print("Error: Prediction is nil")
            }
            return
        }

        print("Prediction Results:")
        print(String(repeating: "=", count: 60))
        print("Symbol: \(symbolWithUSD)")

        let predictedPrice = pred.prediction
        print("Predicted Price: $\(String(format: "%.6f", predictedPrice))")

        let confidence = pred.confidence
        print("Confidence: \(String(format: "%.2f", confidence * 100))%")

        let uncertainty = pred.uncertainty
        print("Uncertainty: \(String(format: "%.2f", uncertainty * 100))%")

        let modelVersion = pred.modelVersion
        print("Model Version: \(modelVersion)")

        let timestamp = pred.timestamp
        let formatter = ISO8601DateFormatter()
        let timestampStr = formatter.string(from: timestamp)
        print("Timestamp: \(timestampStr)")

        if detailed {
            print("")
            print("Detailed Breakdown:")
            print(String(repeating: "-", count: 60))

            let volatilityPrediction = try? await mlEngine.getPrediction(
                for: symbolWithUSD,
                timeHorizon: timeHorizon,
                modelType: .volatilityPrediction
            )

            if let volPred = volatilityPrediction {
                print("Volatility Prediction: \(String(format: "%.4f", volPred.prediction))")
                print("Volatility Confidence: \(String(format: "%.2f", volPred.confidence * 100))%")
            }

            let patterns = try? await mlEngine.detectPatterns(for: symbolWithUSD)
            if let patterns = patterns, !patterns.isEmpty {
                print("")
                print("Detected Patterns: \(patterns.count)")
                for pattern in patterns.prefix(5) {
                    print("  - \(pattern.patternType.rawValue): \(String(format: "%.2f", pattern.confidence * 100))% confidence")
                }
            }

            let trend = try? await mlEngine.classifyTrend(for: symbolWithUSD)
            if let trend = trend {
                print("")
                print("Trend Classification:")
                print("  Type: \(trend.trendType.rawValue)")
                print("  Strength: \(String(format: "%.2f", trend.strength * 100))%")
                print("  Confidence: \(String(format: "%.2f", trend.confidence * 100))%")
            }
        }

        print("")
        print(String(repeating: "=", count: 60))
    }
}

struct TrainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "train",
        abstract: "Train MLX price prediction model with historical data"
    )

    @Argument(help: "Coin symbol to train on (e.g., BTC, ETH, SOL). Default: BTC")
    var symbol: String = "BTC"

    @Option(name: .shortAndLong, help: "Number of training epochs (default: 1000)")
    var epochs: Int = 1000

    @Option(name: .shortAndLong, help: "Learning rate (default: 0.001)")
    var learningRate: Float = 0.001

    @Option(name: .shortAndLong, help: "Days of historical data to use (default: 90)")
    var days: Int = 90

    @Option(name: .long, help: "Maximum number of training samples (default: unlimited)")
    var maxSamples: Int?

    @Flag(name: .long, help: "Enable data augmentation")
    var dataAugmentation: Bool = false

    @Flag(name: .long, help: "Enable adversarial training")
    var adversarialTraining: Bool = false

    @Option(name: .long, help: "Validation split ratio (default: 0.2)")
    var validationSplit: Double = 0.2

    func run() async throws {
        let logger = StructuredLogger(enabled: true)

        print("Initializing MLX training environment...")

        #if canImport(MLPatternEngineMLX) && os(macOS)
        MLXInitialization.configureMLX()
        setupMLXEnvironment()

        do {
            try MLXAdapter.ensureInitialized()
        } catch {
            print("Error: MLX initialization failed: \(error.localizedDescription)")
            print("Make sure MLX metallib is available. Run: ./scripts/build-mlx-metallib.sh")
            return
        }
        #else
        print("Error: MLX not available on this platform")
        return
        #endif

        let symbolWithUSD = symbol.uppercased().hasSuffix("-USD") ? symbol.uppercased() : "\(symbol.uppercased())-USD"

        print("")
        print("Training Configuration:")
        print(String(repeating: "=", count: 60))
        print("Symbol: \(symbolWithUSD)")
        print("Epochs: \(epochs)")
        print("Learning Rate: \(learningRate)")
        print("Historical Days: \(days)")
        if let maxSamples = maxSamples {
            print("Max Samples: \(maxSamples)")
        }
        print("Data Augmentation: \(dataAugmentation ? "Enabled" : "Disabled")")
        print("Adversarial Training: \(adversarialTraining ? "Enabled" : "Disabled")")
        print("Validation Split: \(String(format: "%.1f", validationSplit * 100))%")
        print("")

        let database = try SQLiteTimeSeriesDatabase(logger: logger)
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else {
            print("Error: Failed to calculate start date")
            return
        }

        print("Loading historical data from database...")
        let historicalData = try await database.getMarketData(symbol: symbolWithUSD, from: startDate, to: endDate)

        if historicalData.count < 100 {
            print("Error: Insufficient training data. Found \(historicalData.count) data points, need at least 100.")
            print("Try fetching more data or reducing the --days parameter.")
            return
        }

        print("Found \(historicalData.count) data points")
        print("")

        let featureExtractor = FeatureExtractor(
            technicalIndicators: TechnicalIndicators(),
            logger: logger
        )

        print("Extracting features from historical data...")
        var trainingInputs: [[Double]] = []
        var trainingTargets: [[Double]] = []

        let windowSize = 10
        for i in windowSize..<historicalData.count {
            let window = Array(historicalData[i-windowSize..<i])
            let features = try await featureExtractor.extractFeatures(from: window)
            if let latestFeatures = features.last {
                let featureVector = convertFeaturesToTrainingVector(latestFeatures.features)
                let targetPrice = historicalData[i].close
                trainingInputs.append(featureVector)
                trainingTargets.append([targetPrice])
            }
        }

        if trainingInputs.isEmpty {
            print("Error: Failed to extract features from data")
            return
        }

        let totalSamples = trainingInputs.count
        let samplesToUse = maxSamples.map { min($0, totalSamples) } ?? totalSamples

        if samplesToUse < totalSamples {
            print("Limiting training to \(samplesToUse) samples (from \(totalSamples) available)")
            trainingInputs = Array(trainingInputs.prefix(samplesToUse))
            trainingTargets = Array(trainingTargets.prefix(samplesToUse))
        }

        print("Prepared \(trainingInputs.count) training samples")
        print("Feature vector size: \(trainingInputs.first?.count ?? 0)")
        print("")
        print("Starting model training...")
        print(String(repeating: "-", count: 60))

        do {
            let priceModel = try MLXPricePredictionModel(logger: logger, useMixedPrecision: false)
            priceModel.compile()

            let result = try await priceModel.train(
                inputs: trainingInputs,
                targets: trainingTargets,
                epochs: epochs,
                learningRate: learningRate,
                validationSplit: validationSplit,
                enableDataAugmentation: dataAugmentation,
                enableAdversarialTraining: adversarialTraining
            )

            let factory = MLPatternEngineFactory(logger: logger, useMLXModels: true)
            let mlEngine = try await factory.createMLPatternEngine()

            if let mlxEngine = try? MLXPredictionEngine(logger: logger) {
                try mlxEngine.saveModelForCoin(symbol: symbol, model: priceModel, trainingResult: result)
                print("✓ Model saved for \(symbol)")

                try await mlxEngine.reloadModelForCoin(symbol: symbol)
                print("✓ Model reloaded into memory")
            }

            print("")
            print(String(repeating: "=", count: 60))
            print("Training Completed Successfully!")
            print(String(repeating: "=", count: 60))
            print("Final Training Loss: \(String(format: "%.6f", result.finalLoss))")
            if let valLoss = result.validationLoss {
                print("Final Validation Loss: \(String(format: "%.6f", valLoss))")
            }
            print("Best Validation Loss: \(String(format: "%.6f", result.bestLoss))")
            print("Training Epochs: \(result.epochs)")
            if let bestEpoch = result.bestEpoch {
                print("Best Epoch: \(bestEpoch)")
            }
            print("Learning Rate: \(String(format: "%.6f", result.learningRate))")
            print("")
            print("Model saved and ready for predictions!")
            print("This model is specific to \(symbol) and will be used for predictions.")
            print("Use 'sv predict \(symbol)' to test the trained model.")
        } catch {
            print("")
            print("Error during training: \(error.localizedDescription)")
            if let mlxError = error as? MLPatternEngineMLX.MLXError {
                print("MLX Error details: \(mlxError)")
            }
            throw error
        }
    }

    private func convertFeaturesToTrainingVector(_ features: [String: Double]) -> [Double] {
        let featureOrder = ["price", "volume", "high", "low", "open", "close",
                           "rsi", "macd", "macd_signal", "volatility"]
        return featureOrder.map { key in
            if key == "close" && features[key] == nil {
                return features["price"] ?? 0.0
            }
            return features[key] ?? 0.0
        }
    }
}

struct RankCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rank",
        abstract: "Fetch Robinhood coins, train models, and rank by predicted profitability"
    )

    @Flag(name: .long, help: "Train models before ranking (default: use existing models)")
    var train: Bool = false

    @Option(name: .shortAndLong, help: "Number of top coins to show (default: 10)")
    var limit: Int = 10

    @Option(name: .shortAndLong, help: "Training epochs if --train is used (default: 500)")
    var epochs: Int = 500

    @Option(name: .shortAndLong, help: "Days of historical data for training (default: 90)")
    var days: Int = 90

    @Option(name: .long, help: "Time horizon for predictions in hours (default: 24)")
    var horizon: Int = 24

    @Flag(name: .long, help: "Show detailed profitability breakdown")
    var detailed: Bool = false

    func run() async throws {
        let logger = StructuredLogger(enabled: true)

        print("Fetching Robinhood-supported coins...")

        let symbols: [String]
        do {
            symbols = try await RobinhoodInstrumentsAPI.shared.fetchSupportedSymbols(logger: logger, forceRefresh: true)
            print("Found \(symbols.count) coins on Robinhood")
        } catch {
            print("Warning: Could not fetch from Robinhood API: \(error.localizedDescription)")
            print("Using fallback list...")
            symbols = [
                "AAVE", "ADA", "ARB", "ASTER", "AVAX", "BCH", "BNB", "BONK",
                "BTC", "COMP", "CRV", "DOGE", "ETC", "ETH", "FLOKI", "HBAR",
                "HYPE", "LINK", "LTC", "MEW", "MOODENG", "ONDO", "OP", "PENGU",
                "PEPE", "PNUT", "POPCAT", "SHIB", "SOL", "SUI", "TON", "TRUMP",
                "UNI", "USDC", "XLM", "XPL", "XRP", "XTZ", "WLFI", "WIF",
                "VIRTUAL", "ZORA"
            ]
            print("Using \(symbols.count) fallback coins")
        }

        print("")

        #if canImport(MLPatternEngineMLX) && os(macOS)
        MLXInitialization.configureMLX()
        setupMLXEnvironment()

        do {
            try MLXAdapter.ensureInitialized()
        } catch {
            print("Error: MLX initialization failed: \(error.localizedDescription)")
            return
        }
        #else
        print("Error: MLX not available on this platform")
        return
        #endif

        let factory = MLPatternEngineFactory(logger: logger, useMLXModels: true)
        let mlEngine = try await factory.createMLPatternEngine()
        try await mlEngine.start()

        if train {
            print("Training models on Robinhood coins...")
            print(String(repeating: "=", count: 60))

            let database = try SQLiteTimeSeriesDatabase(logger: logger)
            let endDate = Date()
            guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else {
                print("Error: Failed to calculate start date")
                return
            }

            let featureExtractor = FeatureExtractor(
                technicalIndicators: TechnicalIndicators(),
                logger: logger
            )

            var trainedCount = 0
            var skippedCount = 0

            for symbol in symbols.prefix(10) {
                let symbolWithUSD = "\(symbol)-USD"
                print("Training \(symbolWithUSD)...", terminator: " ")

                do {
                    let historicalData = try await database.getMarketData(symbol: symbolWithUSD, from: startDate, to: endDate)

                    if historicalData.count < 100 {
                        print("Skipped (insufficient data: \(historicalData.count) points)")
                        skippedCount += 1
                        continue
                    }

                    var trainingInputs: [[Double]] = []
                    var trainingTargets: [[Double]] = []

                    let windowSize = 10
                    for i in windowSize..<historicalData.count {
                        let window = Array(historicalData[i-windowSize..<i])
                        let features = try await featureExtractor.extractFeatures(from: window)
                        if let latestFeatures = features.last {
                            let featureVector = convertFeaturesToTrainingVector(latestFeatures.features)
                            let targetPrice = historicalData[i].close
                            trainingInputs.append(featureVector)
                            trainingTargets.append([targetPrice])
                        }
                    }

                    if trainingInputs.count > 50 {
                        let priceModel = try MLXPricePredictionModel(logger: logger, useMixedPrecision: false)
                        priceModel.compile()

                        let samplesToUse = min(1000, trainingInputs.count)
                        let trainingBatch = Array(trainingInputs.prefix(samplesToUse))
                        let targetBatch = Array(trainingTargets.prefix(samplesToUse))

                        let result = try await priceModel.train(
                            inputs: trainingBatch,
                            targets: targetBatch,
                            epochs: epochs,
                            learningRate: 0.001,
                            validationSplit: 0.2
                        )

                        if let mlxEngine = try? MLXPredictionEngine(logger: logger) {
                            try? mlxEngine.saveModelForCoin(symbol: symbol, model: priceModel, trainingResult: result)
                        }

                        print("✓ Trained (\(samplesToUse) samples)")
                        trainedCount += 1
                    } else {
                        print("Skipped (insufficient features)")
                        skippedCount += 1
                    }
                } catch {
                    print("Failed: \(error.localizedDescription)")
                    skippedCount += 1
                }
            }

            print("")
            print("Training Summary: \(trainedCount) trained, \(skippedCount) skipped")
            print("")
        }

        print("Predicting profitability for all coins...")
        print(String(repeating: "=", count: 60))

        struct CoinProfitability {
            let symbol: String
            let currentPrice: Double
            let predictedPrice: Double
            let expectedReturn: Double
            let confidence: Double
            let riskLevel: String
        }

        var profitabilityResults: [CoinProfitability] = []
        let timeHorizon = TimeInterval(horizon * 3600)

        for symbol in symbols {
            let symbolWithUSD = "\(symbol)-USD"

            do {
                let latestData = try await mlEngine.getLatestData(symbols: [symbolWithUSD])
                guard let currentData = latestData.first else {
                    continue
                }

                let currentPrice = currentData.close

                let pricePrediction = try await mlEngine.getPrediction(
                    for: symbolWithUSD,
                    timeHorizon: timeHorizon,
                    modelType: .pricePrediction
                )

                guard pricePrediction.prediction.isFinite && !pricePrediction.prediction.isNaN,
                      currentPrice > 0 else {
                    continue
                }

                let predictedPrice = pricePrediction.prediction
                let expectedReturn = (predictedPrice - currentPrice) / currentPrice
                let confidence = pricePrediction.confidence

                let riskLevel: String
                if expectedReturn > 0.05 && confidence > 0.7 {
                    riskLevel = "Low"
                } else if expectedReturn > 0.02 && confidence > 0.5 {
                    riskLevel = "Medium"
                } else {
                    riskLevel = "High"
                }

                profitabilityResults.append(CoinProfitability(
                    symbol: symbol,
                    currentPrice: currentPrice,
                    predictedPrice: predictedPrice,
                    expectedReturn: expectedReturn,
                    confidence: confidence,
                    riskLevel: riskLevel
                ))
            } catch {
                continue
            }
        }

        profitabilityResults.sort { $0.expectedReturn > $1.expectedReturn }

        print("")
        print("Top \(min(limit, profitabilityResults.count)) Most Profitable Coins:")
        print(String(repeating: "=", count: 80))
        print(String(format: "%-8s %12s %12s %10s %10s %8s", "Symbol", "Current", "Predicted", "Return %", "Confidence", "Risk"))
        print(String(repeating: "-", count: 80))

        for (index, result) in profitabilityResults.prefix(limit).enumerated() {
            let rank = index + 1
            let returnPercent = result.expectedReturn * 100
            let confidencePercent = result.confidence * 100

            print(String(format: "%-2d. %-6s $%10.6f $%10.6f %8.2f%% %8.2f%% %8s",
                        rank,
                        result.symbol,
                        result.currentPrice,
                        result.predictedPrice,
                        returnPercent,
                        confidencePercent,
                        result.riskLevel))

            if detailed {
                let priceChange = result.predictedPrice - result.currentPrice
                print("      Expected gain: $\(String(format: "%.6f", priceChange))")
                print("      Risk-adjusted return: \(String(format: "%.2f", returnPercent * result.confidence))%")
                print("")
            }
        }

        print("")
        print("Summary:")
        print("  Total coins analyzed: \(profitabilityResults.count)")
        print("  Average expected return: \(String(format: "%.2f", profitabilityResults.map { $0.expectedReturn }.reduce(0, +) / Double(profitabilityResults.count) * 100))%")
        print("  Time horizon: \(horizon) hours")
        print("")
        print("Use 'sv predict <SYMBOL>' for detailed prediction on a specific coin.")
    }

    private func convertFeaturesToTrainingVector(_ features: [String: Double]) -> [Double] {
        let featureOrder = ["price", "volume", "high", "low", "open", "close",
                           "rsi", "macd", "macd_signal", "volatility"]
        return featureOrder.map { key in
            if key == "close" && features[key] == nil {
                return features["price"] ?? 0.0
            }
            return features[key] ?? 0.0
        }
    }
}

struct ModelsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "List and manage trained models per coin"
    )

    @Flag(name: .long, help: "Show detailed model information")
    var detailed: Bool = false

    @Option(name: .shortAndLong, help: "Filter by coin symbol")
    var symbol: String?

    func run() async throws {
        let logger = StructuredLogger(enabled: true)

        let defaultPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent(".mercatus/models")
        let registry = ModelRegistry(registryPath: defaultPath, logger: logger)

        print("Trained Models:")
        print(String(repeating: "=", count: 80))

        let registryFile = (defaultPath as NSString).appendingPathComponent("registry.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: registryFile)),
              let versions = try? JSONDecoder().decode([String: [ModelVersion]].self, from: data) else {
            print("No models found. Train models using: sv train <SYMBOL>")
            return
        }

        var allModels: [(String, ModelVersion)] = []
        for (modelId, modelVersions) in versions {
            if let latest = modelVersions.sorted(by: { $0.createdAt > $1.createdAt }).first {
                allModels.append((modelId, latest))
            }
        }

        allModels.sort { $0.0 < $1.0 }

        if let symbolFilter = symbol?.lowercased() {
            allModels = allModels.filter { $0.0.contains(symbolFilter) }
        }

        if allModels.isEmpty {
            print("No models found\(symbol != nil ? " for \(symbol!)" : "").")
            print("Train models using: sv train <SYMBOL>")
            return
        }

        print(String(format: "%-20s %12s %20s %10s", "Coin", "Version", "Created", "Loss"))
        print(String(repeating: "-", count: 80))

        for (modelId, version) in allModels {
            let coinSymbol = modelId.replacingOccurrences(of: "_price_prediction", with: "").uppercased()
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            let createdStr = dateFormatter.string(from: version.createdAt)

            let loss = version.metadata["finalLoss"] ?? "N/A"

            print(String(format: "%-20s %12s %20s %10s",
                        coinSymbol,
                        version.version,
                        createdStr,
                        loss))

            if detailed {
                if let epochs = version.metadata["trainingEpochs"] {
                    print("  Epochs: \(epochs)")
                }
                if let valLoss = version.metadata["validationLoss"], !valLoss.isEmpty {
                    print("  Validation Loss: \(valLoss)")
                }
                if let accuracy = version.metadata["accuracy"], !accuracy.isEmpty {
                    print("  Accuracy: \(accuracy)")
                }
                print("  Path: \(version.filePath)")
                print("")
            }
        }

        print("")
        print("Total models: \(allModels.count)")
        print("Use 'sv train <SYMBOL>' to train a new model or update an existing one.")
    }
}

struct UpdateModelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-model",
        abstract: "Update a model at runtime (incremental learning or reload from disk)"
    )

    @Argument(help: "Coin symbol to update (e.g., BTC, ETH)")
    var symbol: String

    @Flag(name: .long, help: "Reload model from disk (use after retraining)")
    var reload: Bool = false

    @Option(name: .long, help: "Path to training data CSV (for incremental update)")
    var dataPath: String?

    @Option(name: .long, help: "Learning rate for incremental update (default: 0.0001)")
    var learningRate: Float = 0.0001

    func run() async throws {
        let logger = StructuredLogger(enabled: true)

        print("Updating model for \(symbol)...")

        #if canImport(MLPatternEngineMLX) && os(macOS)
        MLXInitialization.configureMLX()
        setupMLXEnvironment()

        do {
            try MLXAdapter.ensureInitialized()
        } catch {
            print("Error: MLX initialization failed: \(error.localizedDescription)")
            return
        }
        #else
        print("Error: MLX not available on this platform")
        return
        #endif

        let factory = MLPatternEngineFactory(logger: logger, useMLXModels: true)
        let mlEngine = try await factory.createMLPatternEngine()
        try await mlEngine.start()

        guard let mlxEngine = try? MLXPredictionEngine(logger: logger) else {
            print("Error: Failed to create MLX prediction engine")
            return
        }

        if reload {
            print("Reloading model from disk...")
            try await mlxEngine.reloadModelForCoin(symbol: symbol)
            print("✓ Model reloaded successfully")
            print("")
            print("The model will now use the latest version from disk.")
            print("Use 'sv predict \(symbol)' to test the updated model.")
        } else if let dataPath = dataPath {
            print("Performing incremental update with data from \(dataPath)...")

            guard let data = try? String(contentsOfFile: dataPath),
                  let lines = data.components(separatedBy: "\n").filter({ !$0.isEmpty }).dropFirst() as? [String] else {
                print("Error: Could not read training data from \(dataPath)")
                return
            }

            var batch: [[Double]] = []
            var targets: [[Double]] = []

            for line in lines.prefix(100) {
                let parts = line.components(separatedBy: ",")
                if parts.count >= 19 {
                    let features = parts.prefix(18).compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    let target = parts[18].trimmingCharacters(in: .whitespaces)

                    if features.count == 18, let targetValue = Double(target) {
                        batch.append(features)
                        targets.append([targetValue])
                    }
                }
            }

            if batch.isEmpty {
                print("Error: No valid training data found")
                return
            }

            try await mlxEngine.updateModelForCoin(
                symbol: symbol,
                batch: batch,
                targets: targets,
                learningRate: learningRate
            )

            print("✓ Model updated incrementally with \(batch.count) samples")
            print("")
            print("The model has been updated and saved.")
            print("Use 'sv predict \(symbol)' to test the updated model.")
        } else {
            print("Error: Must specify either --reload or --data-path")
            print("")
            print("Usage:")
            print("  sv update-model BTC --reload                    # Reload from disk")
            print("  sv update-model BTC --data-path data.csv        # Incremental update")
        }
    }
}

struct SwapCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swap",
        abstract: "Evaluate swapping one coin for another"
    )

    @Argument(help: "Source asset symbol (e.g., BTC)")
    var fromAsset: String

    @Argument(help: "Destination asset symbol (e.g., ETH)")
    var toAsset: String

    @Option(name: .shortAndLong, help: "Quantity of source asset to swap")
    var quantity: Double?

    @Option(name: .shortAndLong, help: "Exchange name (default: robinhood)")
    var exchange: String = "robinhood"

    @Option(name: .shortAndLong, help: "Path to configuration file")
    var configPath: String?

    @Flag(name: .long, help: "Execute the swap (requires --production flag or confirmation)")
    var execute: Bool = false

    @Flag(name: .long, help: "Dry run mode (evaluate only, do not execute)")
    var dryRun: Bool = false

    func run() async throws {
        let logger = StructuredLogger()
        let configManager = try SmartVestorConfigurationManager(configPath: configPath)
        let config = configManager.currentConfig

        guard let swapConfig = config.swapAnalysis, swapConfig.enabled else {
            print("Error: Swap analysis is not enabled in configuration")
            return
        }

        var exchangeConnectors: [String: ExchangeConnectorProtocol] = [:]

        var apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"]
        var privateKeyBase64 = ProcessInfo.processInfo.environment["ROBINHOOD_PRIVATE_KEY"]

        if apiKey == nil || privateKeyBase64 == nil {
            let envPath = ".env"
            if let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) {
                for line in envContent.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count >= 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)

                        if key == "ROBINHOOD_API_KEY" && apiKey == nil {
                            apiKey = value
                        } else if key == "ROBINHOOD_PRIVATE_KEY" && privateKeyBase64 == nil {
                            privateKeyBase64 = value
                        }
                    }
                }
            }
        }

        if let apiKey = apiKey, let privateKeyBase64 = privateKeyBase64 {
            let sanitizedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            let sanitizedPrivateKey = privateKeyBase64
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                .filter { !$0.isWhitespace && $0 != "\n" && $0 != "\r" }

            if !sanitizedApiKey.isEmpty && !sanitizedPrivateKey.isEmpty {
                do {
                    let credentials = try RobinhoodConnector.Configuration.Credentials(
                        apiKey: sanitizedApiKey,
                        privateKeyBase64: sanitizedPrivateKey
                    )
                    let robinhoodConnector = RobinhoodConnector(
                        logger: logger,
                        configuration: RobinhoodConnector.Configuration(
                            credentials: credentials
                        )
                    )
                    exchangeConnectors["robinhood"] = robinhoodConnector
                } catch {
                    print("Warning: Failed to initialize Robinhood connector: \(error.localizedDescription)")
                }
            }
        }

        let persistence = try createPersistence()
        try persistence.initialize()

        let crossExchangeAnalyzer = CrossExchangeAnalyzer(
            config: config,
            exchangeConnectors: exchangeConnectors
        )

        let marketDataProvider: MarketDataProviderProtocol? = {
            if let providerConfig = config.marketDataProvider,
               providerConfig.type == "multi" {
                let providerOrder = providerConfig.providerOrder?.compactMap {
                    MultiProviderMarketDataProvider.MarketDataProviderType(rawValue: $0)
                } ?? [.coinGecko, .cryptoCompare, .binance, .coinMarketCap, .coinbase]

                return MultiProviderMarketDataProvider(
                    coinGeckoAPIKey: providerConfig.coinGeckoAPIKey,
                    coinMarketCapAPIKey: providerConfig.coinMarketCapAPIKey,
                    cryptoCompareAPIKey: providerConfig.cryptoCompareAPIKey,
                    binanceAPIKey: providerConfig.binanceAPIKey,
                    binanceSecretKey: providerConfig.binanceSecretKey,
                    coinbaseAPIKey: providerConfig.coinbaseAPIKey,
                    coinbaseSecretKey: providerConfig.coinbaseSecretKey,
                    providerOrder: providerOrder,
                    logger: logger
                )
            }
            return nil
        }()

        let coinScoringEngine: CoinScoringEngineProtocol? = {
            if let provider = marketDataProvider {
                return CoinScoringEngine(
                    config: config,
                    persistence: persistence,
                    marketDataProvider: provider
                )
            }
            return nil
        }()

        let swapAnalyzer = SwapAnalyzer(
            config: config,
            exchangeConnectors: exchangeConnectors,
            crossExchangeAnalyzer: crossExchangeAnalyzer,
            coinScoringEngine: coinScoringEngine,
            persistence: persistence,
            marketDataProvider: marketDataProvider
        )

        var swapQuantity: Double
        if let quantity = quantity {
            swapQuantity = quantity
        } else {
            let holdings = try persistence.getAllAccounts().filter { $0.exchange == exchange }
            if let holding = holdings.first(where: { $0.asset == fromAsset }) {
                swapQuantity = holding.available
                print("Using available balance: \(swapQuantity) \(fromAsset)")
            } else {
                print("Error: No holding found for \(fromAsset) on \(exchange)")
                print("   Please specify quantity: sv swap \(fromAsset) \(toAsset) --quantity 1.0")
                return
            }
        }

        guard swapQuantity > 0 else {
            print("Error: Quantity must be greater than 0")
            return
        }

        print("Evaluating swap: \(swapQuantity) \(fromAsset) → \(toAsset) on \(exchange)")
        print("")

        do {
            let evaluation = try await swapAnalyzer.evaluateSwap(
                fromAsset: fromAsset,
                toAsset: toAsset,
                quantity: swapQuantity,
                exchange: exchange
            )

            print("Swap Evaluation Results:")
            print(String(repeating: "=", count: 60))
            print("")

            print("Costs:")
            print("  Sell Fee:      $\(String(format: "%.4f", evaluation.totalCost.sellFee))")
            print("  Buy Fee:       $\(String(format: "%.4f", evaluation.totalCost.buyFee))")
            print("  Sell Spread:   $\(String(format: "%.4f", evaluation.totalCost.sellSpread))")
            print("  Buy Spread:    $\(String(format: "%.4f", evaluation.totalCost.buySpread))")
            print("  Sell Slippage: $\(String(format: "%.4f", evaluation.totalCost.sellSlippage))")
            print("  Buy Slippage:  $\(String(format: "%.4f", evaluation.totalCost.buySlippage))")
            print("  Total Cost:    $\(String(format: "%.4f", evaluation.totalCost.totalCostUSD)) (\(String(format: "%.2f", evaluation.totalCost.costPercentage))%)")
            print("")

            print("Benefits:")
            print("  Return Differential: \(String(format: "%.2f", evaluation.potentialBenefit.expectedReturnDifferential * 100))%")
            print("  Portfolio Improvement: \(String(format: "%.2f", evaluation.potentialBenefit.portfolioImprovement * 100))%")
            if let riskReduction = evaluation.potentialBenefit.riskReduction {
                print("  Risk Reduction: \(String(format: "%.2f", riskReduction * 100))%")
            }
            print("  Allocation Alignment: \(String(format: "%.2f", evaluation.potentialBenefit.allocationAlignment * 100))%")
            print("  Total Benefit: $\(String(format: "%.4f", evaluation.potentialBenefit.totalBenefitUSD)) (\(String(format: "%.2f", evaluation.potentialBenefit.benefitPercentage * 100))%)")
            print("")

            print("Summary:")
            print("  Net Value:     $\(String(format: "%.4f", evaluation.netValue))")
            print("  Confidence:    \(String(format: "%.1f", evaluation.confidence * 100))%")
            print("  Worthwhile:    \(evaluation.isWorthwhile ? "YES" : "NO")")
            print("")

            if swapAnalyzer.shouldExecuteSwap(evaluation) {
                print("This swap meets all execution criteria and is recommended.")
            } else {
                print("Warning: This swap does not meet execution criteria.")
                if evaluation.netValue < swapConfig.minProfitThreshold {
                    print("   - Net value ($\(String(format: "%.2f", evaluation.netValue))) below minimum ($\(String(format: "%.2f", swapConfig.minProfitThreshold)))")
                }
                if evaluation.potentialBenefit.benefitPercentage < swapConfig.minProfitPercentage {
                    print("   - Benefit percentage (\(String(format: "%.2f", evaluation.potentialBenefit.benefitPercentage * 100))%) below minimum (\(String(format: "%.2f", swapConfig.minProfitPercentage * 100))%)")
                }
                if evaluation.totalCost.costPercentage > swapConfig.maxCostPercentage {
                    print("   - Cost percentage (\(String(format: "%.2f", evaluation.totalCost.costPercentage))%) exceeds maximum (\(String(format: "%.2f", swapConfig.maxCostPercentage * 100))%)")
                }
                if evaluation.confidence < swapConfig.minConfidence {
                    print("   - Confidence (\(String(format: "%.1f", evaluation.confidence * 100))%) below minimum (\(String(format: "%.1f", swapConfig.minConfidence * 100))%)")
                }
            }

            if execute {
                guard exchangeConnectors[exchange] != nil else {
                    print("Error: No connector available for exchange: \(exchange)")
                    return
                }

                let isDryRun = dryRun || !swapAnalyzer.shouldExecuteSwap(evaluation)

                if isDryRun && !dryRun {
                    print("")
                    print("Warning: Swap does not meet execution criteria. Running in dry-run mode.")
                } else if dryRun {
                    print("")
                    print("Running in dry-run mode (no trades will be executed)")
                } else {
                    print("")
                    print("EXECUTING REAL TRADE - This will place actual orders!")

                    let prompter = SafetyPrompter(logger: logger)
                    guard prompter.confirmProductionMode(config: config) else {
                        print("Swap execution cancelled by user")
                        return
                    }
                }

                print("")
                print("Executing swap:")
                print("  1. Selling \(String(format: "%.6f", evaluation.fromQuantity)) \(evaluation.fromAsset)")
                print("  2. Buying ~\(String(format: "%.6f", evaluation.estimatedToQuantity)) \(evaluation.toAsset)")
                print("")

                do {
                    if exchange.lowercased() == "robinhood", let connector = exchangeConnectors["robinhood"] {
                        print("Placing sell order...")

                        if isDryRun {
                            let mockPrice = Double.random(in: evaluation.totalCost.totalCostUSD / evaluation.fromQuantity * 0.95...evaluation.totalCost.totalCostUSD / evaluation.fromQuantity * 1.05)
                            print("[DRY RUN] Sell order simulated: \(String(format: "%.6f", evaluation.fromQuantity)) \(evaluation.fromAsset) @ $\(String(format: "%.2f", mockPrice))")
                        } else {
                            let symbol = "\(evaluation.fromAsset)-USD"
                            let sellOrder = try await connector.placeOrder(
                                symbol: symbol,
                                side: .sell,
                                type: .market,
                                quantity: evaluation.fromQuantity,
                                price: 0
                            )
                            print("Sell order placed: \(String(format: "%.6f", evaluation.fromQuantity)) \(evaluation.fromAsset)")
                            print("   Order ID: \(sellOrder.id)")

                            let sellTx = InvestmentTransaction(
                                type: .sell,
                                exchange: exchange,
                                asset: evaluation.fromAsset,
                                quantity: evaluation.fromQuantity,
                                price: 0,
                                fee: evaluation.totalCost.sellFee,
                                metadata: [
                                    "order_id": sellOrder.id,
                                    "order_type": "market",
                                    "side": "sell",
                                    "swap_id": evaluation.id.uuidString
                                ]
                            )
                            try persistence.saveTransaction(sellTx)

                            try? await Task.sleep(nanoseconds: 200_000_000)
                        }

                        print("Placing buy order...")

                        if isDryRun {
                            let mockPrice = Double.random(in: 100...1000)
                            print("[DRY RUN] Buy order simulated: \(String(format: "%.6f", evaluation.estimatedToQuantity)) \(evaluation.toAsset) @ $\(String(format: "%.2f", mockPrice))")
                            print("")
                            print("[DRY RUN] Swap execution completed successfully")
                        } else {
                            let symbol = "\(evaluation.toAsset)-USD"
                            let buyOrder = try await connector.placeOrder(
                                symbol: symbol,
                                side: .buy,
                                type: .market,
                                quantity: evaluation.estimatedToQuantity,
                                price: 0
                            )
                            print("Buy order placed: \(String(format: "%.6f", evaluation.estimatedToQuantity)) \(evaluation.toAsset)")
                            print("   Order ID: \(buyOrder.id)")

                            let buyTx = InvestmentTransaction(
                                type: .buy,
                                exchange: exchange,
                                asset: evaluation.toAsset,
                                quantity: evaluation.estimatedToQuantity,
                                price: 0,
                                fee: evaluation.totalCost.buyFee,
                                metadata: [
                                    "order_id": buyOrder.id,
                                    "order_type": "market",
                                    "side": "buy",
                                    "swap_id": evaluation.id.uuidString
                                ]
                            )
                            try persistence.saveTransaction(buyTx)

                            print("")
                            print("Swap execution completed successfully")
                            print("   Transactions saved to database")
                        }
                    } else {
                        print("Error: Swap execution currently only supported for Robinhood exchange")
                    }
                } catch {
                    print("Error executing swap: \(error.localizedDescription)")
                }
            }

        } catch {
            print("Error evaluating swap: \(error.localizedDescription)")
        }
    }
}

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Refresh live balances from broker(s) and persist them"
    )

    @Flag(name: .shortAndLong, help: "Verbose logs")
    var verbose: Bool = false

    func run() async throws {
        let logger = StructuredLogger()

        var exchangeConnectors: [String: ExchangeConnectorProtocol] = [:]

        var apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"]
        var privateKeyBase64 = ProcessInfo.processInfo.environment["ROBINHOOD_PRIVATE_KEY"]

        if apiKey == nil || privateKeyBase64 == nil {
            let envPath = ".env"
            if let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) {
                for line in envContent.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count >= 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)

                        if key == "ROBINHOOD_API_KEY" && apiKey == nil {
                            apiKey = value
                        } else if key == "ROBINHOOD_PRIVATE_KEY" && privateKeyBase64 == nil {
                            privateKeyBase64 = value
                        }
                    }
                }
            }
        }

        if let apiKey = apiKey, let privateKeyBase64 = privateKeyBase64 {
            let sanitizedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            let sanitizedPrivateKey = privateKeyBase64
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                .filter { !$0.isWhitespace && $0 != "\n" && $0 != "\r" }

            if !sanitizedApiKey.isEmpty && !sanitizedPrivateKey.isEmpty {
                // Set environment variables - RobinhoodConnector.getHoldings() checks these
                setenv("ROBINHOOD_API_KEY", sanitizedApiKey, 1)
                setenv("ROBINHOOD_PRIVATE_KEY", sanitizedPrivateKey, 1)

                do {
                    let credentials = try RobinhoodConnector.Configuration.Credentials(
                        apiKey: sanitizedApiKey,
                        privateKeyBase64: sanitizedPrivateKey
                    )
                    let robinhoodConnector = RobinhoodConnector(
                        logger: logger,
                        configuration: RobinhoodConnector.Configuration(
                            credentials: credentials
                        )
                    )
                    exchangeConnectors["robinhood"] = robinhoodConnector
                } catch {
                    print("Warning: Could not initialize Robinhood connector: \(error.localizedDescription)")
                    throw error
                }
            } else {
                print("Error: Robinhood API credentials are empty or invalid")
                throw NSError(domain: "SyncCommand", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"])
            }
        } else {
            print("Error: Robinhood API credentials not found. Set ROBINHOOD_API_KEY and ROBINHOOD_PRIVATE_KEY environment variables or add them to .env file")
            throw NSError(domain: "SyncCommand", code: 1, userInfo: [NSLocalizedDescriptionKey: "Credentials not found"])
        }

        // Verify connector is properly set
        guard let robinhoodConnector = exchangeConnectors["robinhood"] as? RobinhoodConnector else {
            print("Error: Robinhood connector not found or wrong type")
            return
        }

        let persistence = try createPersistence(config: nil)
        try persistence.initialize()
        try persistence.migrate()

        logger.info(component: "SyncCommand", event: "Starting balance sync")
        print("Refreshing balances from broker(s)...")

        do {
            // Use typed method directly to avoid protocol dispatch issue
            let typedHoldings = try await robinhoodConnector.getHoldings(assetCode: nil)
            let existingAll = try persistence.getAllAccounts().filter { $0.exchange == "robinhood" }
            var existingMap: [String: Holding] = [:]
            for h in existingAll { existingMap[h.asset] = h }

            var assetsToKeep = Set<String>()
            var refreshedBalances: [Holding] = []

            for holding in typedHoldings {
                let asset = holding.assetCode
                let totalQuantity = holding.quantity
                let availableQuantity = holding.available
                let pendingQuantity = holding.pending
                let stakedQuantity = holding.staked

                if totalQuantity > 0 || availableQuantity > 0 || pendingQuantity > 0 || stakedQuantity > 0 {
                    assetsToKeep.insert(asset)

                    let nonAvailable = totalQuantity - availableQuantity
                    let pending = pendingQuantity > 0 ? pendingQuantity : (nonAvailable > 0 ? nonAvailable : 0.0)
                    let staked = stakedQuantity > 0 ? stakedQuantity : 0.0

                    let existing = existingMap[asset]
                    let account = Holding(
                        id: existing?.id ?? UUID(),
                        exchange: "robinhood",
                        asset: asset,
                        available: availableQuantity,
                        pending: pending,
                        staked: staked,
                        updatedAt: Date()
                    )
                    try persistence.saveAccount(account)
                    refreshedBalances.append(account)
                }
            }

            for (asset, existing) in existingMap {
                if !assetsToKeep.contains(asset) && asset != "USD" {
                    let zeroAccount = Holding(
                        id: existing.id,
                        exchange: "robinhood",
                        asset: asset,
                        available: 0,
                        pending: 0,
                        staked: 0,
                        updatedAt: Date()
                    )
                    try persistence.saveAccount(zeroAccount)
                }
            }

            let accountInfo = try? await robinhoodConnector.getAccountBalance()
            if let accountInfo = accountInfo,
               let bpStr = accountInfo["crypto_buying_power"],
               let bp = Double(bpStr), bp >= 0 {
                let existingUSD = try? persistence.getAccount(exchange: "robinhood", asset: "USD")
                let usdHolding = Holding(
                    id: existingUSD?.id ?? UUID(),
                    exchange: "robinhood",
                    asset: "USD",
                    available: bp,
                    pending: 0,
                    staked: 0,
                    updatedAt: Date()
                )
                try persistence.saveAccount(usdHolding)
                refreshedBalances.append(usdHolding)
            }

            let balances = refreshedBalances
            logger.info(component: "SyncCommand", event: "Balances synchronized", data: [
                "asset_count": String(balances.count)
            ])
            print("Synchronized \(balances.count) balance\(balances.count == 1 ? "" : "s")")

            print("Importing transactions from broker(s)...")
            do {
                let coreTransactions = try await robinhoodConnector.getRecentTransactions(limit: 100)
                var importedCount = 0
                var skippedCount = 0

                for coreTx in coreTransactions {
                    let existing = try? persistence.getTransaction(by: coreTx.id)
                    if existing != nil {
                        skippedCount += 1
                        continue
                    }

                    let investmentTx = InvestmentTransaction(
                        id: UUID(),
                        type: coreTx.type == .buy ? .buy : .sell,
                        exchange: "robinhood",
                        asset: coreTx.asset,
                        quantity: coreTx.quantity,
                        price: coreTx.price,
                        fee: 0.0,
                        timestamp: coreTx.timestamp,
                        metadata: ["order_id": coreTx.id],
                        idempotencyKey: coreTx.id
                    )

                    try persistence.saveTransaction(investmentTx)
                    importedCount += 1
                }

                logger.info(component: "SyncCommand", event: "Transactions imported", data: [
                    "imported": String(importedCount),
                    "skipped": String(skippedCount)
                ])
                print("Imported \(importedCount) transaction\(importedCount == 1 ? "" : "s"), skipped \(skippedCount) existing")
            } catch {
                logger.warn(component: "SyncCommand", event: "Transaction import failed", data: [
                    "error": error.localizedDescription
                ])
                print("Warning: Could not import transactions: \(error.localizedDescription)")
            }
        } catch {
            logger.error(component: "SyncCommand", event: "Balance sync failed", data: [
                "error": error.localizedDescription
            ])
            print("Error refreshing balances: \(error.localizedDescription)")
            throw error
        }
    }
}

struct BalancesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "balances",
        abstract: "View current holdings in tabular format"
    )

    func run() async throws {
        let logger = StructuredLogger()
        let config = try? SmartVestorConfigurationManager().currentConfig
        let persistence = try createPersistence(config: config)

        do {
            try persistence.initialize()
            try persistence.migrate()
        } catch {
            print("Warning: Could not initialize database: \(error.localizedDescription)")
        }

        var allBalances = (try? persistence.getAllAccounts()) ?? []
        allBalances = allBalances.filter { $0.total > 0 }

        if allBalances.isEmpty {
            print("No balances found")
            return
        }

        var symbols = Array(Set(allBalances.map { $0.asset }))
        if !symbols.contains("USDC") && !symbols.contains("USD") {
            symbols.append("USDC")
        }

        let provider = MultiProviderMarketDataProvider(logger: logger)
        var prices: [String: Double] = [:]
        if !symbols.isEmpty {
            prices = (try? await provider.getCurrentPrices(symbols: symbols)) ?? [:]
        }

        if prices["USDC"] == nil && prices["USD"] == nil {
            prices["USDC"] = 1.0
            prices["USD"] = 1.0
        }

        // Sort by value (descending)
        let sortedBalances = allBalances.sorted { (prices[$0.asset] ?? 0.0) * $0.total > (prices[$1.asset] ?? 0.0) * $1.total }

        // Print header
        let assetCol = "Asset".padding(toLength: 10, withPad: " ", startingAt: 0)
        let availCol = "Available".padding(toLength: 15, withPad: " ", startingAt: 0)
        let pendCol = "Pending".padding(toLength: 15, withPad: " ", startingAt: 0)
        let stakedCol = "Staked".padding(toLength: 15, withPad: " ", startingAt: 0)
        let totalCol = "Total".padding(toLength: 15, withPad: " ", startingAt: 0)
        let valueCol = "Value".padding(toLength: 15, withPad: " ", startingAt: 0)
        print("\(assetCol) \(availCol) \(pendCol) \(stakedCol) \(totalCol) \(valueCol)")

        // Print rows
        for balance in sortedBalances {
            let value = (prices[balance.asset] ?? 0.0) * balance.total
            let assetStr = balance.asset.padding(toLength: 10, withPad: " ", startingAt: 0)
            let availStr = String(format: "%.8f", balance.available).padding(toLength: 15, withPad: " ", startingAt: 0)
            let pendStr = String(format: "%.8f", balance.pending).padding(toLength: 15, withPad: " ", startingAt: 0)
            let stakedStr = String(format: "%.8f", balance.staked).padding(toLength: 15, withPad: " ", startingAt: 0)
            let totalStr = String(format: "%.8f", balance.total).padding(toLength: 15, withPad: " ", startingAt: 0)
            let valueStr = String(format: "$%.2f", value).padding(toLength: 15, withPad: " ", startingAt: 0)
            print("\(assetStr) \(availStr) \(pendStr) \(stakedStr) \(totalStr) \(valueStr)")
        }
    }
}

struct ActivityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activity",
        abstract: "View recent transactions"
    )

    @Option(name: .shortAndLong, help: "Number of transactions to show")
    var limit: Int = 50

    @Flag(name: .long, help: "Show only transactions from the last 24 hours")
    var last24Hours: Bool = false

    func run() async throws {
        let config = try? SmartVestorConfigurationManager().currentConfig
        let persistence = try createPersistence(config: config)

        do {
            try persistence.initialize()
            try persistence.migrate()
        } catch {
            print("Warning: Could not initialize database: \(error.localizedDescription)")
        }

        // Get recent transactions
        var allTransactions = (try? persistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: min(limit, 100))) ?? []

        // Filter to last 24 hours if requested
        if last24Hours {
            let now = Date()
            let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60)
            allTransactions = allTransactions
                .filter { $0.timestamp >= twentyFourHoursAgo }
        }

        let recentTrades = allTransactions
            .sorted { $0.timestamp > $1.timestamp }

        if recentTrades.isEmpty {
            if last24Hours {
                print("No transactions in the last 24 hours")
            } else {
                print("No transactions found")
            }
            return
        }

        // Print header
        let timeCol = "Time".padding(toLength: 19, withPad: " ", startingAt: 0)
        let typeCol = "Type".padding(toLength: 10, withPad: " ", startingAt: 0)
        let assetCol = "Asset".padding(toLength: 10, withPad: " ", startingAt: 0)
        let qtyCol = "Quantity".padding(toLength: 15, withPad: " ", startingAt: 0)
        let priceCol = "Price".padding(toLength: 12, withPad: " ", startingAt: 0)
        let exchangeCol = "Exchange".padding(toLength: 10, withPad: " ", startingAt: 0)
        print("\(timeCol) \(typeCol) \(assetCol) \(qtyCol) \(priceCol) \(exchangeCol)")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // Print rows
        for trade in recentTrades {
            let timeStr = dateFormatter.string(from: trade.timestamp).padding(toLength: 19, withPad: " ", startingAt: 0)
            let typeStr = trade.type.rawValue.uppercased().padding(toLength: 10, withPad: " ", startingAt: 0)
            let assetStr = trade.asset.padding(toLength: 10, withPad: " ", startingAt: 0)
            let qtyStr = String(format: "%.6f", trade.quantity).padding(toLength: 15, withPad: " ", startingAt: 0)
            let priceStr = String(format: "$%.6f", trade.price).padding(toLength: 12, withPad: " ", startingAt: 0)
            let exchangeStr = trade.exchange.padding(toLength: 10, withPad: " ", startingAt: 0)
            print("\(timeStr) \(typeStr) \(assetStr) \(qtyStr) \(priceStr) \(exchangeStr)")
        }
    }
}

struct DiagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diag",
        abstract: "Diagnose MLX and system configuration",
        subcommands: [FeatureExtractionDiagnostic.self]
    )

    @Flag(name: .long, help: "Check MLX configuration")
    var mlx: Bool = false

    func run() async throws {
        if mlx {
            print("=== MLX Diagnostic ===")
            print("")

            #if canImport(MLPatternEngineMLX) && os(macOS)
            // Check Metal availability
            guard let device = MTLCreateSystemDefaultDevice() else {
                print("❌ Metal: Not available")
                print("   MLX GPU acceleration requires Metal-compatible GPU")
                return
            }

            print("✓ Metal: Available")
            print("   Device: \(device.name)")
            print("   Low Power: \(device.isLowPower ? "Yes" : "No")")
            print("   Removable: \(device.isRemovable ? "Yes" : "No")")
            print("")

            // Check metallib
            let fileManager = FileManager.default
            let homeDir = fileManager.homeDirectoryForCurrentUser
            let mlxPath = homeDir.appendingPathComponent(".mlx/default.metallib")
            let cwdPath = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("default.metallib")
            // Try to find bundle resource - check multiple possible bundle locations
            var bundlePath: URL?
            if let resourcePath = Bundle.main.resourcePath {
                let candidate = URL(fileURLWithPath: resourcePath).appendingPathComponent("default.metallib")
                if fileManager.fileExists(atPath: candidate.path) {
                    bundlePath = candidate
                }
            }

            var metallibPath: URL?

            if fileManager.fileExists(atPath: mlxPath.path) {
                metallibPath = mlxPath
                print("✓ Metallib found: ~/.mlx/default.metallib")
            } else if fileManager.fileExists(atPath: cwdPath.path) {
                metallibPath = cwdPath
                print("✓ Metallib found: ./default.metallib")
            } else if let bundlePath = bundlePath {
                metallibPath = bundlePath
                print("✓ Metallib found: Bundle resource")
            } else {
                print("❌ Metallib: Not found")
                print("   Run: ./scripts/build-mlx-metallib.sh")
            }

            if let path = metallibPath {
                // Check file size
                if let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
                   let size = attributes[.size] as? Int64 {
                    let sizeMB = Double(size) / 1_000_000.0
                    print("   Size: \(String(format: "%.2f", sizeMB)) MB")
                }

                // Try to load the library - this is the authoritative check
                do {
                    let library = try device.makeLibrary(URL: path)
                    print("   ✓ Library loads successfully")

                    // Try to get a function (this will fail if kernel is missing)
                    if library.makeFunction(name: "rbitsc") != nil {
                        print("   ✓ rbitsc kernel: Available")
                    } else {
                        print("   ⚠ rbitsc kernel: Not found (kernel may not be compiled)")
                    }
                } catch {
                    print("   ❌ Library load failed: \(error.localizedDescription)")
                    print("   ⚠ rbitsc kernel: Cannot verify (library load failed)")
                }
            }

            print("")

            // Check environment variables
            print("Environment:")
            if let metalPath = ProcessInfo.processInfo.environment["METAL_PATH"] {
                print("   METAL_PATH: \(metalPath)")
            } else {
                print("   METAL_PATH: Not set")
            }

            if let mlxDevice = ProcessInfo.processInfo.environment["MLX_DEVICE"] {
                print("   MLX_DEVICE: \(mlxDevice)")
            } else {
                print("   MLX_DEVICE: Not set (defaults to GPU)")
            }

            if let disableMetal = ProcessInfo.processInfo.environment["MLX_DISABLE_METAL"] {
                print("   MLX_DISABLE_METAL: \(disableMetal)")
            } else {
                print("   MLX_DISABLE_METAL: Not set")
            }

            print("")

            // Check MLX initialization
            print("MLX Initialization:")
            do {
                MLXInitialization.configureMLX()
                setupMLXEnvironment()
                try MLXAdapter.ensureInitialized()
                print("   ✓ MLX initialized successfully")
            } catch {
                print("   ❌ MLX initialization failed: \(error.localizedDescription)")
                print("")
                print("   To use CPU fallback:")
                print("     export MLX_DEVICE=cpu")
                print("     swift run SmartVestorCLI coins --ml-based")
                print("")
                print("   To disable Metal completely:")
                print("     export MLX_DISABLE_METAL=1")
                print("     swift run SmartVestorCLI coins --ml-based")
            }

            #else
            print("❌ MLX: Not available (not macOS or MLPatternEngineMLX not imported)")
            #endif
        } else {
            print("Usage: sv diag <subcommand>")
            print("")
            print("Subcommands:")
            print("  features    Diagnose feature extraction pipeline")
            print("")
            print("Options:")
            print("  --mlx       Check MLX and Metal configuration")
            print("")
            print("Examples:")
            print("  sv diag --mlx")
            print("  sv diag features")
            print("  sv diag features --symbol ETH-USD")
        }
    }
}

struct LogsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "View recent system logs and transactions"
    )

    @Option(name: .shortAndLong, help: "Number of log lines to show")
    var limit: Int = 50

    func run() async throws {
        let config = try? SmartVestorConfigurationManager().currentConfig
        let persistence = try createPersistence(config: config)

        do {
            try persistence.initialize()
            try persistence.migrate()
        } catch {
            print("Warning: Could not initialize database: \(error.localizedDescription)")
        }

        var lines: [String] = []

        // Recent transactions
        if let transactions = try? persistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: 10) {
            lines.append("=== Recent Transactions ===")
            if transactions.isEmpty {
                lines.append("No recent transactions")
            } else {
                lines.append("Showing \(transactions.count) most recent:")
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withSpaceBetweenDateAndTime]
                for tx in transactions {
                    let dateStr = dateFormatter.string(from: tx.timestamp)
                    lines.append("[\(dateStr)] \(tx.type.rawValue.uppercased()) \(tx.asset) qty=\(String(format: "%.6f", tx.quantity)) @ \(String(format: "%.6f", tx.price)) ex=\(tx.exchange)")
                }
            }
            lines.append("")
        }

        // System logs
        lines.append("=== System Logs ===")

        #if os(macOS) || os(Linux)
        let logPaths = [
            "/tmp/smartvestor-automation.log",
            "/tmp/smartvestor.log",
            "smartvestor.log",
            ProcessInfo.processInfo.environment["SMARTVESTOR_LOG_PATH"] ?? ""
        ].filter { !$0.isEmpty }

        var foundLogs = false
        for logPath in logPaths {
            if let logContent = try? String(contentsOfFile: logPath, encoding: .utf8) {
                let allLines = logContent.components(separatedBy: .newlines)
                let recentLines = Array(allLines.suffix(limit))
                lines.append("--- \(logPath) (last \(recentLines.count) lines) ---")
                lines.append(contentsOf: recentLines)
                foundLogs = true
                break
            }
        }

        if !foundLogs {
            lines.append("No log files found. Checked:")
            for path in logPaths {
                lines.append("  - \(path)")
            }
        }
        #else
        lines.append("Log file reading not available on this platform")
        #endif

        print(lines.joined(separator: "\n"))
    }
}
