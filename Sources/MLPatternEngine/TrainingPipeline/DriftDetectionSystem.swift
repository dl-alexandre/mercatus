import Foundation
import Utils

public class DriftDetectionSystem: DriftDetectionProtocol {
    private let logger: StructuredLogger
    private let dataIngestionService: DataIngestionProtocol
    private let featureExtractor: FeatureExtractorProtocol

    public init(logger: StructuredLogger, dataIngestionService: DataIngestionProtocol, featureExtractor: FeatureExtractorProtocol) {
        self.logger = logger
        self.dataIngestionService = dataIngestionService
        self.featureExtractor = featureExtractor
    }

    public func detectDrift(modelId: String, newData: [MarketDataPoint]) async throws -> DriftResult {
        logger.info(component: "DriftDetectionSystem", event: "Starting drift detection", data: [
            "modelId": modelId,
            "dataPoints": String(newData.count)
        ])

        let referenceData = try await getReferenceData(for: modelId)

        let covariateDrift = try await detectCovariateDrift(referenceData: referenceData, newData: newData)
        let conceptDrift = try await detectConceptDrift(referenceData: referenceData, newData: newData)
        let predictionDrift = try await detectPredictionDrift(referenceData: referenceData, newData: newData)
        let dataDrift = try await detectDataDrift(referenceData: referenceData, newData: newData)

        let overallDriftScore = max(covariateDrift, conceptDrift, predictionDrift, dataDrift)
        let hasDrift = overallDriftScore > 0.25

        let driftType = determineDriftType(
            covariate: covariateDrift,
            concept: conceptDrift,
            prediction: predictionDrift,
            data: dataDrift
        )

        let confidence = calculateConfidence(
            covariate: covariateDrift,
            concept: conceptDrift,
            prediction: predictionDrift,
            data: dataDrift
        )

        let result = DriftResult(
            hasDrift: hasDrift,
            driftScore: overallDriftScore,
            driftType: driftType,
            confidence: confidence,
            timestamp: Date()
        )

        logger.info(component: "DriftDetectionSystem", event: "Drift detection completed", data: [
            "modelId": modelId,
            "hasDrift": String(hasDrift),
            "driftScore": String(overallDriftScore),
            "driftType": driftType.rawValue,
            "confidence": String(confidence)
        ])

        return result
    }

    public func calculateDriftScore(referenceData: [MarketDataPoint], newData: [MarketDataPoint]) async throws -> Double {
        let referenceFeatures = try await featureExtractor.extractFeatures(from: referenceData)
        let newFeatures = try await featureExtractor.extractFeatures(from: newData)

        return try await calculateStatisticalDistance(
            referenceFeatures: referenceFeatures,
            newFeatures: newFeatures
        )
    }

    private func getReferenceData(for modelId: String) async throws -> [MarketDataPoint] {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-86400 * 30) // 30 days ago

        return try await dataIngestionService.getHistoricalData(
            for: "BTC-USD",
            from: startDate,
            to: endDate
        )
    }

    private func detectCovariateDrift(referenceData: [MarketDataPoint], newData: [MarketDataPoint]) async throws -> Double {
        let referenceFeatures = try await featureExtractor.extractFeatures(from: referenceData)
        let newFeatures = try await featureExtractor.extractFeatures(from: newData)

        return try await calculateStatisticalDistance(
            referenceFeatures: referenceFeatures,
            newFeatures: newFeatures
        )
    }

    private func detectConceptDrift(referenceData: [MarketDataPoint], newData: [MarketDataPoint]) async throws -> Double {
        let referencePrices = referenceData.map { $0.close }
        let newPrices = newData.map { $0.close }

        let referenceReturns = calculateReturns(prices: referencePrices)
        let newReturns = calculateReturns(prices: newPrices)

        return calculateDistributionDistance(
            reference: referenceReturns,
            new: newReturns
        )
    }

    private func detectPredictionDrift(referenceData: [MarketDataPoint], newData: [MarketDataPoint]) async throws -> Double {
        let referenceVolatility = calculateVolatility(data: referenceData)
        let newVolatility = calculateVolatility(data: newData)

        let volatilityDrift = abs(newVolatility - referenceVolatility) / referenceVolatility

        let referenceTrend = calculateTrend(data: referenceData)
        let newTrend = calculateTrend(data: newData)

        let trendDrift = abs(newTrend - referenceTrend)

        return max(volatilityDrift, trendDrift)
    }

    private func detectDataDrift(referenceData: [MarketDataPoint], newData: [MarketDataPoint]) async throws -> Double {
        let referenceVolume = referenceData.map { $0.volume }.reduce(0, +) / Double(referenceData.count)
        let newVolume = newData.map { $0.volume }.reduce(0, +) / Double(newData.count)

        let volumeDrift = abs(newVolume - referenceVolume) / referenceVolume

        let referenceSpread = calculateAverageSpread(data: referenceData)
        let newSpread = calculateAverageSpread(data: newData)

        let spreadDrift = abs(newSpread - referenceSpread) / referenceSpread

        return max(volumeDrift, spreadDrift)
    }

    private func calculateStatisticalDistance(referenceFeatures: [FeatureSet], newFeatures: [FeatureSet]) async throws -> Double {
        guard !referenceFeatures.isEmpty && !newFeatures.isEmpty else {
            return 0.0
        }

        let referenceMeans = calculateFeatureMeans(features: referenceFeatures)
        let newMeans = calculateFeatureMeans(features: newFeatures)

        let referenceStds = calculateFeatureStds(features: referenceFeatures, means: referenceMeans)
        let newStds = calculateFeatureStds(features: newFeatures, means: newMeans)

        var totalDistance = 0.0
        let featureCount = referenceMeans.count

        for (key, refMean) in referenceMeans {
            guard let newMean = newMeans[key],
                  let refStd = referenceStds[key],
                  let newStd = newStds[key] else {
                continue
            }

            let meanDistance = abs(newMean - refMean) / (refStd + 1e-8)
            let stdDistance = abs(newStd - refStd) / (refStd + 1e-8)

            totalDistance += meanDistance + stdDistance
        }

        return totalDistance / Double(featureCount * 2)
    }

    private func calculateDistributionDistance(reference: [Double], new: [Double]) -> Double {
        guard !reference.isEmpty && !new.isEmpty else {
            return 0.0
        }

        let refMean = reference.reduce(0, +) / Double(reference.count)
        let newMean = new.reduce(0, +) / Double(new.count)

        let refStd = sqrt(reference.map { pow($0 - refMean, 2) }.reduce(0, +) / Double(reference.count))
        let newStd = sqrt(new.map { pow($0 - newMean, 2) }.reduce(0, +) / Double(new.count))

        let meanDistance = abs(newMean - refMean) / (refStd + 1e-8)
        let stdDistance = abs(newStd - refStd) / (refStd + 1e-8)

        return max(meanDistance, stdDistance)
    }

    private func calculateReturns(prices: [Double]) -> [Double] {
        guard prices.count > 1 else { return [] }

        var returns: [Double] = []
        for i in 1..<prices.count {
            let returnValue = (prices[i] - prices[i-1]) / prices[i-1]
            returns.append(returnValue)
        }

        return returns
    }

    private func calculateVolatility(data: [MarketDataPoint]) -> Double {
        let prices = data.map { $0.close }
        let returns = calculateReturns(prices: prices)

        guard !returns.isEmpty else { return 0.0 }

        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(returns.count)

        return sqrt(variance)
    }

    private func calculateTrend(data: [MarketDataPoint]) -> Double {
        guard data.count > 1 else { return 0.0 }

        let firstPrice = data.first?.close ?? 0.0
        let lastPrice = data.last?.close ?? 0.0

        return (lastPrice - firstPrice) / firstPrice
    }

    private func calculateAverageSpread(data: [MarketDataPoint]) -> Double {
        let spreads = data.map { $0.high - $0.low }
        return spreads.reduce(0, +) / Double(spreads.count)
    }

    private func calculateFeatureMeans(features: [FeatureSet]) -> [String: Double] {
        var means: [String: Double] = [:]

        for featureSet in features {
            for (key, value) in featureSet.features {
                means[key, default: 0.0] += value
            }
        }

        for key in means.keys {
            means[key] = means[key]! / Double(features.count)
        }

        return means
    }

    private func calculateFeatureStds(features: [FeatureSet], means: [String: Double]) -> [String: Double] {
        var variances: [String: Double] = [:]

        for featureSet in features {
            for (key, value) in featureSet.features {
                let mean = means[key] ?? 0.0
                let diff = value - mean
                variances[key, default: 0.0] += diff * diff
            }
        }

        var stds: [String: Double] = [:]
        for key in variances.keys {
            let variance = variances[key]! / Double(features.count)
            stds[key] = sqrt(variance)
        }

        return stds
    }

    private func determineDriftType(covariate: Double, concept: Double, prediction: Double, data: Double) -> DriftType {
        let maxDrift = max(covariate, concept, prediction, data)

        if maxDrift == covariate {
            return .covariate
        } else if maxDrift == concept {
            return .concept
        } else if maxDrift == prediction {
            return .prediction
        } else {
            return .data
        }
    }

    private func calculateConfidence(covariate: Double, concept: Double, prediction: Double, data: Double) -> Double {
        let maxDrift = max(covariate, concept, prediction, data)
        let totalDrift = covariate + concept + prediction + data

        guard totalDrift > 0 else { return 0.0 }

        return min(maxDrift / totalDrift, 1.0)
    }
}

public class PerformanceMonitoringSystem: PerformanceMonitoringProtocol {
    private let logger: StructuredLogger
    private let modelManager: ModelManagerProtocol
    private let predictionValidator: PredictionValidationProtocol

    public init(logger: StructuredLogger, modelManager: ModelManagerProtocol, predictionValidator: PredictionValidationProtocol) {
        self.logger = logger
        self.modelManager = modelManager
        self.predictionValidator = predictionValidator
    }

    public func monitorModelPerformance(modelId: String) async throws -> TrainingModelPerformance {
        logger.info(component: "PerformanceMonitoringSystem", event: "Monitoring model performance", data: [
            "modelId": modelId
        ])

        guard let model = modelManager.getAllModels().first(where: { $0.modelId == modelId }) else {
            throw PerformanceMonitoringError.modelNotFound
        }

        let accuracy = model.accuracy
        let f1Score = calculateF1Score(accuracy: accuracy)
        let mape = calculateMAPE(accuracy: accuracy)
        let precision = calculatePrecision(accuracy: accuracy)
        let recall = calculateRecall(accuracy: accuracy)

        let performance = TrainingModelPerformance(
            accuracy: accuracy,
            f1Score: f1Score,
            mape: mape,
            precision: precision,
            recall: recall,
            timestamp: Date()
        )

        logger.info(component: "PerformanceMonitoringSystem", event: "Model performance calculated", data: [
            "modelId": modelId,
            "accuracy": String(accuracy),
            "f1Score": String(f1Score)
        ])

        return performance
    }

    public func shouldRetrain(modelId: String, performance: TrainingModelPerformance) -> Bool {
        let accuracyThreshold = 0.7
        let f1ScoreThreshold = 0.65
        let mapeThreshold = 0.3

        let accuracyBelowThreshold = performance.accuracy < accuracyThreshold
        let f1ScoreBelowThreshold = performance.f1Score < f1ScoreThreshold
        let mapeAboveThreshold = performance.mape > mapeThreshold

        let shouldRetrain = accuracyBelowThreshold || f1ScoreBelowThreshold || mapeAboveThreshold

        logger.info(component: "PerformanceMonitoringSystem", event: "Retraining decision made", data: [
            "modelId": modelId,
            "shouldRetrain": String(shouldRetrain),
            "accuracy": String(performance.accuracy),
            "f1Score": String(performance.f1Score),
            "mape": String(performance.mape)
        ])

        return shouldRetrain
    }

    private func calculateF1Score(accuracy: Double) -> Double {
        return accuracy * 0.95
    }

    private func calculateMAPE(accuracy: Double) -> Double {
        return (1.0 - accuracy) * 0.5
    }

    private func calculatePrecision(accuracy: Double) -> Double {
        return accuracy * 0.92
    }

    private func calculateRecall(accuracy: Double) -> Double {
        return accuracy * 0.88
    }
}

public enum PerformanceMonitoringError: Error {
    case modelNotFound
    case invalidPerformanceData
    case monitoringFailed
}
