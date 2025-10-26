import Foundation
import Core
import Utils

public class MLPatternEngine {
    private let dataIngestionService: DataIngestionProtocol
    private let featureExtractor: FeatureExtractorProtocol
    private let patternRecognizer: PatternRecognitionProtocol
    private let predictionEngine: PredictionEngineProtocol
    private let volatilityPredictor: VolatilityPredictionProtocol
    private let trendClassifier: TrendClassificationProtocol
    private let predictionValidator: PredictionValidationProtocol
    private let bootstrapTrainer: BootstrapTrainingProtocol
    private let modelManager: ModelManagerProtocol
    private let inferenceService: InferenceServiceProtocol
    private let logger: StructuredLogger

    public init(
        dataIngestionService: DataIngestionProtocol,
        featureExtractor: FeatureExtractorProtocol,
        patternRecognizer: PatternRecognitionProtocol,
        predictionEngine: PredictionEngineProtocol,
        volatilityPredictor: VolatilityPredictionProtocol,
        trendClassifier: TrendClassificationProtocol,
        predictionValidator: PredictionValidationProtocol,
        bootstrapTrainer: BootstrapTrainingProtocol,
        modelManager: ModelManagerProtocol,
        inferenceService: InferenceServiceProtocol,
        logger: StructuredLogger
    ) {
        self.dataIngestionService = dataIngestionService
        self.featureExtractor = featureExtractor
        self.patternRecognizer = patternRecognizer
        self.predictionEngine = predictionEngine
        self.volatilityPredictor = volatilityPredictor
        self.trendClassifier = trendClassifier
        self.predictionValidator = predictionValidator
        self.bootstrapTrainer = bootstrapTrainer
        self.modelManager = modelManager
        self.inferenceService = inferenceService
        self.logger = logger
    }

    public func start() async throws {
        logger.info(component: "MLPatternEngine", event: "Starting ML Pattern Engine")

        try await dataIngestionService.startIngestion()
        try await inferenceService.warmupModels()

        logger.info(component: "MLPatternEngine", event: "ML Pattern Engine started successfully")
    }

    public func stop() async throws {
        logger.info(component: "MLPatternEngine", event: "Stopping ML Pattern Engine")

        try await dataIngestionService.stopIngestion()

        logger.info(component: "MLPatternEngine", event: "ML Pattern Engine stopped")
    }

    public func getPrediction(for symbol: String, timeHorizon: TimeInterval, modelType: ModelInfo.ModelType) async throws -> PredictionResponse {
        let historicalData = try await dataIngestionService.getLatestData(for: symbol, limit: 100)

        guard !historicalData.isEmpty else {
            throw MLEngineError.insufficientData
        }

        let features = try await featureExtractor.extractFeatures(from: historicalData)
        guard let latestFeatures = features.last else {
            throw MLEngineError.featureExtractionFailed
        }

        let request = PredictionRequest(
            symbol: symbol,
            timeHorizon: timeHorizon,
            features: latestFeatures.features,
            modelType: modelType
        )

        return try await inferenceService.predict(request: request)
    }

    public func detectPatterns(for symbol: String) async throws -> [DetectedPattern] {
        let historicalData = try await dataIngestionService.getLatestData(for: symbol, limit: 200)

        guard !historicalData.isEmpty else {
            throw MLEngineError.insufficientData
        }

        return try await patternRecognizer.detectPatterns(in: historicalData)
    }

    public func getServiceHealth() -> InferenceServiceHealth {
        return inferenceService.getServiceHealth()
    }

    public func getLatestData(symbols: [String]) async throws -> [MarketDataPoint] {
        var allData: [MarketDataPoint] = []
        for symbol in symbols {
            // Use limit of 100 to ensure enough data for feature extraction
            let data = try await dataIngestionService.getLatestData(for: symbol, limit: 100)
            allData.append(contentsOf: data)
        }
        return allData
    }

    public func extractFeatures(for symbol: String, historicalData: [MarketDataPoint]) async throws -> FeatureSet {
        let features = try await featureExtractor.extractFeatures(from: historicalData)
        guard let latestFeatures = features.last else {
            throw MLEngineError.featureExtractionFailed
        }
        return latestFeatures
    }

    // MARK: - Volatility Prediction Methods

    public func predictVolatility(for symbol: String, horizon: TimeInterval = 3600) async throws -> VolatilityPrediction {
        let historicalData = try await dataIngestionService.getLatestData(for: symbol, limit: 1000)
        return try await volatilityPredictor.predictVolatility(for: symbol, historicalData: historicalData, horizon: horizon)
    }

    public func predictVolatility(for symbol: String, historicalData: [MarketDataPoint], horizon: TimeInterval = 3600) async throws -> VolatilityPrediction {
        return try await volatilityPredictor.predictVolatility(for: symbol, historicalData: historicalData, horizon: horizon)
    }

    public func getVolatilityForecast(for symbol: String, steps: Int = 12) async throws -> [Double] {
        let prediction = try await predictVolatility(for: symbol, horizon: TimeInterval(steps * 300))
        return prediction.predictedVolatility
    }

    // MARK: - Volatility Alert Methods

    public func checkVolatilityAlerts(for symbol: String) async throws -> [VolatilityAlert] {
        var alerts: [VolatilityAlert] = []

        // Check 1-hour volatility
        let volatility1h = try await predictVolatility(for: symbol, horizon: 3600)
        if volatility1h.confidence > 0.5 {
            let maxVolatility = volatility1h.predictedVolatility.max() ?? 0.0
            if maxVolatility > 0.6 {
                alerts.append(VolatilityAlert(
                    symbol: symbol,
                    horizon: 3600,
                    volatility: maxVolatility,
                    threshold: 0.6,
                    severity: "high",
                    message: "High volatility detected (1-hour horizon): \(String(format: "%.2f", maxVolatility * 100))%"
                ))
            }
        }

        // Check 4-hour volatility
        let volatility4h = try await predictVolatility(for: symbol, horizon: 14400)
        if volatility4h.confidence > 0.5 {
            let maxVolatility = volatility4h.predictedVolatility.max() ?? 0.0
            if maxVolatility > 0.8 {
                alerts.append(VolatilityAlert(
                    symbol: symbol,
                    horizon: 14400,
                    volatility: maxVolatility,
                    threshold: 0.8,
                    severity: "critical",
                    message: "Critical volatility detected (4-hour horizon): \(String(format: "%.2f", maxVolatility * 100))%"
                ))
            }
        }

        // Check 24-hour volatility
        let volatility24h = try await predictVolatility(for: symbol, horizon: 86400)
        if volatility24h.confidence > 0.5 {
            let maxVolatility = volatility24h.predictedVolatility.max() ?? 0.0
            if maxVolatility > 1.0 {
                alerts.append(VolatilityAlert(
                    symbol: symbol,
                    horizon: 86400,
                    volatility: maxVolatility,
                    threshold: 1.0,
                    severity: "critical",
                    message: "Extreme volatility detected (24-hour horizon): \(String(format: "%.2f", maxVolatility * 100))%"
                ))
            }
        }

        return alerts
    }

    public func generateVolatilityTradingSignals(for symbol: String) async throws -> [TradingSignal] {
        let volatilityPrediction = try await predictVolatility(for: symbol, horizon: 3600)
        var signals: [TradingSignal] = []

        guard volatilityPrediction.confidence > 0.5 else {
            return signals
        }

        let avgVolatility = volatilityPrediction.predictedVolatility.reduce(0, +) / Double(volatilityPrediction.predictedVolatility.count)

        if avgVolatility > 0.8 {
            // High volatility - suggest reducing position size or hedging
            signals.append(TradingSignal(
                timestamp: Date(),
                symbol: symbol,
                signalType: .hold,
                confidence: volatilityPrediction.confidence,
                timeHorizon: 3600
            ))
        } else if avgVolatility < 0.2 {
            // Low volatility - potential breakout opportunity
            signals.append(TradingSignal(
                timestamp: Date(),
                symbol: symbol,
                signalType: .buy,
                confidence: volatilityPrediction.confidence,
                timeHorizon: 3600
            ))
        }

        return signals
    }

    // MARK: - Trend Classification Methods

    public func classifyTrend(for symbol: String) async throws -> TrendClassification {
        let historicalData = try await dataIngestionService.getLatestData(for: symbol, limit: 200)
        return try await trendClassifier.classifyTrend(for: symbol, historicalData: historicalData)
    }

    public func classifyTrend(for symbol: String, historicalData: [MarketDataPoint]) async throws -> TrendClassification {
        return try await trendClassifier.classifyTrend(for: symbol, historicalData: historicalData)
    }

    public func predictReversal(for symbol: String) async throws -> ReversalPrediction {
        let historicalData = try await dataIngestionService.getLatestData(for: symbol, limit: 200)
        return try await trendClassifier.predictReversal(for: symbol, historicalData: historicalData)
    }

    public func predictReversal(for symbol: String, historicalData: [MarketDataPoint]) async throws -> ReversalPrediction {
        return try await trendClassifier.predictReversal(for: symbol, historicalData: historicalData)
    }

    public func getTrendStrength(for symbol: String, trendType: TrendType) async throws -> Double {
        let historicalData = try await dataIngestionService.getLatestData(for: symbol, limit: 100)
        return try await trendClassifier.calculateTrendStrength(data: historicalData, trendType: trendType)
    }

    // MARK: - Validation Methods

    public func validatePrediction(prediction: PredictionResponse, symbol: String) async throws -> ValidationResult {
        let actualData = try await dataIngestionService.getLatestData(for: symbol, limit: 200)
        return try await predictionValidator.validatePricePrediction(prediction: prediction, actualData: actualData)
    }

    public func validateVolatilityPrediction(prediction: VolatilityPrediction, symbol: String) async throws -> ValidationResult {
        let actualData = try await dataIngestionService.getLatestData(for: symbol, limit: 200)
        return try await predictionValidator.validateVolatilityPrediction(prediction: prediction, actualData: actualData)
    }

    public func validateTrendClassification(classification: TrendClassification, symbol: String) async throws -> ValidationResult {
        let actualData = try await dataIngestionService.getLatestData(for: symbol, limit: 200)
        return try await predictionValidator.validateTrendClassification(classification: classification, actualData: actualData)
    }

    public func validateReversalPrediction(prediction: ReversalPrediction, symbol: String) async throws -> ValidationResult {
        let actualData = try await dataIngestionService.getLatestData(for: symbol, limit: 200)
        return try await predictionValidator.validateReversalPrediction(prediction: prediction, actualData: actualData)
    }

    public func performBacktesting(for symbol: String, modelType: ModelType, lookbackDays: Int = 30) async throws -> BacktestResult {
        let lookbackPeriod = TimeInterval(lookbackDays * 24 * 60 * 60)
        let historicalData = try await dataIngestionService.getLatestData(for: symbol, limit: 1000)
        return try await predictionValidator.performBacktesting(modelType: modelType, historicalData: historicalData, lookbackPeriod: lookbackPeriod)
    }

    public func getModelMetrics(for symbol: String, modelType: ModelType) async throws -> ModelMetrics {
        let historicalData = try await dataIngestionService.getLatestData(for: symbol, limit: 500)

        // Generate sample predictions for validation
        var predictions: [PredictionResponse] = []
        for i in 0..<min(10, historicalData.count - 50) {
            _ = Array(historicalData.prefix(i + 50))
            let prediction = try await predictionEngine.predictPrice(
                request: PredictionRequest(
                    symbol: symbol,
                    timeHorizon: 300,
                    features: [:], // Empty features for now
                    modelType: .pricePrediction
                )
            )
            predictions.append(prediction)
        }

        let validationMetrics = try await predictionValidator.calculateModelMetrics(predictions: predictions, actualData: historicalData)

        // Convert ValidationModelMetrics to ModelMetrics
        return ModelMetrics(
            totalModels: 1,
            activeModels: 1,
            modelPerformance: [],
            averageAccuracy: validationMetrics.averageAccuracy,
            totalPredictions: validationMetrics.totalValidations,
            predictionsPerSecond: Double(validationMetrics.totalValidations) / validationMetrics.validationPeriod,
            lastRetraining: Date(),
            nextRetraining: Date().addingTimeInterval(3600)
        )
    }

    // MARK: - Bootstrap Training Methods

    public func bootstrapModel(for symbol: String, modelType: ModelType) async throws -> BootstrapResult {
        let trainingData = try await dataIngestionService.getLatestData(for: symbol, limit: 1000)
        return try await bootstrapTrainer.bootstrapModel(for: modelType, trainingData: trainingData)
    }

    public func bootstrapModel(for symbol: String, modelType: ModelType, trainingData: [MarketDataPoint]) async throws -> BootstrapResult {
        return try await bootstrapTrainer.bootstrapModel(for: modelType, trainingData: trainingData)
    }

    public func createInitialModel(for symbol: String, modelType: ModelType) async throws -> ModelInfo {
        return try await bootstrapTrainer.createInitialModel(symbol: symbol, modelType: modelType)
    }

    public func deployModel(_ model: ModelInfo) async throws -> DeploymentResult {
        return try await bootstrapTrainer.deployBootstrapModel(model: model)
    }

    public func bootstrapAndDeployModel(for symbol: String, modelType: ModelType) async throws -> DeploymentResult {
        // Bootstrap train the model
        let bootstrapResult = try await bootstrapModel(for: symbol, modelType: modelType)

        // Deploy the trained model
        let deploymentResult = try await deployModel(bootstrapResult.modelInfo)

        logger.info(component: "MLPatternEngine", event: "Bootstrap training and deployment completed", data: [
            "symbol": symbol,
            "modelType": modelType.rawValue,
            "modelId": bootstrapResult.modelInfo.modelId,
            "accuracy": String(bootstrapResult.validationResult.accuracy),
            "deploymentStatus": deploymentResult.deploymentStatus.rawValue
        ])

        return deploymentResult
    }
}

public enum MLEngineError: Error {
    case insufficientData
    case featureExtractionFailed
    case patternDetectionFailed
    case predictionFailed
    case modelNotReady
}
