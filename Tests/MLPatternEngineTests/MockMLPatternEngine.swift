import Foundation
import Testing
import MLPatternEngine
import Core
import Utils

// Factory function to create failing MLPatternEngine instances with mock dependencies
public func createFailingMockMLPatternEngine(
    logger: StructuredLogger
) -> MLPatternEngine {
    let mockDataIngestion = MockDataIngestionService(logger: logger)
    let mockFeatureExtractor = MockFeatureExtractor(logger: logger)
    let mockPatternRecognizer = MockPatternRecognizer(logger: logger)
    let mockPredictionEngine = FailingMockPredictionEngine(logger: logger)
    let mockVolatilityPredictor = MockVolatilityPredictor(logger: logger)
    let mockTrendClassifier = MockTrendClassifier(logger: logger)
    let mockPredictionValidator = MockPredictionValidator(logger: logger)
    let mockBootstrapTrainer = MockBootstrapTrainer(logger: logger)
    let mockModelManager = MockModelManager(logger: logger)
    let mockInferenceService = FailingMockInferenceService(logger: logger)

    return MLPatternEngine(
        dataIngestionService: mockDataIngestion,
        featureExtractor: mockFeatureExtractor,
        patternRecognizer: mockPatternRecognizer,
        predictionEngine: mockPredictionEngine,
        volatilityPredictor: mockVolatilityPredictor,
        trendClassifier: mockTrendClassifier,
        predictionValidator: mockPredictionValidator,
        bootstrapTrainer: mockBootstrapTrainer,
        modelManager: mockModelManager,
        inferenceService: mockInferenceService,
        logger: logger
    )
}

// Factory function to create MLPatternEngine instances with mock dependencies
public func createMockMLPatternEngine(
    mockPredictionResponse: PredictionResponse? = nil,
    mockPatternResponse: [DetectedPattern]? = nil,
    mockServiceHealth: ServiceHealth? = nil,
    logger: StructuredLogger
) -> MLPatternEngine {
    let mockDataIngestion = MockDataIngestionService(logger: logger)
    let mockFeatureExtractor = MockFeatureExtractor(logger: logger)
    let mockPatternRecognizer = MockPatternRecognizer(logger: logger)
    let mockPredictionEngine = MockPredictionEngine(logger: logger)
    let mockVolatilityPredictor = MockVolatilityPredictor(logger: logger)
    let mockTrendClassifier = MockTrendClassifier(logger: logger)
    let mockPredictionValidator = MockPredictionValidator(logger: logger)
    let mockBootstrapTrainer = MockBootstrapTrainer(logger: logger)
    let mockModelManager = MockModelManager(logger: logger)
    let mockInferenceService = MockInferenceService(logger: logger)

    return MLPatternEngine(
        dataIngestionService: mockDataIngestion,
        featureExtractor: mockFeatureExtractor,
        patternRecognizer: mockPatternRecognizer,
        predictionEngine: mockPredictionEngine,
        volatilityPredictor: mockVolatilityPredictor,
        trendClassifier: mockTrendClassifier,
        predictionValidator: mockPredictionValidator,
        bootstrapTrainer: mockBootstrapTrainer,
        modelManager: mockModelManager,
        inferenceService: mockInferenceService,
        logger: logger
    )
}

// MARK: - Mock Protocol Implementations

public class MockDataIngestionService: DataIngestionProtocol {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func startIngestion() async throws {
        logger.info(component: "MockDataIngestionService", event: "Started ingestion")
    }

    public func stopIngestion() async throws {
        logger.info(component: "MockDataIngestionService", event: "Stopped ingestion")
    }

    public func getLatestData(for symbol: String, limit: Int) async throws -> [MarketDataPoint] {
        return generateMockMarketData(symbol: symbol, count: limit)
    }

    public func getHistoricalData(for symbol: String, from: Date, to: Date) async throws -> [MarketDataPoint] {
        return generateMockMarketData(symbol: symbol, count: 100)
    }

    public func subscribeToRealTimeData(for symbols: [String], callback: @escaping (MarketDataPoint) -> Void) async throws {
        // Mock implementation
    }

    private func generateMockMarketData(symbol: String, count: Int) -> [MarketDataPoint] {
        var dataPoints: [MarketDataPoint] = []
        let basePrice = 50000.0

        for i in 0..<count {
            let price = basePrice + Double.random(in: -1000...1000)
            let dataPoint = MarketDataPoint(
                timestamp: Date().addingTimeInterval(-Double(i) * 300),
                symbol: symbol,
                open: price,
                high: price * Double.random(in: 1.0...1.02),
                low: price * Double.random(in: 0.98...1.0),
                close: price * Double.random(in: 0.99...1.01),
                volume: Double.random(in: 1000...10000),
                exchange: "MOCK"
            )
            dataPoints.append(dataPoint)
        }

        return dataPoints
    }
}

public class MockFeatureExtractor: FeatureExtractorProtocol {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func extractFeatures(from dataPoints: [MarketDataPoint]) async throws -> [FeatureSet] {
        return dataPoints.map { dataPoint in
            FeatureSet(
                timestamp: dataPoint.timestamp,
                symbol: dataPoint.symbol,
                features: [
                    "price": dataPoint.close,
                    "volatility": Double.random(in: 0.01...0.05),
                    "trend_strength": Double.random(in: 0.0...1.0),
                    "rsi": Double.random(in: 20...80),
                    "macd": Double.random(in: -100...100)
                ],
                qualityScore: 0.9
            )
        }
    }

    public func extractFeatures(from dataPoint: MarketDataPoint, historicalData: [MarketDataPoint]) async throws -> FeatureSet {
        return FeatureSet(
            timestamp: dataPoint.timestamp,
            symbol: dataPoint.symbol,
            features: [
                "price": dataPoint.close,
                "volatility": Double.random(in: 0.01...0.05),
                "trend_strength": Double.random(in: 0.0...1.0),
                "rsi": Double.random(in: 20...80),
                "macd": Double.random(in: -100...100)
            ],
            qualityScore: 0.9
        )
    }

    public func getFeatureNames() -> [String] {
        return ["price", "volatility", "trend_strength", "rsi", "macd"]
    }

    public func validateFeatureSet(_ featureSet: FeatureSet) -> Bool {
        return !featureSet.features.isEmpty
    }
}

public class MockPatternRecognizer: PatternRecognitionProtocol {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func detectPatterns(in dataPoints: [MarketDataPoint]) async throws -> [DetectedPattern] {
        guard !dataPoints.isEmpty else { return [] }

        let headAndShouldersPattern = DetectedPattern(
            patternId: UUID().uuidString,
            patternType: .headAndShoulders,
            symbol: dataPoints.first?.symbol ?? "BTC-USD",
            startTime: dataPoints.first?.timestamp ?? Date(),
            endTime: dataPoints.last?.timestamp ?? Date(),
            confidence: 0.85,
            completionScore: 0.9,
            priceTarget: 52000.0,
            stopLoss: 48000.0,
            marketConditions: ["trend": "Bullish", "volatility": "Medium"]
        )

        return [headAndShouldersPattern]
    }

    public func detectPattern(in dataPoints: [MarketDataPoint], patternType: DetectedPattern.PatternType) async throws -> [DetectedPattern] {
        return []
    }

    public func calculatePatternConfidence(_ pattern: DetectedPattern, historicalData: [MarketDataPoint]) -> Double {
        return 0.8
    }

    public func validatePattern(_ pattern: DetectedPattern) -> Bool {
        return true
    }
}

public class MockPredictionEngine: PredictionEngineProtocol, @unchecked Sendable {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func predictPrice(request: PredictionRequest) async throws -> PredictionResponse {
        return PredictionResponse(
            id: UUID().uuidString,
            prediction: Double.random(in: 40000...60000),
            confidence: Double.random(in: 0.7...0.95),
            uncertainty: Double.random(in: 0.05...0.2),
            modelVersion: "1.0.0",
            timestamp: Date()
        )
    }

    public func predictVolatility(request: PredictionRequest) async throws -> PredictionResponse {
        return PredictionResponse(
            id: UUID().uuidString,
            prediction: Double.random(in: 0.01...0.05),
            confidence: Double.random(in: 0.7...0.95),
            uncertainty: Double.random(in: 0.05...0.2),
            modelVersion: "1.0.0",
            timestamp: Date()
        )
    }

    public func classifyTrend(request: PredictionRequest) async throws -> PredictionResponse {
        return PredictionResponse(
            id: UUID().uuidString,
            prediction: Double.random(in: 0...1),
            confidence: Double.random(in: 0.7...0.95),
            uncertainty: Double.random(in: 0.05...0.2),
            modelVersion: "1.0.0",
            timestamp: Date()
        )
    }

    public func batchPredict(requests: [PredictionRequest]) async throws -> [PredictionResponse] {
        var results: [PredictionResponse] = []
        for request in requests {
            let response = try await predictPrice(request: request)
            results.append(response)
        }
        return results
    }

    public func getModelInfo(for modelType: ModelInfo.ModelType) -> ModelInfo? {
        return ModelInfo(
            modelId: "mock-\(modelType.rawValue.lowercased())",
            version: "1.0.0",
            modelType: modelType,
            trainingDataHash: "mock-hash",
            accuracy: 0.85,
            createdAt: Date(),
            isActive: true
        )
    }
}

public class FailingMockPredictionEngine: PredictionEngineProtocol, @unchecked Sendable {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func predictPrice(request: PredictionRequest) async throws -> PredictionResponse {
        throw PredictionError.predictionFailed
    }

    public func predictVolatility(request: PredictionRequest) async throws -> PredictionResponse {
        throw PredictionError.predictionFailed
    }

    public func classifyTrend(request: PredictionRequest) async throws -> PredictionResponse {
        throw PredictionError.predictionFailed
    }

    public func batchPredict(requests: [PredictionRequest]) async throws -> [PredictionResponse] {
        throw PredictionError.predictionFailed
    }

    public func getModelInfo(for modelType: ModelInfo.ModelType) -> ModelInfo? {
        return nil
    }
}

public class MockVolatilityPredictor: VolatilityPredictionProtocol {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func predictVolatility(for symbol: String, historicalData: [MarketDataPoint], horizon: TimeInterval) async throws -> VolatilityPrediction {
        let parameters = GARCHParameters(
            omega: 0.0001,
            alpha: 0.1,
            beta: 0.85,
            mu: 0.001,
            logLikelihood: -100.0,
            aic: 200.0,
            bic: 220.0
        )

        return VolatilityPrediction(
            symbol: symbol,
            timestamp: Date(),
            horizon: horizon,
            predictedVolatility: [Double.random(in: 0.01...0.05)],
            confidence: 0.8,
            modelType: "GARCH(1,1)",
            parameters: parameters,
            r2: 0.75,
            mse: 0.001
        )
    }

    public func calculateGARCHParameters(returns: [Double]) async throws -> GARCHParameters {
        return GARCHParameters(
            omega: 0.0001,
            alpha: 0.1,
            beta: 0.85,
            mu: 0.001,
            logLikelihood: -100.0,
            aic: 200.0,
            bic: 220.0
        )
    }

    public func forecastVolatility(parameters: GARCHParameters, lastReturns: [Double], horizon: Int) async throws -> [Double] {
        return Array(repeating: Double.random(in: 0.01...0.05), count: horizon)
    }
}

public class MockTrendClassifier: TrendClassificationProtocol {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func classifyTrend(for symbol: String, historicalData: [MarketDataPoint]) async throws -> TrendClassification {
        let features = TrendFeatures(
            priceMomentum: Double.random(in: -0.1...0.1),
            volumeMomentum: Double.random(in: 0.8...1.2),
            volatility: Double.random(in: 0.01...0.05),
            priceRange: Double.random(in: 0.02...0.1),
            movingAverageSlope: Double.random(in: -0.05...0.05),
            rsiDivergence: Double.random(in: 0...0.5),
            macdSignal: Double.random(in: -0.02...0.02),
            bollingerPosition: Double.random(in: 0...1)
        )

        let indicators = TrendIndicators(
            sma20: 50000.0,
            sma50: 49500.0,
            sma200: 48000.0,
            rsi: Double.random(in: 20...80),
            macd: Double.random(in: -100...100),
            macdSignal: Double.random(in: -100...100),
            bollingerUpper: 52000.0,
            bollingerLower: 48000.0,
            bollingerMiddle: 50000.0,
            volumeSMA: 5000.0
        )

        return TrendClassification(
            symbol: symbol,
            timestamp: Date(),
            trendType: .uptrend,
            confidence: 0.8,
            strength: 0.7,
            duration: 3600,
            supportLevel: 48000.0,
            resistanceLevel: 52000.0,
            features: features,
            indicators: indicators
        )
    }

    public func predictReversal(for symbol: String, historicalData: [MarketDataPoint]) async throws -> ReversalPrediction {
        return ReversalPrediction(
            symbol: symbol,
            timestamp: Date(),
            reversalType: .noReversal,
            confidence: 0.6,
            probability: 0.3,
            timeToReversal: nil,
            triggerPrice: nil,
            stopLoss: nil,
            takeProfit: nil,
            signals: []
        )
    }

    public func calculateTrendStrength(data: [MarketDataPoint], trendType: TrendType) async throws -> Double {
        return Double.random(in: 0.5...1.0)
    }
}

public class MockPredictionValidator: PredictionValidationProtocol {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func validatePricePrediction(prediction: PredictionResponse, actualData: [MarketDataPoint]) async throws -> ValidationResult {
        return ValidationResult(
            modelType: .pricePrediction,
            timestamp: Date(),
            accuracy: 0.85,
            precision: 0.82,
            recall: 0.88,
            f1Score: 0.85,
            mae: 100.0,
            mse: 10000.0,
            rmse: 100.0,
            mape: 2.0,
            directionalAccuracy: 0.8,
            sharpeRatio: 1.5,
            maxDrawdown: 0.05,
            hitRate: 0.85,
            confidence: prediction.confidence,
            validationPeriod: 3600,
            sampleSize: actualData.count
        )
    }

    public func validateVolatilityPrediction(prediction: VolatilityPrediction, actualData: [MarketDataPoint]) async throws -> ValidationResult {
        return ValidationResult(
            modelType: .volatilityPrediction,
            timestamp: Date(),
            accuracy: 0.8,
            precision: 0.78,
            recall: 0.82,
            f1Score: 0.8,
            mae: 0.01,
            mse: 0.0001,
            rmse: 0.01,
            mape: 5.0,
            directionalAccuracy: 0.75,
            sharpeRatio: nil,
            maxDrawdown: nil,
            hitRate: 0.8,
            confidence: prediction.confidence,
            validationPeriod: prediction.horizon,
            sampleSize: 1
        )
    }

    public func validateTrendClassification(classification: TrendClassification, actualData: [MarketDataPoint]) async throws -> ValidationResult {
        return ValidationResult(
            modelType: .trendClassification,
            timestamp: Date(),
            accuracy: 0.9,
            precision: 0.88,
            recall: 0.92,
            f1Score: 0.9,
            mae: 0.1,
            mse: 0.01,
            rmse: 0.1,
            mape: 10.0,
            directionalAccuracy: 0.9,
            sharpeRatio: nil,
            maxDrawdown: nil,
            hitRate: 0.9,
            confidence: classification.confidence,
            validationPeriod: classification.duration,
            sampleSize: actualData.count
        )
    }

    public func validateReversalPrediction(prediction: ReversalPrediction, actualData: [MarketDataPoint]) async throws -> ValidationResult {
        return ValidationResult(
            modelType: .reversalPrediction,
            timestamp: Date(),
            accuracy: 0.7,
            precision: 0.65,
            recall: 0.75,
            f1Score: 0.7,
            mae: 0.2,
            mse: 0.04,
            rmse: 0.2,
            mape: 20.0,
            directionalAccuracy: 0.7,
            sharpeRatio: nil,
            maxDrawdown: nil,
            hitRate: 0.7,
            confidence: prediction.confidence,
            validationPeriod: 3600,
            sampleSize: actualData.count
        )
    }

    public func calculateModelMetrics(predictions: [PredictionResponse], actualData: [MarketDataPoint]) async throws -> ValidationModelMetrics {
        return ValidationModelMetrics(
            modelType: .pricePrediction,
            averageAccuracy: 0.85,
            averagePrecision: 0.82,
            averageRecall: 0.88,
            averageF1Score: 0.85,
            averageMAE: 100.0,
            averageMSE: 10000.0,
            averageRMSE: 100.0,
            averageMAPE: 2.0,
            averageDirectionalAccuracy: 0.8,
            averageHitRate: 0.85,
            consistency: 0.9,
            stability: 0.85,
            totalValidations: predictions.count,
            validationPeriod: 3600,
            lastUpdated: Date()
        )
    }

    public func performBacktesting(modelType: ModelType, historicalData: [MarketDataPoint], lookbackPeriod: TimeInterval) async throws -> BacktestResult {
        return BacktestResult(
            modelType: modelType,
            startDate: historicalData.first?.timestamp ?? Date(),
            endDate: historicalData.last?.timestamp ?? Date(),
            totalTrades: 100,
            winningTrades: 60,
            losingTrades: 40,
            winRate: 0.6,
            averageWin: 150.0,
            averageLoss: -100.0,
            profitFactor: 1.5,
            totalReturn: 0.15,
            annualizedReturn: 0.12,
            sharpeRatio: 1.2,
            maxDrawdown: 0.08,
            maxDrawdownDuration: 3600,
            calmarRatio: 1.5,
            sortinoRatio: 1.8,
            var95: -0.05,
            cvar95: -0.08,
            trades: []
        )
    }

    public func performWalkForwardValidation(modelType: ModelType, historicalData: [MarketDataPoint], trainingWindow: TimeInterval, validationWindow: TimeInterval, stepSize: TimeInterval) async throws -> WalkForwardResult {
        _ = Int((historicalData.count * Int(stepSize)) / Int(validationWindow))
        let averageAccuracy = Double.random(in: 0.7...0.9)
        _ = Double.random(in: 0.1...0.3)

        return WalkForwardResult(
            modelType: .pricePrediction,
            totalFolds: 5,
            averageAccuracy: averageAccuracy,
            averageF1Score: Double.random(in: 0.6...0.9),
            averageMAPE: Double.random(in: 0.05...0.15),
            averageMAE: Double.random(in: 0.02...0.08),
            averageRMSE: Double.random(in: 0.03...0.12),
            consistency: Double.random(in: 0.7...0.95),
            stability: Double.random(in: 0.6...0.9),
            foldResults: [],
            timestamp: Date()
        )
    }

    public func trackPredictionAccuracy(prediction: PredictionResponse, actualData: [MarketDataPoint]) async throws -> AccuracyTrackingResult {
        let actualValue = actualData.last?.close ?? 0.0
        let predictedValue = prediction.prediction
        let error = abs(predictedValue - actualValue)
        let absoluteError = error
        let percentageError = actualValue != 0 ? (error / actualValue) * 100 : 0
        let tolerance = 0.05
        let isWithinTolerance = percentageError <= tolerance * 100

        return AccuracyTrackingResult(
            predictionId: prediction.id,
            timestamp: Date(),
            actualValue: actualValue,
            predictedValue: predictedValue,
            error: error,
            absoluteError: absoluteError,
            percentageError: percentageError,
            isWithinTolerance: isWithinTolerance,
            tolerance: tolerance,
            confidence: prediction.confidence
        )
    }
}

public class MockBootstrapTrainer: BootstrapTrainingProtocol {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func bootstrapModel(for modelType: ModelType, trainingData: [MarketDataPoint]) async throws -> BootstrapResult {
        let modelInfo = ModelInfo(
            modelId: "bootstrap-\(modelType.rawValue.lowercased())",
            version: "1.0.0",
            modelType: ModelInfo.ModelType(rawValue: modelType.rawValue) ?? .pricePrediction,
            trainingDataHash: "bootstrap-hash",
            accuracy: 0.85,
            createdAt: Date(),
            isActive: true
        )

        let trainingMetrics = TrainingMetrics(
            epochs: 100,
            learningRate: 0.001,
            batchSize: 32,
            trainingLoss: 0.1,
            validationLoss: 0.12,
            accuracy: 0.85,
            precision: 0.82,
            recall: 0.88,
            f1Score: 0.85,
            convergenceEpoch: 80,
            overfittingDetected: false,
            gradientNorm: 0.5
        )

        let validationResult = ValidationResult(
            modelType: modelType,
            timestamp: Date(),
            accuracy: 0.85,
            precision: 0.82,
            recall: 0.88,
            f1Score: 0.85,
            mae: 100.0,
            mse: 10000.0,
            rmse: 100.0,
            mape: 2.0,
            directionalAccuracy: 0.8,
            sharpeRatio: 1.5,
            maxDrawdown: 0.05,
            hitRate: 0.85,
            confidence: 0.85,
            validationPeriod: 3600,
            sampleSize: trainingData.count
        )

        return BootstrapResult(
            modelType: modelType,
            symbol: trainingData.first?.symbol ?? "UNKNOWN",
            modelInfo: modelInfo,
            trainingMetrics: trainingMetrics,
            validationResult: validationResult,
            bootstrapSamples: 10,
            trainingDuration: 3600,
            timestamp: Date()
        )
    }

    public func createInitialModel(symbol: String, modelType: ModelType) async throws -> ModelInfo {
        return ModelInfo(
            modelId: "initial-\(modelType.rawValue.lowercased())",
            version: "1.0.0",
            modelType: ModelInfo.ModelType(rawValue: modelType.rawValue) ?? .pricePrediction,
            trainingDataHash: "initial-hash",
            accuracy: 0.8,
            createdAt: Date(),
            isActive: true
        )
    }

    public func validateBootstrapModel(model: ModelInfo, validationData: [MarketDataPoint]) async throws -> ValidationResult {
        return ValidationResult(
            modelType: ModelType(rawValue: model.modelType.rawValue) ?? .pricePrediction,
            timestamp: Date(),
            accuracy: model.accuracy,
            precision: model.accuracy * 0.95,
            recall: model.accuracy * 1.05,
            f1Score: model.accuracy,
            mae: 100.0,
            mse: 10000.0,
            rmse: 100.0,
            mape: 2.0,
            directionalAccuracy: model.accuracy,
            sharpeRatio: 1.5,
            maxDrawdown: 0.05,
            hitRate: model.accuracy,
            confidence: model.accuracy,
            validationPeriod: 3600,
            sampleSize: validationData.count
        )
    }

    public func deployBootstrapModel(model: ModelInfo) async throws -> DeploymentResult {
        return DeploymentResult(
            modelId: model.modelId,
            deploymentStatus: .deployed,
            deploymentTime: Date(),
            endpoint: "http://localhost:8080/predict",
            version: model.version,
            healthCheck: ServiceHealth(
                name: "MockService",
                status: .healthy,
                latency: 0.05,
                errorRate: 0.01,
                lastCheck: Date(),
                details: ["activeModels": model.modelId]
            ),
            performanceMetrics: TrainingPerformanceMetrics(
                latency: 0.05,
                throughput: 1000.0,
                memoryUsage: 0.4,
                cpuUsage: 0.3,
                errorRate: 0.01,
                availability: 0.99
            )
        )
    }
}

public class MockModelManager: ModelManagerProtocol {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func deployModel(_ modelInfo: ModelInfo, strategy: DeploymentStrategy) async throws {
        logger.info(component: "MockModelManager", event: "Deployed model \(modelInfo.modelId)")
    }

    public func rollbackModel(to version: String) async throws {
        logger.info(component: "MockModelManager", event: "Rolled back to version \(version)")
    }

    public func getActiveModel(for modelType: ModelInfo.ModelType) -> ModelInfo? {
        return ModelInfo(
            modelId: "active-\(modelType.rawValue.lowercased())",
            version: "1.0.0",
            modelType: modelType,
            trainingDataHash: "active-hash",
            accuracy: 0.85,
            createdAt: Date(),
            isActive: true
        )
    }

    public func getAllModels() -> [ModelInfo] {
        return [
            getActiveModel(for: .pricePrediction),
            getActiveModel(for: .volatilityPrediction),
            getActiveModel(for: .trendClassification)
        ].compactMap { $0 }
    }

    public func validateModel(_ modelInfo: ModelInfo) -> Bool {
        return modelInfo.accuracy > 0.0 && modelInfo.accuracy <= 1.0
    }

    public func archiveModel(_ modelId: String) async throws {
        logger.info(component: "MockModelManager", event: "Archived model \(modelId)")
    }
}

public class MockInferenceService: InferenceServiceProtocol, @unchecked Sendable {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func predict(request: PredictionRequest) async throws -> PredictionResponse {
        let prediction: Double
        switch request.modelType {
        case .pricePrediction:
            prediction = Double.random(in: 40000...60000)
        case .volatilityPrediction:
            prediction = Double.random(in: 0.01...0.05)
        case .trendClassification:
            prediction = Double.random(in: 0...1)
        case .patternRecognition:
            prediction = 0.0
        }

        return PredictionResponse(
            id: UUID().uuidString,
            prediction: prediction,
            confidence: Double.random(in: 0.7...0.95),
            uncertainty: Double.random(in: 0.05...0.2),
            modelVersion: "1.0.0",
            timestamp: Date()
        )
    }

    public func batchPredict(requests: [PredictionRequest]) async throws -> [PredictionResponse] {
        var results: [PredictionResponse] = []
        for request in requests {
            let response = try await predict(request: request)
            results.append(response)
        }
        return results
    }

    public func getServiceHealth() -> InferenceServiceHealth {
        return InferenceServiceHealth(
            isHealthy: true,
            latency: 0.05,
            cacheHitRate: 0.85,
            activeModels: ["price-prediction-v1"],
            lastUpdated: Date()
        )
    }

    public func warmupModels() async throws {
        logger.info(component: "MockInferenceService", event: "Models warmed up")
    }
}

public class FailingMockInferenceService: InferenceServiceProtocol, @unchecked Sendable {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func predict(request: PredictionRequest) async throws -> PredictionResponse {
        throw MLEngineError.predictionFailed
    }

    public func batchPredict(requests: [PredictionRequest]) async throws -> [PredictionResponse] {
        throw MLEngineError.predictionFailed
    }

    public func getServiceHealth() -> InferenceServiceHealth {
        return InferenceServiceHealth(
            isHealthy: false,
            latency: 0.0,
            cacheHitRate: 0.0,
            activeModels: [],
            lastUpdated: Date()
        )
    }

    public func warmupModels() async throws {
        throw MLEngineError.predictionFailed
    }
}

public class SlowMockPredictionEngine: PredictionEngineProtocol, @unchecked Sendable {
    private let logger: StructuredLogger
    private let delay: TimeInterval

    public init(logger: StructuredLogger, delay: TimeInterval) {
        self.logger = logger
        self.delay = delay
    }

    public func predictPrice(request: PredictionRequest) async throws -> PredictionResponse {
        try await Task.sleep(for: .seconds(delay))
        return PredictionResponse(
            id: UUID().uuidString,
            prediction: Double.random(in: 40000...60000),
            confidence: Double.random(in: 0.7...0.95),
            uncertainty: Double.random(in: 0.05...0.2),
            modelVersion: "1.0.0",
            timestamp: Date()
        )
    }

    public func predictVolatility(request: PredictionRequest) async throws -> PredictionResponse {
        try await Task.sleep(for: .seconds(delay))
        throw PredictionError.predictionFailed
    }

    public func classifyTrend(request: PredictionRequest) async throws -> PredictionResponse {
        try await Task.sleep(for: .seconds(delay))
        throw PredictionError.predictionFailed
    }

    public func batchPredict(requests: [PredictionRequest]) async throws -> [PredictionResponse] {
        try await Task.sleep(for: .seconds(delay))
        throw PredictionError.predictionFailed
    }

    public func getModelInfo(for modelType: ModelInfo.ModelType) -> ModelInfo? {
        return nil
    }
}

public func createSlowMockMLPatternEngine(
    logger: StructuredLogger,
    delay: TimeInterval
) -> MLPatternEngine {
    let mockDataIngestion = MockDataIngestionService(logger: logger)
    let mockFeatureExtractor = MockFeatureExtractor(logger: logger)
    let mockPatternRecognizer = MockPatternRecognizer(logger: logger)
    let mockPredictionEngine = SlowMockPredictionEngine(logger: logger, delay: delay)
    let mockVolatilityPredictor = MockVolatilityPredictor(logger: logger)
    let mockTrendClassifier = MockTrendClassifier(logger: logger)
    let mockPredictionValidator = MockPredictionValidator(logger: logger)
    let mockBootstrapTrainer = MockBootstrapTrainer(logger: logger)
    let mockModelManager = MockModelManager(logger: logger)
    let mockInferenceService = MockInferenceService(logger: logger)

    return MLPatternEngine(
        dataIngestionService: mockDataIngestion,
        featureExtractor: mockFeatureExtractor,
        patternRecognizer: mockPatternRecognizer,
        predictionEngine: mockPredictionEngine,
        volatilityPredictor: mockVolatilityPredictor,
        trendClassifier: mockTrendClassifier,
        predictionValidator: mockPredictionValidator,
        bootstrapTrainer: mockBootstrapTrainer,
        modelManager: mockModelManager,
        inferenceService: mockInferenceService,
        logger: logger
    )
}