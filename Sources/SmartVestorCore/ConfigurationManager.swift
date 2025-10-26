import Foundation
import Security

public class SmartVestorConfigurationManager {
    private let config: SmartVestorConfig
    private let keychain = KeychainManager()

    public init(configPath: String? = nil) throws {
        if let path = configPath {
            self.config = try Self.loadConfig(from: path)
        } else {
            self.config = try Self.loadConfigFromEnvironment()
        }
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
            simulation: simulation
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

    private static func loadSimulationConfig() -> SimulationConfig {
        let enabled = ProcessInfo.processInfo.environment["SMARTVESTOR_SIMULATION_ENABLED"]?.lowercased() == "true"
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
