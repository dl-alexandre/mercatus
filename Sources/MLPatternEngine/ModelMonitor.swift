// Model monitoring and drift detection for portfolio ML models
// Implements concept drift detection and performance monitoring

import Foundation
import Utils

public class ModelMonitor {
    private let referenceDistribution: [String: (hist: [Float], bins: [Float])]
    private let driftThreshold: Float
    private var alerts: [(timestamp: Date, driftScore: Float, featuresAffected: Int)] = []
    private let logger: StructuredLogger

    public init(referenceData: [[String: Float]], driftThreshold: Float = 0.1, logger: StructuredLogger) {
        self.referenceDistribution = Self.calculateDistribution(data: referenceData)
        self.driftThreshold = driftThreshold
        self.logger = logger
    }

    public func detectDrift(newData: [[String: Float]]) -> Bool {
        let newDistribution = Self.calculateDistribution(data: newData)
        var driftScore: Float = 0.0
        var affectedFeatures = 0

        for (feature, (refHist, refBins)) in referenceDistribution {
            if let (newHist, newBins) = newDistribution[feature] {
                // Simplified Kolmogorov-Smirnov test approximation
                let ksStatistic = calculateKSDistance(hist1: refHist, bins1: refBins, hist2: newHist, bins2: newBins)

                if ksStatistic > 0.1 {  // Significant difference threshold
                    driftScore += ksStatistic
                    affectedFeatures += 1
                }
            }
        }

        if driftScore > driftThreshold {
            let alert = (timestamp: Date(), driftScore: driftScore, featuresAffected: affectedFeatures)
            alerts.append(alert)

            logger.info(component: "ModelMonitor", event: "Concept drift detected",
                        data: [
                            "driftScore": String(driftScore),
                            "featuresAffected": String(affectedFeatures),
                            "threshold": String(driftThreshold)
                        ])

            return true
        }

        return false
    }

    public func getAlerts() -> [(timestamp: Date, driftScore: Float, featuresAffected: Int)] {
        return alerts
    }

    public func resetAlerts() {
        alerts.removeAll()
    }

    private static func calculateDistribution(data: [[String: Float]]) -> [String: (hist: [Float], bins: [Float])] {
        var distributions: [String: (hist: [Float], bins: [Float])] = [:]

        guard let firstRow = data.first else { return distributions }

        for feature in firstRow.keys {
            let values = data.compactMap { $0[feature] }
            let (hist, bins) = histogram(values: values, bins: 50)
            distributions[feature] = (hist: hist, bins: bins)
        }

        return distributions
    }

    private func calculateKSDistance(hist1: [Float], bins1: [Float], hist2: [Float], bins2: [Float]) -> Float {
        // Simplified KS distance calculation
        // In practice, use proper statistical tests
        var maxDiff: Float = 0.0

        // Normalize histograms
        let sum1 = hist1.reduce(0, +)
        let sum2 = hist2.reduce(0, +)
        let normHist1 = hist1.map { $0 / sum1 }
        let normHist2 = hist2.map { $0 / sum2 }

        for i in 0..<min(normHist1.count, normHist2.count) {
            let diff = abs(normHist1[i] - normHist2[i])
            maxDiff = max(maxDiff, diff)
        }

        return maxDiff
    }

    private static func histogram(values: [Float], bins: Int) -> (hist: [Float], bins: [Float]) {
        guard !values.isEmpty else { return ([], []) }

        let minVal = values.min()!
        let maxVal = values.max()!
        let binWidth = (maxVal - minVal) / Float(bins)

        var hist = Array(repeating: Float(0), count: bins)
        var binEdges: [Float] = []

        for i in 0...bins {
            binEdges.append(minVal + Float(i) * binWidth)
        }

        for value in values {
            let binIndex = min(Int((value - minVal) / binWidth), bins - 1)
            hist[binIndex] += 1
        }

        return (hist, binEdges)
    }
}

// Performance monitoring for ML models
public class PerformanceMonitor {
    private var predictions: [(actual: Float, predicted: Float, timestamp: Date)] = []
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func recordPrediction(actual: Float, predicted: Float) {
        predictions.append((actual: actual, predicted: predicted, timestamp: Date()))

        // Keep only last 1000 predictions for memory efficiency
        if predictions.count > 1000 {
            predictions.removeFirst(predictions.count - 1000)
        }
    }

    public func calculateMetrics() -> (mae: Float, rmse: Float, mape: Float) {
        guard !predictions.isEmpty else { return (0, 0, 0) }

        var sumMAE: Float = 0
        var sumMSE: Float = 0
        var sumMAPE: Float = 0

        for pred in predictions {
            let error = pred.predicted - pred.actual
            sumMAE += abs(error)
            sumMSE += error * error
            sumMAPE += abs(error / max(pred.actual, 0.001))
        }

        let count = Float(predictions.count)
        let mae = sumMAE / count
        let rmse = sqrt(sumMSE / count)
        let mape = sumMAPE / count

        return (mae, rmse, mape)
    }

    public func getRecentPredictions(count: Int = 100) -> [(actual: Float, predicted: Float, timestamp: Date)] {
        return Array(predictions.suffix(count))
    }

    public func checkPerformanceThreshold(maeThreshold: Float = 0.1) -> Bool {
        let metrics = calculateMetrics()
        let degraded = metrics.mae > maeThreshold

        if degraded {
            logger.info(component: "PerformanceMonitor", event: "Model performance degraded",
                        data: [
                            "mae": String(metrics.mae),
                            "rmse": String(metrics.rmse),
                            "mape": String(metrics.mape),
                            "threshold": String(maeThreshold)
                        ])
        }

        return degraded
    }
}
