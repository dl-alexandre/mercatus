import Foundation
import Utils

public class FeatureExtractor: FeatureExtractorProtocol {
    private let technicalIndicators: TechnicalIndicatorsProtocol
    private let logger: StructuredLogger

    public init(technicalIndicators: TechnicalIndicatorsProtocol, logger: StructuredLogger) {
        self.technicalIndicators = technicalIndicators
        self.logger = logger
    }

    public func extractFeatures(from dataPoints: [MarketDataPoint]) async throws -> [FeatureSet] {
        guard dataPoints.count >= 50 else {
            throw FeatureExtractionError.insufficientData
        }

        let sortedData = dataPoints.sorted { $0.timestamp < $1.timestamp }
        var featureSets: [FeatureSet] = []

        for i in 50..<sortedData.count {
            let historicalData = Array(sortedData[0...i])
            let currentData = sortedData[i]

            do {
                let featureSet = try await extractFeatures(from: currentData, historicalData: historicalData)
                featureSets.append(featureSet)
            } catch {
                logger.warn(component: "FeatureExtractor", event: "Failed to extract features for \(currentData.symbol) at \(currentData.timestamp): \(error)")
            }
        }

        return featureSets
    }

    public func extractFeatures(from dataPoint: MarketDataPoint, historicalData: [MarketDataPoint]) async throws -> FeatureSet {
        guard historicalData.count >= 50 else {
            throw FeatureExtractionError.insufficientData
        }

        let sortedData = historicalData.sorted { $0.timestamp < $1.timestamp }
        let prices = sortedData.map { $0.close }
        let volumes = sortedData.map { $0.volume }
        let highs = sortedData.map { $0.high }
        let lows = sortedData.map { $0.low }

        var features: [String: Double] = [:]

        features["price"] = dataPoint.close
        features["volume"] = dataPoint.volume
        features["price_change"] = calculatePriceChange(prices)
        features["volume_change"] = calculateVolumeChange(volumes)
        features["volatility"] = calculateVolatility(prices)

        let rsi = technicalIndicators.calculateRSI(prices: prices, period: 14)
        if let lastRSI = rsi.last {
            features["rsi"] = lastRSI
        }

        let macd = technicalIndicators.calculateMACD(prices: prices, fastPeriod: 12, slowPeriod: 26, signalPeriod: 9)
        if let lastMACD = macd.macd.last {
            features["macd"] = lastMACD
        }
        if let lastSignal = macd.signal.last {
            features["macd_signal"] = lastSignal
        }
        if let lastHistogram = macd.histogram.last {
            features["macd_histogram"] = lastHistogram
        }

        let ema12 = technicalIndicators.calculateEMA(prices: prices, period: 12)
        if let lastEMA12 = ema12.last {
            features["ema_12"] = lastEMA12
        }

        let ema26 = technicalIndicators.calculateEMA(prices: prices, period: 26)
        if let lastEMA26 = ema26.last {
            features["ema_26"] = lastEMA26
        }

        let bollinger = technicalIndicators.calculateBollingerBands(prices: prices, period: 20, standardDeviations: 2.0)
        if let lastUpper = bollinger.upper.last,
           let lastMiddle = bollinger.middle.last,
           let lastLower = bollinger.lower.last {
            features["bb_upper"] = lastUpper
            features["bb_middle"] = lastMiddle
            features["bb_lower"] = lastLower
            features["bb_position"] = (dataPoint.close - lastLower) / (lastUpper - lastLower)
        }

        let stochastic = technicalIndicators.calculateStochastic(high: highs, low: lows, close: prices, kPeriod: 14, dPeriod: 3)
        if let lastK = stochastic.k.last {
            features["stoch_k"] = lastK
        }
        if let lastD = stochastic.d.last {
            features["stoch_d"] = lastD
        }

        let volumeProfile = technicalIndicators.calculateVolumeProfile(volumes: volumes, prices: prices, bins: 20)
        features["volume_profile_peak"] = volumeProfile.values.max() ?? 0

        features["support_level"] = calculateSupportLevel(prices)
        features["resistance_level"] = calculateResistanceLevel(prices)
        features["trend_strength"] = calculateTrendStrength(prices)

        let qualityScore = calculateFeatureQuality(features)

        return FeatureSet(
            timestamp: dataPoint.timestamp,
            symbol: dataPoint.symbol,
            features: features,
            qualityScore: qualityScore
        )
    }

    public func getFeatureNames() -> [String] {
        return [
            "price", "volume", "price_change", "volume_change", "volatility",
            "rsi", "macd", "macd_signal", "macd_histogram",
            "ema_12", "ema_26",
            "bb_upper", "bb_middle", "bb_lower", "bb_position",
            "stoch_k", "stoch_d",
            "volume_profile_peak",
            "support_level", "resistance_level", "trend_strength"
        ]
    }

    public func validateFeatureSet(_ featureSet: FeatureSet) -> Bool {
        let requiredFeatures = getFeatureNames()

        for featureName in requiredFeatures {
            guard let value = featureSet.features[featureName] else {
                return false
            }

            if value.isNaN || value.isInfinite {
                return false
            }
        }

        return featureSet.qualityScore > 0.5
    }

    private func calculatePriceChange(_ prices: [Double]) -> Double {
        guard prices.count >= 2 else { return 0.0 }
        return (prices.last! - prices[prices.count - 2]) / prices[prices.count - 2]
    }

    private func calculateVolumeChange(_ volumes: [Double]) -> Double {
        guard volumes.count >= 2 else { return 0.0 }
        return (volumes.last! - volumes[volumes.count - 2]) / volumes[volumes.count - 2]
    }

    private func calculateVolatility(_ prices: [Double]) -> Double {
        guard prices.count >= 2 else { return 0.0 }

        let returns = zip(prices.dropFirst(), prices).map { (current, previous) in
            (current - previous) / previous
        }

        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(returns.count)

        return sqrt(variance)
    }

    private func calculateSupportLevel(_ prices: [Double]) -> Double {
        guard prices.count >= 20 else { return prices.min() ?? 0.0 }

        let recentPrices = Array(prices.suffix(20))
        return recentPrices.min() ?? 0.0
    }

    private func calculateResistanceLevel(_ prices: [Double]) -> Double {
        guard prices.count >= 20 else { return prices.max() ?? 0.0 }

        let recentPrices = Array(prices.suffix(20))
        return recentPrices.max() ?? 0.0
    }

    private func calculateTrendStrength(_ prices: [Double]) -> Double {
        guard prices.count >= 20 else { return 0.0 }

        let recentPrices = Array(prices.suffix(20))
        let firstPrice = recentPrices.first!
        let lastPrice = recentPrices.last!

        return (lastPrice - firstPrice) / firstPrice
    }

    private func calculateFeatureQuality(_ features: [String: Double]) -> Double {
        let validFeatures = features.values.filter { !$0.isNaN && !$0.isInfinite }
        return Double(validFeatures.count) / Double(features.count)
    }
}

public enum FeatureExtractionError: Error {
    case insufficientData
    case invalidDataPoint
    case calculationError
}
