import Foundation
import Utils

public class FeatureExtractor: FeatureExtractorProtocol {
    private let technicalIndicators: TechnicalIndicatorsProtocol
    private let logger: StructuredLogger
    private let fftAnalyzer: FFTAnalyzerProtocol

    public init(
        technicalIndicators: TechnicalIndicatorsProtocol,
        logger: StructuredLogger,
        fftAnalyzer: FFTAnalyzerProtocol? = nil
    ) {
        self.technicalIndicators = technicalIndicators
        self.logger = logger
        self.fftAnalyzer = fftAnalyzer ?? FFTAnalyzer(logger: logger)
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
        let volumes = sortedData.map { Double($0.volume) }
        let highs = sortedData.map { $0.high }
        let lows = sortedData.map { $0.low }

        var features: [String: Double] = [:]

        features["price"] = dataPoint.close
        features["close"] = dataPoint.close
        features["open"] = dataPoint.open
        features["high"] = dataPoint.high
        features["low"] = dataPoint.low
        features["volume"] = Double(dataPoint.volume)
        features["price_change"] = calculatePriceChange(prices)
        features["volume_change"] = calculateVolumeChange(volumes)
        features["volatility"] = calculateVolatility(prices)

        let currentIdx = prices.count - 1
        if currentIdx > 0 {
            features["close_prev"] = prices[currentIdx - 1]
            let ret = log(prices[currentIdx] / prices[currentIdx - 1])
            features["ret"] = ret

            if currentIdx >= 1 {
                features["ret_1d"] = log(prices[currentIdx] / prices[max(0, currentIdx - 1)])
            }
            if currentIdx >= 5 {
                features["ret_5d"] = log(prices[currentIdx] / prices[max(0, currentIdx - 5)])
            }
            if currentIdx >= 20 {
                features["ret_20d"] = log(prices[currentIdx] / prices[max(0, currentIdx - 20)])
            }
        }

        if volumes.count >= 20 {
            let vol20d = Array(volumes[max(0, volumes.count - 20)...])
            let avgVol20d = vol20d.reduce(0, +) / Double(vol20d.count)
            features["avg_vol_20d"] = avgVol20d
            if avgVol20d > 0 {
                features["vol_ratio"] = volumes[currentIdx] / avgVol20d
            }
            if volumes.count >= 2 {
                features["vol_delta"] = volumes[currentIdx] - volumes[currentIdx - 1]
            }
        }

        if prices.count >= 15 {
            let roc = (prices[currentIdx] - prices[currentIdx - 14]) / prices[currentIdx - 14] * 100.0
            features["roc_14"] = roc
        }

        let atr = calculateATR(highs: highs, lows: lows, closes: prices, period: 14)
        if let lastATR = atr.last {
            features["atr_14"] = lastATR
            if dataPoint.close > 0 {
                features["atr_ratio"] = lastATR / dataPoint.close
            }
        }

        let vwap = calculateVWAP(prices: prices, volumes: volumes)
        if let lastVWAP = vwap.last {
            features["vwap"] = lastVWAP
            if lastVWAP > 0 {
                features["vwap_distance"] = (dataPoint.close - lastVWAP) / lastVWAP
            }
        }

        var cumDelta: Double = 0.0
        for i in 1..<min(prices.count, volumes.count) {
            let priceChange = prices[i] - prices[i-1]
            let volumeChange = volumes[i] - volumes[i-1]
            cumDelta += priceChange * volumeChange
        }
        features["cum_delta"] = cumDelta

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
            let bbRange = lastUpper - lastLower
            if bbRange > 0 {
                features["bb_position"] = (dataPoint.close - lastLower) / bbRange
            }
            features["bb_width"] = bbRange
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

        if let fftFeatures = extractFFTFeatures(prices: prices, dataPoint: dataPoint) {
            features.merge(fftFeatures) { (_, new) in new }
        }

        let qualityScore = calculateFeatureQuality(features)

        return FeatureSet(
            timestamp: dataPoint.timestamp,
            symbol: dataPoint.symbol,
            features: features,
            qualityScore: qualityScore
        )
    }

    private func extractFFTFeatures(prices: [Double], dataPoint: MarketDataPoint) -> [String: Double]? {
        guard prices.count >= 64 else {
            return nil
        }

        do {
            let sampleRate = 1.0 / 3600.0

            let fftResult = try fftAnalyzer.analyzeFrequencies(
                timeSeries: prices,
                sampleRate: sampleRate
            )

            var fftFeatures: [String: Double] = [:]

            if let peakFreq = fftResult.peakFrequency {
                fftFeatures["fft_peak_frequency"] = peakFreq
                fftFeatures["fft_peak_period"] = peakFreq > 0 ? 1.0 / peakFreq : 0.0
            }

            if let dominantFreq = fftResult.dominantFrequencies.first {
                fftFeatures["fft_dominant_frequency"] = dominantFreq.frequency
                fftFeatures["fft_dominant_magnitude"] = dominantFreq.magnitude
                fftFeatures["fft_dominant_phase"] = dominantFreq.phase
                fftFeatures["fft_dominant_period"] = dominantFreq.period
                fftFeatures["fft_dominant_significance"] = dominantFreq.significance
            }

            if fftResult.dominantFrequencies.count > 1 {
                let secondFreq = fftResult.dominantFrequencies[1]
                fftFeatures["fft_second_frequency"] = secondFreq.frequency
                fftFeatures["fft_second_significance"] = secondFreq.significance
            }

            fftFeatures["fft_total_energy"] = fftResult.totalEnergy
            fftFeatures["fft_spectral_low_power"] = fftResult.spectralPower.lowFrequencyPower
            fftFeatures["fft_spectral_mid_power"] = fftResult.spectralPower.midFrequencyPower
            fftFeatures["fft_spectral_high_power"] = fftResult.spectralPower.highFrequencyPower
            fftFeatures["fft_signal_to_noise"] = fftResult.spectralPower.signalToNoiseRatio

            if let strongCycle = fftResult.cyclicPatterns.first(where: { $0.strength > 0.3 }) {
                fftFeatures["fft_cycle_strength"] = strongCycle.strength
                fftFeatures["fft_cycle_period"] = strongCycle.period

                let cycleTypeValue: Double
                switch strongCycle.periodType {
                case .veryShort: cycleTypeValue = 1.0
                case .short: cycleTypeValue = 2.0
                case .medium: cycleTypeValue = 3.0
                case .long: cycleTypeValue = 4.0
                case .veryLong: cycleTypeValue = 5.0
                case .unknown: cycleTypeValue = 0.0
                }
                fftFeatures["fft_cycle_type"] = cycleTypeValue
            }

            let dailyCycleStrength = fftResult.cyclicPatterns.first { cycle in
                let periodHours = cycle.period / 3600.0
                return abs(periodHours - 24.0) < 6.0 && cycle.strength > 0.2
            }?.strength ?? 0.0
            fftFeatures["fft_daily_cycle_strength"] = dailyCycleStrength

            let weeklyCycleStrength = fftResult.cyclicPatterns.first { cycle in
                let periodHours = cycle.period / 3600.0
                return abs(periodHours - 168.0) < 24.0 && cycle.strength > 0.2
            }?.strength ?? 0.0
            fftFeatures["fft_weekly_cycle_strength"] = weeklyCycleStrength

            return fftFeatures
        } catch {
            logger.debug(component: "FeatureExtractor", event: "FFT analysis failed", data: [
                "error": error.localizedDescription
            ])
            return nil
        }
    }

    public func getFeatureNames() -> [String] {
        return [
            "price", "volume", "price_change", "volume_change", "volatility",
            "rsi", "macd", "macd_signal", "macd_histogram",
            "ema_12", "ema_26",
            "bb_upper", "bb_middle", "bb_lower", "bb_position",
            "stoch_k", "stoch_d",
            "volume_profile_peak",
            "support_level", "resistance_level", "trend_strength",
            "fft_peak_frequency", "fft_peak_period",
            "fft_dominant_frequency", "fft_dominant_magnitude", "fft_dominant_phase",
            "fft_dominant_period", "fft_dominant_significance",
            "fft_second_frequency", "fft_second_significance",
            "fft_total_energy",
            "fft_spectral_low_power", "fft_spectral_mid_power", "fft_spectral_high_power",
            "fft_signal_to_noise",
            "fft_cycle_strength", "fft_cycle_period", "fft_cycle_type",
            "fft_daily_cycle_strength", "fft_weekly_cycle_strength"
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

    private func calculateATR(highs: [Double], lows: [Double], closes: [Double], period: Int) -> [Double] {
        guard highs.count == lows.count && lows.count == closes.count,
              highs.count >= period + 1 else { return [] }

        var trueRanges: [Double] = []
        for i in 1..<highs.count {
            let tr1 = highs[i] - lows[i]
            let tr2 = abs(highs[i] - closes[i-1])
            let tr3 = abs(lows[i] - closes[i-1])
            trueRanges.append(max(tr1, tr2, tr3))
        }

        guard trueRanges.count >= period else { return [] }

        var atr: [Double] = []
        var sum: Double = 0.0

        for i in 0..<period {
            sum += trueRanges[i]
        }
        atr.append(sum / Double(period))

        for i in period..<trueRanges.count {
            sum = (atr.last! * Double(period - 1) + trueRanges[i]) / Double(period)
            atr.append(sum)
        }

        return atr
    }

    private func calculateVWAP(prices: [Double], volumes: [Double]) -> [Double] {
        guard prices.count == volumes.count, !prices.isEmpty else { return [] }

        var vwap: [Double] = []
        var cumulativePriceVolume: Double = 0.0
        var cumulativeVolume: Double = 0.0

        for i in 0..<prices.count {
            cumulativePriceVolume += prices[i] * volumes[i]
            cumulativeVolume += volumes[i]

            if cumulativeVolume > 0 {
                vwap.append(cumulativePriceVolume / cumulativeVolume)
            } else {
                vwap.append(prices[i])
            }
        }

        return vwap
    }
}

public enum FeatureExtractionError: Error {
    case insufficientData
    case invalidDataPoint
    case calculationError
}
