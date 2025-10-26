import Foundation
import Utils

public class PredictionEngine: PredictionEngineProtocol {
    private let logger: StructuredLogger
    private var models: [ModelInfo.ModelType: ModelInfo] = [:]

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func predictPrice(request: PredictionRequest) async throws -> PredictionResponse {
        guard let model = models[request.modelType] else {
            throw PredictionError.modelNotAvailable
        }

        let prediction = try await performPricePrediction(features: request.features, timeHorizon: request.timeHorizon)
        let confidence = calculateConfidence(features: request.features)
        let uncertainty = calculateUncertainty(features: request.features)

        return PredictionResponse(
            id: UUID().uuidString,
            prediction: prediction,
            confidence: confidence,
            uncertainty: uncertainty,
            modelVersion: model.version,
            timestamp: Date()
        )
    }

    public func predictVolatility(request: PredictionRequest) async throws -> PredictionResponse {
        guard let model = models[request.modelType] else {
            throw PredictionError.modelNotAvailable
        }

        let prediction = try await performVolatilityPrediction(features: request.features, timeHorizon: request.timeHorizon)
        let confidence = calculateConfidence(features: request.features)
        let uncertainty = calculateUncertainty(features: request.features)

        return PredictionResponse(
            id: UUID().uuidString,
            prediction: prediction,
            confidence: confidence,
            uncertainty: uncertainty,
            modelVersion: model.version,
            timestamp: Date()
        )
    }

    public func classifyTrend(request: PredictionRequest) async throws -> PredictionResponse {
        guard let model = models[request.modelType] else {
            throw PredictionError.modelNotAvailable
        }

        let prediction = try await performTrendClassification(features: request.features)
        let confidence = calculateConfidence(features: request.features)
        let uncertainty = calculateUncertainty(features: request.features)

        return PredictionResponse(
            id: UUID().uuidString,
            prediction: prediction,
            confidence: confidence,
            uncertainty: uncertainty,
            modelVersion: model.version,
            timestamp: Date()
        )
    }

    public func batchPredict(requests: [PredictionRequest]) async throws -> [PredictionResponse] {
        var responses: [PredictionResponse] = []

        for request in requests {
            do {
                let response: PredictionResponse
                switch request.modelType {
                case .pricePrediction:
                    response = try await predictPrice(request: request)
                case .volatilityPrediction:
                    response = try await predictVolatility(request: request)
                case .trendClassification:
                    response = try await classifyTrend(request: request)
                case .patternRecognition:
                    throw PredictionError.unsupportedModelType
                }
                responses.append(response)
            } catch {
                logger.error(component: "PredictionEngine", event: "Failed to predict for \(request.symbol): \(error)")
            }
        }

        return responses
    }

    public func getModelInfo(for modelType: ModelInfo.ModelType) -> ModelInfo? {
        return models[modelType]
    }

    public func loadModel(_ modelInfo: ModelInfo) {
        models[modelInfo.modelType] = modelInfo
        logger.info(component: "PredictionEngine", event: "Loaded model \(modelInfo.modelId) version \(modelInfo.version)")
    }

    private func performPricePrediction(features: [String: Double], timeHorizon: TimeInterval) async throws -> Double {
        guard let currentPrice = features["price"] else {
            throw PredictionError.invalidFeatures
        }

        let trendStrength = features["trend_strength"] ?? 0.0
        let volatility = features["volatility"] ?? 0.0
        let rsi = features["rsi"] ?? 50.0

        let timeMultiplier = timeHorizon / 3600.0 // Convert to hours

        let trendComponent = trendStrength * timeMultiplier * 0.1
        let volatilityComponent = volatility * timeMultiplier * 0.05
        let rsiComponent = (rsi - 50.0) / 50.0 * timeMultiplier * 0.02

        let prediction = currentPrice * (1.0 + trendComponent + volatilityComponent + rsiComponent)

        return max(0.0, prediction)
    }

    private func performVolatilityPrediction(features: [String: Double], timeHorizon: TimeInterval) async throws -> Double {
        let currentVolatility = features["volatility"] ?? 0.0
        let priceChange = features["price_change"] ?? 0.0
        let volumeChange = features["volume_change"] ?? 0.0

        let timeMultiplier = timeHorizon / 3600.0

        let priceVolatilityComponent = abs(priceChange) * timeMultiplier
        let volumeVolatilityComponent = abs(volumeChange) * timeMultiplier * 0.5

        let prediction = currentVolatility * (1.0 + priceVolatilityComponent + volumeVolatilityComponent)

        return max(0.0, prediction)
    }

    private func performTrendClassification(features: [String: Double]) async throws -> Double {
        let trendStrength = features["trend_strength"] ?? 0.0
        let rsi = features["rsi"] ?? 50.0
        let macd = features["macd"] ?? 0.0
        let macdSignal = features["macd_signal"] ?? 0.0

        let trendScore = trendStrength * 0.4
        let rsiScore = (rsi - 50.0) / 50.0 * 0.3
        let macdScore = (macd - macdSignal) * 0.3

        let classification = trendScore + rsiScore + macdScore

        return max(-1.0, min(1.0, classification))
    }

    private func calculateConfidence(features: [String: Double]) -> Double {
        let requiredFeatures = ["price", "volatility", "trend_strength", "rsi", "macd"]
        let availableFeatures = requiredFeatures.filter { features[$0] != nil }.count

        let featureCompleteness = Double(availableFeatures) / Double(requiredFeatures.count)

        let volatility = features["volatility"] ?? 0.0
        let volatilityPenalty = min(1.0, volatility * 2.0)

        return featureCompleteness * (1.0 - volatilityPenalty * 0.3)
    }

    private func calculateUncertainty(features: [String: Double]) -> Double {
        let volatility = features["volatility"] ?? 0.0
        let priceChange = abs(features["price_change"] ?? 0.0)
        let volumeChange = abs(features["volume_change"] ?? 0.0)

        let baseUncertainty = volatility * 0.5
        let changeUncertainty = (priceChange + volumeChange) * 0.3

        return min(1.0, baseUncertainty + changeUncertainty)
    }
}

public enum PredictionError: Error {
    case modelNotAvailable
    case invalidFeatures
    case unsupportedModelType
    case predictionFailed
}
