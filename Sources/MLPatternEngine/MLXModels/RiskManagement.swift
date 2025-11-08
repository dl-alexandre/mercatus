import Foundation
import Utils

public struct KellyCriterionResult {
    public let optimalFraction: Double
    public let expectedReturn: Double
    public let winProbability: Double
    public let recommendedPositionSize: Double
    public let riskAdjustedReturn: Double

    public init(optimalFraction: Double, expectedReturn: Double, winProbability: Double, recommendedPositionSize: Double, riskAdjustedReturn: Double) {
        self.optimalFraction = optimalFraction
        self.expectedReturn = expectedReturn
        self.winProbability = winProbability
        self.recommendedPositionSize = recommendedPositionSize
        self.riskAdjustedReturn = riskAdjustedReturn
    }
}

public class KellyCriterionCalculator {
    private let logger: StructuredLogger
    private let maxPositionFraction: Double
    private let minPositionFraction: Double

    public init(logger: StructuredLogger, maxPositionFraction: Double = 0.25, minPositionFraction: Double = 0.01) {
        self.logger = logger
        self.maxPositionFraction = maxPositionFraction
        self.minPositionFraction = minPositionFraction
    }

    public func calculate(winRate: Double, avgWin: Double, avgLoss: Double, totalCapital: Double) -> KellyCriterionResult {
        guard winRate > 0 && winRate < 1 && avgLoss != 0 else {
            logger.warn(component: "KellyCriterionCalculator", event: "Invalid parameters for Kelly criterion", data: [
                "winRate": String(winRate),
                "avgWin": String(avgWin),
                "avgLoss": String(avgLoss)
            ])
            return KellyCriterionResult(
                optimalFraction: minPositionFraction,
                expectedReturn: 0.0,
                winProbability: winRate,
                recommendedPositionSize: totalCapital * minPositionFraction,
                riskAdjustedReturn: 0.0
            )
        }

        let lossRate = 1.0 - winRate
        let winLossRatio = abs(avgWin / avgLoss)

        let kellyFraction = (winRate * winLossRatio - lossRate) / winLossRatio

        let clampedFraction = max(minPositionFraction, min(maxPositionFraction, kellyFraction))
        let recommendedSize = totalCapital * clampedFraction

        let expectedReturn = winRate * avgWin - lossRate * abs(avgLoss)
        let riskAdjustedReturn = expectedReturn * clampedFraction

        logger.info(component: "KellyCriterionCalculator", event: "Kelly criterion calculated", data: [
            "optimalFraction": String(kellyFraction),
            "clampedFraction": String(clampedFraction),
            "recommendedSize": String(recommendedSize),
            "expectedReturn": String(expectedReturn)
        ])

        return KellyCriterionResult(
            optimalFraction: kellyFraction,
            expectedReturn: expectedReturn,
            winProbability: winRate,
            recommendedPositionSize: recommendedSize,
            riskAdjustedReturn: riskAdjustedReturn
        )
    }

    public func calculateFromTrades(trades: [(profit: Double, loss: Double)], totalCapital: Double) -> KellyCriterionResult {
        let profitableTrades = trades.filter { $0.profit > 0 }
        let losingTrades = trades.filter { $0.loss < 0 }

        let winRate = trades.isEmpty ? 0.0 : Double(profitableTrades.count) / Double(trades.count)
        let avgWin = profitableTrades.isEmpty ? 0.0 : profitableTrades.map { $0.profit }.reduce(0, +) / Double(profitableTrades.count)
        let avgLoss = losingTrades.isEmpty ? 0.0 : abs(losingTrades.map { $0.loss }.reduce(0, +) / Double(losingTrades.count))

        return calculate(winRate: winRate, avgWin: avgWin, avgLoss: avgLoss, totalCapital: totalCapital)
    }
}

public class RiskManager {
    private let kellyCalculator: KellyCriterionCalculator
    private let logger: StructuredLogger
    private let maxDrawdown: Double
    private let stopLossFraction: Double

    public init(logger: StructuredLogger, maxDrawdown: Double = 0.20, stopLossFraction: Double = 0.05) {
        self.logger = logger
        self.kellyCalculator = KellyCriterionCalculator(logger: logger)
        self.maxDrawdown = maxDrawdown
        self.stopLossFraction = stopLossFraction
    }

    public func calculatePositionSize(
        prediction: Double,
        confidence: Double,
        currentPrice: Double,
        totalCapital: Double,
        historicalWinRate: Double,
        historicalAvgWin: Double,
        historicalAvgLoss: Double
    ) -> Double {
        let kellyResult = kellyCalculator.calculate(
            winRate: historicalWinRate,
            avgWin: historicalAvgWin,
            avgLoss: historicalAvgLoss,
            totalCapital: totalCapital
        )

        let confidenceAdjusted = kellyResult.recommendedPositionSize * confidence

        let maxPosition = totalCapital * 0.25
        let minPosition = totalCapital * 0.01

        let finalSize = max(minPosition, min(maxPosition, confidenceAdjusted))

        logger.info(component: "RiskManager", event: "Position size calculated", data: [
            "prediction": String(prediction),
            "confidence": String(confidence),
            "kellySize": String(kellyResult.recommendedPositionSize),
            "finalSize": String(finalSize)
        ])

        return finalSize
    }

    public func shouldExit(currentPrice: Double, entryPrice: Double, position: String, currentDrawdown: Double) -> Bool {
        if currentDrawdown >= maxDrawdown {
            logger.warn(component: "RiskManager", event: "Max drawdown reached, exiting position")
            return true
        }

        let priceChange = abs(currentPrice - entryPrice) / entryPrice
        if priceChange >= stopLossFraction {
            logger.info(component: "RiskManager", event: "Stop loss triggered", data: [
                "priceChange": String(priceChange),
                "stopLossFraction": String(stopLossFraction)
            ])
            return true
        }

        return false
    }
}
