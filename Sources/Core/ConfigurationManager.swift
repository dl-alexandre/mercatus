import Foundation
import Utils

/// Loads application configuration from either the process environment variables or a JSON file.
public final class ConfigurationManager: @unchecked Sendable {
    private let environment: [String: String]
    private let fileManager: FileManager

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    /// Attempts to load configuration, preferring an explicit file path over environment variables.
    /// - Parameter path: Optional JSON file path. If `nil` the manager looks for `ARBITRAGE_CONFIG_FILE`.
    public func load(path: String? = nil) throws -> ArbitrageConfig {
        if let explicitPath = path {
            return try loadFromFile(at: explicitPath)
        }

        if let envPath = environment["ARBITRAGE_CONFIG_FILE"], !envPath.isEmpty {
            return try loadFromFile(at: envPath)
        }

        return try loadFromEnvironment()
    }

    public func logConfiguration(_ config: ArbitrageConfig, logger: StructuredLogger) {
        let metadata = [
            "binanceApiKey": config.binanceCredentials.maskedKey,
            "coinbaseApiKey": config.coinbaseCredentials.maskedKey,
            "krakenApiKey": config.krakenCredentials.maskedKey,
            "tradingPairs": config.tradingPairs.map(\.symbol).joined(separator: ","),
            "spreadThreshold": String(config.thresholds.minimumSpreadPercentage),
            "maxLatencyMs": String(config.thresholds.maximumLatencyMilliseconds),
            "virtualBalanceUSD": String(config.defaults.virtualUSDStartingBalance)
        ]

        logger.info(
            component: "ConfigurationManager",
            event: "configuration_loaded",
            data: metadata
        )
    }

    private func loadFromFile(at path: String) throws -> ArbitrageConfig {
        guard fileManager.fileExists(atPath: path) else {
            throw ConfigurationError.fileNotFound(path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw ConfigurationError.invalidJSON(error.localizedDescription)
        }

        do {
            let decoder = JSONDecoder()
            let config = try decoder.decode(ArbitrageConfig.self, from: data)
            try config.validate()
            return config
        } catch let error as ConfigurationError {
            throw error
        } catch {
            throw ConfigurationError.invalidJSON(error.localizedDescription)
        }
    }

    private func loadFromEnvironment() throws -> ArbitrageConfig {
        let binanceKey = environment["ARBITRAGE_BINANCE_API_KEY"] ?? ""
        let binanceSecret = environment["ARBITRAGE_BINANCE_API_SECRET"] ?? ""
        let coinbaseKey = environment["ARBITRAGE_COINBASE_API_KEY"] ?? ""
        let coinbaseSecret = environment["ARBITRAGE_COINBASE_API_SECRET"] ?? ""
        let krakenKey = environment["ARBITRAGE_KRAKEN_API_KEY"] ?? ""
        let krakenSecret = environment["ARBITRAGE_KRAKEN_API_SECRET"] ?? ""

        let pairsString = environment["ARBITRAGE_TRADING_PAIRS"] ?? ""
        let pairTokens = pairsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let tradingPairs: [TradingPair] = pairTokens.compactMap { token in
            let parts = token.replacingOccurrences(of: "/", with: "-").split(separator: "-")
            guard parts.count == 2 else { return nil }
            return TradingPair(base: String(parts[0]), quote: String(parts[1]))
        }

        let spreadThreshold = Double(environment["ARBITRAGE_MIN_SPREAD_PERCENT"] ?? "")
            ?? ArbitrageConfig.Thresholds.defaultMinimumSpreadPercentage
        let maxLatency = Double(environment["ARBITRAGE_MAX_LATENCY_MS"] ?? "")
            ?? ArbitrageConfig.Thresholds.defaultMaximumLatencyMilliseconds
        let startingBalance = Double(environment["ARBITRAGE_VIRTUAL_BALANCE_USD"] ?? "")
            ?? ArbitrageConfig.Defaults().virtualUSDStartingBalance

        let thresholds = ArbitrageConfig.Thresholds(
            minimumSpreadPercentage: spreadThreshold,
            maximumLatencyMilliseconds: maxLatency
        )

        let defaults = ArbitrageConfig.Defaults(
            virtualUSDStartingBalance: startingBalance
        )

        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: binanceKey, apiSecret: binanceSecret),
            coinbaseCredentials: .init(apiKey: coinbaseKey, apiSecret: coinbaseSecret),
            krakenCredentials: .init(apiKey: krakenKey, apiSecret: krakenSecret),
            tradingPairs: tradingPairs,
            thresholds: thresholds,
            defaults: defaults
        )

        try config.validate()
        return config
    }
}

private extension ArbitrageConfig.Thresholds {
    static var defaultMinimumSpreadPercentage: Double { 0.5 }
    static var defaultMaximumLatencyMilliseconds: Double { 150.0 }
}
