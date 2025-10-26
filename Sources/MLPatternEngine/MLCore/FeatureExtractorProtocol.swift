import Foundation

public protocol FeatureExtractorProtocol {
    func extractFeatures(from dataPoints: [MarketDataPoint]) async throws -> [FeatureSet]
    func extractFeatures(from dataPoint: MarketDataPoint, historicalData: [MarketDataPoint]) async throws -> FeatureSet
    func getFeatureNames() -> [String]
    func validateFeatureSet(_ featureSet: FeatureSet) -> Bool
}

public protocol TechnicalIndicatorsProtocol {
    func calculateRSI(prices: [Double], period: Int) -> [Double]
    func calculateMACD(prices: [Double], fastPeriod: Int, slowPeriod: Int, signalPeriod: Int) -> (macd: [Double], signal: [Double], histogram: [Double])
    func calculateEMA(prices: [Double], period: Int) -> [Double]
    func calculateBollingerBands(prices: [Double], period: Int, standardDeviations: Double) -> (upper: [Double], middle: [Double], lower: [Double])
    func calculateStochastic(high: [Double], low: [Double], close: [Double], kPeriod: Int, dPeriod: Int) -> (k: [Double], d: [Double])
    func calculateVolumeProfile(volumes: [Double], prices: [Double], bins: Int) -> [Double: Double]
}

public protocol PatternRecognitionProtocol {
    func detectPatterns(in dataPoints: [MarketDataPoint]) async throws -> [DetectedPattern]
    func detectPattern(in dataPoints: [MarketDataPoint], patternType: DetectedPattern.PatternType) async throws -> [DetectedPattern]
    func calculatePatternConfidence(_ pattern: DetectedPattern, historicalData: [MarketDataPoint]) -> Double
    func validatePattern(_ pattern: DetectedPattern) -> Bool
}

public protocol PredictionEngineProtocol {
    func predictPrice(request: PredictionRequest) async throws -> PredictionResponse
    func predictVolatility(request: PredictionRequest) async throws -> PredictionResponse
    func classifyTrend(request: PredictionRequest) async throws -> PredictionResponse
    func batchPredict(requests: [PredictionRequest]) async throws -> [PredictionResponse]
    func getModelInfo(for modelType: ModelInfo.ModelType) -> ModelInfo?
}
