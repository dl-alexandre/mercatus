import Foundation
import Security
import Utils

public class SmartVestorConfigurationManager {
    private let config: SmartVestorConfig
    private let keychain = KeychainManager()

    public init(configPath: String? = nil) throws {
        let loadedConfig: SmartVestorConfig

        if let path = configPath {
            loadedConfig = try Self.loadConfig(from: path)
        } else {
            let defaultPaths = [
                "config/smartvestor_config.json",
                "smartvestor_config.json",
                "./config/smartvestor_config.json"
            ]

            var loaded = false
            var tempConfig: SmartVestorConfig?

            for defaultPath in defaultPaths {
                if FileManager.default.fileExists(atPath: defaultPath) {
                    do {
                        tempConfig = try Self.loadConfig(from: defaultPath)
                        loaded = true
                        break
                    } catch {
                        continue
                    }
                }
            }

            if loaded, let config = tempConfig {
                loadedConfig = config
            } else {
                loadedConfig = try Self.loadConfigFromEnvironment()
            }
        }

        if let tigerBeetle = loadedConfig.tigerbeetle {
            try tigerBeetle.validate()
        }
        self.config = loadedConfig
    }

    public var currentConfig: SmartVestorConfig {
        return config
    }

    public func getExchangeCredentials(for exchange: String) throws -> ExchangeCredentials {
        return try keychain.getCredentials(for: exchange)
    }

    public func storeExchangeCredentials(_ credentials: ExchangeCredentials, for exchange: String) throws {
        try keychain.storeCredentials(credentials, for: exchange)
    }

    public func createPersistence(
        dbPath: String = "smartvestor.db",
        logger: StructuredLogger = StructuredLogger(),
        validateColdStart: Bool = false
    ) throws -> PersistenceProtocol {
        let sqlitePersistence = SQLitePersistence(dbPath: dbPath)

        guard let tigerBeetleConfig = config.tigerbeetle,
              tigerBeetleConfig.enabled else {
            return sqlitePersistence
        }

        try ClockSanityChecker.validateClock()

        let client = InMemoryTigerBeetleClient()
        let tigerBeetlePersistence = TigerBeetlePersistence(client: client, logger: logger)

        if validateColdStart {
            let validator = ColdStartValidator(
                sqlitePersistence: sqlitePersistence,
                tigerBeetlePersistence: tigerBeetlePersistence,
                logger: logger
            )
            _ = try validator.validateColdStart()
        }

        return HybridPersistence(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: tigerBeetlePersistence,
            useTigerBeetleForTransactions: tigerBeetleConfig.useTigerBeetleForTransactions,
            useTigerBeetleForBalances: tigerBeetleConfig.useTigerBeetleForBalances,
            logger: logger
        )
    }

    private static func loadConfig(from path: String) throws -> SmartVestorConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(SmartVestorConfig.self, from: data)
    }

    private static func loadConfigFromEnvironment() throws -> SmartVestorConfig {
        let baseAllocation = BaseAllocation(
            btc: Double(ProcessInfo.processInfo.environment["SMARTVESTOR_BTC_ALLOCATION"] ?? "0.4") ?? 0.4,
            eth: Double(ProcessInfo.processInfo.environment["SMARTVESTOR_ETH_ALLOCATION"] ?? "0.3") ?? 0.3,
            altcoins: Double(ProcessInfo.processInfo.environment["SMARTVESTOR_ALTCOIN_ALLOCATION"] ?? "0.3") ?? 0.3
        )

        let volatilityThreshold = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_VOLATILITY_THRESHOLD"] ?? "0.15") ?? 0.15
        let volatilityMultiplier = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_VOLATILITY_MULTIPLIER"] ?? "1.2") ?? 1.2
        let feeCap = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_FEE_CAP"] ?? "0.003") ?? 0.003
        let depositAmount = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_DEPOSIT_AMOUNT"] ?? "100.0") ?? 100.0
        let depositTolerance = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_DEPOSIT_TOLERANCE"] ?? "0.05") ?? 0.05
        let rsiThreshold = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_RSI_THRESHOLD"] ?? "70.0") ?? 70.0
        let priceThreshold = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_PRICE_THRESHOLD"] ?? "1.10") ?? 1.10
        let movingAveragePeriod = Int(ProcessInfo.processInfo.environment["SMARTVESTOR_MA_PERIOD"] ?? "30") ?? 30

        let exchanges = loadExchangeConfigs()
        let staking = loadStakingConfig()
        let simulation = loadSimulationConfig()

        let swapAnalysis = loadSwapAnalysisConfig()
        let tigerbeetle = loadTigerBeetleConfig()

        return SmartVestorConfig(
            baseAllocation: baseAllocation,
            volatilityThreshold: volatilityThreshold,
            volatilityMultiplier: volatilityMultiplier,
            feeCap: feeCap,
            depositAmount: depositAmount,
            depositTolerance: depositTolerance,
            rsiThreshold: rsiThreshold,
            priceThreshold: priceThreshold,
            movingAveragePeriod: movingAveragePeriod,
            exchanges: exchanges,
            staking: staking,
            simulation: simulation,
            swapAnalysis: swapAnalysis,
            tigerbeetle: tigerbeetle
        )
    }

    private static func loadExchangeConfigs() -> [ExchangeConfig] {
        let exchangeNames = ProcessInfo.processInfo.environment["SMARTVESTOR_EXCHANGES"]?.components(separatedBy: ",") ?? ["kraken", "coinbase", "gemini"]

        return exchangeNames.compactMap { name in
            let enabled = ProcessInfo.processInfo.environment["SMARTVESTOR_\(name.uppercased())_ENABLED"]?.lowercased() == "true"
            let sandbox = ProcessInfo.processInfo.environment["SMARTVESTOR_\(name.uppercased())_SANDBOX"]?.lowercased() == "true"
            let supportedNetworks = ProcessInfo.processInfo.environment["SMARTVESTOR_\(name.uppercased())_NETWORKS"]?.components(separatedBy: ",") ?? ["USDC-ETH", "USDC-SOL"]

            let rateLimit = RateLimitConfig(
                requestsPerSecond: Int(ProcessInfo.processInfo.environment["SMARTVESTOR_\(name.uppercased())_RATE_LIMIT"] ?? "10") ?? 10,
                burstLimit: Int(ProcessInfo.processInfo.environment["SMARTVESTOR_\(name.uppercased())_BURST_LIMIT"] ?? "50") ?? 50,
                globalCeiling: Int(ProcessInfo.processInfo.environment["SMARTVESTOR_\(name.uppercased())_GLOBAL_CEILING"] ?? "100") ?? 100
            )

            return ExchangeConfig(
                name: name,
                enabled: enabled,
                sandbox: sandbox,
                supportedNetworks: supportedNetworks,
                rateLimit: rateLimit
            )
        }
    }

    private static func loadStakingConfig() -> StakingConfig {
        let enabled = ProcessInfo.processInfo.environment["SMARTVESTOR_STAKING_ENABLED"]?.lowercased() == "true"
        let allowedAssets = ProcessInfo.processInfo.environment["SMARTVESTOR_STAKING_ASSETS"]?.components(separatedBy: ",") ?? ["ETH", "SOL"]
        let minStakingAmount = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_MIN_STAKING_AMOUNT"] ?? "0.1") ?? 0.1
        let autoCompound = ProcessInfo.processInfo.environment["SMARTVESTOR_AUTO_COMPOUND"]?.lowercased() == "true"

        return StakingConfig(
            enabled: enabled,
            allowedAssets: allowedAssets,
            minStakingAmount: minStakingAmount,
            autoCompound: autoCompound
        )
    }

    private static func loadSwapAnalysisConfig() -> SwapAnalysisConfig {
        let enabled = ProcessInfo.processInfo.environment["SMARTVESTOR_SWAP_ANALYSIS_ENABLED"]?.lowercased() == "true"
        let minProfitThreshold = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_SWAP_MIN_PROFIT_THRESHOLD"] ?? "1.0") ?? 1.0
        let minProfitPercentage = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_SWAP_MIN_PROFIT_PERCENTAGE"] ?? "0.005") ?? 0.005
        let safetyMultiplier = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_SWAP_SAFETY_MULTIPLIER"] ?? "1.2") ?? 1.2
        let maxCostPercentage = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_SWAP_MAX_COST_PERCENTAGE"] ?? "0.02") ?? 0.02
        let minConfidence = Double(ProcessInfo.processInfo.environment["SMARTVESTOR_SWAP_MIN_CONFIDENCE"] ?? "0.6") ?? 0.6
        let enableAutoSwaps = ProcessInfo.processInfo.environment["SMARTVESTOR_SWAP_AUTO_ENABLED"]?.lowercased() == "true"
        let maxSwapsPerCycle = Int(ProcessInfo.processInfo.environment["SMARTVESTOR_SWAP_MAX_PER_CYCLE"] ?? "3") ?? 3

        return SwapAnalysisConfig(
            enabled: enabled,
            minProfitThreshold: minProfitThreshold,
            minProfitPercentage: minProfitPercentage,
            safetyMultiplier: safetyMultiplier,
            maxCostPercentage: maxCostPercentage,
            minConfidence: minConfidence,
            enableAutoSwaps: enableAutoSwaps,
            maxSwapsPerCycle: maxSwapsPerCycle
        )
    }

    private static func loadTigerBeetleConfig() -> TigerBeetleConfig? {
        let enabled = ProcessInfo.processInfo.environment["TIGERBEETLE_ENABLED"]?.lowercased() == "true"
        guard enabled || ProcessInfo.processInfo.environment["TIGERBEETLE_CLUSTER_ID"] != nil else {
            return nil
        }

        let clusterId = UInt32(ProcessInfo.processInfo.environment["TIGERBEETLE_CLUSTER_ID"] ?? "0") ?? 0
        let replicaAddresses = ProcessInfo.processInfo.environment["TIGERBEETLE_REPLICA_ADDRESSES"]?
            .components(separatedBy: ",") ?? ["127.0.0.1:3001"]
        let useForTransactions = ProcessInfo.processInfo.environment["TIGERBEETLE_USE_FOR_TRANSACTIONS"]?.lowercased() != "false"
        let useForBalances = ProcessInfo.processInfo.environment["TIGERBEETLE_USE_FOR_BALANCES"]?.lowercased() != "false"

        return TigerBeetleConfig(
            enabled: enabled,
            clusterId: clusterId,
            replicaAddresses: replicaAddresses,
            useTigerBeetleForTransactions: useForTransactions,
            useTigerBeetleForBalances: useForBalances
        )
    }

    private static func loadSimulationConfig() -> SimulationConfig {
        // Check for production mode override first
        let productionMode = ProcessInfo.processInfo.environment["SMARTVESTOR_PRODUCTION_MODE"]?.lowercased() == "true"
        let simulationEnabled = ProcessInfo.processInfo.environment["SMARTVESTOR_SIMULATION_ENABLED"]?.lowercased() == "true"

        // If production mode is set, disable simulation
        let enabled = productionMode ? false : simulationEnabled

        let historicalDataPath = ProcessInfo.processInfo.environment["SMARTVESTOR_HISTORICAL_DATA_PATH"]

        let startDate: Date?
        if let startDateString = ProcessInfo.processInfo.environment["SMARTVESTOR_SIMULATION_START_DATE"] {
            startDate = ISO8601DateFormatter().date(from: startDateString)
        } else {
            startDate = nil
        }

        let endDate: Date?
        if let endDateString = ProcessInfo.processInfo.environment["SMARTVESTOR_SIMULATION_END_DATE"] {
            endDate = ISO8601DateFormatter().date(from: endDateString)
        } else {
            endDate = nil
        }

        return SimulationConfig(
            enabled: enabled,
            historicalDataPath: historicalDataPath,
            startDate: startDate,
            endDate: endDate
        )
    }
}

public struct ExchangeCredentials: Codable {
    public let apiKey: String
    public let secretKey: String
    public let passphrase: String?

    public init(apiKey: String, secretKey: String, passphrase: String? = nil) {
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.passphrase = passphrase
    }
}

public class KeychainManager {
    private let serviceName = "SmartVestor"

    public init() {}

    public func storeCredentials(_ credentials: ExchangeCredentials, for exchange: String) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: exchange,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SmartVestorError.keychainError("Failed to store credentials: \(status)")
        }
    }

    public func getCredentials(for exchange: String) throws -> ExchangeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: exchange,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            throw SmartVestorError.keychainError("Failed to retrieve credentials: \(status)")
        }

        return try JSONDecoder().decode(ExchangeCredentials.self, from: data)
    }

    public func deleteCredentials(for exchange: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: exchange
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SmartVestorError.keychainError("Failed to delete credentials: \(status)")
        }
    }
}

public enum SmartVestorError: Error, LocalizedError {
    case configurationError(String)
    case keychainError(String)
    case validationError(String)
    case exchangeError(String)
    case allocationError(String)
    case executionError(String)
    case persistenceError(String)

    public var errorDescription: String? {
        switch self {
        case .configurationError(let message):
            return "Configuration Error: \(message)"
        case .keychainError(let message):
            return "Keychain Error: \(message)"
        case .validationError(let message):
            return "Validation Error: \(message)"
        case .exchangeError(let message):
            return "Exchange Error: \(message)"
        case .allocationError(let message):
            return "Allocation Error: \(message)"
        case .executionError(let message):
            return "Execution Error: \(message)"
        case .persistenceError(let message):
            return "Persistence Error: \(message)"
        }
    }
}
