import Foundation
import Utils
import Core

public struct AutomationComponents {
    public let config: SmartVestorConfig
    public let persistence: PersistenceProtocol
    public let logger: StructuredLogger
    public let robinhoodConnector: ExchangeConnectorProtocol?
    public let exchangeConnectors: [String: ExchangeConnectorProtocol]
    public let crossExchangeAnalyzer: CrossExchangeAnalyzerProtocol
    public let executionEngine: ExecutionEngineProtocol
    public let depositMonitor: DepositMonitorProtocol
    public let allocationManager: AllocationManagerProtocol
    public let continuousRunner: ContinuousRunner?

    public init(
        config: SmartVestorConfig,
        persistence: PersistenceProtocol,
        logger: StructuredLogger,
        robinhoodConnector: ExchangeConnectorProtocol?,
        exchangeConnectors: [String: ExchangeConnectorProtocol],
        crossExchangeAnalyzer: CrossExchangeAnalyzerProtocol,
        executionEngine: ExecutionEngineProtocol,
        depositMonitor: DepositMonitorProtocol,
        allocationManager: AllocationManagerProtocol,
        continuousRunner: ContinuousRunner?
    ) {
        self.config = config
        self.persistence = persistence
        self.logger = logger
        self.robinhoodConnector = robinhoodConnector
        self.exchangeConnectors = exchangeConnectors
        self.crossExchangeAnalyzer = crossExchangeAnalyzer
        self.executionEngine = executionEngine
        self.depositMonitor = depositMonitor
        self.allocationManager = allocationManager
        self.continuousRunner = continuousRunner
    }
}

public struct AutomationBootstrapper {
    private static func loadEnvFile() {
        let envPath = ".env"
        guard let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            return
        }

        for line in envContent.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.components(separatedBy: "=")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)

                if ProcessInfo.processInfo.environment[key] == nil {
                    setenv(key, value, 1)
                }
            }
        }
    }

    private static func loadRobinhoodCredentials() -> (apiKey: String, privateKeyBase64: String)? {
        var apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"]
        var privateKeyBase64 = ProcessInfo.processInfo.environment["ROBINHOOD_PRIVATE_KEY"]

        if apiKey == nil || privateKeyBase64 == nil {
            loadEnvFile()
            apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"]
            privateKeyBase64 = ProcessInfo.processInfo.environment["ROBINHOOD_PRIVATE_KEY"]
        }

        guard let apiKey = apiKey,
              let privateKeyBase64 = privateKeyBase64,
              !apiKey.isEmpty,
              !privateKeyBase64.isEmpty else {
            return nil
        }

        let sanitizedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        let sanitizedPrivateKey = privateKeyBase64
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            .filter { !$0.isWhitespace && $0 != "\n" && $0 != "\r" }

        guard !sanitizedApiKey.isEmpty, !sanitizedPrivateKey.isEmpty else {
            return nil
        }

        return (sanitizedApiKey, sanitizedPrivateKey)
    }

    public static func createComponents(
        configPath: String? = nil,
        productionMode: Bool = false,
        exchangeConnectors: [String: ExchangeConnectorProtocol] = [:],
        logger: StructuredLogger = StructuredLogger(maxLogsPerMinute: 300)
    ) async throws -> AutomationComponents {
        logger.info(component: "AutomationBootstrapper", event: "Initializing automation components")

        let configManager = try SmartVestorConfigurationManager(configPath: configPath)
        var config = configManager.currentConfig

        if productionMode {
            let simulationConfig = SimulationConfig(
                enabled: false,
                historicalDataPath: config.simulation.historicalDataPath,
                startDate: config.simulation.startDate,
                endDate: config.simulation.endDate,
                initialCapital: config.simulation.initialCapital,
                transactionFee: config.simulation.transactionFee
            )
            config = SmartVestorConfig(
                allocationMode: config.allocationMode,
                baseAllocation: config.baseAllocation,
                volatilityThreshold: config.volatilityThreshold,
                volatilityMultiplier: config.volatilityMultiplier,
                feeCap: config.feeCap,
                depositAmount: config.depositAmount,
                depositTolerance: config.depositTolerance,
                rsiThreshold: config.rsiThreshold,
                priceThreshold: config.priceThreshold,
                movingAveragePeriod: config.movingAveragePeriod,
                exchanges: config.exchanges,
                staking: config.staking,
                simulation: simulationConfig,
                scoreBasedAllocation: config.scoreBasedAllocation,
                maxPortfolioRisk: config.maxPortfolioRisk,
                marketDataProvider: config.marketDataProvider
            )
        }

        let persistence = SQLitePersistence(dbPath: "smartvestor.db")
        try persistence.initialize()
        logger.info(component: "AutomationBootstrapper", event: "Database initialized")

        let allConnectors = exchangeConnectors
        let robinhoodConnector = allConnectors["robinhood"]

        let crossExchangeAnalyzer = CrossExchangeAnalyzer(
            config: config,
            exchangeConnectors: allConnectors
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

        let swapAnalyzer: SwapAnalyzerProtocol? = {
            if config.swapAnalysis?.enabled == true {
                return SwapAnalyzer(
                    config: config,
                    exchangeConnectors: allConnectors,
                    crossExchangeAnalyzer: crossExchangeAnalyzer,
                    coinScoringEngine: coinScoringEngine,
                    persistence: persistence,
                    marketDataProvider: marketDataProvider
                )
            }
            return nil
        }()

        let executionEngine = ExecutionEngine(
            config: config,
            persistence: persistence,
            exchangeConnectors: allConnectors,
            crossExchangeAnalyzer: crossExchangeAnalyzer,
            swapAnalyzer: swapAnalyzer
        )

        let depositMonitor = DepositMonitor(
            config: config,
            persistence: persistence,
            exchangeConnectors: allConnectors,
            logger: logger
        )

        let allocationManager = AllocationManager(
            config: config,
            persistence: persistence
        )

        let continuousRunner = ContinuousRunner(
            config: config,
            persistence: persistence,
            depositMonitor: depositMonitor,
            allocationManager: allocationManager,
            executionEngine: executionEngine,
            crossExchangeAnalyzer: crossExchangeAnalyzer,
            logger: logger
        )

        logger.info(component: "AutomationBootstrapper", event: "All components initialized successfully")

        return AutomationComponents(
            config: config,
            persistence: persistence,
            logger: logger,
            robinhoodConnector: robinhoodConnector,
            exchangeConnectors: allConnectors,
            crossExchangeAnalyzer: crossExchangeAnalyzer,
            executionEngine: executionEngine,
            depositMonitor: depositMonitor,
            allocationManager: allocationManager,
            continuousRunner: continuousRunner
        )
    }
}
