import Foundation
import Utils
import MLPatternEngine

public class RobinhoodMLIntegration: @unchecked Sendable {
    private let mlEngine: MLPatternEngine
    private let marketDataProvider: RobinhoodMarketDataProviderProtocol
    private let logger: StructuredLogger
    private var isRunning = false

    public init(
        mlEngine: MLPatternEngine,
        marketDataProvider: RobinhoodMarketDataProviderProtocol,
        logger: StructuredLogger
    ) {
        self.mlEngine = mlEngine
        self.marketDataProvider = marketDataProvider
        self.logger = logger
    }

    public func start() async throws {
        guard !isRunning else {
            logger.warn(component: "RobinhoodMLIntegration", event: "Already running")
            return
        }

        isRunning = true

        try await mlEngine.start()

        logger.info(component: "RobinhoodMLIntegration", event: "ML integration started with Robinhood")
    }

    public func stop() async throws {
        guard isRunning else {
            logger.warn(component: "RobinhoodMLIntegration", event: "Not running")
            return
        }

        isRunning = false

        try await mlEngine.stop()

        logger.info(component: "RobinhoodMLIntegration", event: "ML integration stopped")
    }

    public func getPredictionForCoin(symbol: String, timeHorizon: TimeInterval = 3600) async throws -> PredictionResponse {
        try await mlEngine.getPrediction(
            for: symbol,
            timeHorizon: timeHorizon,
            modelType: .pricePrediction
        )
    }

    public func getTrendClassification(symbol: String) async throws -> TrendClassification {
        let historicalData = try await mlEngine.getLatestData(symbols: [symbol])

        guard let trendClassifier = mlEngine.trendClassifier else {
            throw MLIntegrationError.trendClassificationUnavailable
        }

        return try await trendClassifier.classifyTrend(
            for: symbol,
            historicalData: historicalData
        )
    }

    public func getVolatilityPrediction(symbol: String) async throws -> PredictionResponse {
        try await mlEngine.getPrediction(
            for: symbol,
            timeHorizon: 3600,
            modelType: .volatilityPrediction
        )
    }

    public func getPatternsForSymbol(symbol: String) async throws -> [DetectedPattern] {
        try await mlEngine.detectPatterns(for: symbol)
    }

    public func updateDataFromRobinhood(symbol: String) async throws {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-7 * 24 * 60 * 60)

        let dataPoints = try await marketDataProvider.fetchOHLCVData(
            symbol: symbol,
            startDate: startDate,
            endDate: endDate
        )

        guard let dataIngestion = mlEngine.dataIngestion else {
            throw MLIntegrationError.dataIngestionUnavailable
        }

        logger.info(
            component: "RobinhoodMLIntegration",
            event: "Updated data from Robinhood",
            data: ["symbol": symbol, "data_points": String(dataPoints.count)]
        )
    }
}

public enum MLIntegrationError: Error {
    case trendClassificationUnavailable
    case dataIngestionUnavailable
    case mlEngineNotRunning
}

extension MLPatternEngine {
    var trendClassifier: (any TrendClassificationProtocol)? {
        nil
    }

    var dataIngestion: DataIngestionProtocol? {
        nil
    }
}
