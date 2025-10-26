import Foundation

public protocol ModelManagerProtocol {
    func deployModel(_ modelInfo: ModelInfo, strategy: DeploymentStrategy) async throws
    func rollbackModel(to version: String) async throws
    func getActiveModel(for modelType: ModelInfo.ModelType) -> ModelInfo?
    func getAllModels() -> [ModelInfo]
    func validateModel(_ modelInfo: ModelInfo) -> Bool
    func archiveModel(_ modelId: String) async throws
}

public enum DeploymentStrategy: String, CaseIterable {
    case immediate = "IMMEDIATE"
    case canary = "CANARY"
    case shadow = "SHADOW"
}

public protocol TrainingOrchestratorProtocol {
    func trainModel(modelType: ModelInfo.ModelType, trainingData: [MarketDataPoint]) async throws -> ModelInfo
    func retrainModel(modelId: String, newData: [MarketDataPoint]) async throws -> ModelInfo
    func validateModelPerformance(_ modelInfo: ModelInfo, testData: [MarketDataPoint]) async throws -> TrainingModelPerformance
    func detectDrift(modelId: String, newData: [MarketDataPoint]) async throws -> DriftResult
}

public struct TrainingModelPerformance {
    public let accuracy: Double
    public let f1Score: Double
    public let mape: Double
    public let precision: Double
    public let recall: Double
    public let timestamp: Date

    public init(accuracy: Double, f1Score: Double, mape: Double, precision: Double, recall: Double, timestamp: Date) {
        self.accuracy = accuracy
        self.f1Score = f1Score
        self.mape = mape
        self.precision = precision
        self.recall = recall
        self.timestamp = timestamp
    }
}

public struct DriftResult {
    public let hasDrift: Bool
    public let driftScore: Double
    public let driftType: DriftType
    public let confidence: Double
    public let timestamp: Date

    public init(hasDrift: Bool, driftScore: Double, driftType: DriftType, confidence: Double, timestamp: Date) {
        self.hasDrift = hasDrift
        self.driftScore = driftScore
        self.driftType = driftType
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

public enum DriftType: String, CaseIterable {
    case covariate = "COVARIATE"
    case concept = "CONCEPT"
    case prediction = "PREDICTION"
    case data = "DATA"
}
