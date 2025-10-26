import Foundation
import Utils

public protocol ScoreBasedAllocationManagerProtocol {
    func createScoreBasedAllocation(amount: Double, maxPositions: Int) async throws -> ScoreBasedAllocationPlan
    func calculateOptimalPositionSizes(coinScores: [CoinScore], totalAmount: Double) async throws -> [PositionAllocation]
    func applyRiskConstraints(allocations: [PositionAllocation], maxRisk: Double) async throws -> [PositionAllocation]
    func calculatePortfolioMetrics(allocations: [PositionAllocation]) async throws -> PortfolioMetrics
}

public class ScoreBasedAllocationManager: ScoreBasedAllocationManagerProtocol {
    private let config: SmartVestorConfig
    private let persistence: PersistenceProtocol
    private let coinScoringEngine: CoinScoringEngineProtocol
    private let marketDataProvider: MarketDataProviderProtocol
    private let logger: StructuredLogger

    public init(
        config: SmartVestorConfig,
        persistence: PersistenceProtocol,
        coinScoringEngine: CoinScoringEngineProtocol,
        marketDataProvider: MarketDataProviderProtocol
    ) {
        self.config = config
        self.persistence = persistence
        self.coinScoringEngine = coinScoringEngine
        self.marketDataProvider = marketDataProvider
        self.logger = StructuredLogger()
    }

    public func createScoreBasedAllocation(amount: Double, maxPositions: Int) async throws -> ScoreBasedAllocationPlan {
        logger.info(component: "ScoreBasedAllocationManager", event: "Creating score-based allocation", data: [
            "amount": String(amount),
            "max_positions": String(maxPositions)
        ])

        let coinScores = try await coinScoringEngine.scoreAllCoins()
        let filteredCoins = filterEligibleCoins(coinScores)

        let positionSizes = try await calculateOptimalPositionSizes(
            coinScores: filteredCoins,
            totalAmount: amount
        )

        let riskConstrainedAllocations = try await applyRiskConstraints(
            allocations: positionSizes,
            maxRisk: config.maxPortfolioRisk ?? 0.15
        )

        let topAllocations = selectTopAllocations(
            allocations: riskConstrainedAllocations,
            maxPositions: maxPositions
        )

        let portfolioMetrics = try await calculatePortfolioMetrics(allocations: topAllocations)

        let rationale = generateAllocationRationale(
            allocations: topAllocations,
            totalCoinsEvaluated: coinScores.count,
            portfolioMetrics: portfolioMetrics
        )

        let plan = ScoreBasedAllocationPlan(
            totalAmount: amount,
            allocations: topAllocations,
            portfolioMetrics: portfolioMetrics,
            rationale: rationale,
            evaluationTimestamp: Date()
        )

        logger.info(component: "ScoreBasedAllocationManager", event: "Score-based allocation created", data: [
            "plan_id": plan.id.uuidString,
            "total_positions": String(topAllocations.count),
            "total_exposure": String(topAllocations.reduce(0) { $0 + $1.percentage }),
            "expected_return": String(portfolioMetrics.expectedReturn)
        ])

        return plan
    }

    public func calculateOptimalPositionSizes(coinScores: [CoinScore], totalAmount: Double) async throws -> [PositionAllocation] {
        logger.info(component: "ScoreBasedAllocationManager", event: "Calculating optimal position sizes")

        var allocations: [PositionAllocation] = []

        for coinScore in coinScores {
            let baseAllocation = calculateBaseAllocation(coinScore: coinScore)
            let riskAdjustment = calculateRiskAdjustment(coinScore: coinScore)
            let liquidityAdjustment = calculateLiquidityAdjustment(coinScore: coinScore)
            let momentumBoost = calculateMomentumBoost(coinScore: coinScore)

            let adjustedAllocation = baseAllocation * riskAdjustment * liquidityAdjustment * momentumBoost
            let maxPositionSize = calculateMaxPositionSize(coinScore: coinScore, totalAmount: totalAmount)

            let finalAllocation = min(adjustedAllocation, maxPositionSize)

            if finalAllocation > 0.01 {
                let allocation = PositionAllocation(
                    symbol: coinScore.symbol,
                    percentage: finalAllocation,
                    amount: totalAmount * finalAllocation,
                    score: coinScore.totalScore,
                    category: coinScore.category,
                    riskLevel: coinScore.riskLevel,
                    expectedReturn: calculateExpectedReturn(coinScore: coinScore),
                    volatility: coinScore.volatilityScore,
                    liquidity: coinScore.liquidityScore,
                    momentum: coinScore.momentumScore,
                    exchange: selectBestExchange(for: coinScore.symbol)
                )
                allocations.append(allocation)
            }
        }

        allocations.sort { $0.score > $1.score }

        logger.info(component: "ScoreBasedAllocationManager", event: "Position sizes calculated", data: [
            "total_allocations": String(allocations.count),
            "top_score": String(allocations.first?.score ?? 0.0)
        ])

        return allocations
    }

    public func applyRiskConstraints(allocations: [PositionAllocation], maxRisk: Double) async throws -> [PositionAllocation] {
        logger.info(component: "ScoreBasedAllocationManager", event: "Applying risk constraints", data: [
            "max_risk": String(maxRisk)
        ])

        var constrainedAllocations: [PositionAllocation] = []
        var totalRisk = 0.0

        for allocation in allocations {
            let positionRisk = calculatePositionRisk(allocation: allocation)

            if totalRisk + positionRisk <= maxRisk {
                constrainedAllocations.append(allocation)
                totalRisk += positionRisk
            } else {
                let remainingRisk = maxRisk - totalRisk
                if remainingRisk > 0.01 {
                    let adjustedPercentage = allocation.percentage * (remainingRisk / positionRisk)
                    let adjustedAllocation = PositionAllocation(
                        symbol: allocation.symbol,
                        percentage: adjustedPercentage,
                        amount: allocation.amount * (adjustedPercentage / allocation.percentage),
                        score: allocation.score,
                        category: allocation.category,
                        riskLevel: allocation.riskLevel,
                        expectedReturn: allocation.expectedReturn,
                        volatility: allocation.volatility,
                        liquidity: allocation.liquidity,
                        momentum: allocation.momentum,
                        exchange: allocation.exchange
                    )
                    constrainedAllocations.append(adjustedAllocation)
                }
                break
            }
        }

        logger.info(component: "ScoreBasedAllocationManager", event: "Risk constraints applied", data: [
            "constrained_positions": String(constrainedAllocations.count),
            "total_risk": String(totalRisk)
        ])

        return constrainedAllocations
    }

    public func calculatePortfolioMetrics(allocations: [PositionAllocation]) async throws -> PortfolioMetrics {
        logger.info(component: "ScoreBasedAllocationManager", event: "Calculating portfolio metrics")

        let totalExposure = allocations.reduce(0) { $0 + $1.percentage }
        let weightedExpectedReturn = allocations.reduce(0) { $0 + ($1.percentage * $1.expectedReturn) }
        let weightedVolatility = calculateWeightedVolatility(allocations: allocations)
        let diversificationScore = calculateDiversificationScore(allocations: allocations)
        let liquidityScore = calculatePortfolioLiquidity(allocations: allocations)
        let momentumScore = calculatePortfolioMomentum(allocations: allocations)

        let sharpeRatio = weightedExpectedReturn / weightedVolatility
        let maxDrawdown = calculateMaxDrawdown(allocations: allocations)

        return PortfolioMetrics(
            totalExposure: totalExposure,
            expectedReturn: weightedExpectedReturn,
            volatility: weightedVolatility,
            sharpeRatio: sharpeRatio,
            maxDrawdown: maxDrawdown,
            diversificationScore: diversificationScore,
            liquidityScore: liquidityScore,
            momentumScore: momentumScore,
            positionCount: allocations.count
        )
    }

    private func filterEligibleCoins(_ coinScores: [CoinScore]) -> [CoinScore] {
        return coinScores.filter { coinScore in
            coinScore.totalScore > 0.4 &&
            coinScore.liquidityScore > 0.3 &&
            coinScore.marketCap > 50_000_000 &&
            coinScore.riskLevel != .veryHigh
        }
    }

    private func calculateBaseAllocation(coinScore: CoinScore) -> Double {
        let scoreWeight = coinScore.totalScore
        let categoryWeight = getCategoryWeight(category: coinScore.category)
        let marketCapWeight = calculateMarketCapWeight(marketCap: coinScore.marketCap)

        return scoreWeight * categoryWeight * marketCapWeight * 0.1
    }

    private func calculateRiskAdjustment(coinScore: CoinScore) -> Double {
        switch coinScore.riskLevel {
        case .low: return 1.2
        case .medium: return 1.0
        case .high: return 0.8
        case .veryHigh: return 0.5
        }
    }

    private func calculateLiquidityAdjustment(coinScore: CoinScore) -> Double {
        if coinScore.liquidityScore > 0.8 {
            return 1.1
        } else if coinScore.liquidityScore > 0.6 {
            return 1.0
        } else if coinScore.liquidityScore > 0.4 {
            return 0.9
        } else {
            return 0.7
        }
    }

    private func calculateMomentumBoost(coinScore: CoinScore) -> Double {
        if coinScore.momentumScore > 0.8 {
            return 1.15
        } else if coinScore.momentumScore > 0.6 {
            return 1.05
        } else if coinScore.momentumScore > 0.4 {
            return 1.0
        } else {
            return 0.95
        }
    }

    private func calculateMaxPositionSize(coinScore: CoinScore, totalAmount: Double) -> Double {
        let baseMaxSize = 0.15

        let marketCapAdjustment = min(1.0, coinScore.marketCap / 1_000_000_000)
        let liquidityAdjustment = min(1.0, coinScore.liquidityScore)
        let riskAdjustment = coinScore.riskLevel == .low ? 1.0 : 0.8

        return baseMaxSize * marketCapAdjustment * liquidityAdjustment * riskAdjustment
    }

    private func calculateExpectedReturn(coinScore: CoinScore) -> Double {
        let baseReturn = 0.12

        let momentumAdjustment = coinScore.momentumScore > 0.7 ? 1.2 : 1.0
        let technicalAdjustment = coinScore.technicalScore > 0.7 ? 1.1 : 1.0
        let fundamentalAdjustment = coinScore.fundamentalScore > 0.7 ? 1.15 : 1.0

        return baseReturn * momentumAdjustment * technicalAdjustment * fundamentalAdjustment
    }

    private func calculatePositionRisk(allocation: PositionAllocation) -> Double {
        let volatilityRisk = allocation.volatility * allocation.percentage
        let liquidityRisk = (1.0 - allocation.liquidity) * allocation.percentage * 0.5
        let concentrationRisk = allocation.percentage * allocation.percentage

        return volatilityRisk + liquidityRisk + concentrationRisk
    }

    private func calculateWeightedVolatility(allocations: [PositionAllocation]) -> Double {
        let totalWeight = allocations.reduce(0) { $0 + $1.percentage }
        let weightedVolatility = allocations.reduce(0) { $0 + ($1.percentage * $1.volatility) }

        return totalWeight > 0 ? weightedVolatility / totalWeight : 0.0
    }

    private func calculateDiversificationScore(allocations: [PositionAllocation]) -> Double {
        let categories = Set(allocations.map { $0.category })
        let categoryCount = Double(categories.count)
        let maxCategories = Double(CoinCategory.allCases.count)

        let categoryDiversification = categoryCount / maxCategories

        let positionCount = Double(allocations.count)
        let maxPositions = 20.0
        let positionDiversification = min(1.0, positionCount / maxPositions)

        return (categoryDiversification + positionDiversification) / 2.0
    }

    private func calculatePortfolioLiquidity(allocations: [PositionAllocation]) -> Double {
        let totalWeight = allocations.reduce(0) { $0 + $1.percentage }
        let weightedLiquidity = allocations.reduce(0) { $0 + ($1.percentage * $1.liquidity) }

        return totalWeight > 0 ? weightedLiquidity / totalWeight : 0.0
    }

    private func calculatePortfolioMomentum(allocations: [PositionAllocation]) -> Double {
        let totalWeight = allocations.reduce(0) { $0 + $1.percentage }
        let weightedMomentum = allocations.reduce(0) { $0 + ($1.percentage * $1.momentum) }

        return totalWeight > 0 ? weightedMomentum / totalWeight : 0.0
    }

    private func calculateMaxDrawdown(allocations: [PositionAllocation]) -> Double {
        let maxVolatility = allocations.map { $0.volatility }.max() ?? 0.0
        return maxVolatility * 2.0
    }

    private func selectTopAllocations(allocations: [PositionAllocation], maxPositions: Int) -> [PositionAllocation] {
        return Array(allocations.prefix(maxPositions))
    }

    private func selectBestExchange(for symbol: String) -> String {
        return "kraken"
    }

    private func getCategoryWeight(category: CoinCategory) -> Double {
        switch category {
        case .layer1: return 1.0
        case .defi: return 0.95
        case .infrastructure: return 0.9
        case .layer2: return 0.85
        case .ai: return 0.8
        case .gaming: return 0.7
        case .storage: return 0.65
        case .nft: return 0.6
        case .privacy: return 0.5
        case .meme: return 0.3
        }
    }

    private func calculateMarketCapWeight(marketCap: Double) -> Double {
        if marketCap >= 10_000_000_000 {
            return 1.0
        } else if marketCap >= 1_000_000_000 {
            return 0.9
        } else if marketCap >= 100_000_000 {
            return 0.8
        } else if marketCap >= 50_000_000 {
            return 0.7
        } else {
            return 0.5
        }
    }

    private func generateAllocationRationale(
        allocations: [PositionAllocation],
        totalCoinsEvaluated: Int,
        portfolioMetrics: PortfolioMetrics
    ) -> String {
        var rationale = "Score-based allocation maximizing exposure across \(allocations.count) positions from \(totalCoinsEvaluated) evaluated coins. "

        rationale += "Portfolio metrics: Expected return \(String(format: "%.1f", portfolioMetrics.expectedReturn * 100))%, "
        rationale += "Volatility \(String(format: "%.1f", portfolioMetrics.volatility * 100))%, "
        rationale += "Sharpe ratio \(String(format: "%.2f", portfolioMetrics.sharpeRatio)), "
        rationale += "Diversification score \(String(format: "%.2f", portfolioMetrics.diversificationScore)). "

        if let topAllocation = allocations.first {
            rationale += "Top position: \(topAllocation.symbol) (\(String(format: "%.1f", topAllocation.percentage * 100))%) with score \(String(format: "%.2f", topAllocation.score))."
        }

        return rationale
    }
}

public struct ScoreBasedAllocationPlan: Codable, Identifiable {
    public let id: UUID
    public let totalAmount: Double
    public let allocations: [PositionAllocation]
    public let portfolioMetrics: PortfolioMetrics
    public let rationale: String
    public let evaluationTimestamp: Date

    public init(
        id: UUID = UUID(),
        totalAmount: Double,
        allocations: [PositionAllocation],
        portfolioMetrics: PortfolioMetrics,
        rationale: String,
        evaluationTimestamp: Date
    ) {
        self.id = id
        self.totalAmount = totalAmount
        self.allocations = allocations
        self.portfolioMetrics = portfolioMetrics
        self.rationale = rationale
        self.evaluationTimestamp = evaluationTimestamp
    }

    public var totalExposure: Double {
        return allocations.reduce(0) { $0 + $1.percentage }
    }

    public var topPositions: [PositionAllocation] {
        return Array(allocations.prefix(5))
    }
}

public struct PositionAllocation: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let percentage: Double
    public let amount: Double
    public let score: Double
    public let category: CoinCategory
    public let riskLevel: RiskLevel
    public let expectedReturn: Double
    public let volatility: Double
    public let liquidity: Double
    public let momentum: Double
    public let exchange: String

    public init(
        id: UUID = UUID(),
        symbol: String,
        percentage: Double,
        amount: Double,
        score: Double,
        category: CoinCategory,
        riskLevel: RiskLevel,
        expectedReturn: Double,
        volatility: Double,
        liquidity: Double,
        momentum: Double,
        exchange: String
    ) {
        self.id = id
        self.symbol = symbol
        self.percentage = percentage
        self.amount = amount
        self.score = score
        self.category = category
        self.riskLevel = riskLevel
        self.expectedReturn = expectedReturn
        self.volatility = volatility
        self.liquidity = liquidity
        self.momentum = momentum
        self.exchange = exchange
    }
}

public struct PortfolioMetrics: Codable {
    public let totalExposure: Double
    public let expectedReturn: Double
    public let volatility: Double
    public let sharpeRatio: Double
    public let maxDrawdown: Double
    public let diversificationScore: Double
    public let liquidityScore: Double
    public let momentumScore: Double
    public let positionCount: Int

    public init(
        totalExposure: Double,
        expectedReturn: Double,
        volatility: Double,
        sharpeRatio: Double,
        maxDrawdown: Double,
        diversificationScore: Double,
        liquidityScore: Double,
        momentumScore: Double,
        positionCount: Int
    ) {
        self.totalExposure = totalExposure
        self.expectedReturn = expectedReturn
        self.volatility = volatility
        self.sharpeRatio = sharpeRatio
        self.maxDrawdown = maxDrawdown
        self.diversificationScore = diversificationScore
        self.liquidityScore = liquidityScore
        self.momentumScore = momentumScore
        self.positionCount = positionCount
    }
}
