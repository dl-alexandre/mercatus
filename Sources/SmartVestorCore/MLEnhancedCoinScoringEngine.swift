import Foundation
import Utils
import MLPatternEngine

public class MLEnhancedCoinScoringEngine: CoinScoringEngineProtocol, @unchecked Sendable {
    private let baseEngine: CoinScoringEngineProtocol
    private let mlScoringEngine: MLScoringEngineProtocol
    private let logger: StructuredLogger

    public init(
        baseEngine: CoinScoringEngineProtocol,
        mlScoringEngine: MLScoringEngineProtocol,
        logger: StructuredLogger
    ) {
        self.baseEngine = baseEngine
        self.mlScoringEngine = mlScoringEngine
        self.logger = logger
    }

    public func scoreAllCoins() async throws -> [CoinScore] {
        logger.info(component: "MLEnhancedCoinScoringEngine", event: "Scoring all coins with ML enhancement")

        let baseScores = try await baseEngine.scoreAllCoins()
        let mlScores = try await mlScoringEngine.scoreAllCoins()

        var combinedScores: [String: CoinScore] = [:]

        for score in baseScores {
            combinedScores[score.symbol] = score
        }

        for mlScore in mlScores {
            if let baseScore = combinedScores[mlScore.symbol] {
                let enhancedScore = combineScores(baseScore: baseScore, mlScore: mlScore)
                combinedScores[mlScore.symbol] = enhancedScore
            } else {
                combinedScores[mlScore.symbol] = mlScore
            }
        }

        let finalScores = Array(combinedScores.values).sorted { $0.totalScore > $1.totalScore }

        logger.info(component: "MLEnhancedCoinScoringEngine", event: "ML-enhanced scoring completed", data: [
            "total_coins": String(finalScores.count),
            "ml_enhanced": String(mlScores.count)
        ])

        return finalScores
    }

    public func scoreCoin(symbol: String) async throws -> CoinScore {
        logger.info(component: "MLEnhancedCoinScoringEngine", event: "Scoring coin with ML enhancement", data: ["symbol": symbol])

        let baseScore = try await baseEngine.scoreCoin(symbol: symbol)
        let mlScore = try await mlScoringEngine.scoreCoin(symbol: symbol)

        return combineScores(baseScore: baseScore, mlScore: mlScore)
    }

    public func updateCoinScores() async throws {
        try await baseEngine.updateCoinScores()
    }

    public func getTopCoins(limit: Int, category: CoinCategory?) async throws -> [CoinScore] {
        let allScores = try await scoreAllCoins()
        let filtered = category != nil ? allScores.filter { $0.category == category } : allScores
        return Array(filtered.prefix(limit))
    }

    public func getCoinsByRiskLevel(_ riskLevel: RiskLevel) async throws -> [CoinScore] {
        let allScores = try await scoreAllCoins()
        return allScores.filter { $0.riskLevel == riskLevel }
    }

    private func combineScores(baseScore: CoinScore, mlScore: CoinScore) -> CoinScore {
        let mlWeight = 0.6
        let baseWeight = 0.4

        let combinedScore = (baseScore.totalScore * baseWeight) + (mlScore.totalScore * mlWeight)
        let combinedTechnical = (baseScore.technicalScore * baseWeight) + (mlScore.technicalScore * mlWeight)
        let combinedFundamental = (baseScore.fundamentalScore * baseWeight) + (mlScore.fundamentalScore * mlWeight)
        let combinedVolatility = (baseScore.volatilityScore * baseWeight) + (mlScore.volatilityScore * mlWeight)
        let combinedLiquidity = (baseScore.liquidityScore * baseWeight) + (mlScore.liquidityScore * mlWeight)

        let riskLevel = determineHigherConfidenceRisk(risk1: baseScore.riskLevel, risk2: mlScore.riskLevel)

        return CoinScore(
            symbol: baseScore.symbol,
            totalScore: combinedScore,
            technicalScore: combinedTechnical,
            fundamentalScore: combinedFundamental,
            momentumScore: mlScore.momentumScore,
            volatilityScore: combinedVolatility,
            liquidityScore: combinedLiquidity,
            category: baseScore.category,
            riskLevel: riskLevel,
            marketCap: baseScore.marketCap,
            volume24h: baseScore.volume24h,
            priceChange24h: baseScore.priceChange24h,
            priceChange7d: baseScore.priceChange7d,
            priceChange30d: baseScore.priceChange30d
        )
    }

    private func determineHigherConfidenceRisk(risk1: RiskLevel, risk2: RiskLevel) -> RiskLevel {
        if risk1 == .veryHigh || risk2 == .veryHigh {
            return .veryHigh
        } else if risk1 == .high || risk2 == .high {
            return .high
        } else if risk1 == .low && risk2 == .low {
            return .low
        } else {
            return .medium
        }
    }
}
