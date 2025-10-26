import Foundation
import Utils
import Core
import MLPatternEngine

public class IntegrationOrchestrator {
    private let mlEngine: MLPatternEngine
    private let arbitrageIntegration: ArbitrageIntegration
    private let smartVestorIntegration: SmartVestorIntegration
    private let logger: StructuredLogger
    private let metricsCollector: MetricsCollector
    private let alertingSystem: AlertingSystem

    public init(
        mlEngine: MLPatternEngine,
        arbitrageDetector: TriangularArbitrageDetector,
        logger: StructuredLogger,
        metricsCollector: MetricsCollector,
        alertingSystem: AlertingSystem
    ) {
        self.mlEngine = mlEngine
        self.arbitrageIntegration = ArbitrageIntegration(
            mlEngine: mlEngine,
            arbitrageDetector: arbitrageDetector,
            logger: logger,
            metricsCollector: metricsCollector
        )
        self.smartVestorIntegration = SmartVestorIntegration(
            mlEngine: mlEngine,
            logger: logger,
            metricsCollector: metricsCollector
        )
        self.logger = logger
        self.metricsCollector = metricsCollector
        self.alertingSystem = alertingSystem
    }

    // MARK: - Unified Trading Strategy

    public func generateUnifiedTradingStrategy() async throws -> UnifiedTradingStrategy {
        let startTime = Date()

        logger.info(component: "IntegrationOrchestrator", event: "Generating unified trading strategy")

        // Get arbitrage opportunities
        let arbitrageOpportunities = try await arbitrageIntegration.detectArbitrageOpportunities()

        // Get portfolio recommendations
        let portfolioRecommendation = try await smartVestorIntegration.generatePortfolioRecommendations()

        // Get risk assessment
        let riskAssessment = try await smartVestorIntegration.assessPortfolioRisk(portfolio: portfolioRecommendation.allocation)

        // Generate unified strategy
        let strategy = UnifiedTradingStrategy(
            timestamp: Date(),
            arbitrageOpportunities: arbitrageOpportunities,
            portfolioRecommendation: portfolioRecommendation,
            riskAssessment: riskAssessment,
            recommendedActions: generateRecommendedActions(
                arbitrageOpportunities: arbitrageOpportunities,
                portfolioRecommendation: portfolioRecommendation,
                riskAssessment: riskAssessment
            ),
            confidence: calculateOverallConfidence(
                arbitrageOpportunities: arbitrageOpportunities,
                portfolioRecommendation: portfolioRecommendation
            )
        )

        let latency = Date().timeIntervalSince(startTime)
        metricsCollector.recordPredictionLatency(latency, modelType: "unified_strategy")

        logger.info(component: "IntegrationOrchestrator", event: "Unified trading strategy generated", data: [
            "arbitrage_opportunities": "\(arbitrageOpportunities.count)",
            "confidence": "\(strategy.confidence)",
            "latency_ms": "\(latency * 1000)"
        ])

        return strategy
    }

    // MARK: - Real-time Market Analysis

    public func performRealTimeAnalysis() async throws -> RealTimeAnalysis {
        let startTime = Date()

        // Get current market data
        let symbols = ["BTC-USD", "ETH-USD", "BNB-USD", "ADA-USD", "SOL-USD"]
        let marketData = try await mlEngine.getLatestData(symbols: symbols)

        var analysisResults: [String: SymbolAnalysis] = [:]

        for symbol in symbols {
            // Get predictions
            let pricePrediction = try await mlEngine.getPrediction(
                for: symbol,
                timeHorizon: 300, // 5 minutes
                modelType: .pricePrediction
            )

            let volatilityPrediction = try await mlEngine.getPrediction(
                for: symbol,
                timeHorizon: 300,
                modelType: .volatilityPrediction
            )

            // Detect patterns
            let patterns = try await mlEngine.detectPatterns(for: symbol)

            // Extract features
            let features = try await mlEngine.extractFeatures(for: symbol, historicalData: marketData)

            let analysis = SymbolAnalysis(
                symbol: symbol,
                pricePrediction: pricePrediction,
                volatilityPrediction: volatilityPrediction,
                patterns: patterns,
                features: features,
                marketSentiment: calculateMarketSentiment(patterns: patterns, features: features),
                tradingSignal: generateTradingSignal(
                    pricePrediction: pricePrediction,
                    volatilityPrediction: volatilityPrediction,
                    patterns: patterns
                )
            )

            analysisResults[symbol] = analysis
        }

        // Calculate market-wide metrics
        let marketMetrics = calculateMarketMetrics(analysisResults: analysisResults)

        let analysis = RealTimeAnalysis(
            timestamp: Date(),
            symbolAnalysis: analysisResults,
            marketMetrics: marketMetrics,
            overallSentiment: calculateOverallSentiment(analysisResults: analysisResults),
            riskLevel: calculateOverallRiskLevel(analysisResults: analysisResults)
        )

        let latency = Date().timeIntervalSince(startTime)
        metricsCollector.recordPredictionLatency(latency, modelType: "realtime_analysis")

        logger.info(component: "IntegrationOrchestrator", event: "Real-time analysis completed", data: [
            "symbols_analyzed": "\(symbols.count)",
            "overall_sentiment": "\(analysis.overallSentiment.rawValue)",
            "latency_ms": "\(latency * 1000)"
        ])

        return analysis
    }

    // MARK: - Performance Monitoring

    public func monitorPerformance() async throws -> PerformanceReport {
        let startTime = Date()

        // Get metrics summary
        let metricsSummary = metricsCollector.getMetricsSummary()

        // Get active alerts
        let activeAlerts = alertingSystem.getActiveAlerts()

        // Calculate performance metrics
        let performanceMetrics = PerformanceMetrics(
            predictionLatencyP95: metricsSummary.predictionLatencyP95,
            averageAccuracy: metricsSummary.averageAccuracy,
            cacheHitRate: metricsSummary.cacheHitRate,
            totalRequests: metricsSummary.totalAPIRequests,
            errorRate: calculateErrorRate(metricsSummary: metricsSummary),
            uptime: calculateUptime(),
            activeAlerts: activeAlerts.count
        )

        // Generate recommendations
        let recommendations = generatePerformanceRecommendations(metrics: performanceMetrics, alerts: activeAlerts)

        let report = PerformanceReport(
            timestamp: Date(),
            metrics: performanceMetrics,
            recommendations: recommendations,
            healthStatus: determineHealthStatus(metrics: performanceMetrics, alerts: activeAlerts)
        )

        let latency = Date().timeIntervalSince(startTime)
        metricsCollector.recordPredictionLatency(latency, modelType: "performance_monitoring")

        logger.info(component: "IntegrationOrchestrator", event: "Performance monitoring completed", data: [
            "prediction_latency_p95": "\(performanceMetrics.predictionLatencyP95)",
            "cache_hit_rate": "\(performanceMetrics.cacheHitRate)",
            "active_alerts": "\(activeAlerts.count)"
        ])

        return report
    }

    // MARK: - Private Helper Methods

    private func generateRecommendedActions(
        arbitrageOpportunities: [EnhancedArbitrageOpportunity],
        portfolioRecommendation: MLPortfolioRecommendation,
        riskAssessment: RiskAssessment
    ) -> [RecommendedAction] {
        var actions: [RecommendedAction] = []

        // High-confidence arbitrage opportunities
        let highConfidenceArbitrage = arbitrageOpportunities.filter { $0.mlConfidence > 0.8 && $0.riskScore < 0.3 }
        if !highConfidenceArbitrage.isEmpty {
            actions.append(RecommendedAction(
                type: .executeArbitrage,
                priority: .high,
                description: "Execute \(highConfidenceArbitrage.count) high-confidence arbitrage opportunities",
                estimatedProfit: highConfidenceArbitrage.reduce(0.0) { $0 + $1.baseOpportunity.profitPercentage },
                confidence: highConfidenceArbitrage.map { $0.mlConfidence }.reduce(0, +) / Double(highConfidenceArbitrage.count)
            ))
        }

        // Portfolio rebalancing
        if portfolioRecommendation.rebalanceRecommendation == .rebalance {
            actions.append(RecommendedAction(
                type: .rebalancePortfolio,
                priority: .medium,
                description: "Rebalance portfolio based on ML recommendations",
                estimatedProfit: portfolioRecommendation.expectedReturn,
                confidence: portfolioRecommendation.confidence
            ))
        }

        // Risk management
        if riskAssessment.riskLevel == .high {
            actions.append(RecommendedAction(
                type: .reduceRisk,
                priority: .high,
                description: "Reduce portfolio risk - high risk level detected",
                estimatedProfit: 0.0,
                confidence: 0.9
            ))
        }

        return actions
    }

    private func calculateOverallConfidence(
        arbitrageOpportunities: [EnhancedArbitrageOpportunity],
        portfolioRecommendation: MLPortfolioRecommendation
    ) -> Double {
        let arbitrageConfidence = arbitrageOpportunities.isEmpty ? 0.0 :
            arbitrageOpportunities.map { $0.mlConfidence }.reduce(0, +) / Double(arbitrageOpportunities.count)

        return (arbitrageConfidence + portfolioRecommendation.confidence) / 2.0
    }

    private func calculateMarketSentiment(patterns: [DetectedPattern], features: FeatureSet) -> MarketSentiment {
        var bullishSignals = 0
        var bearishSignals = 0

        // Analyze patterns
        for pattern in patterns {
            switch pattern.patternType {
            case .triangle, .flag:
                bullishSignals += 1
            case .headAndShoulders:
                bearishSignals += 1
            default:
                break
            }
        }

        // Analyze RSI
        if let rsi = features.features["rsi"] {
            if rsi < 30 {
                bullishSignals += 1
            } else if rsi > 70 {
                bearishSignals += 1
            }
        }

        if bullishSignals > bearishSignals + 1 {
            return .bullish
        } else if bearishSignals > bullishSignals + 1 {
            return .bearish
        } else {
            return .neutral
        }
    }

    private func generateTradingSignal(
        pricePrediction: PredictionResponse,
        volatilityPrediction: PredictionResponse,
        patterns: [DetectedPattern]
    ) -> TradingSignal {
        var signalType = TradingSignal.SignalType.hold
        var confidence = 0.5

        // Price prediction signal
        if pricePrediction.confidence > 0.7 {
            if pricePrediction.prediction > 0.02 { // 2% increase
                signalType = .buy
                confidence = pricePrediction.confidence
            } else if pricePrediction.prediction < -0.02 { // 2% decrease
                signalType = .sell
                confidence = pricePrediction.confidence
            }
        }

        // Pattern confirmation
        for pattern in patterns {
            if pattern.confidence > 0.7 {
                switch pattern.patternType {
                case .triangle, .flag:
                    if signalType == .buy {
                        confidence = min(confidence + 0.1, 1.0)
                    }
                case .headAndShoulders:
                    if signalType == .sell {
                        confidence = min(confidence + 0.1, 1.0)
                    }
                default:
                    break
                }
            }
        }

        return TradingSignal(
            timestamp: Date(),
            symbol: "", // Will be set by caller
            signalType: signalType,
            confidence: confidence,
            priceTarget: pricePrediction.prediction > 0 ? pricePrediction.prediction : nil,
            stopLoss: volatilityPrediction.prediction > 0.5 ? -volatilityPrediction.prediction : nil,
            timeHorizon: 300 // 5 minutes
        )
    }

    private func calculateMarketMetrics(analysisResults: [String: SymbolAnalysis]) -> MarketMetrics {
        let totalSymbols = analysisResults.count
        var bullishCount = 0
        var bearishCount = 0
        var totalVolatility = 0.0
        var totalConfidence = 0.0

        for analysis in analysisResults.values {
            switch analysis.marketSentiment {
            case .bullish:
                bullishCount += 1
            case .bearish:
                bearishCount += 1
            case .neutral:
                break
            }

            totalVolatility += analysis.volatilityPrediction.prediction
            totalConfidence += analysis.pricePrediction.confidence
        }

        return MarketMetrics(
            bullishRatio: Double(bullishCount) / Double(totalSymbols),
            bearishRatio: Double(bearishCount) / Double(totalSymbols),
            averageVolatility: totalVolatility / Double(totalSymbols),
            averageConfidence: totalConfidence / Double(totalSymbols)
        )
    }

    private func calculateOverallSentiment(analysisResults: [String: SymbolAnalysis]) -> MarketSentiment {
        let bullishCount = analysisResults.values.filter { $0.marketSentiment == .bullish }.count
        let bearishCount = analysisResults.values.filter { $0.marketSentiment == .bearish }.count

        if bullishCount > bearishCount + 1 {
            return .bullish
        } else if bearishCount > bullishCount + 1 {
            return .bearish
        } else {
            return .neutral
        }
    }

    private func calculateOverallRiskLevel(analysisResults: [String: SymbolAnalysis]) -> RiskLevel {
        let highRiskCount = analysisResults.values.filter { $0.volatilityPrediction.prediction > 0.7 }.count
        let totalCount = analysisResults.count

        if Double(highRiskCount) / Double(totalCount) > 0.6 {
            return .high
        } else if Double(highRiskCount) / Double(totalCount) > 0.3 {
            return .medium
        } else {
            return .low
        }
    }

    private func calculateErrorRate(metricsSummary: MetricsSummary) -> Double {
        // Simplified error rate calculation
        return 0.01 // 1% placeholder
    }

    private func calculateUptime() -> Double {
        // Simplified uptime calculation
        return 0.999 // 99.9% placeholder
    }

    private func generatePerformanceRecommendations(metrics: PerformanceMetrics, alerts: [Alert]) -> [String] {
        var recommendations: [String] = []

        if metrics.predictionLatencyP95 > 0.1 {
            recommendations.append("Prediction latency is high - consider optimizing models or increasing resources")
        }

        if metrics.cacheHitRate < 0.8 {
            recommendations.append("Cache hit rate is low - consider adjusting cache strategy")
        }

        if metrics.errorRate > 0.05 {
            recommendations.append("Error rate is elevated - investigate and fix issues")
        }

        if alerts.count > 5 {
            recommendations.append("High number of active alerts - review system health")
        }

        return recommendations
    }

    private func determineHealthStatus(metrics: PerformanceMetrics, alerts: [Alert]) -> HealthStatus {
        let criticalAlerts = alerts.filter { $0.severity == .critical }.count

        if criticalAlerts > 0 || metrics.errorRate > 0.1 {
            return .critical
        } else if alerts.count > 3 || metrics.predictionLatencyP95 > 0.2 {
            return .warning
        } else {
            return .healthy
        }
    }
}

// MARK: - Integration Models

public struct UnifiedTradingStrategy {
    public let timestamp: Date
    public let arbitrageOpportunities: [EnhancedArbitrageOpportunity]
    public let portfolioRecommendation: MLPortfolioRecommendation
    public let riskAssessment: RiskAssessment
    public let recommendedActions: [RecommendedAction]
    public let confidence: Double

    public init(timestamp: Date, arbitrageOpportunities: [EnhancedArbitrageOpportunity], portfolioRecommendation: MLPortfolioRecommendation, riskAssessment: RiskAssessment, recommendedActions: [RecommendedAction], confidence: Double) {
        self.timestamp = timestamp
        self.arbitrageOpportunities = arbitrageOpportunities
        self.portfolioRecommendation = portfolioRecommendation
        self.riskAssessment = riskAssessment
        self.recommendedActions = recommendedActions
        self.confidence = confidence
    }
}

public struct RealTimeAnalysis {
    public let timestamp: Date
    public let symbolAnalysis: [String: SymbolAnalysis]
    public let marketMetrics: MarketMetrics
    public let overallSentiment: MarketSentiment
    public let riskLevel: RiskLevel

    public init(timestamp: Date, symbolAnalysis: [String: SymbolAnalysis], marketMetrics: MarketMetrics, overallSentiment: MarketSentiment, riskLevel: RiskLevel) {
        self.timestamp = timestamp
        self.symbolAnalysis = symbolAnalysis
        self.marketMetrics = marketMetrics
        self.overallSentiment = overallSentiment
        self.riskLevel = riskLevel
    }
}

public struct SymbolAnalysis {
    public let symbol: String
    public let pricePrediction: PredictionResponse
    public let volatilityPrediction: PredictionResponse
    public let patterns: [DetectedPattern]
    public let features: FeatureSet
    public let marketSentiment: MarketSentiment
    public let tradingSignal: TradingSignal

    public init(symbol: String, pricePrediction: PredictionResponse, volatilityPrediction: PredictionResponse, patterns: [DetectedPattern], features: FeatureSet, marketSentiment: MarketSentiment, tradingSignal: TradingSignal) {
        self.symbol = symbol
        self.pricePrediction = pricePrediction
        self.volatilityPrediction = volatilityPrediction
        self.patterns = patterns
        self.features = features
        self.marketSentiment = marketSentiment
        self.tradingSignal = tradingSignal
    }
}

public struct MarketMetrics {
    public let bullishRatio: Double
    public let bearishRatio: Double
    public let averageVolatility: Double
    public let averageConfidence: Double

    public init(bullishRatio: Double, bearishRatio: Double, averageVolatility: Double, averageConfidence: Double) {
        self.bullishRatio = bullishRatio
        self.bearishRatio = bearishRatio
        self.averageVolatility = averageVolatility
        self.averageConfidence = averageConfidence
    }
}

public enum MarketSentiment: String, CaseIterable {
    case bullish = "BULLISH"
    case bearish = "BEARISH"
    case neutral = "NEUTRAL"
}

public struct PerformanceReport {
    public let timestamp: Date
    public let metrics: PerformanceMetrics
    public let recommendations: [String]
    public let healthStatus: HealthStatus

    public init(timestamp: Date, metrics: PerformanceMetrics, recommendations: [String], healthStatus: HealthStatus) {
        self.timestamp = timestamp
        self.metrics = metrics
        self.recommendations = recommendations
        self.healthStatus = healthStatus
    }
}

public struct PerformanceMetrics {
    public let predictionLatencyP95: Double
    public let averageAccuracy: Double
    public let cacheHitRate: Double
    public let totalRequests: Int
    public let errorRate: Double
    public let uptime: Double
    public let activeAlerts: Int

    public init(predictionLatencyP95: Double, averageAccuracy: Double, cacheHitRate: Double, totalRequests: Int, errorRate: Double, uptime: Double, activeAlerts: Int) {
        self.predictionLatencyP95 = predictionLatencyP95
        self.averageAccuracy = averageAccuracy
        self.cacheHitRate = cacheHitRate
        self.totalRequests = totalRequests
        self.errorRate = errorRate
        self.uptime = uptime
        self.activeAlerts = activeAlerts
    }
}

public enum HealthStatus: String, CaseIterable {
    case healthy = "HEALTHY"
    case warning = "WARNING"
    case critical = "CRITICAL"
}

public struct RecommendedAction {
    public let type: ActionType
    public let priority: ActionPriority
    public let description: String
    public let estimatedProfit: Double
    public let confidence: Double

    public init(type: ActionType, priority: ActionPriority, description: String, estimatedProfit: Double, confidence: Double) {
        self.type = type
        self.priority = priority
        self.description = description
        self.estimatedProfit = estimatedProfit
        self.confidence = confidence
    }
}

public enum ActionType: String, CaseIterable {
    case executeArbitrage = "EXECUTE_ARBITRAGE"
    case rebalancePortfolio = "REBALANCE_PORTFOLIO"
    case reduceRisk = "REDUCE_RISK"
    case increaseExposure = "INCREASE_EXPOSURE"
    case hold = "HOLD"
}

public enum ActionPriority: String, CaseIterable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case critical = "CRITICAL"
}

// MARK: - Mock Types for Compilation

public class AlertingSystem {
    public init() {}

    public func getActiveAlerts() -> [Alert] { return [] }
}

public class Alert {
    public let severity: AlertSeverity

    public init(severity: AlertSeverity) {
        self.severity = severity
    }
}

public enum AlertSeverity: String, CaseIterable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case critical = "CRITICAL"
}

public struct MetricsSummary {
    public let predictionLatencyP95: Double
    public let averageAccuracy: Double
    public let cacheHitRate: Double
    public let totalAPIRequests: Int
    public let cacheHits: Int
    public let cacheMisses: Int

    public init() {
        self.predictionLatencyP95 = 0.0
        self.averageAccuracy = 0.0
        self.cacheHitRate = 0.0
        self.totalAPIRequests = 0
        self.cacheHits = 0
        self.cacheMisses = 0
    }
}
