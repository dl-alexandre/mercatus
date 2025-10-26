import Foundation
import Utils
import MLPatternEngine

public class SmartVestorIntegration {
    private let mlEngine: MLPatternEngine
    private let logger: StructuredLogger
    private let metricsCollector: MetricsCollector

    public init(mlEngine: MLPatternEngine, logger: StructuredLogger, metricsCollector: MetricsCollector) {
        self.mlEngine = mlEngine
        self.logger = logger
        self.metricsCollector = metricsCollector
    }

    // MARK: - ML-Enhanced Portfolio Management

    public func generatePortfolioRecommendations() async throws -> MLPortfolioRecommendation {
        let startTime = Date()

        // Get market data for major cryptocurrencies
        let symbols = ["BTC-USD", "ETH-USD", "BNB-USD", "ADA-USD", "SOL-USD", "MATIC-USD", "AVAX-USD", "DOT-USD"]
        _ = try await mlEngine.getLatestData(symbols: symbols)

        var assetAnalysis: [MLAssetAnalysis] = []

        for symbol in symbols {
            // Get comprehensive ML analysis for each asset
            let analysis = try await analyzeAsset(symbol: symbol)
            assetAnalysis.append(analysis)
        }

        // Generate portfolio allocation
        let portfolioAllocation = calculatePortfolioAllocation(assetAnalysis: assetAnalysis)

        // Calculate portfolio metrics
        let portfolioMetrics = calculatePortfolioMetrics(assetAnalysis: assetAnalysis, allocation: portfolioAllocation)

        let recommendation = MLPortfolioRecommendation(
            timestamp: Date(),
            allocation: portfolioAllocation,
            expectedReturn: portfolioMetrics.expectedReturn,
            expectedVolatility: portfolioMetrics.expectedVolatility,
            sharpeRatio: portfolioMetrics.sharpeRatio,
            maxDrawdown: portfolioMetrics.maxDrawdown,
            confidence: portfolioMetrics.confidence,
            riskLevel: portfolioMetrics.riskLevel,
            rebalanceRecommendation: portfolioMetrics.rebalanceRecommendation,
            timeHorizon: 86400 // 24 hours
        )

        let latency = Date().timeIntervalSince(startTime)
        metricsCollector.recordPredictionLatency(latency, modelType: "portfolio_recommendation")

        logger.info(component: "SmartVestorIntegration", event: "Portfolio recommendations generated", data: [
            "assets_analyzed": "\(assetAnalysis.count)",
            "expected_return": "\(portfolioMetrics.expectedReturn)",
            "latency_ms": "\(latency * 1000)"
        ])

        return recommendation
    }

    // MARK: - Dynamic Rebalancing

    public func shouldRebalance(currentPortfolio: [String: Double], targetAllocation: [String: Double]) async throws -> RebalancingRecommendation {
        let startTime = Date()

        // Calculate drift from target allocation
        let drift = calculateAllocationDrift(current: currentPortfolio, target: targetAllocation)

        // Get current market conditions
        let symbols = Array(currentPortfolio.keys)
        _ = try await mlEngine.getLatestData(symbols: symbols)

        // Analyze market volatility
        let volatilityAnalysis = try await analyzeMarketVolatility(symbols: symbols)

        // Determine rebalancing strategy
        let strategy = determineRebalancingStrategy(drift: drift, volatility: volatilityAnalysis)

        let recommendation = RebalancingRecommendation(
            shouldRebalance: strategy.shouldRebalance,
            urgency: strategy.urgency,
            targetAllocation: strategy.targetAllocation,
            reasoning: strategy.reasoning,
            estimatedCost: strategy.estimatedCost,
            confidence: strategy.confidence
        )

        let latency = Date().timeIntervalSince(startTime)
        metricsCollector.recordPredictionLatency(latency, modelType: "rebalancing_analysis")

        logger.info(component: "SmartVestorIntegration", event: "Rebalancing analysis completed", data: [
            "should_rebalance": "\(strategy.shouldRebalance)",
            "urgency": "\(strategy.urgency.rawValue)",
            "latency_ms": "\(latency * 1000)"
        ])

        return recommendation
    }

    // MARK: - Risk Management

    public func assessPortfolioRisk(portfolio: [String: Double]) async throws -> RiskAssessment {
        let startTime = Date()

        var riskFactors: [RiskFactor] = []
        var totalRiskScore = 0.0

        for (symbol, allocation) in portfolio {
            // Get volatility prediction
            let volatilityPrediction = try await mlEngine.getPrediction(
                for: symbol,
                timeHorizon: 3600,
                modelType: .volatilityPrediction
            )

            // Detect patterns
            let patterns = try await mlEngine.detectPatterns(for: symbol)

            // Calculate asset-specific risk
            let assetRisk = calculateAssetRisk(
                symbol: symbol,
                allocation: allocation,
                volatility: volatilityPrediction.prediction,
                patterns: patterns
            )

            riskFactors.append(assetRisk)
            totalRiskScore += assetRisk.score * allocation
        }

        // Calculate correlation risk
        let correlationRisk = try await calculateCorrelationRisk(symbols: Array(portfolio.keys))

        // Calculate concentration risk
        let concentrationRisk = calculateConcentrationRisk(portfolio: portfolio)

        let assessment = RiskAssessment(
            timestamp: Date(),
            overallRiskScore: totalRiskScore,
            riskLevel: determineRiskLevel(score: totalRiskScore),
            riskFactors: riskFactors,
            correlationRisk: correlationRisk,
            concentrationRisk: concentrationRisk,
            recommendations: generateRiskRecommendations(riskFactors: riskFactors, correlationRisk: correlationRisk, concentrationRisk: concentrationRisk)
        )

        let latency = Date().timeIntervalSince(startTime)
        metricsCollector.recordPredictionLatency(latency, modelType: "risk_assessment")

        logger.info(component: "SmartVestorIntegration", event: "Risk assessment completed", data: [
            "overall_risk_score": "\(totalRiskScore)",
            "risk_level": "\(assessment.riskLevel.rawValue)",
            "latency_ms": "\(latency * 1000)"
        ])

        return assessment
    }

    // MARK: - Private Helper Methods

    private func analyzeAsset(symbol: String) async throws -> MLAssetAnalysis {
        // Get price prediction
        let pricePrediction = try await mlEngine.getPrediction(
            for: symbol,
            timeHorizon: 3600,
            modelType: .pricePrediction
        )

        // Get volatility prediction
        let volatilityPrediction = try await mlEngine.getPrediction(
            for: symbol,
            timeHorizon: 3600,
            modelType: .volatilityPrediction
        )

        // Detect patterns
        let patterns = try await mlEngine.detectPatterns(for: symbol)

        // Calculate technical indicators
        let marketData = try await mlEngine.getLatestData(symbols: [symbol])
        let features = try await mlEngine.extractFeatures(for: symbol, historicalData: marketData)

        // Calculate ML score
        let mlScore = calculateMLScore(
            priceConfidence: pricePrediction.confidence,
            volatility: volatilityPrediction.prediction,
            patterns: patterns,
            features: features
        )

        return MLAssetAnalysis(
            symbol: symbol,
            pricePrediction: pricePrediction,
            volatilityPrediction: volatilityPrediction,
            patterns: patterns,
            mlScore: mlScore,
            recommendedAllocation: calculateRecommendedAllocation(mlScore: mlScore, volatility: volatilityPrediction.prediction),
            riskLevel: determineAssetRiskLevel(volatility: volatilityPrediction.prediction, patterns: patterns)
        )
    }

    private func calculateMLScore(priceConfidence: Double, volatility: Double, patterns: [DetectedPattern], features: FeatureSet) -> Double {
        var score = priceConfidence * 0.4 // Base score from prediction confidence

        // Adjust for volatility (lower volatility = higher score)
        score += (1.0 - volatility) * 0.3

        // Boost for bullish patterns
        for pattern in patterns {
            switch pattern.patternType {
            case .triangle, .flag:
                score += 0.1
            case .headAndShoulders, .doubleTop, .doubleBottom:
                score -= 0.1
            default:
                break
            }
        }

        // Adjust based on technical indicators
        if let rsi = features.features["rsi"] {
            if rsi < 30 { // Oversold
                score += 0.1
            } else if rsi > 70 { // Overbought
                score -= 0.1
            }
        }

        if let macd = features.features["macd"] {
            if macd > 0 { // Bullish MACD
                score += 0.05
            } else { // Bearish MACD
                score -= 0.05
            }
        }

        return max(0.0, min(score, 1.0))
    }

    private func calculateRecommendedAllocation(mlScore: Double, volatility: Double) -> Double {
        var allocation = mlScore * 0.3 // Base allocation

        // Adjust for volatility
        if volatility < 0.3 {
            allocation += 0.1 // Low volatility = higher allocation
        } else if volatility > 0.7 {
            allocation -= 0.1 // High volatility = lower allocation
        }

        return max(0.0, min(allocation, 0.4)) // Cap at 40% per asset
    }

    private func determineAssetRiskLevel(volatility: Double, patterns: [DetectedPattern]) -> RiskLevel {
        var riskLevel = RiskLevel.low

        if volatility > 0.7 {
            riskLevel = .high
        } else if volatility > 0.4 {
            riskLevel = .medium
        }

        // Adjust based on patterns
        for pattern in patterns {
            switch pattern.patternType {
            case .headAndShoulders, .doubleTop:
                riskLevel = .high
            case .triangle, .flag:
                if riskLevel == .low {
                    riskLevel = .medium
                }
            default:
                break
            }
        }

        return riskLevel
    }

    private func calculatePortfolioAllocation(assetAnalysis: [MLAssetAnalysis]) -> [String: Double] {
        var allocation: [String: Double] = [:]
        let totalScore = assetAnalysis.map { $0.mlScore }.reduce(0, +)

        guard totalScore > 0 else { return allocation }

        for analysis in assetAnalysis {
            let normalizedScore = analysis.mlScore / totalScore
            allocation[analysis.symbol] = normalizedScore * 0.8 // Use 80% of portfolio
        }

        // Ensure allocations sum to 1.0
        let currentTotal = allocation.values.reduce(0, +)
        if currentTotal > 0 {
            for symbol in allocation.keys {
                allocation[symbol] = allocation[symbol]! / currentTotal
            }
        }

        return allocation
    }

    private func calculatePortfolioMetrics(assetAnalysis: [MLAssetAnalysis], allocation: [String: Double]) -> PortfolioMetrics {
        let weightedReturn = assetAnalysis.map { analysis in
            (analysis.pricePrediction.prediction - 1.0) * (allocation[analysis.symbol] ?? 0.0)
        }.reduce(0, +)

        let weightedVolatility = assetAnalysis.map { analysis in
            analysis.volatilityPrediction.prediction * (allocation[analysis.symbol] ?? 0.0)
        }.reduce(0, +)

        let averageConfidence = assetAnalysis.map { $0.pricePrediction.confidence }.reduce(0, +) / Double(assetAnalysis.count)

        return PortfolioMetrics(
            expectedReturn: weightedReturn,
            expectedVolatility: weightedVolatility,
            sharpeRatio: weightedVolatility > 0 ? weightedReturn / weightedVolatility : 0.0,
            maxDrawdown: calculateMaxDrawdown(assetAnalysis: assetAnalysis),
            confidence: averageConfidence,
            riskLevel: determineRiskLevel(volatility: weightedVolatility),
            rebalanceRecommendation: averageConfidence < 0.6 ? .reduceRisk : .maintain
        )
    }

    private func calculateMaxDrawdown(assetAnalysis: [MLAssetAnalysis]) -> Double {
        // Simplified max drawdown calculation
        let maxVolatility = assetAnalysis.map { $0.volatilityPrediction.prediction }.max() ?? 0.0
        return maxVolatility * 0.5 // Assume max drawdown is 50% of max volatility
    }

    private func calculateDiversificationRatio(allocation: [String: Double]) -> Double {
        let allocationValues = allocation.values
        let count = Double(allocationValues.count)

        guard count > 0 else { return 0.0 }

        // Calculate Herfindahl index
        let herfindahlIndex = allocationValues.map { $0 * $0 }.reduce(0, +)

        // Convert to diversification ratio (1 - Herfindahl index)
        return 1.0 - herfindahlIndex
    }

    private func generateRecommendedActions(arbitrageOpportunities: [EnhancedArbitrageOpportunity], portfolioRecommendation: MLPortfolioRecommendation, riskAssessment: RiskAssessment) -> [RecommendedAction] {
        var actions: [RecommendedAction] = []

        // Add arbitrage actions
        for opportunity in arbitrageOpportunities {
            if opportunity.recommendedAction == .execute {
                actions.append(RecommendedAction(
                    type: .executeArbitrage,
                    priority: .high,
                    description: "Execute arbitrage opportunity for \(opportunity.baseOpportunity.baseSymbol ?? "UNKNOWN")",
                    estimatedProfit: opportunity.baseOpportunity.profitPercentage * 1000, // Convert to dollar amount
                    confidence: opportunity.mlConfidence
                ))
            }
        }

        // Add portfolio rebalancing actions
        for (symbol, allocation) in portfolioRecommendation.allocation {
            if allocation > 0.1 { // Only recommend for significant allocations
                actions.append(RecommendedAction(
                    type: .rebalancePortfolio,
                    priority: .medium,
                    description: "Rebalance portfolio allocation for \(symbol)",
                    estimatedProfit: 0.0, // No direct profit from rebalancing
                    confidence: portfolioRecommendation.confidence
                ))
            }
        }

        // Add risk management actions
        if riskAssessment.riskLevel == .high {
            actions.append(RecommendedAction(
                type: .reduceRisk,
                priority: .high,
                description: "Implement risk management measures",
                estimatedProfit: 0.0, // Risk management doesn't generate profit
                confidence: 0.9
            ))
        }

        return actions
    }

    private func calculateOverallConfidence(arbitrageOpportunities: [EnhancedArbitrageOpportunity], portfolioRecommendation: MLPortfolioRecommendation) -> Double {
        var totalConfidence = portfolioRecommendation.confidence
        var count = 1

        for opportunity in arbitrageOpportunities {
            totalConfidence += opportunity.mlConfidence
            count += 1
        }

        return count > 0 ? totalConfidence / Double(count) : 0.0
    }
}

    private func calculateRecommendedAllocation(mlScore: Double, volatility: Double) -> Double {
        var allocation = mlScore * 0.2 // Base allocation

        // Adjust for volatility
        if volatility < 0.3 {
            allocation *= 1.2 // Increase for low volatility
        } else if volatility > 0.7 {
            allocation *= 0.8 // Decrease for high volatility
        }

        return max(0.0, min(allocation, 0.3)) // Cap at 30% per asset
    }

    private func determineAssetRiskLevel(volatility: Double, patterns: [DetectedPattern]) -> RiskLevel {
        var riskLevel = RiskLevel.low

        if volatility > 0.7 {
            riskLevel = .high
        } else if volatility > 0.4 {
            riskLevel = .medium
        }

        // Adjust based on patterns
        for pattern in patterns {
            if pattern.patternType == .headAndShoulders || pattern.patternType == .triangle {
                riskLevel = .high
                break
            }
        }

        return riskLevel
    }

    private func calculatePortfolioAllocation(assetAnalysis: [MLAssetAnalysis]) -> [String: Double] {
        var allocation: [String: Double] = [:]
        let totalScore = assetAnalysis.reduce(0.0) { $0 + $1.mlScore }

        for analysis in assetAnalysis {
            let normalizedScore = analysis.mlScore / totalScore
            allocation[analysis.symbol] = normalizedScore * 0.8 // Use 80% of portfolio
        }

        // Add 20% cash allocation
        allocation["CASH"] = 0.2

        return allocation
    }

    private func calculatePortfolioMetrics(assetAnalysis: [MLAssetAnalysis], allocation: [String: Double]) -> PortfolioMetrics {
        var expectedReturn = 0.0
        var expectedVolatility = 0.0
        var confidence = 0.0

        for analysis in assetAnalysis {
            if let weight = allocation[analysis.symbol] {
                expectedReturn += analysis.pricePrediction.prediction * weight
                expectedVolatility += analysis.volatilityPrediction.prediction * weight
                confidence += analysis.pricePrediction.confidence * weight
            }
        }

        let sharpeRatio = expectedReturn / max(expectedVolatility, 0.01)
        let maxDrawdown = expectedVolatility * 2.0 // Simplified calculation

        return PortfolioMetrics(
            expectedReturn: expectedReturn,
            expectedVolatility: expectedVolatility,
            sharpeRatio: sharpeRatio,
            maxDrawdown: maxDrawdown,
            confidence: confidence,
            riskLevel: determineRiskLevel(score: expectedVolatility),
            rebalanceRecommendation: confidence < 0.6 ? .reduceRisk : .maintain
        )
    }

    private func calculateAllocationDrift(current: [String: Double], target: [String: Double]) -> Double {
        var totalDrift = 0.0

        for (symbol, targetWeight) in target {
            let currentWeight = current[symbol] ?? 0.0
            totalDrift += abs(currentWeight - targetWeight)
        }

        return totalDrift
    }

    private func analyzeMarketVolatility(symbols: [String]) async throws -> Double {
        var totalVolatility = 0.0

        for _ in symbols {
            // Mock volatility prediction - in production this would use the ML engine
            let mockVolatility = Double.random(in: 0.1...0.5)
            totalVolatility += mockVolatility
        }

        return totalVolatility / Double(symbols.count)
    }

    private func determineRebalancingStrategy(drift: Double, volatility: Double) -> RebalancingStrategy {
        let shouldRebalance = drift > 0.05 || volatility > 0.6

        let urgency: RebalancingUrgency
        if drift > 0.15 || volatility > 0.8 {
            urgency = .high
        } else if drift > 0.08 || volatility > 0.6 {
            urgency = .medium
        } else {
            urgency = .low
        }

        let reasoning = generateRebalancingReasoning(drift: drift, volatility: volatility)

        return RebalancingStrategy(
            shouldRebalance: shouldRebalance,
            urgency: urgency,
            targetAllocation: [:], // Would be calculated based on current analysis
            reasoning: reasoning,
            estimatedCost: drift * 0.001, // 0.1% of portfolio value
            confidence: 0.8
        )
    }

    private func generateRebalancingReasoning(drift: Double, volatility: Double) -> String {
        var reasoning = "Rebalancing analysis: "

        if drift > 0.15 {
            reasoning += "Significant allocation drift detected. "
        } else if drift > 0.08 {
            reasoning += "Moderate allocation drift detected. "
        }

        if volatility > 0.8 {
            reasoning += "High market volatility requires defensive positioning. "
        } else if volatility > 0.6 {
            reasoning += "Elevated volatility suggests cautious rebalancing. "
        }

        return reasoning
    }

    private func calculateAssetRisk(symbol: String, allocation: Double, volatility: Double, patterns: [DetectedPattern]) -> RiskFactor {
        var riskScore = volatility * allocation

        // Adjust for patterns
        for pattern in patterns {
            if pattern.patternType == .headAndShoulders || pattern.patternType == .triangle {
                riskScore += 0.2
            }
        }

        return RiskFactor(
            symbol: symbol,
            riskType: .volatility,
            score: riskScore,
            description: "Volatility risk for \(symbol)",
            mitigation: "Consider reducing allocation or hedging"
        )
    }

    private func calculateCorrelationRisk(symbols: [String]) async throws -> Double {
        // Simplified correlation calculation
        // In a real implementation, this would calculate actual correlations
        return 0.3 // Placeholder
    }

    private func calculateConcentrationRisk(portfolio: [String: Double]) -> Double {
        let maxAllocation = portfolio.values.max() ?? 0.0
        return maxAllocation > 0.4 ? 0.8 : 0.2
    }

    private func determineRiskLevel(score: Double) -> RiskLevel {
        if score > 0.7 {
            return .high
        } else if score > 0.4 {
            return .medium
        } else {
            return .low
        }
    }

    private func generateRiskRecommendations(riskFactors: [RiskFactor], correlationRisk: Double, concentrationRisk: Double) -> [String] {
        var recommendations: [String] = []

        if concentrationRisk > 0.6 {
            recommendations.append("Consider diversifying portfolio to reduce concentration risk")
        }

        if correlationRisk > 0.5 {
            recommendations.append("High correlation detected - consider adding uncorrelated assets")
        }

        for factor in riskFactors {
            if factor.score > 0.6 {
                recommendations.append("High risk detected for \(factor.symbol): \(factor.mitigation)")
            }
        }

        return recommendations
    }

    private func determineRiskLevel(volatility: Double) -> RiskLevel {
        switch volatility {
        case 0..<0.2:
            return .low
        case 0.2..<0.4:
            return .medium
        default:
            return .high
        }
    }

// MARK: - Integration Models

public struct MLPortfolioRecommendation {
    public let timestamp: Date
    public let allocation: [String: Double]
    public let expectedReturn: Double
    public let expectedVolatility: Double
    public let sharpeRatio: Double
    public let maxDrawdown: Double
    public let confidence: Double
    public let riskLevel: RiskLevel
    public let rebalanceRecommendation: RebalanceRecommendation
    public let timeHorizon: TimeInterval

    public init(timestamp: Date, allocation: [String: Double], expectedReturn: Double, expectedVolatility: Double, sharpeRatio: Double, maxDrawdown: Double, confidence: Double, riskLevel: RiskLevel, rebalanceRecommendation: RebalanceRecommendation, timeHorizon: TimeInterval) {
        self.timestamp = timestamp
        self.allocation = allocation
        self.expectedReturn = expectedReturn
        self.expectedVolatility = expectedVolatility
        self.sharpeRatio = sharpeRatio
        self.maxDrawdown = maxDrawdown
        self.confidence = confidence
        self.riskLevel = riskLevel
        self.rebalanceRecommendation = rebalanceRecommendation
        self.timeHorizon = timeHorizon
    }
}

public struct MLAssetAnalysis {
    public let symbol: String
    public let pricePrediction: PredictionResponse
    public let volatilityPrediction: PredictionResponse
    public let patterns: [DetectedPattern]
    public let mlScore: Double
    public let recommendedAllocation: Double
    public let riskLevel: RiskLevel

    public init(symbol: String, pricePrediction: PredictionResponse, volatilityPrediction: PredictionResponse, patterns: [DetectedPattern], mlScore: Double, recommendedAllocation: Double, riskLevel: RiskLevel) {
        self.symbol = symbol
        self.pricePrediction = pricePrediction
        self.volatilityPrediction = volatilityPrediction
        self.patterns = patterns
        self.mlScore = mlScore
        self.recommendedAllocation = recommendedAllocation
        self.riskLevel = riskLevel
    }
}

public struct RebalancingRecommendation {
    public let shouldRebalance: Bool
    public let urgency: RebalancingUrgency
    public let targetAllocation: [String: Double]
    public let reasoning: String
    public let estimatedCost: Double
    public let confidence: Double

    public init(shouldRebalance: Bool, urgency: RebalancingUrgency, targetAllocation: [String: Double], reasoning: String, estimatedCost: Double, confidence: Double) {
        self.shouldRebalance = shouldRebalance
        self.urgency = urgency
        self.targetAllocation = targetAllocation
        self.reasoning = reasoning
        self.estimatedCost = estimatedCost
        self.confidence = confidence
    }
}

public struct RiskAssessment {
    public let timestamp: Date
    public let overallRiskScore: Double
    public let riskLevel: RiskLevel
    public let riskFactors: [RiskFactor]
    public let correlationRisk: Double
    public let concentrationRisk: Double
    public let recommendations: [String]

    public init(timestamp: Date, overallRiskScore: Double, riskLevel: RiskLevel, riskFactors: [RiskFactor], correlationRisk: Double, concentrationRisk: Double, recommendations: [String]) {
        self.timestamp = timestamp
        self.overallRiskScore = overallRiskScore
        self.riskLevel = riskLevel
        self.riskFactors = riskFactors
        self.correlationRisk = correlationRisk
        self.concentrationRisk = concentrationRisk
        self.recommendations = recommendations
    }
}

public struct RiskFactor {
    public let symbol: String
    public let riskType: RiskType
    public let score: Double
    public let description: String
    public let mitigation: String

    public init(symbol: String, riskType: RiskType, score: Double, description: String, mitigation: String) {
        self.symbol = symbol
        self.riskType = riskType
        self.score = score
        self.description = description
        self.mitigation = mitigation
    }
}

public enum RiskType: String, CaseIterable {
    case volatility = "VOLATILITY"
    case correlation = "CORRELATION"
    case concentration = "CONCENTRATION"
    case liquidity = "LIQUIDITY"
    case market = "MARKET"
}

public enum RebalancingUrgency: String, CaseIterable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
}

public enum RebalanceRecommendation: String, CaseIterable {
    case maintain = "MAINTAIN"
    case reduceRisk = "REDUCE_RISK"
    case increaseRisk = "INCREASE_RISK"
    case rebalance = "REBALANCE"
}

public struct RebalancingStrategy {
    public let shouldRebalance: Bool
    public let urgency: RebalancingUrgency
    public let targetAllocation: [String: Double]
    public let reasoning: String
    public let estimatedCost: Double
    public let confidence: Double

    public init(shouldRebalance: Bool, urgency: RebalancingUrgency, targetAllocation: [String: Double], reasoning: String, estimatedCost: Double, confidence: Double) {
        self.shouldRebalance = shouldRebalance
        self.urgency = urgency
        self.targetAllocation = targetAllocation
        self.reasoning = reasoning
        self.estimatedCost = estimatedCost
        self.confidence = confidence
    }
}

public struct PortfolioMetrics {
    public let expectedReturn: Double
    public let expectedVolatility: Double
    public let sharpeRatio: Double
    public let maxDrawdown: Double
    public let confidence: Double
    public let riskLevel: RiskLevel
    public let rebalanceRecommendation: RebalanceRecommendation

    public init(expectedReturn: Double, expectedVolatility: Double, sharpeRatio: Double, maxDrawdown: Double, confidence: Double, riskLevel: RiskLevel, rebalanceRecommendation: RebalanceRecommendation) {
        self.expectedReturn = expectedReturn
        self.expectedVolatility = expectedVolatility
        self.sharpeRatio = sharpeRatio
        self.maxDrawdown = maxDrawdown
        self.confidence = confidence
        self.riskLevel = riskLevel
        self.rebalanceRecommendation = rebalanceRecommendation
    }
}
