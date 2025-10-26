import Testing
import Foundation
@testable import MLPatternEngine
@testable import Core
@testable import Utils

@Suite("Data Ingestion Tests")
struct DataIngestionTests {

    @Test("Data ingestion service should start and stop correctly")
    func testDataIngestionStartStop() async throws {
        let logger = createTestLogger()
        let database = try SQLiteTimeSeriesDatabase(location: .inMemory, logger: logger)
        let timeSeriesStore = TimeSeriesStore(database: database, logger: logger)
        let qualityValidator = DataQualityValidator(logger: logger)

        let exchangeConnectors: [String: any ExchangeConnector] = [:]
        let ingestionService = DataIngestionService(
            exchangeConnectors: exchangeConnectors,
            qualityValidator: qualityValidator,
            timeSeriesStore: timeSeriesStore,
            logger: logger
        )

        try await ingestionService.startIngestion()
        try await ingestionService.stopIngestion()
    }


    @Test("Technical indicators should calculate RSI correctly")
    func testRSICalculation() {
        let indicators = TechnicalIndicators()
        let prices = [44.0, 44.25, 44.5, 44.75, 45.0, 45.25, 45.5, 45.75, 46.0, 46.25, 46.5, 46.75, 47.0, 47.25, 47.5]

        let rsi = indicators.calculateRSI(prices: prices, period: 14)

        #expect(!rsi.isEmpty)
        #expect(rsi.allSatisfy { $0 >= 0.0 && $0 <= 100.0 })
    }

    @Test("Feature extractor should extract features from market data")
    func testFeatureExtraction() async throws {
        let logger = createTestLogger()
        let indicators = TechnicalIndicators()
        let extractor = FeatureExtractor(technicalIndicators: indicators, logger: logger)

        var dataPoints: [MarketDataPoint] = []
        let basePrice = 50000.0

        for i in 0..<100 {
            let price = basePrice + Double(i) * 10.0
            let dataPoint = MarketDataPoint(
                timestamp: Date().addingTimeInterval(TimeInterval(i * 60)),
                symbol: "BTC-USD",
                open: price,
                high: price + 100.0,
                low: price - 100.0,
                close: price + 50.0,
                volume: 1000.0 + Double(i),
                exchange: "test"
            )
            dataPoints.append(dataPoint)
        }

        let features = try await extractor.extractFeatures(from: dataPoints)

        #expect(!features.isEmpty)
        #expect(features.first?.features.count ?? 0 > 10)
    }
}
