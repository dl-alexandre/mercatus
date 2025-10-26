import Foundation
import MLPatternEngine
import Utils
import Core

public class MLPatternEngineFactory {
    private let logger: StructuredLogger
    private let useMLXModels: Bool

    public init(logger: StructuredLogger, useMLXModels: Bool = false) {
        self.logger = logger
        self.useMLXModels = false // MLX integration not yet implemented
    }

    public func createMLPatternEngine() async throws -> MLPatternEngine {
        logger.info(component: "MLPatternEngineFactory", event: "Creating MLPatternEngine instance")

        let database = try SQLiteTimeSeriesDatabase(logger: logger)
        let timeSeriesStore = TimeSeriesStore(database: database, logger: logger)
        let qualityValidator = DataQualityValidator(logger: logger)

        let dataIngestionService = DataIngestionService(
            exchangeConnectors: [:],
            qualityValidator: qualityValidator,
            timeSeriesStore: timeSeriesStore,
            logger: logger
        )

        let technicalIndicators = TechnicalIndicators()
        let featureExtractor = FeatureExtractor(
            technicalIndicators: technicalIndicators,
            logger: logger
        )

        let patternStorageService = PatternStorageService(
            database: database,
            logger: logger
        )
        let patternRecognizer = PatternRecognizer(
            logger: logger,
            patternStorage: patternStorageService
        )

        let predictionEngine: PredictionEngineProtocol
        let volatilityPredictor: VolatilityPredictionProtocol
        let trendClassifier: TrendClassificationProtocol
        let predictionValidator = PredictionValidator(logger: logger)
        let modelManager = ModelManager(logger: logger)
        let cacheManager = MockCacheManager(logger: logger)
        let circuitBreaker = MockCircuitBreaker()

        logger.info(component: "MLPatternEngineFactory", event: "Using traditional models")

        predictionEngine = PredictionEngine(logger: logger)
        volatilityPredictor = GARCHVolatilityPredictor(logger: logger)
        trendClassifier = TrendClassifier(
            logger: logger,
            technicalIndicators: technicalIndicators
        )

        let bootstrapTrainer = BootstrapTrainer(
            logger: logger,
            featureExtractor: featureExtractor,
            predictionValidator: predictionValidator,
            modelManager: modelManager
        )

        let inferenceService = InferenceService(
            predictionEngine: predictionEngine,
            cacheManager: cacheManager,
            circuitBreaker: circuitBreaker,
            logger: logger
        )

        let modelPrice = try await bootstrapTrainer.createInitialModel(symbol: "BTC-USD", modelType: .pricePrediction)
        let modelVolatility = try await bootstrapTrainer.createInitialModel(symbol: "BTC-USD", modelType: .volatilityPrediction)
        let modelTrend = try await bootstrapTrainer.createInitialModel(symbol: "BTC-USD", modelType: .trendClassification)

        if let concreteEngine = predictionEngine as? PredictionEngine {
            concreteEngine.loadModel(modelPrice)
            concreteEngine.loadModel(modelVolatility)
            concreteEngine.loadModel(modelTrend)
        }

        // Fetch and seed historical data from market data providers
        try await seedHistoricalDataFromProviders(into: database)

        let mlEngine = MLPatternEngine(
            dataIngestionService: dataIngestionService,
            featureExtractor: featureExtractor,
            patternRecognizer: patternRecognizer,
            predictionEngine: predictionEngine,
            volatilityPredictor: volatilityPredictor,
            trendClassifier: trendClassifier,
            predictionValidator: predictionValidator,
            bootstrapTrainer: bootstrapTrainer,
            modelManager: modelManager,
            inferenceService: inferenceService,
            logger: logger
        )

        logger.info(component: "MLPatternEngineFactory", event: "MLPatternEngine created successfully")
        return mlEngine
    }

    public func createMLXTrainingPipeline() throws {
        logger.warn(component: "MLPatternEngineFactory", event: "MLX training pipeline not yet implemented")
        throw NSError(domain: "MLPatternEngineFactory", code: 1, userInfo: [NSLocalizedDescriptionKey: "MLX integration not yet implemented"])
    }

    private func seedHistoricalDataFromProviders(into database: DatabaseProtocol) async throws {
        let symbols = ["BTC", "ETH", "ADA", "DOT", "LINK", "UNI", "SOL", "AVAX", "MATIC", "DOGE",
                       "SHIB", "FIL", "AR", "SC", "ATOM", "NEAR", "FTM", "ALGO"]
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -90, to: endDate) else {
            logger.error(component: "MLPatternEngineFactory", event: "Failed to calculate start date")
            return
        }

        let totalCount = try await checkTotalDataExists(database: database)

        if totalCount >= 1000 {
            logger.debug(component: "MLPatternEngineFactory", event: "Sufficient cached data exists, skipping detailed checks", data: [
                "total_count": String(totalCount)
            ])
            return
        }

        var symbolsNeedingData: [String] = []

        for symbol in symbols {
            let count = try await checkDataExists(database: database, symbol: symbol, from: startDate, to: endDate)
            if count < 50 {
                symbolsNeedingData.append(symbol)
            }
        }

        guard !symbolsNeedingData.isEmpty else {
            logger.info(component: "MLPatternEngineFactory", event: "All symbols have cached data, skipping fetch")
            return
        }

        logger.info(component: "MLPatternEngineFactory", event: "Fetching historical data for missing symbols", data: [
            "symbols": String(symbolsNeedingData.count)
        ])

        let marketDataProvider = MultiProviderMarketDataProvider()

        for symbol in symbolsNeedingData {
            do {
                let data = try await marketDataProvider.getHistoricalData(
                    startDate: startDate,
                    endDate: endDate,
                    symbols: [symbol]
                )

                if let historicalData = data[symbol], !historicalData.isEmpty {
                    try await insertDataDirectly(into: database, points: historicalData, symbol: symbol)

                    logger.info(component: "MLPatternEngineFactory", event: "Inserted data for symbol", data: [
                        "symbol": symbol,
                        "points": String(historicalData.count)
                    ])
                }
            } catch {
                logger.warn(component: "MLPatternEngineFactory", event: "Failed to fetch data", data: [
                    "symbol": symbol,
                    "error": error.localizedDescription
                ])
            }
        }
    }

    private func checkTotalDataExists(database: DatabaseProtocol) async throws -> Int {
        let sql = """
        SELECT COUNT(*) as count
        FROM market_data;
        """

        let rows = try await database.executeQuery(sql, parameters: [])

        if let firstRow = rows.first,
           let countValue = firstRow["count"] {
            if let count = countValue as? Int {
                return count
            } else if let count = countValue as? Int32 {
                return Int(count)
            } else if let count = countValue as? Double {
                return Int(count)
            }
        }
        return 0
    }

    private func checkDataExists(database: DatabaseProtocol, symbol: String, from: Date, to: Date) async throws -> Int {
        let sql = """
        SELECT COUNT(*) as count
        FROM market_data
        WHERE symbol = ? AND timestamp BETWEEN ? AND ?;
        """

        let rows = try await database.executeQuery(sql, parameters: [
            "\(symbol)-USD",
            from.timeIntervalSince1970,
            to.timeIntervalSince1970
        ])

        if let firstRow = rows.first,
           let countValue = firstRow["count"] {
            if let count = countValue as? Int {
                return count
            } else if let count = countValue as? Int32 {
                return Int(count)
            } else if let count = countValue as? Double {
                return Int(count)
            }
        }
        return 0
    }

    private func insertDataDirectly(into database: DatabaseProtocol, points: [MarketDataPoint], symbol: String) async throws {
        // Insert data using raw SQL to bypass type conflicts
        let batchSize = 100
        let batches = points.chunked(into: batchSize)

        for batch in batches {
            for point in batch {
                let sql = """
                INSERT INTO market_data(symbol, exchange, timestamp, open, high, low, close, volume)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?);
                """

                let parameters: [any Sendable] = [
                    "\(symbol)-USD",
                    "provider",
                    point.timestamp.timeIntervalSince1970,
                    point.open,
                    point.high,
                    point.low,
                    point.close,
                    point.volume
                ]

                _ = try await database.executeUpdate(sql, parameters: parameters)
            }

            // Force checkpoint after each batch to ensure data is immediately readable
            let checkpointSQL = "PRAGMA wal_checkpoint(FULL);"
            _ = try? await database.executeUpdate(checkpointSQL, parameters: [])
        }
    }

}
