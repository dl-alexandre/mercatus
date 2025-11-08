import Testing
import Foundation
@testable import MLPatternEngine
@testable import Core
@testable import Utils

struct TestLogger: StructuredLogger {
    func info(component: String, event: String, data: [String: String] = [:]) {}
    func warn(component: String, event: String, data: [String: String] = [:]) {}
    func error(component: String, event: String, data: [String: String] = [:]) {}
    func debug(component: String, event: String, data: [String: String] = [:]) {}
}

private func createTestLogger() -> StructuredLogger {
    return TestLogger()
}

@Suite("Feature Extractor Adapter Tests")
struct FeatureExtractorAdapterTests {

    @Test("createMarketDataPoint should create correct MLPatternEngine.MarketDataPoint instance")
    func testCreateMarketDataPoint() {
        let timestamp = Date()
        let symbol = "BTC-USD"
        let open = 50000.0
        let high = 51000.0
        let low = 49000.0
        let close = 50500.0
        let volume = 1000.0
        let exchange = "test-exchange"

        let point = createMarketDataPoint(
            timestamp: timestamp,
            symbol: symbol,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            exchange: exchange
        )

        #expect(point.timestamp == timestamp)
        #expect(point.symbol == symbol)
        #expect(point.open == open)
        #expect(point.high == high)
        #expect(point.low == low)
        #expect(point.close == close)
        #expect(point.volume == volume)
        #expect(point.exchange == exchange)
    }

    @Test("extractFeaturesAdapter should convert properties and call extractFeatures")
    func testExtractFeaturesAdapter() async throws {
        let logger = createTestLogger()
        let technicalIndicators = TechnicalIndicators()
        let extractor = FeatureExtractor(technicalIndicators: technicalIndicators, logger: logger)

        // Create test data with properties matching MLPatternEngine.MarketDataPoint
        let currentProps = (
            timestamp: Date(),
            symbol: "BTC-USD",
            open: 50000.0,
            high: 51000.0,
            low: 49000.0,
            close: 50500.0,
            volume: 1000.0,
            exchange: "test"
        )

        // Create historical data (need at least 50 points for feature extraction)
        var historicalProps: [(timestamp: Date, symbol: String, open: Double, high: Double, low: Double, close: Double, volume: Double, exchange: String)] = []
        let basePrice = 50000.0

        for i in 0..<60 {
            let price = basePrice + Double(i) * 10.0
            historicalProps.append((
                timestamp: Date().addingTimeInterval(TimeInterval(-60 + i) * 60),
                symbol: "BTC-USD",
                open: price,
                high: price * 1.01,
                low: price * 0.99,
                close: price,
                volume: 1000.0,
                exchange: "test"
            ))
        }

        // Call adapter
        let featureSet = try await extractFeaturesAdapter(
            extractor: extractor,
            currentProps: currentProps,
            historicalProps: historicalProps
        )

        // Verify feature set was created
        #expect(featureSet.timestamp == currentProps.timestamp)
        #expect(featureSet.symbol == currentProps.symbol)
        #expect(!featureSet.features.isEmpty)
    }

    @Test("Adapter should preserve all property values through round-trip")
    func testPropertyRoundTrip() {
        let timestamp = Date(timeIntervalSince1970: 1234567890)
        let symbol = "ETH-USD"
        let open = 3000.0
        let high = 3100.0
        let low = 2900.0
        let close = 3050.0
        let volume = 5000.0
        let exchange = "binance"

        let point = createMarketDataPoint(
            timestamp: timestamp,
            symbol: symbol,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            exchange: exchange
        )

        // Verify all properties round-trip correctly
        #expect(point.timestamp == timestamp, "timestamp should match")
        #expect(point.symbol == symbol, "symbol should match")
        #expect(point.open == open, "open should match")
        #expect(point.high == high, "high should match")
        #expect(point.low == low, "low should match")
        #expect(point.close == close, "close should match")
        #expect(point.volume == volume, "volume should match")
        #expect(point.exchange == exchange, "exchange should match")
    }

    @Test("Adapter should handle edge cases")
    func testEdgeCases() {
        // Test with zero values
        let zeroPoint = createMarketDataPoint(
            timestamp: Date(),
            symbol: "",
            open: 0.0,
            high: 0.0,
            low: 0.0,
            close: 0.0,
            volume: 0.0,
            exchange: ""
        )

        #expect(zeroPoint.open == 0.0)
        #expect(zeroPoint.symbol.isEmpty)

        // Test with very large values
        let largePoint = createMarketDataPoint(
            timestamp: Date(),
            symbol: "TEST",
            open: Double.greatestFiniteMagnitude,
            high: Double.greatestFiniteMagnitude,
            low: 0.0,
            close: Double.greatestFiniteMagnitude,
            volume: Double.greatestFiniteMagnitude,
            exchange: "test"
        )

        #expect(largePoint.open == Double.greatestFiniteMagnitude)
    }
}
