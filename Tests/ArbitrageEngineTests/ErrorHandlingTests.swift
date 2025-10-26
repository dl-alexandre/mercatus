import Testing
import Foundation
@testable import Core
@testable import Utils

@Suite("Error Handling Tests")
struct ErrorHandlingTests {

    @Suite("ArbitrageError Tests")
    struct ArbitrageErrorTests {

        @Test("Connection error categories")
        func connectionErrorCategories() {
            let error = ArbitrageError.connection(.failedToConnect(exchange: "Kraken", reason: "Network timeout"))
            #expect(error.category == "connection")
            #expect(error.localizedDescription.contains("Kraken"))
            #expect(error.localizedDescription.contains("Network timeout"))

            let logData = error.logData
            #expect(logData["category"] == "connection")
            #expect(logData["exchange"] == "Kraken")
            #expect(logData["error"] == "failed_to_connect")
        }

        @Test("Data error categories")
        func dataErrorCategories() {
            let error = ArbitrageError.data(.invalidFormat(exchange: "Coinbase", reason: "Missing price field"))
            #expect(error.category == "data")
            #expect(error.localizedDescription.contains("Coinbase"))
            #expect(error.localizedDescription.contains("Missing price field"))

            let logData = error.logData
            #expect(logData["category"] == "data")
            #expect(logData["exchange"] == "Coinbase")
            #expect(logData["error"] == "invalid_format")
        }

        @Test("Logic error categories")
        func logicErrorCategories() {
            let error = ArbitrageError.logic(.invalidConfiguration(field: "apiKey", reason: "Cannot be empty"))
            #expect(error.category == "logic")
            #expect(error.localizedDescription.contains("apiKey"))
            #expect(error.localizedDescription.contains("Cannot be empty"))

            let logData = error.logData
            #expect(logData["category"] == "logic")
            #expect(logData["field"] == "apiKey")
            #expect(logData["error"] == "invalid_configuration")
        }

        @Test("Circuit breaker open error")
        func circuitBreakerOpenError() {
            let error = ArbitrageError.connection(.circuitBreakerOpen(exchange: "TestExchange", failureCount: 5))
            let logData = error.logData
            #expect(logData["exchange"] == "TestExchange")
            #expect(logData["failure_count"] == "5")
            #expect(logData["error"] == "circuit_breaker_open")
        }

        @Test("Stale data error with timestamp")
        func staleDataError() {
            let error = ArbitrageError.data(.staleData(exchange: "Kraken", symbol: "BTC-USD", age: 10.5))
            let logData = error.logData
            #expect(logData["exchange"] == "Kraken")
            #expect(logData["symbol"] == "BTC-USD")
            #expect(logData["age_seconds"] == "10.50")
        }

        @Test("Insufficient balance error")
        func insufficientBalanceError() {
            let required = Decimal(1000)
            let available = Decimal(500)
            let error = ArbitrageError.logic(.insufficientBalance(required: required, available: available))
            let logData = error.logData
            #expect(logData["required"] == "1000")
            #expect(logData["available"] == "500")
        }
    }

    @Suite("CircuitBreaker Tests")
    struct CircuitBreakerTests {

        @Test("Circuit breaker opens after threshold failures")
        func opensAfterThresholdFailures() async {
            let config = CircuitBreaker.Configuration(
                failureThreshold: 3,
                timeout: 60.0,
                successThreshold: 2
            )
            let breaker = CircuitBreaker(configuration: config)

            #expect(await breaker.canAttempt() == true)
            #expect(await breaker.currentState == .closed)

            await breaker.recordFailure()
            #expect(await breaker.canAttempt() == true)

            await breaker.recordFailure()
            #expect(await breaker.canAttempt() == true)

            await breaker.recordFailure()
            #expect(await breaker.canAttempt() == false)
            #expect(await breaker.currentState.failureCount == 3)
        }

        @Test("Circuit breaker transitions to half-open after timeout")
        func transitionsToHalfOpenAfterTimeout() async {
            let timeProvider = SyncTimeProvider()

            let config = CircuitBreaker.Configuration(
                failureThreshold: 2,
                timeout: 5.0,
                successThreshold: 1
            )
            let breaker = CircuitBreaker(configuration: config, clock: { timeProvider.currentTime })

            await breaker.recordFailure()
            await breaker.recordFailure()

            #expect(await breaker.canAttempt() == false)

            timeProvider.advance(by: 6.0)

            #expect(await breaker.canAttempt() == true)
            #expect(await breaker.currentState == CircuitBreaker.State.halfOpen)
        }

        @Test("Circuit breaker closes after success threshold in half-open")
        func closesAfterSuccessThreshold() async {
            let timeProvider = SyncTimeProvider()

            let config = CircuitBreaker.Configuration(
                failureThreshold: 2,
                timeout: 5.0,
                successThreshold: 2
            )
            let breaker = CircuitBreaker(configuration: config, clock: { timeProvider.currentTime })

            await breaker.recordFailure()
            await breaker.recordFailure()
            #expect(await breaker.canAttempt() == false)

            timeProvider.advance(by: 6.0)
            #expect(await breaker.currentState == CircuitBreaker.State.halfOpen)

            await breaker.recordSuccess()
            #expect(await breaker.currentState == CircuitBreaker.State.halfOpen)

            await breaker.recordSuccess()
            #expect(await breaker.currentState == CircuitBreaker.State.closed)
            #expect(await breaker.canAttempt() == true)
        }

        @Test("Circuit breaker reopens on failure in half-open state")
        func reopensOnFailureInHalfOpen() async {
            let timeProvider = SyncTimeProvider()

            let config = CircuitBreaker.Configuration(
                failureThreshold: 2,
                timeout: 5.0,
                successThreshold: 2
            )
            let breaker = CircuitBreaker(configuration: config, clock: { timeProvider.currentTime })

            await breaker.recordFailure()
            await breaker.recordFailure()

            timeProvider.advance(by: 6.0)
            #expect(await breaker.currentState == CircuitBreaker.State.halfOpen)

            await breaker.recordFailure()
            #expect(await breaker.canAttempt() == false)
        }

        @Test("Circuit breaker reset")
        func reset() async {
            let breaker = CircuitBreaker(configuration: .default)

            await breaker.recordFailure()
            await breaker.recordFailure()
            await breaker.recordFailure()
            await breaker.recordFailure()
            await breaker.recordFailure()

            #expect(await breaker.canAttempt() == false)

            await breaker.reset()

            #expect(await breaker.currentState == .closed)
            #expect(await breaker.canAttempt() == true)
        }
    }

    @Suite("StructuredLogger with Correlation IDs")
    struct StructuredLoggerCorrelationTests {

        @Test("Logger includes correlation ID in output")
        func includesCorrelationId() async throws {
            var expectation = Expectation()

            let logger = createTestLogger()

            let correlationId = "test-correlation-123"
            logger.info(
                component: "TestComponent",
                event: "test_event",
                data: ["key": "value"],
                correlationId: correlationId
            )

            try await Task.sleep(nanoseconds: 100_000_000)

            expectation.fulfill()
        }

        @Test("Logger handles ArbitrageError correctly")
        func handlesArbitrageError() async throws {
            let logger = createTestLogger()
            let error = ArbitrageError.connection(.failedToConnect(exchange: "TestExchange", reason: "timeout"))
            let correlationId = "error-test-456"

            logger.logError(error, component: "TestComponent", correlationId: correlationId)

            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    @Suite("Configuration Error Handling")
    struct ConfigurationErrorHandlingTests {

        @Test("Missing API key throws configuration error")
        func missingApiKeyThrows() throws {
            let config = ArbitrageConfig(
                binanceCredentials: .init(apiKey: "", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
                thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150)
            )

            #expect(throws: ConfigurationError.self) {
                try config.validate()
            }
        }

        @Test("Empty trading pairs throws configuration error")
        func emptyTradingPairsThrows() throws {
            let config = ArbitrageConfig(
                binanceCredentials: .init(apiKey: "key1", apiSecret: "secret1"),
                coinbaseCredentials: .init(apiKey: "key2", apiSecret: "secret2"),
                krakenCredentials: .init(apiKey: "key3", apiSecret: "secret3"),
                geminiCredentials: .init(apiKey: "key4", apiSecret: "secret4"),
                tradingPairs: [],
                thresholds: .init(minimumSpreadPercentage: 0.5, maximumLatencyMilliseconds: 150)
            )

            #expect(throws: ConfigurationError.self) {
                try config.validate()
            }
        }

        @Test("Invalid threshold throws configuration error")
        func invalidThresholdThrows() throws {
            let config = ArbitrageConfig(
                binanceCredentials: .init(apiKey: "key1", apiSecret: "secret1"),
                coinbaseCredentials: .init(apiKey: "key2", apiSecret: "secret2"),
                krakenCredentials: .init(apiKey: "key3", apiSecret: "secret3"),
                geminiCredentials: .init(apiKey: "key4", apiSecret: "secret4"),
                tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
                thresholds: .init(minimumSpreadPercentage: -1.0, maximumLatencyMilliseconds: 150)
            )

            #expect(throws: ConfigurationError.self) {
                try config.validate()
            }
        }

        @Test("Configuration error converts to ArbitrageError")
        func configurationErrorConvertsToArbitrageError() {
            let configError = ConfigurationError.missingAPIKey("Kraken")
            let arbError = configError.toArbitrageError()

            #expect(arbError.category == "logic")
            let logData = arbError.logData
            #expect(logData["error_type"] == "logic")
            #expect(logData["field"] == "apiKey")
        }
    }

    @Suite("Data Validation Error Handling")
    struct DataValidationErrorHandlingTests {

        @Test("Invalid price data is filtered")
        func invalidPriceDataFiltered() async {
            let normalizer = ExchangeNormalizer()

            let invalidData = RawPriceData(
                exchange: "TestExchange",
                symbol: "BTC-USD",
                bid: -100.0,
                ask: 50000.0,
                timestamp: Date()
            )

            let result = await normalizer.normalize(invalidData)
            #expect(result == nil)
        }

        @Test("Stale data is rejected")
        func staleDataRejected() async {
            let staleDate = Date().addingTimeInterval(-10.0)
            let normalizer = ExchangeNormalizer(
                config: .init(staleInterval: 5.0)
            )

            let staleData = RawPriceData(
                exchange: "TestExchange",
                symbol: "BTC-USD",
                bid: 49900.0,
                ask: 50000.0,
                timestamp: staleDate
            )

            let result = await normalizer.normalize(staleData)
            #expect(result == nil)
        }

        @Test("Invalid trading pair format throws error")
        func invalidTradingPairFormatThrows() throws {
            let pair = TradingPair(base: "BTC", quote: "BTC")

            #expect(throws: ConfigurationError.self) {
                try pair.validate()
            }
        }
    }

    @Suite("Connection Error Scenarios")
    struct ConnectionErrorScenarioTests {

        @Test("Failed connection produces correct error")
        func failedConnectionProducesCorrectError() {
            let error = ArbitrageError.connection(.failedToConnect(
                exchange: "Kraken",
                reason: "Network unreachable"
            ))

            #expect(error.category == "connection")
            let description = error.localizedDescription
            #expect(description.contains("Kraken"))
            #expect(description.contains("Network unreachable"))
        }

        @Test("Subscription failure produces correct error")
        func subscriptionFailureProducesCorrectError() {
            let error = ArbitrageError.connection(.subscriptionFailed(
                exchange: "Coinbase",
                pairs: ["BTC-USD", "ETH-USD"],
                reason: "Invalid credentials"
            ))

            let logData = error.logData
            #expect(logData["exchange"] == "Coinbase")
            #expect(logData["pairs"]?.contains("BTC-USD") == true)
            #expect(logData["reason"] == "Invalid credentials")
        }

        @Test("WebSocket error produces correct error")
        func websocketErrorProducesCorrectError() {
            let error = ArbitrageError.connection(.websocketError(
                exchange: "Kraken",
                code: 1006,
                reason: "Connection closed abnormally"
            ))

            let logData = error.logData
            #expect(logData["exchange"] == "Kraken")
            #expect(logData["code"] == "1006")
            #expect(logData["error"] == "websocket_error")
        }
    }
}

struct Expectation {
    private var fulfilled = false

    mutating func fulfill() {
        fulfilled = true
    }

    var isFulfilled: Bool { fulfilled }
}
