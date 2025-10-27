import Foundation
import Accelerate

public class TechnicalIndicators: TechnicalIndicatorsProtocol {

    public init() {}

    public func calculateRSI(prices: [Double], period: Int = 14) -> [Double] {
        guard prices.count > period else { return [] }

        let count = prices.count
        var gains = [Double](repeating: 0, count: count - 1)
        var losses = [Double](repeating: 0, count: count - 1)

        for i in 1..<count {
            let change = prices[i] - prices[i-1]
            gains[i-1] = max(0, change)
            losses[i-1] = max(0, -change)
        }

        let rsiCount = gains.count - period + 1
        var rsi = [Double](repeating: 0, count: rsiCount)

        for i in 0..<rsiCount {
            let start = i
            let end = i + period

            var avgGain: Double = 0.0
            var avgLoss: Double = 0.0

            gains[start..<end].withUnsafeBufferPointer { buffer in
                vDSP_meanvD(buffer.baseAddress!, 1, &avgGain, vDSP_Length(period))
            }
            losses[start..<end].withUnsafeBufferPointer { buffer in
                vDSP_meanvD(buffer.baseAddress!, 1, &avgLoss, vDSP_Length(period))
            }

            if avgLoss == 0 {
                rsi[i] = 100.0
            } else {
                let rs = avgGain / avgLoss
                rsi[i] = 100.0 - (100.0 / (1.0 + rs))
            }
        }

        return rsi
    }

    public func calculateMACD(prices: [Double], fastPeriod: Int = 12, slowPeriod: Int = 26, signalPeriod: Int = 9) -> (macd: [Double], signal: [Double], histogram: [Double]) {
        let fastEMA = calculateEMA(prices: prices, period: fastPeriod)
        let slowEMA = calculateEMA(prices: prices, period: slowPeriod)

        guard fastEMA.count == slowEMA.count else { return ([], [], []) }

        var macd: [Double] = []
        for i in 0..<fastEMA.count {
            macd.append(fastEMA[i] - slowEMA[i])
        }

        let signal = calculateEMA(prices: macd, period: signalPeriod)

        var histogram: [Double] = []
        let minCount = min(macd.count, signal.count)
        for i in 0..<minCount {
            histogram.append(macd[i] - signal[i])
        }

        return (macd, signal, histogram)
    }

    public func calculateEMA(prices: [Double], period: Int) -> [Double] {
        guard !prices.isEmpty, period > 0 else { return [] }

        let multiplier = 2.0 / (Double(period) + 1.0)
        var ema: [Double] = []

        ema.append(prices[0])

        for i in 1..<prices.count {
            let emaValue = (prices[i] * multiplier) + (ema[i-1] * (1.0 - multiplier))
            ema.append(emaValue)
        }

        return ema
    }

    public func calculateBollingerBands(prices: [Double], period: Int = 20, standardDeviations: Double = 2.0) -> (upper: [Double], middle: [Double], lower: [Double]) {
        guard prices.count >= period else { return ([], [], []) }

        let resultCount = prices.count - period + 1
        var upper = [Double](repeating: 0, count: resultCount)
        var middle = [Double](repeating: 0, count: resultCount)
        var lower = [Double](repeating: 0, count: resultCount)

        for i in 0..<resultCount {
            let start = i
            let end = i + period

            var sma: Double = 0.0
            prices[start..<end].withUnsafeBufferPointer { buffer in
                vDSP_meanvD(buffer.baseAddress!, 1, &sma, vDSP_Length(period))
            }

            let tempArray = Array(prices[start..<end]).map { pow($0 - sma, 2) }
            var varianceSum: Double = 0.0
            tempArray.withUnsafeBufferPointer { buffer in
                vDSP_sveD(buffer.baseAddress!, 1, &varianceSum, vDSP_Length(period))
            }
            let variance = varianceSum / Double(period)
            let standardDeviation = sqrt(variance)

            middle[i] = sma
            upper[i] = sma + (standardDeviations * standardDeviation)
            lower[i] = sma - (standardDeviations * standardDeviation)
        }

        return (upper, middle, lower)
    }

    public func calculateStochastic(high: [Double], low: [Double], close: [Double], kPeriod: Int = 14, dPeriod: Int = 3) -> (k: [Double], d: [Double]) {
        guard high.count == low.count && low.count == close.count,
              high.count >= kPeriod else { return ([], []) }

        let kCount = close.count - kPeriod + 1
        var kValues = [Double](repeating: 0, count: kCount)

        for i in 0..<kCount {
            let start = i
            let end = i + kPeriod

            var highestHigh = high[start]
            var lowestLow = low[start]

            for j in start..<end {
                if high[j] > highestHigh { highestHigh = high[j] }
                if low[j] < lowestLow { lowestLow = low[j] }
            }

            let currentClose = close[end - 1]
            kValues[i] = highestHigh == lowestLow ? 50.0 : ((currentClose - lowestLow) / (highestHigh - lowestLow)) * 100.0
        }

        let dValues = calculateSMA(prices: kValues, period: dPeriod)

        return (kValues, dValues)
    }

    public func calculateVolumeProfile(volumes: [Double], prices: [Double], bins: Int = 20) -> [Double: Double] {
        guard volumes.count == prices.count, !volumes.isEmpty else { return [:] }

        let minPrice = prices.min() ?? 0
        let maxPrice = prices.max() ?? 0
        let priceRange = maxPrice - minPrice
        let binSize = priceRange / Double(bins)

        guard binSize > 0 && binSize.isFinite else { return [:] }

        var volumeProfile: [Double: Double] = [:]

        for i in 0..<prices.count {
            let normalizedPrice = (prices[i] - minPrice) / binSize
            let binIndex = Int(normalizedPrice.rounded())
            let binPrice = minPrice + (Double(binIndex) * binSize)

            if normalizedPrice.isFinite && binIndex >= 0 {
                volumeProfile[binPrice, default: 0] += volumes[i]
            }
        }

        return volumeProfile
    }

    private func calculateSMA(prices: [Double], period: Int) -> [Double] {
        guard prices.count >= period else { return [] }

        let smaCount = prices.count - period + 1
        var sma = [Double](repeating: 0, count: smaCount)

        for i in 0..<smaCount {
            let start = i
            let end = i + period

            var avg: Double = 0.0
            prices[start..<end].withUnsafeBufferPointer { buffer in
                vDSP_meanvD(buffer.baseAddress!, 1, &avg, vDSP_Length(period))
            }
            sma[i] = avg
        }

        return sma
    }
}
