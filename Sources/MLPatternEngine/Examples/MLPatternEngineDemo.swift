import Foundation
import Core
import Utils

public class MLPatternEngineDemo {
    private let logger: StructuredLogger

    public init() {
        self.logger = StructuredLogger()
    }

    public func runDemo() async throws {
        logger.info(component: "MLPatternEngineDemo", event: "Starting ML Pattern Engine Demo")

        let mlEngine = try await createMLEngine()

        try await mlEngine.start()

        let demoData = generateDemoData()
        try await demonstrateFeatures(mlEngine: mlEngine, data: demoData)

        try await mlEngine.stop()

        logger.info(component: "MLPatternEngineDemo", event: "ML Pattern Engine Demo completed")
    }

    private func createMLEngine() async throws -> MLPatternEngine {
        let database = try SQLiteTimeSeriesDatabase(logger: logger)
        let timeSeriesStore = TimeSeriesStore(database: database, logger: logger)
        let qualityValidator = DataQualityValidator(logger: logger)
        let exchangeConnectors: [String: any ExchangeConnector] = [:]

        let dataIngestionService = DataIngestionService(
            exchangeConnectors: exchangeConnectors,
            qualityValidator: qualityValidator,
            timeSeriesStore: timeSeriesStore,
            logger: logger
        )

        let technicalIndicators = TechnicalIndicators()
        let featureExtractor = FeatureExtractor(technicalIndicators: technicalIndicators, logger: logger)

        let patternStorageService = PatternStorageService(database: database, logger: logger)
        let patternRecognizer = PatternRecognizer(logger: logger, patternStorage: patternStorageService)

        let predictionEngine = PredictionEngine(logger: logger)
        let volatilityPredictor = GARCHVolatilityPredictor(logger: logger)
        let trendClassifier = TrendClassifier(logger: logger, technicalIndicators: technicalIndicators)
        let predictionValidator = PredictionValidator(logger: logger)
        let modelManager = ModelManager(logger: logger)
        let bootstrapTrainer = BootstrapTrainer(logger: logger, featureExtractor: featureExtractor, predictionValidator: predictionValidator, modelManager: modelManager)

        let cacheManager = MockCacheManager(logger: logger)
        let circuitBreaker = MockCircuitBreaker()
        let inferenceService = InferenceService(
            predictionEngine: predictionEngine,
            cacheManager: cacheManager,
            circuitBreaker: circuitBreaker,
            logger: logger
        )

        let modelInfo = ModelInfo(
            modelId: "demo-model",
            version: "1.0.0",
            modelType: .pricePrediction,
            trainingDataHash: "demo-hash",
            accuracy: 0.85,
            createdAt: Date(),
            isActive: true
        )

        predictionEngine.loadModel(modelInfo)

        return MLPatternEngine(
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
    }

    private func generateDemoData() -> [MarketDataPoint] {
        var dataPoints: [MarketDataPoint] = []
        let basePrice = 50000.0
        let startTime = Date().addingTimeInterval(-3600) // 1 hour ago

        for i in 0..<100 {
            let timeOffset = TimeInterval(i * 60) // 1 minute intervals
            let price = basePrice + Double(i) * 10.0 + sin(Double(i) * 0.1) * 500.0

            let dataPoint = MarketDataPoint(
                timestamp: startTime.addingTimeInterval(timeOffset),
                symbol: "BTC-USD",
                open: price,
                high: price + 200.0,
                low: price - 200.0,
                close: price + 100.0,
                volume: 1000.0 + Double(i) * 10.0,
                exchange: "demo"
            )
            dataPoints.append(dataPoint)
        }

        return dataPoints
    }

    private func demonstrateFeatures(mlEngine: MLPatternEngine, data: [MarketDataPoint]) async throws {
        logger.info(component: "MLPatternEngineDemo", event: "Demonstrating ML Pattern Engine features")

        let symbol = "BTC-USD"

        logger.info(component: "MLPatternEngineDemo", event: "1. Pattern Detection")
        let patterns = try await mlEngine.detectPatterns(for: symbol)
        logger.info(component: "MLPatternEngineDemo", event: "Detected \(patterns.count) patterns")
        for pattern in patterns.prefix(3) {
            logger.info(component: "MLPatternEngineDemo", event: "Pattern: \(pattern.patternType.rawValue) with confidence \(pattern.confidence)")
        }

        logger.info(component: "MLPatternEngineDemo", event: "2. Price Prediction")
        let pricePrediction = try await mlEngine.getPrediction(
            for: symbol,
            timeHorizon: 300, // 5 minutes
            modelType: .pricePrediction
        )
        logger.info(component: "MLPatternEngineDemo", event: "Price prediction: \(pricePrediction.prediction) with confidence \(pricePrediction.confidence)")

        logger.info(component: "MLPatternEngineDemo", event: "3. Volatility Prediction")
        let volatilityPrediction = try await mlEngine.predictVolatility(for: symbol, horizon: 3600) // 1 hour
        logger.info(component: "MLPatternEngineDemo", event: "Volatility prediction: \(volatilityPrediction.predictedVolatility.prefix(5)) with confidence \(volatilityPrediction.confidence)")
        logger.info(component: "MLPatternEngineDemo", event: "GARCH parameters - Omega: \(volatilityPrediction.parameters.omega), Alpha: \(volatilityPrediction.parameters.alpha), Beta: \(volatilityPrediction.parameters.beta)")
        logger.info(component: "MLPatternEngineDemo", event: "Model R²: \(volatilityPrediction.r2), MSE: \(volatilityPrediction.mse)")

        logger.info(component: "MLPatternEngineDemo", event: "4. Trend Classification")
        let trendClassification = try await mlEngine.classifyTrend(for: symbol)
        logger.info(component: "MLPatternEngineDemo", event: "Trend type: \(trendClassification.trendType.rawValue) with confidence \(trendClassification.confidence)")
        logger.info(component: "MLPatternEngineDemo", event: "Trend strength: \(trendClassification.strength), duration: \(trendClassification.duration)")
        logger.info(component: "MLPatternEngineDemo", event: "Support: \(trendClassification.supportLevel ?? 0), Resistance: \(trendClassification.resistanceLevel ?? 0)")

        logger.info(component: "MLPatternEngineDemo", event: "5. Reversal Prediction")
        let reversalPrediction = try await mlEngine.predictReversal(for: symbol)
        logger.info(component: "MLPatternEngineDemo", event: "Reversal type: \(reversalPrediction.reversalType.rawValue) with confidence \(reversalPrediction.confidence)")
        logger.info(component: "MLPatternEngineDemo", event: "Reversal probability: \(reversalPrediction.probability), signals: \(reversalPrediction.signals.count)")

        logger.info(component: "MLPatternEngineDemo", event: "6. Prediction Validation")
        let validationResult = try await mlEngine.validatePrediction(prediction: pricePrediction, symbol: symbol)
        logger.info(component: "MLPatternEngineDemo", event: "Validation accuracy: \(validationResult.accuracy), MAE: \(validationResult.mae), Hit Rate: \(validationResult.hitRate)")

        logger.info(component: "MLPatternEngineDemo", event: "7. Backtesting")
        let backtestResult = try await mlEngine.performBacktesting(for: symbol, modelType: .pricePrediction, lookbackDays: 7)
        logger.info(component: "MLPatternEngineDemo", event: "Backtest - Total trades: \(backtestResult.totalTrades), Win rate: \(backtestResult.winRate), Total return: \(backtestResult.totalReturn)")

        logger.info(component: "MLPatternEngineDemo", event: "8. Bootstrap Training")
        let bootstrapResult = try await mlEngine.bootstrapModel(for: symbol, modelType: .pricePrediction)
        logger.info(component: "MLPatternEngineDemo", event: "Bootstrap training completed - Model ID: \(bootstrapResult.modelInfo.modelId)")
        logger.info(component: "MLPatternEngineDemo", event: "Training metrics - Accuracy: \(bootstrapResult.trainingMetrics.accuracy), Loss: \(bootstrapResult.trainingMetrics.trainingLoss)")
        logger.info(component: "MLPatternEngineDemo", event: "Bootstrap samples: \(bootstrapResult.bootstrapSamples), Duration: \(bootstrapResult.trainingDuration)")

        logger.info(component: "MLPatternEngineDemo", event: "9. Model Deployment")
        let deploymentResult = try await mlEngine.deployModel(bootstrapResult.modelInfo)
        logger.info(component: "MLPatternEngineDemo", event: "Model deployed - Status: \(deploymentResult.deploymentStatus.rawValue)")
        logger.info(component: "MLPatternEngineDemo", event: "Endpoint: \(deploymentResult.endpoint ?? "N/A"), Performance: \(deploymentResult.performanceMetrics.latency)ms latency")

        logger.info(component: "MLPatternEngineDemo", event: "10. Service Health")
        let health = mlEngine.getServiceHealth()
        logger.info(component: "MLPatternEngineDemo", event: "Service health: \(health.isHealthy), cache hit rate: \(health.cacheHitRate)")
    }
}
