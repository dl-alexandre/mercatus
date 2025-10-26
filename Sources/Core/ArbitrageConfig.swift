import Foundation

/// Describes the trading pair symbol used across connectors.
public struct TradingPair: Codable, Hashable, Sendable {
    public let base: String
    public let quote: String

    public init(base: String, quote: String) {
        self.base = base.uppercased()
        self.quote = quote.uppercased()
    }

    public var symbol: String { "\(base)-\(quote)" }

    /// Basic format validation for asset tickers (alphanumeric, 1-12 chars, base != quote).
    public func validate() throws {
        let validCharacters = CharacterSet.alphanumerics

        func isComponentValid(_ value: String) -> Bool {
            guard (1...12).contains(value.count) else { return false }
            return value.unicodeScalars.allSatisfy { validCharacters.contains($0) }
        }

        guard isComponentValid(base), isComponentValid(quote) else {
            throw ConfigurationError.invalidTradingPair(symbol)
        }

        guard base != quote else {
            throw ConfigurationError.invalidTradingPair(symbol)
        }
    }
}

/// Aggregates all runtime configuration required by the arbitrage engine.
public struct ArbitrageConfig: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case binanceCredentials
        case coinbaseCredentials
        case krakenCredentials
        case geminiCredentials
        case tradingPairs
        case thresholds
        case defaults
    }

    public struct ExchangeCredentials: Codable, Equatable, Sendable {
        public let apiKey: String
        public let apiSecret: String

        public init(apiKey: String, apiSecret: String) {
            self.apiKey = apiKey
            self.apiSecret = apiSecret
        }

        func validate(exchange: String) throws {
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConfigurationError.missingAPIKey(exchange)
            }
            guard !apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConfigurationError.missingAPISecret(exchange)
            }
        }

        var maskedKey: String {
            guard apiKey.count > 4 else { return "****" }
            let suffix = apiKey.suffix(4)
            return "****\(suffix)"
        }
    }

    public struct Thresholds: Codable, Equatable, Sendable {
        public let minimumSpreadPercentage: Double
        public let maximumLatencyMilliseconds: Double

        public init(minimumSpreadPercentage: Double, maximumLatencyMilliseconds: Double) {
            self.minimumSpreadPercentage = minimumSpreadPercentage
            self.maximumLatencyMilliseconds = maximumLatencyMilliseconds
        }

        func validate() throws {
            guard minimumSpreadPercentage > 0 else {
                throw ConfigurationError.invalidThreshold("minimumSpreadPercentage")
            }
            guard maximumLatencyMilliseconds > 0 else {
                throw ConfigurationError.invalidThreshold("maximumLatencyMilliseconds")
            }
        }
    }

    public struct Defaults: Codable, Equatable, Sendable {
        public let virtualUSDStartingBalance: Double

        public init(virtualUSDStartingBalance: Double = 10_000) {
            self.virtualUSDStartingBalance = virtualUSDStartingBalance
        }

        func validate() throws {
            guard virtualUSDStartingBalance > 0 else {
                throw ConfigurationError.invalidDefault("virtualUSDStartingBalance")
            }
        }
    }

    public let binanceCredentials: ExchangeCredentials
    public let coinbaseCredentials: ExchangeCredentials
    public let krakenCredentials: ExchangeCredentials
    public let geminiCredentials: ExchangeCredentials
    public let tradingPairs: [TradingPair]
    public let thresholds: Thresholds
    public let defaults: Defaults

    public init(
        binanceCredentials: ExchangeCredentials,
        coinbaseCredentials: ExchangeCredentials,
        krakenCredentials: ExchangeCredentials,
        geminiCredentials: ExchangeCredentials,
        tradingPairs: [TradingPair],
        thresholds: Thresholds,
        defaults: Defaults = Defaults()
    ) {
        self.binanceCredentials = binanceCredentials
        self.coinbaseCredentials = coinbaseCredentials
        self.krakenCredentials = krakenCredentials
        self.geminiCredentials = geminiCredentials
        self.tradingPairs = tradingPairs
        self.thresholds = thresholds
        self.defaults = defaults
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        binanceCredentials = try container.decode(ExchangeCredentials.self, forKey: .binanceCredentials)
        coinbaseCredentials = try container.decode(ExchangeCredentials.self, forKey: .coinbaseCredentials)
        krakenCredentials = try container.decode(ExchangeCredentials.self, forKey: .krakenCredentials)
        geminiCredentials = try container.decode(ExchangeCredentials.self, forKey: .geminiCredentials)
        tradingPairs = try container.decode([TradingPair].self, forKey: .tradingPairs)
        thresholds = try container.decode(Thresholds.self, forKey: .thresholds)
        defaults = try container.decodeIfPresent(Defaults.self, forKey: .defaults) ?? Defaults()
    }

    public func validate() throws {
        try binanceCredentials.validate(exchange: "Binance")
        try coinbaseCredentials.validate(exchange: "Coinbase")
        try krakenCredentials.validate(exchange: "Kraken")
        try geminiCredentials.validate(exchange: "Gemini")

        guard !tradingPairs.isEmpty else {
            throw ConfigurationError.noTradingPairs
        }

        try tradingPairs.forEach { try $0.validate() }
        try thresholds.validate()
        try defaults.validate()
    }
}

public enum ConfigurationError: Error, LocalizedError, Sendable, Equatable {
    case missingAPIKey(String)
    case missingAPISecret(String)
    case invalidTradingPair(String)
    case noTradingPairs
    case invalidThreshold(String)
    case invalidDefault(String)
    case fileNotFound(String)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let exchange):
            return "Missing API key for \(exchange)."
        case .missingAPISecret(let exchange):
            return "Missing API secret for \(exchange)."
        case .invalidTradingPair(let symbol):
            return "Invalid trading pair: \(symbol)."
        case .noTradingPairs:
            return "At least one trading pair is required."
        case .invalidThreshold(let name):
            return "Threshold '\(name)' must be greater than zero."
        case .invalidDefault(let name):
            return "Default value '\(name)' must be greater than zero."
        case .fileNotFound(let path):
            return "Configuration file not found at path \(path)."
        case .invalidJSON(let reason):
            return "Invalid configuration JSON: \(reason)."
        }
    }

    public func toArbitrageError() -> ArbitrageError {
        switch self {
        case .missingAPIKey(let exchange):
            return .logic(.invalidConfiguration(field: "apiKey", reason: "Missing API key for \(exchange)"))
        case .missingAPISecret(let exchange):
            return .logic(.invalidConfiguration(field: "apiSecret", reason: "Missing API secret for \(exchange)"))
        case .invalidTradingPair(let symbol):
            return .logic(.invalidConfiguration(field: "tradingPairs", reason: "Invalid trading pair: \(symbol)"))
        case .noTradingPairs:
            return .logic(.invalidConfiguration(field: "tradingPairs", reason: "At least one trading pair is required"))
        case .invalidThreshold(let name):
            return .logic(.invalidConfiguration(field: name, reason: "Must be greater than zero"))
        case .invalidDefault(let name):
            return .logic(.invalidConfiguration(field: name, reason: "Must be greater than zero"))
        case .fileNotFound(let path):
            return .logic(.invalidConfiguration(field: "configFile", reason: "File not found at path \(path)"))
        case .invalidJSON(let reason):
            return .logic(.invalidConfiguration(field: "configJSON", reason: reason))
        }
    }
}
