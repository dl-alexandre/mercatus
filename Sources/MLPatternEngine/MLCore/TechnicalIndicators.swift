import Foundation

public class TechnicalIndicators: TechnicalIndicatorsProtocol {

    public init() {}

    public func calculateRSI(prices: [Double], period: Int = 14) -> [Double] {
        guard prices.count > period else { return [] }

        var rsi: [Double] = []
        var gains: [Double] = []
        var losses: [Double] = []

        for i in 1..<prices.count {
            let change = prices[i] - prices[i-1]
            gains.append(max(0, change))
            losses.append(max(0, -change))
        }

        for i in period-1..<gains.count {
            let avgGain = gains[(i-period+1)...i].reduce(0, +) / Double(period)
            let avgLoss = losses[(i-period+1)...i].reduce(0, +) / Double(period)

            if avgLoss == 0 {
                rsi.append(100.0)
            } else {
                let rs = avgGain / avgLoss
                let rsiValue = 100.0 - (100.0 / (1.0 + rs))
                rsi.append(rsiValue)
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

        var upper: [Double] = []
        var middle: [Double] = []
        var lower: [Double] = []

        for i in (period-1)..<prices.count {
            let periodPrices = Array(prices[(i-period+1)...i])
            let sma = periodPrices.reduce(0, +) / Double(period)

            let variance = periodPrices.map { pow($0 - sma, 2) }.reduce(0, +) / Double(period)
            let standardDeviation = sqrt(variance)

            let upperBand = sma + (standardDeviations * standardDeviation)
            let lowerBand = sma - (standardDeviations * standardDeviation)

            upper.append(upperBand)
            middle.append(sma)
            lower.append(lowerBand)
        }

        return (upper, middle, lower)
    }

    public func calculateStochastic(high: [Double], low: [Double], close: [Double], kPeriod: Int = 14, dPeriod: Int = 3) -> (k: [Double], d: [Double]) {
        guard high.count == low.count && low.count == close.count,
              high.count >= kPeriod else { return ([], []) }

        var kValues: [Double] = []

        for i in (kPeriod-1)..<close.count {
            let periodHigh = Array(high[(i-kPeriod+1)...i])
            let periodLow = Array(low[(i-kPeriod+1)...i])
            let currentClose = close[i]

            let highestHigh = periodHigh.max() ?? 0
            let lowestLow = periodLow.min() ?? 0

            let kValue = highestHigh == lowestLow ? 50.0 : ((currentClose - lowestLow) / (highestHigh - lowestLow)) * 100.0
            kValues.append(kValue)
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

        var sma: [Double] = []

        for i in (period-1)..<prices.count {
            let periodPrices = Array(prices[(i-period+1)...i])
            let average = periodPrices.reduce(0, +) / Double(period)
            sma.append(average)
        }

        return sma
    }
}
