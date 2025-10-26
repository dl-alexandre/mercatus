import Foundation
import Testing
@testable import Core
@testable import Utils

@Suite("Configuration Validation Tests")
struct ConfigurationValidationTests {

    @Test("Valid configuration passes all checks")
    func validConfiguration() throws {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "binance_key_123", apiSecret: "binance_secret_456"),
            coinbaseCredentials: .init(apiKey: "coinbase_key_789", apiSecret: "coinbase_secret_012"),
            krakenCredentials: .init(apiKey: "kraken_key_345", apiSecret: "kraken_secret_678"),
            geminiCredentials: .init(apiKey: "gemini_key_901", apiSecret: "gemini_secret_234"),
            tradingPairs: [
                TradingPair(base: "BTC", quote: "USD"),
                TradingPair(base: "ETH", quote: "USD")
            ],
            thresholds: .init(
                minimumSpreadPercentage: 0.5,
                maximumLatencyMilliseconds: 150.0
            ),
            defaults: .init(virtualUSDStartingBalance: 10_000)
        )

        try config.validate()
    }

    @Test("Missing Binance API key throws error")
    func missingBinanceApiKey() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150),
            defaults: .init()
        )

        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }

    @Test("Missing Binance API secret throws error")
    func missingBinanceApiSecret() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key", apiSecret: ""),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150),
            defaults: .init()
        )

        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }

    @Test("Whitespace-only API key throws error")
    func whitespaceOnlyApiKey() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "   ", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150),
            defaults: .init()
        )

        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }

    @Test("Missing Coinbase credentials throws error")
    func missingCoinbaseCredentials() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "", apiSecret: ""),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150),
            defaults: .init()
        )

        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }

    @Test("Empty trading pairs throws error")
    func emptyTradingPairs() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150),
            defaults: .init()
        )

        #expect(throws: ConfigurationError.noTradingPairs) {
            try config.validate()
        }
    }

    @Test("Invalid trading pair format throws error")
    func invalidTradingPairFormat() {
        let pair = TradingPair(base: "", quote: "USD")

        #expect(throws: ConfigurationError.self) {
            try pair.validate()
        }
    }

    @Test("Trading pair with same base and quote throws error")
    func sameCurrencyTradingPair() {
        let pair = TradingPair(base: "BTC", quote: "BTC")

        #expect(throws: ConfigurationError.self) {
            try pair.validate()
        }
    }

    @Test("Trading pair with too long symbol throws error")
    func tooLongSymbol() {
        let pair = TradingPair(base: "VERYLONGSYMBOL", quote: "USD")

        #expect(throws: ConfigurationError.self) {
            try pair.validate()
        }
    }

    @Test("Trading pair normalizes to uppercase")
    func symbolNormalization() {
        let pair = TradingPair(base: "btc", quote: "usd")

        #expect(pair.base == "BTC")
        #expect(pair.quote == "USD")
        #expect(pair.symbol == "BTC-USD")
    }

    @Test("Valid trading pair symbols")
    func validTradingPairSymbols() throws {
        let pairs = [
            TradingPair(base: "BTC", quote: "USD"),
            TradingPair(base: "ETH", quote: "EUR"),
            TradingPair(base: "DOGE", quote: "USDT"),
            TradingPair(base: "ADA", quote: "BTC")
        ]

        for pair in pairs {
            try pair.validate()
        }
    }

    @Test("Zero spread threshold throws error")
    func zeroSpreadThreshold() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.0, maximumLatencyMilliseconds: 150),
            defaults: .init()
        )

        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }

    @Test("Negative spread threshold throws error")
    func negativeSpreadThreshold() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: -0.5, maximumLatencyMilliseconds: 150),
            defaults: .init()
        )

        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }

    @Test("Zero latency threshold throws error")
    func zeroLatencyThreshold() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 0.0),
            defaults: .init()
        )

        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }

    @Test("Negative latency threshold throws error")
    func negativeLatencyThreshold() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: -150),
            defaults: .init()
        )

        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }

    @Test("Zero virtual balance throws error")
    func zeroVirtualBalance() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150),
            defaults: .init(virtualUSDStartingBalance: 0.0)
        )

        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }

    @Test("Negative virtual balance throws error")
    func negativeVirtualBalance() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150),
            defaults: .init(virtualUSDStartingBalance: -1000)
        )

        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }

    @Test("API key masking shows last 4 characters")
    func apiKeyMasking() {
        let creds = ArbitrageConfig.ExchangeCredentials(
            apiKey: "my_secret_api_key_12345",
            apiSecret: "secret"
        )

        #expect(creds.maskedKey == "****2345")
    }

    @Test("Short API key masking shows only asterisks")
    func shortApiKeyMasking() {
        let creds = ArbitrageConfig.ExchangeCredentials(
            apiKey: "abc",
            apiSecret: "secret"
        )

        #expect(creds.maskedKey == "****")
    }

    @Test("Configuration error provides descriptive messages")
    func errorMessages() {
        let errors: [ConfigurationError] = [
            .missingAPIKey("Binance"),
            .missingAPISecret("Coinbase"),
            .invalidTradingPair("INVALID"),
            .noTradingPairs,
            .invalidThreshold("minimumSpreadPercentage"),
            .invalidDefault("virtualUSDStartingBalance")
        ]

        for error in errors {
            let description = error.errorDescription
            #expect(description != nil)
            #expect(!description!.isEmpty)
        }
    }

    @Test("Configuration is equatable")
    func configurationEquality() {
        let config1 = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key1", apiSecret: "secret1"),
            coinbaseCredentials: .init(apiKey: "key2", apiSecret: "secret2"),
            krakenCredentials: .init(apiKey: "key3", apiSecret: "secret3"),
            geminiCredentials: .init(apiKey: "key4", apiSecret: "secret4"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150),
            defaults: .init(virtualUSDStartingBalance: 10_000)
        )

        let config2 = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key1", apiSecret: "secret1"),
            coinbaseCredentials: .init(apiKey: "key2", apiSecret: "secret2"),
            krakenCredentials: .init(apiKey: "key3", apiSecret: "secret3"),
            geminiCredentials: .init(apiKey: "key4", apiSecret: "secret4"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150),
            defaults: .init(virtualUSDStartingBalance: 10_000)
        )

        let config3 = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "different", apiSecret: "secret1"),
            coinbaseCredentials: .init(apiKey: "key2", apiSecret: "secret2"),
            krakenCredentials: .init(apiKey: "key3", apiSecret: "secret3"),
            geminiCredentials: .init(apiKey: "key4", apiSecret: "secret4"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150),
            defaults: .init(virtualUSDStartingBalance: 10_000)
        )

        #expect(config1 == config2)
        #expect(config1 != config3)
    }

    @Test("Trading pair is hashable")
    func tradingPairHashable() {
        let pair1 = TradingPair(base: "BTC", quote: "USD")
        let pair2 = TradingPair(base: "BTC", quote: "USD")
        let pair3 = TradingPair(base: "ETH", quote: "USD")

        var set = Set<TradingPair>()
        set.insert(pair1)
        set.insert(pair2)
        set.insert(pair3)

        #expect(set.count == 2)
    }

    @Test("Multiple invalid trading pairs detected")
    func multipleInvalidTradingPairs() {
        let config = ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [
                TradingPair(base: "BTC", quote: "USD"),
                TradingPair(base: "ETH", quote: "ETH")
            ],
            thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150),
            defaults: .init()
        )

        #expect(throws: ConfigurationError.self) {
            try config.validate()
        }
    }
}

@Suite("ConfigurationManager Tests")
struct ConfigurationManagerTests {

    @Test("Load from environment variables")
    func loadFromEnvironment() throws {
        let env = [
            "ARBITRAGE_BINANCE_API_KEY": "binance_key",
            "ARBITRAGE_BINANCE_API_SECRET": "binance_secret",
            "ARBITRAGE_COINBASE_API_KEY": "coinbase_key",
            "ARBITRAGE_COINBASE_API_SECRET": "coinbase_secret",
            "ARBITRAGE_KRAKEN_API_KEY": "kraken_key",
            "ARBITRAGE_KRAKEN_API_SECRET": "kraken_secret",
            "ARBITRAGE_GEMINI_API_KEY": "gemini_key",
            "ARBITRAGE_GEMINI_API_SECRET": "gemini_secret",
            "ARBITRAGE_TRADING_PAIRS": "BTC-USD,ETH-USD,DOGE-USDT",
            "ARBITRAGE_MIN_SPREAD_PERCENT": "0.75",
            "ARBITRAGE_MAX_LATENCY_MS": "200",
            "ARBITRAGE_VIRTUAL_BALANCE_USD": "25000"
        ]

        let manager = ConfigurationManager(environment: env)
        let config = try manager.load()

        #expect(config.binanceCredentials.apiKey == "binance_key")
        #expect(config.binanceCredentials.apiSecret == "binance_secret")
        #expect(config.coinbaseCredentials.apiKey == "coinbase_key")
        #expect(config.coinbaseCredentials.apiSecret == "coinbase_secret")
        #expect(config.tradingPairs.count == 3)
        #expect(config.tradingPairs[0].symbol == "BTC-USD")
        #expect(config.tradingPairs[1].symbol == "ETH-USD")
        #expect(config.tradingPairs[2].symbol == "DOGE-USDT")
        #expect(config.thresholds.minimumSpreadPercentage == 0.75)
        #expect(config.thresholds.maximumLatencyMilliseconds == 200)
        #expect(config.defaults.virtualUSDStartingBalance == 25000)
    }

    @Test("Load from environment with defaults")
    func loadFromEnvironmentWithDefaults() throws {
        let env = [
            "ARBITRAGE_BINANCE_API_KEY": "key1",
            "ARBITRAGE_BINANCE_API_SECRET": "secret1",
            "ARBITRAGE_COINBASE_API_KEY": "key2",
            "ARBITRAGE_COINBASE_API_SECRET": "secret2",
            "ARBITRAGE_KRAKEN_API_KEY": "key3",
            "ARBITRAGE_KRAKEN_API_SECRET": "secret3",
            "ARBITRAGE_GEMINI_API_KEY": "key4",
            "ARBITRAGE_GEMINI_API_SECRET": "secret4",
            "ARBITRAGE_TRADING_PAIRS": "BTC-USD"
        ]

        let manager = ConfigurationManager(environment: env)
        let config = try manager.load()

        #expect(config.thresholds.minimumSpreadPercentage == 0.5)
        #expect(config.thresholds.maximumLatencyMilliseconds == 150.0)
        #expect(config.defaults.virtualUSDStartingBalance == 10_000)
    }

    @Test("Load from environment handles slash-separated pairs")
    func slashSeparatedPairs() throws {
        let env = [
            "ARBITRAGE_BINANCE_API_KEY": "key",
            "ARBITRAGE_BINANCE_API_SECRET": "secret",
            "ARBITRAGE_COINBASE_API_KEY": "key",
            "ARBITRAGE_COINBASE_API_SECRET": "secret",
            "ARBITRAGE_KRAKEN_API_KEY": "key",
            "ARBITRAGE_KRAKEN_API_SECRET": "secret",
            "ARBITRAGE_GEMINI_API_KEY": "key",
            "ARBITRAGE_GEMINI_API_SECRET": "secret",
            "ARBITRAGE_TRADING_PAIRS": "BTC/USD,ETH/EUR"
        ]

        let manager = ConfigurationManager(environment: env)
        let config = try manager.load()

        #expect(config.tradingPairs.count == 2)
        #expect(config.tradingPairs[0].symbol == "BTC-USD")
        #expect(config.tradingPairs[1].symbol == "ETH-EUR")
    }

    @Test("Load from environment filters empty trading pairs")
    func filterEmptyTradingPairs() throws {
        let env = [
            "ARBITRAGE_BINANCE_API_KEY": "key",
            "ARBITRAGE_BINANCE_API_SECRET": "secret",
            "ARBITRAGE_COINBASE_API_KEY": "key",
            "ARBITRAGE_COINBASE_API_SECRET": "secret",
            "ARBITRAGE_KRAKEN_API_KEY": "key",
            "ARBITRAGE_KRAKEN_API_SECRET": "secret",
            "ARBITRAGE_GEMINI_API_KEY": "key",
            "ARBITRAGE_GEMINI_API_SECRET": "secret",
            "ARBITRAGE_TRADING_PAIRS": "BTC-USD, , ETH-USD,  "
        ]

        let manager = ConfigurationManager(environment: env)
        let config = try manager.load()

        #expect(config.tradingPairs.count == 2)
    }

    @Test("Load from environment with missing credentials throws")
    func missingCredentials() {
        let env = [
            "ARBITRAGE_BINANCE_API_KEY": "key",
            "ARBITRAGE_TRADING_PAIRS": "BTC-USD"
        ]

        let manager = ConfigurationManager(environment: env)

        #expect(throws: ConfigurationError.self) {
            try manager.load()
        }
    }

    @Test("Load from environment with no pairs throws")
    func noPairs() {
        let env = [
            "ARBITRAGE_BINANCE_API_KEY": "key",
            "ARBITRAGE_BINANCE_API_SECRET": "secret",
            "ARBITRAGE_COINBASE_API_KEY": "key",
            "ARBITRAGE_COINBASE_API_SECRET": "secret",
            "ARBITRAGE_KRAKEN_API_KEY": "key",
            "ARBITRAGE_KRAKEN_API_SECRET": "secret",
            "ARBITRAGE_GEMINI_API_KEY": "key",
            "ARBITRAGE_GEMINI_API_SECRET": "secret",
            "ARBITRAGE_TRADING_PAIRS": ""
        ]

        let manager = ConfigurationManager(environment: env)

        #expect(throws: ConfigurationError.noTradingPairs) {
            try manager.load()
        }
    }

    @Test("Load from JSON file")
    func loadFromJsonFile() throws {
        let json = """
        {
            "binanceCredentials": {
                "apiKey": "json_binance_key",
                "apiSecret": "json_binance_secret"
            },
            "coinbaseCredentials": {
                "apiKey": "json_coinbase_key",
                "apiSecret": "json_coinbase_secret"
            },
            "krakenCredentials": {
                "apiKey": "json_kraken_key",
                "apiSecret": "json_kraken_secret"
            },
            "geminiCredentials": {
                "apiKey": "json_gemini_key",
                "apiSecret": "json_gemini_secret"
            },
            "tradingPairs": [
                {"base": "BTC", "quote": "USD"},
                {"base": "ETH", "quote": "EUR"}
            ],
            "thresholds": {
                "minimumSpreadPercentage": 1.0,
                "maximumLatencyMilliseconds": 100.0
            },
            "defaults": {
                "virtualUSDStartingBalance": 50000.0
            }
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test_config_\(UUID().uuidString).json")
        try json.write(to: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configPath) }

        let manager = ConfigurationManager()
        let config = try manager.load(path: configPath.path)

        #expect(config.binanceCredentials.apiKey == "json_binance_key")
        #expect(config.tradingPairs.count == 2)
        #expect(config.thresholds.minimumSpreadPercentage == 1.0)
        #expect(config.defaults.virtualUSDStartingBalance == 50000.0)
    }

    @Test("Load from non-existent file throws")
    func nonExistentFile() {
        let manager = ConfigurationManager()

        #expect(throws: ConfigurationError.fileNotFound("/path/does/not/exist")) {
            try manager.load(path: "/path/does/not/exist")
        }
    }

    @Test("Load from invalid JSON throws")
    func invalidJson() throws {
        let invalidJson = "{ invalid json }"

        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("invalid_\(UUID().uuidString).json")
        try invalidJson.write(to: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configPath) }

        let manager = ConfigurationManager()

        #expect(throws: ConfigurationError.self) {
            try manager.load(path: configPath.path)
        }
    }

    @Test("Load prefers explicit file over environment")
    func preferExplicitFile() throws {
        let json = """
        {
            "binanceCredentials": {
                "apiKey": "file_key",
                "apiSecret": "file_secret"
            },
            "coinbaseCredentials": {
                "apiKey": "file_key",
                "apiSecret": "file_secret"
            },
            "krakenCredentials": {
                "apiKey": "file_key",
                "apiSecret": "file_secret"
            },
            "geminiCredentials": {
                "apiKey": "file_key",
                "apiSecret": "file_secret"
            },
            "tradingPairs": [
                {"base": "BTC", "quote": "USD"}
            ],
            "thresholds": {
                "minimumSpreadPercentage": 0.5,
                "maximumLatencyMilliseconds": 150.0
            }
        }
        """

        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("explicit_\(UUID().uuidString).json")
        try json.write(to: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configPath) }

        let env = [
            "ARBITRAGE_BINANCE_API_KEY": "env_key",
            "ARBITRAGE_BINANCE_API_SECRET": "env_secret",
            "ARBITRAGE_COINBASE_API_KEY": "env_key",
            "ARBITRAGE_COINBASE_API_SECRET": "env_secret",
            "ARBITRAGE_KRAKEN_API_KEY": "env_key",
            "ARBITRAGE_KRAKEN_API_SECRET": "env_secret",
            "ARBITRAGE_GEMINI_API_KEY": "env_key",
            "ARBITRAGE_GEMINI_API_SECRET": "env_secret",
            "ARBITRAGE_TRADING_PAIRS": "ETH-USD"
        ]

        let manager = ConfigurationManager(environment: env)
        let config = try manager.load(path: configPath.path)

        #expect(config.binanceCredentials.apiKey == "file_key")
        #expect(config.tradingPairs[0].symbol == "BTC-USD")
    }
}
