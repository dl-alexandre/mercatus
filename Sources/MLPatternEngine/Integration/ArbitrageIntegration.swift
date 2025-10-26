import Foundation
import Utils
import Core
import MLPatternEngine

public class ArbitrageIntegration {
    private let mlEngine: MLPatternEngine
    private let arbitrageDetector: TriangularArbitrageDetector
    private let logger: StructuredLogger
    private let metricsCollector: MetricsCollector

    public init(mlEngine: MLPatternEngine, arbitrageDetector: TriangularArbitrageDetector, logger: StructuredLogger, metricsCollector: MetricsCollector) {
        self.mlEngine = mlEngine
        self.arbitrageDetector = arbitrageDetector
        self.logger = logger
        self.metricsCollector = metricsCollector
    }

    // MARK: - Enhanced Arbitrage Detection

    public func detectArbitrageOpportunities() async throws -> [EnhancedArbitrageOpportunity] {
        let startTime = Date()

        // Get current market data
        _ = try await mlEngine.getLatestData(symbols: ["BTC-USD", "ETH-USD", "BNB-USD"])

        // Detect traditional arbitrage opportunities
        // Note: This would need to be implemented in TriangularArbitrageDetector
        let arbitrageOpportunities: [ArbitrageOpportunity] = []

        var enhancedOpportunities: [EnhancedArbitrageOpportunity] = []

        for opportunity in arbitrageOpportunities {
            // Get ML predictions for each symbol in the arbitrage path
            let predictions = try await getPredictionsForArbitragePath(opportunity)

            // Analyze patterns for each symbol
            let patterns = try await getPatternsForArbitragePath(opportunity)

            // Calculate ML-enhanced confidence score
            let mlConfidence = calculateMLConfidence(predictions: predictions, patterns: patterns)

            // Create enhanced opportunity
            let enhancedOpportunity = EnhancedArbitrageOpportunity(
                baseOpportunity: opportunity,
                mlConfidence: mlConfidence,
                pricePredictions: predictions,
                detectedPatterns: patterns,
                riskScore: calculateRiskScore(predictions: predictions, patterns: patterns),
                recommendedAction: getRecommendedAction(mlConfidence: mlConfidence, riskScore: calculateRiskScore(predictions: predictions, patterns: patterns))
            )

            enhancedOpportunities.append(enhancedOpportunity)
        }

        let latency = Date().timeIntervalSince(startTime)
        metricsCollector.recordPredictionLatency(latency, modelType: "arbitrage_enhancement")

        logger.info(component: "ArbitrageIntegration", event: "Enhanced arbitrage detection completed", data: [
            "opportunities_found": "\(enhancedOpportunities.count)",
            "latency_ms": "\(latency * 1000)"
        ])

        return enhancedOpportunities
    }

    // MARK: - SmartVestor Integration

    public func getMLEnhancedAllocationRecommendations() async throws -> [MLAllocationRecommendation] {
        let startTime = Date()

        // Get current market conditions
        _ = try await mlEngine.getLatestData(symbols: ["BTC-USD", "ETH-USD", "BNB-USD", "ADA-USD", "SOL-USD"])

        var recommendations: [MLAllocationRecommendation] = []

        for symbol in ["BTC-USD", "ETH-USD", "BNB-USD", "ADA-USD", "SOL-USD"] {
            // Get price predictions
            let pricePrediction = try await mlEngine.getPrediction(
                for: symbol,
                timeHorizon: 3600, // 1 hour
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

            // Calculate allocation recommendation
            let allocation = calculateAllocation(
                symbol: symbol,
                pricePrediction: pricePrediction,
                volatilityPrediction: volatilityPrediction,
                patterns: patterns
            )

            let recommendation = MLAllocationRecommendation(
                symbol: symbol,
                recommendedAllocation: allocation,
                confidence: pricePrediction.confidence,
                riskLevel: calculateRiskLevel(volatilityPrediction: volatilityPrediction, patterns: patterns),
                reasoning: generateReasoning(pricePrediction: pricePrediction, volatilityPrediction: volatilityPrediction, patterns: patterns),
                timeHorizon: 3600
            )

            recommendations.append(recommendation)
        }

        let latency = Date().timeIntervalSince(startTime)
        metricsCollector.recordPredictionLatency(latency, modelType: "allocation_recommendation")

        logger.info(component: "ArbitrageIntegration", event: "ML allocation recommendations generated", data: [
            "recommendations_count": "\(recommendations.count)",
            "latency_ms": "\(latency * 1000)"
        ])

        return recommendations
    }

    // MARK: - Private Helper Methods

    private func getPredictionsForArbitragePath(_ opportunity: ArbitrageOpportunity) async throws -> [String: PredictionResponse] {
        var predictions: [String: PredictionResponse] = [:]

        // Get predictions for each symbol in the arbitrage path
        for symbol in [opportunity.baseSymbol, opportunity.quoteSymbol, opportunity.intermediateSymbol] {
            if let symbol = symbol {
                let prediction = try await mlEngine.getPrediction(
                    for: symbol,
                    timeHorizon: 300, // 5 minutes
                    modelType: .pricePrediction
                )
                predictions[symbol] = prediction
            }
        }

        return predictions
    }

    private func getPatternsForArbitragePath(_ opportunity: ArbitrageOpportunity) async throws -> [String: [DetectedPattern]] {
        var patterns: [String: [DetectedPattern]] = [:]

        for symbol in [opportunity.baseSymbol, opportunity.quoteSymbol, opportunity.intermediateSymbol] {
            if let symbol = symbol {
                let symbolPatterns = try await mlEngine.detectPatterns(for: symbol)
                patterns[symbol] = symbolPatterns
            }
        }

        return patterns
    }

    private func calculateMLConfidence(predictions: [String: PredictionResponse], patterns: [String: [DetectedPattern]]) -> Double {
        var totalConfidence = 0.0
        var count = 0

        // Average prediction confidence
        for prediction in predictions.values {
            totalConfidence += prediction.confidence
            count += 1
        }

        // Boost confidence for bullish patterns
        for symbolPatterns in patterns.values {
            for pattern in symbolPatterns {
                if pattern.patternType == .triangle || pattern.patternType == .flag {
                    totalConfidence += 0.1
                }
            }
        }

        return count > 0 ? min(totalConfidence / Double(count), 1.0) : 0.0
    }

    private func calculateRiskScore(predictions: [String: PredictionResponse], patterns: [String: [DetectedPattern]]) -> Double {
        var riskScore = 0.0
        var count = 0

        // Higher uncertainty increases risk
        for prediction in predictions.values {
            riskScore += prediction.uncertainty
            count += 1
        }

        // Bearish patterns increase risk
        for symbolPatterns in patterns.values {
            for pattern in symbolPatterns {
                if pattern.patternType == .headAndShoulders || pattern.patternType == .triangle {
                    riskScore += 0.2
                }
            }
        }

        return count > 0 ? min(riskScore / Double(count), 1.0) : 0.0
    }

    private func getRecommendedAction(mlConfidence: Double, riskScore: Double) -> ArbitrageAction {
        if mlConfidence > 0.8 && riskScore < 0.3 {
            return .execute
        } else if mlConfidence > 0.6 && riskScore < 0.5 {
            return .monitor
        } else {
            return .avoid
        }
    }

    private func calculateAllocation(symbol: String, pricePrediction: PredictionResponse, volatilityPrediction: PredictionResponse, patterns: [DetectedPattern]) -> Double {
        var allocation = 0.0

        // Base allocation on price prediction confidence
        allocation += pricePrediction.confidence * 0.3

        // Adjust based on volatility (lower volatility = higher allocation)
        allocation += (1.0 - volatilityPrediction.prediction) * 0.2

        // Boost for bullish patterns
        for pattern in patterns {
            if pattern.patternType == .triangle || pattern.patternType == .flag {
                allocation += 0.1
            } else if pattern.patternType == .headAndShoulders || pattern.patternType == .triangle {
                allocation -= 0.1
            }
        }

        return max(0.0, min(allocation, 0.4)) // Cap at 40% per asset
    }

    private func calculateRiskLevel(volatilityPrediction: PredictionResponse, patterns: [DetectedPattern]) -> RiskLevel {
        let volatility = volatilityPrediction.prediction
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

    private func generateReasoning(pricePrediction: PredictionResponse, volatilityPrediction: PredictionResponse, patterns: [DetectedPattern]) -> String {
        var reasoning = "ML Analysis: "

        if pricePrediction.confidence > 0.8 {
            reasoning += "High confidence price prediction. "
        } else if pricePrediction.confidence > 0.6 {
            reasoning += "Moderate confidence price prediction. "
        } else {
            reasoning += "Low confidence price prediction. "
        }

        if volatilityPrediction.prediction > 0.7 {
            reasoning += "High volatility expected. "
        } else if volatilityPrediction.prediction > 0.4 {
            reasoning += "Moderate volatility expected. "
        } else {
            reasoning += "Low volatility expected. "
        }

        if !patterns.isEmpty {
            let patternTypes = patterns.map { $0.patternType.rawValue }.joined(separator: ", ")
            reasoning += "Detected patterns: \(patternTypes)."
        }

        return reasoning
    }
}

// MARK: - Integration Models

public struct EnhancedArbitrageOpportunity {
    public let baseOpportunity: ArbitrageOpportunity
    public let mlConfidence: Double
    public let pricePredictions: [String: PredictionResponse]
    public let detectedPatterns: [String: [DetectedPattern]]
    public let riskScore: Double
    public let recommendedAction: ArbitrageAction

    public init(baseOpportunity: ArbitrageOpportunity, mlConfidence: Double, pricePredictions: [String: PredictionResponse], detectedPatterns: [String: [DetectedPattern]], riskScore: Double, recommendedAction: ArbitrageAction) {
        self.baseOpportunity = baseOpportunity
        self.mlConfidence = mlConfidence
        self.pricePredictions = pricePredictions
        self.detectedPatterns = detectedPatterns
        self.riskScore = riskScore
        self.recommendedAction = recommendedAction
    }
}

public struct MLAllocationRecommendation {
    public let symbol: String
    public let recommendedAllocation: Double
    public let confidence: Double
    public let riskLevel: RiskLevel
    public let reasoning: String
    public let timeHorizon: TimeInterval

    public init(symbol: String, recommendedAllocation: Double, confidence: Double, riskLevel: RiskLevel, reasoning: String, timeHorizon: TimeInterval) {
        self.symbol = symbol
        self.recommendedAllocation = recommendedAllocation
        self.confidence = confidence
        self.riskLevel = riskLevel
        self.reasoning = reasoning
        self.timeHorizon = timeHorizon
    }
}

public enum ArbitrageAction: String, CaseIterable {
    case execute = "EXECUTE"
    case monitor = "MONITOR"
    case avoid = "AVOID"
}

public enum RiskLevel: String, CaseIterable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
}

// MARK: - Mock ArbitrageOpportunity for compilation

public struct ArbitrageOpportunity {
    public let baseSymbol: String?
    public let quoteSymbol: String?
    public let intermediateSymbol: String?
    public let profitPercentage: Double
    public let timestamp: Date

    public init(baseSymbol: String?, quoteSymbol: String?, intermediateSymbol: String?, profitPercentage: Double, timestamp: Date) {
        self.baseSymbol = baseSymbol
        self.quoteSymbol = quoteSymbol
        self.intermediateSymbol = intermediateSymbol
        self.profitPercentage = profitPercentage
        self.timestamp = timestamp
    }
}

// MARK: - Mock Types for Compilation

public class MetricsCollector {
    public init() {}

    public func recordPredictionLatency(_ latency: TimeInterval, modelType: String) {}
    public func recordPredictionAccuracy(_ accuracy: Double, modelType: String) {}
    public func recordPredictionConfidence(_ confidence: Double, modelType: String) {}
    public func recordPredictionCount(modelType: String) {}
    public func recordLowConfidencePrediction(modelType: String) {}
    public func recordPatternDetectionLatency(_ latency: TimeInterval, patternType: String) {}
    public func recordPatternCount(patternType: String) {}
    public func recordPatternConfidence(_ confidence: Double, patternType: String) {}
    public func recordAPIRequest(endpoint: String, statusCode: Int, latency: TimeInterval) {}
    public func recordAPIError(endpoint: String, errorType: String) {}
    public func recordWebSocketConnection() {}
    public func recordWebSocketDisconnection() {}
    public func recordWebSocketMessage(type: String) {}
    public func recordCacheHit() {}
    public func recordCacheMiss() {}
    public func recordCacheSize(_ size: Int) {}
    public func recordModelDeployment(modelId: String, modelType: String) {}
    public func recordModelAccuracy(_ accuracy: Double, modelId: String) {}
    public func recordModelDrift(_ driftScore: Double, modelId: String) {}
    public func recordMemoryUsage(_ usage: Int64) {}
    public func recordCPUUsage(_ usage: Double) {}
    public func recordActiveConnections(_ count: Int) {}
    public func recordDataQualityScore(_ score: Double, source: String) {}
    public func recordDataQualityIssue(issueType: String, source: String) {}

    public func getMetricsSummary() -> MetricsSummary {
        return MetricsSummary()
    }
}
