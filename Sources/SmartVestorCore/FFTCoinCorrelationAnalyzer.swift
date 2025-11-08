import Foundation
import Utils
import MLPatternEngine

public protocol FFTCoinCorrelationAnalyzerProtocol {
    func analyzeCorrelation(coin1: String, coin2: String, historicalData1: [MarketDataPoint], historicalData2: [MarketDataPoint]) async throws -> FFTCorrelationResult
    func findCorrelatedCoins(targetCoin: String, allCoins: [String], historicalDataMap: [String: [MarketDataPoint]], threshold: Double) async throws -> [CorrelatedCoin]
    func calculatePortfolioPhaseAlignment(coins: [String], historicalDataMap: [String: [MarketDataPoint]]) async throws -> PortfolioPhaseAlignment
}

public struct FFTCorrelationResult {
    public let coin1: String
    public let coin2: String
    public let phaseAlignment: PhaseAlignment
    public let frequencyCorrelation: Double
    public let cycleSynchronicity: Double
    public let recommendation: CorrelationRecommendation

    public enum CorrelationRecommendation {
        case strongDiversification
        case complementaryHolding
        case redundantHolding
        case neutral
    }

    public init(
        coin1: String,
        coin2: String,
        phaseAlignment: PhaseAlignment,
        frequencyCorrelation: Double,
        cycleSynchronicity: Double,
        recommendation: CorrelationRecommendation
    ) {
        self.coin1 = coin1
        self.coin2 = coin2
        self.phaseAlignment = phaseAlignment
        self.frequencyCorrelation = frequencyCorrelation
        self.cycleSynchronicity = cycleSynchronicity
        self.recommendation = recommendation
    }
}

public struct CorrelatedCoin {
    public let symbol: String
    public let correlationStrength: Double
    public let phaseDifference: Double
    public let cycleSync: Double
    public let recommendation: FFTCorrelationResult.CorrelationRecommendation

    public init(
        symbol: String,
        correlationStrength: Double,
        phaseDifference: Double,
        cycleSync: Double,
        recommendation: FFTCorrelationResult.CorrelationRecommendation
    ) {
        self.symbol = symbol
        self.correlationStrength = correlationStrength
        self.phaseDifference = phaseDifference
        self.cycleSync = cycleSync
        self.recommendation = recommendation
    }
}

public struct PortfolioPhaseAlignment {
    public let averageCorrelation: Double
    public let phaseCoherence: Double
    public let diversificationScore: Double
    public let dominantCycleAlignment: Double
    public let recommendedAdjustments: [String]

    public init(
        averageCorrelation: Double,
        phaseCoherence: Double,
        diversificationScore: Double,
        dominantCycleAlignment: Double,
        recommendedAdjustments: [String]
    ) {
        self.averageCorrelation = averageCorrelation
        self.phaseCoherence = phaseCoherence
        self.diversificationScore = diversificationScore
        self.dominantCycleAlignment = dominantCycleAlignment
        self.recommendedAdjustments = recommendedAdjustments
    }
}

public class FFTCoinCorrelationAnalyzer: FFTCoinCorrelationAnalyzerProtocol {
    private let fftAnalyzer: FFTAnalyzerProtocol
    private let logger: StructuredLogger

    public init(
        fftAnalyzer: FFTAnalyzerProtocol? = nil,
        logger: StructuredLogger = StructuredLogger()
    ) {
        self.fftAnalyzer = fftAnalyzer ?? FFTAnalyzer(logger: logger)
        self.logger = logger
    }

    public func analyzeCorrelation(
        coin1: String,
        coin2: String,
        historicalData1: [MarketDataPoint],
        historicalData2: [MarketDataPoint]
    ) async throws -> FFTCorrelationResult {
        guard historicalData1.count >= 64, historicalData2.count >= 64 else {
            throw FFTCorrelationError.insufficientData
        }

        let prices1 = historicalData1.sorted { $0.timestamp < $1.timestamp }.map { $0.close }
        let prices2 = historicalData2.sorted { $0.timestamp < $1.timestamp }.map { $0.close }

        guard prices1.count == prices2.count else {
            let minCount = min(prices1.count, prices2.count)
            let trimmed1 = Array(prices1.prefix(minCount))
            let trimmed2 = Array(prices2.prefix(minCount))
            return try await analyzeCorrelationInternal(coin1: coin1, coin2: coin2, prices1: trimmed1, prices2: trimmed2)
        }

        return try await analyzeCorrelationInternal(coin1: coin1, coin2: coin2, prices1: prices1, prices2: prices2)
    }

    private func analyzeCorrelationInternal(
        coin1: String,
        coin2: String,
        prices1: [Double],
        prices2: [Double]
    ) async throws -> FFTCorrelationResult {
        let sampleRate = 1.0 / 3600.0

        let phaseAlignment = try fftAnalyzer.calculatePhaseAlignment(
            series1: prices1,
            series2: prices2,
            sampleRate: sampleRate
        )

        let analysis1 = try fftAnalyzer.analyzeFrequencies(timeSeries: prices1, sampleRate: sampleRate)
        let analysis2 = try fftAnalyzer.analyzeFrequencies(timeSeries: prices2, sampleRate: sampleRate)

        let frequencyCorrelation = calculateFrequencyCorrelation(
            analysis1: analysis1,
            analysis2: analysis2
        )

        let cycleSynchronicity = calculateCycleSynchronicity(
            patterns1: analysis1.cyclicPatterns,
            patterns2: analysis2.cyclicPatterns
        )

        let recommendation = determineRecommendation(
            phaseAlignment: phaseAlignment,
            frequencyCorrelation: frequencyCorrelation,
            cycleSynchronicity: cycleSynchronicity
        )

        return FFTCorrelationResult(
            coin1: coin1,
            coin2: coin2,
            phaseAlignment: phaseAlignment,
            frequencyCorrelation: frequencyCorrelation,
            cycleSynchronicity: cycleSynchronicity,
            recommendation: recommendation
        )
    }

    private func calculateFrequencyCorrelation(
        analysis1: FFTAnalysisResult,
        analysis2: FFTAnalysisResult
    ) -> Double {
        let minLength = min(analysis1.magnitudes.count, analysis2.magnitudes.count)
        guard minLength > 0 else { return 0.0 }

        var correlationSum: Double = 0.0
        let totalPower1 = analysis1.totalEnergy
        let totalPower2 = analysis2.totalEnergy

        for i in 0..<minLength {
            let normalizedMag1 = totalPower1 > 0 ? analysis1.magnitudes[i] / sqrt(totalPower1) : 0.0
            let normalizedMag2 = totalPower2 > 0 ? analysis2.magnitudes[i] / sqrt(totalPower2) : 0.0
            correlationSum += normalizedMag1 * normalizedMag2
        }

        return correlationSum / Double(minLength)
    }

    private func calculateCycleSynchronicity(
        patterns1: [CyclicPattern],
        patterns2: [CyclicPattern]
    ) -> Double {
        guard !patterns1.isEmpty, !patterns2.isEmpty else { return 0.0 }

        let dominant1 = patterns1.first!
        let dominant2 = patterns2.first!

        let periodDiff = abs(dominant1.period - dominant2.period) / max(dominant1.period, dominant2.period)
        let phaseDiff = abs(dominant1.phase - dominant2.phase) / .pi

        let periodSync = 1.0 - min(periodDiff, 1.0)
        let phaseSync = 1.0 - min(phaseDiff, 1.0)

        let strengthAvg = (dominant1.strength + dominant2.strength) / 2.0

        return (periodSync * 0.5 + phaseSync * 0.5) * strengthAvg
    }

    private func determineRecommendation(
        phaseAlignment: PhaseAlignment,
        frequencyCorrelation: Double,
        cycleSynchronicity: Double
    ) -> FFTCorrelationResult.CorrelationRecommendation {
        if phaseAlignment.coherence > 0.8 && frequencyCorrelation > 0.7 && cycleSynchronicity > 0.7 {
            return .redundantHolding
        } else if phaseAlignment.coherence > 0.6 && frequencyCorrelation > 0.5 {
            return .complementaryHolding
        } else if phaseAlignment.alignmentStrength < 0.3 && frequencyCorrelation < 0.4 {
            return .strongDiversification
        } else {
            return .neutral
        }
    }

    public func findCorrelatedCoins(
        targetCoin: String,
        allCoins: [String],
        historicalDataMap: [String: [MarketDataPoint]],
        threshold: Double
    ) async throws -> [CorrelatedCoin] {
        guard let targetData = historicalDataMap[targetCoin] else {
            throw FFTCorrelationError.targetCoinDataMissing
        }

        var correlatedCoins: [CorrelatedCoin] = []

        for coin in allCoins where coin != targetCoin {
            guard let coinData = historicalDataMap[coin] else { continue }

            do {
                let correlation = try await analyzeCorrelation(
                    coin1: targetCoin,
                    coin2: coin,
                    historicalData1: targetData,
                    historicalData2: coinData
                )

                let overallStrength = (
                    correlation.phaseAlignment.coherence * 0.4 +
                    correlation.frequencyCorrelation * 0.3 +
                    correlation.cycleSynchronicity * 0.3
                )

                if overallStrength >= threshold {
                    correlatedCoins.append(CorrelatedCoin(
                        symbol: coin,
                        correlationStrength: overallStrength,
                        phaseDifference: correlation.phaseAlignment.phaseDifference,
                        cycleSync: correlation.cycleSynchronicity,
                        recommendation: correlation.recommendation
                    ))
                }
            } catch {
                logger.debug(component: "FFTCoinCorrelationAnalyzer", event: "Failed to analyze correlation", data: [
                    "coin1": targetCoin,
                    "coin2": coin,
                    "error": error.localizedDescription
                ])
                continue
            }
        }

        correlatedCoins.sort { $0.correlationStrength > $1.correlationStrength }

        return correlatedCoins
    }

    public func calculatePortfolioPhaseAlignment(
        coins: [String],
        historicalDataMap: [String: [MarketDataPoint]]
    ) async throws -> PortfolioPhaseAlignment {
        guard coins.count >= 2 else {
            throw FFTCorrelationError.insufficientCoins
        }

        var correlations: [Double] = []
        var phaseCoherences: [Double] = []
        var recommendations: [String] = []

        for i in 0..<coins.count {
            for j in (i+1)..<coins.count {
                guard let data1 = historicalDataMap[coins[i]],
                      let data2 = historicalDataMap[coins[j]] else {
                    continue
                }

                do {
                    let correlation = try await analyzeCorrelation(
                        coin1: coins[i],
                        coin2: coins[j],
                        historicalData1: data1,
                        historicalData2: data2
                    )

                    correlations.append(correlation.frequencyCorrelation)
                    phaseCoherences.append(correlation.phaseAlignment.coherence)

                    if correlation.recommendation == .redundantHolding {
                        recommendations.append("\(coins[i]) and \(coins[j]) are highly correlated - consider diversification")
                    }
                } catch {
                    continue
                }
            }
        }

        let avgCorrelation = correlations.isEmpty ? 0.0 : correlations.reduce(0, +) / Double(correlations.count)
        let phaseCoherence = phaseCoherences.isEmpty ? 0.0 : phaseCoherences.reduce(0, +) / Double(phaseCoherences.count)
        let diversificationScore = 1.0 - avgCorrelation

        let dominantCycleAlignment = calculateDominantCycleAlignment(
            coins: coins,
            historicalDataMap: historicalDataMap
        )

        return PortfolioPhaseAlignment(
            averageCorrelation: avgCorrelation,
            phaseCoherence: phaseCoherence,
            diversificationScore: diversificationScore,
            dominantCycleAlignment: dominantCycleAlignment,
            recommendedAdjustments: recommendations
        )
    }

    private func calculateDominantCycleAlignment(
        coins: [String],
        historicalDataMap: [String: [MarketDataPoint]]
    ) -> Double {
        var dominantPeriods: [Double] = []

        for coin in coins {
            guard let data = historicalDataMap[coin],
                  data.count >= 64 else {
                continue
            }

            let prices = data.sorted { $0.timestamp < $1.timestamp }.map { $0.close }

            do {
                let sampleRate = 1.0 / 3600.0
                let analysis = try fftAnalyzer.analyzeFrequencies(
                    timeSeries: prices,
                    sampleRate: sampleRate
                )

                if let dominant = analysis.dominantFrequencies.first {
                    dominantPeriods.append(dominant.period)
                }
            } catch {
                continue
            }
        }

        guard dominantPeriods.count >= 2 else {
            return 0.5
        }

        let meanPeriod = dominantPeriods.reduce(0, +) / Double(dominantPeriods.count)
        let variance = dominantPeriods.map { pow($0 - meanPeriod, 2) }.reduce(0, +) / Double(dominantPeriods.count)
        let stdDev = sqrt(variance)

        let coefficientOfVariation = meanPeriod > 0 ? stdDev / meanPeriod : 1.0
        return 1.0 - min(coefficientOfVariation, 1.0)
    }
}

public enum FFTCorrelationError: Error {
    case insufficientData
    case targetCoinDataMissing
    case insufficientCoins
    case calculationError
}
