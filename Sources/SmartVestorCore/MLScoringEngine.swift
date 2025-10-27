import Foundation
import Utils
import MLPatternEngine

public protocol MLScoringEngineProtocol {
    func scoreAllCoins() async throws -> [CoinScore]
    func scoreCoin(symbol: String) async throws -> CoinScore
}

private struct CachedScore: Codable {
    let coinScore: CoinScore
    let timestamp: TimeInterval
}

public class MLScoringEngine: MLScoringEngineProtocol, @unchecked Sendable {
    private let mlEngine: MLPatternEngine
    private let logger: StructuredLogger
    private let supportedSymbols: [String]
    private let cacheTTL: TimeInterval = 300
    private var cache: [String: (score: CoinScore, timestamp: Date)] = [:]
    private let cacheURL: URL

    public init(
        mlEngine: MLPatternEngine,
        logger: StructuredLogger
    ) {
        self.mlEngine = mlEngine
        self.logger = logger
        self.supportedSymbols = [
            "BTC", "ETH", "ADA", "DOT", "LINK", "UNI", "AAVE", "COMP", "MKR", "SNX",
            "SOL", "AVAX", "MATIC", "ARB", "OP", "ATOM", "NEAR", "FTM", "ALGO", "ICP",
            "DOGE", "SHIB", "PEPE", "FLOKI", "BONK", "WIF", "BOME", "POPCAT", "MEW", "MYRO",
            "AXS", "SAND", "MANA", "GALA", "ENJ", "LOOKS", "RARE", "APE", "GRT", "BAND",
            "API3", "XMR", "ZEC", "DASH", "FET", "AGIX", "OCEAN", "FIL", "AR", "SC"
        ]

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheURL = cacheDir.appendingPathComponent("SmartVestor/scores_cache.json")

        loadCache()
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode([String: CachedScore].self, from: data) else {
            return
        }

        let now = Date()
        for (symbol, cachedScore) in cached {
            let age = now.timeIntervalSince1970 - cachedScore.timestamp
            if age < cacheTTL {
                cache[symbol] = (cachedScore.coinScore, Date(timeIntervalSince1970: cachedScore.timestamp))
            }
        }

        logger.debug(component: "MLScoringEngine", event: "Loaded cache", data: ["count": String(cache.count)])
    }

    private func saveCache() {
        let toSave = cache.mapValues { CachedScore(coinScore: $0.score, timestamp: $0.timestamp.timeIntervalSince1970) }

        guard let data = try? JSONEncoder().encode(toSave) else { return }

        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL)
    }

    public func scoreAllCoins() async throws -> [CoinScore] {
        logger.info(component: "MLScoringEngine", event: "Starting ML-based scoring for all coins")
        let startTime = Date()

        let symbolsWithUSD = supportedSymbols.map { "\($0)-USD" }

        _ = try await mlEngine.getLatestData(symbols: symbolsWithUSD)

        var coinScores = try await withThrowingTaskGroup(of: CoinScore?.self) { group in
            var results: [CoinScore] = []

            for symbol in supportedSymbols {
                group.addTask { [symbol] in
                    do {
                        return try await self.scoreCoin(symbol: symbol)
                    } catch {
                        self.logger.warn(component: "MLScoringEngine", event: "Failed to score coin with ML, continuing", data: [
                            "symbol": symbol,
                            "error": error.localizedDescription
                        ])
                        return nil
                    }
                }
            }

            for try await result in group {
                if let score = result {
                    results.append(score)
                }
            }

            return results
        }

        coinScores.sort { $0.totalScore > $1.totalScore }

        let duration = Date().timeIntervalSince(startTime)
        logger.info(component: "MLScoringEngine", event: "ML scoring completed", data: [
            "total_coins": String(coinScores.count),
            "duration_seconds": String(duration),
            "average_duration_per_coin": String(duration / Double(coinScores.count))
        ])

        saveCache()

        return coinScores
    }

    public func scoreCoin(symbol: String) async throws -> CoinScore {
        if let cached = cache[symbol], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            logger.debug(component: "MLScoringEngine", event: "Using cached result", data: ["symbol": symbol])
            return cached.score
        }

        logger.info(component: "MLScoringEngine", event: "Scoring coin with ML", data: ["symbol": symbol])

        let symbolWithUSD = "\(symbol)-USD"

        let pricePrediction = try await mlEngine.getPrediction(
            for: symbolWithUSD,
            timeHorizon: 3600,
            modelType: .pricePrediction
        )

        let volatilityPrediction = try await mlEngine.getPrediction(
            for: symbolWithUSD,
            timeHorizon: 3600,
            modelType: .volatilityPrediction
        )

        let patterns = try await mlEngine.detectPatterns(for: symbolWithUSD)

        let historicalDataPoints = try await mlEngine.getLatestData(symbols: [symbolWithUSD])
        let features = try await mlEngine.extractFeatures(
            for: symbolWithUSD,
            historicalData: historicalDataPoints
        )

        let (marketCap, volume24h, priceChange24h, priceChange7d, priceChange30d) = extractRealMarketData(historicalDataPoints: historicalDataPoints, baseSymbol: symbol)

        let mlScore = calculateMLScore(
            priceConfidence: pricePrediction.confidence,
            volatility: volatilityPrediction.prediction,
            patterns: patterns,
            features: features
        )

        let riskLevel = determineRiskLevel(
            volatility: volatilityPrediction.prediction,
            confidence: pricePrediction.confidence,
            patterns: patterns
        )

        let category = getCategoryForSymbol(symbol)

        let coinScore = CoinScore(
            symbol: symbol,
            totalScore: mlScore,
            technicalScore: calculateTechnicalScore(patterns: patterns, features: features),
            fundamentalScore: calculateFundamentalScore(symbol: symbol),
            momentumScore: pricePrediction.prediction > 0 ? 0.5 : 0.0,
            volatilityScore: volatilityPrediction.prediction,
            liquidityScore: 0.7,
            category: category,
            riskLevel: riskLevel,
            marketCap: marketCap,
            volume24h: volume24h,
            priceChange24h: priceChange24h,
            priceChange7d: priceChange7d,
            priceChange30d: priceChange30d
        )

        logger.info(component: "MLScoringEngine", event: "Coin scored with ML", data: [
            "symbol": symbol,
            "ml_score": String(mlScore),
            "confidence": String(pricePrediction.confidence)
        ])

        cache[symbol] = (coinScore, Date())

        return coinScore
    }

    private func calculateMLScore(
        priceConfidence: Double,
        volatility: Double,
        patterns: [DetectedPattern],
        features: FeatureSet
    ) -> Double {
        var score = priceConfidence * 0.4

        let inverseVolatility = 1.0 - min(1.0, volatility)
        score += inverseVolatility * 0.3

        for pattern in patterns {
            let patternName = pattern.patternType.rawValue
            if patternName.contains("bull") || patternName.contains("ascending") {
                score += 0.05
            } else if patternName.contains("bear") || patternName.contains("descending") {
                score -= 0.05
            }
        }

        if let rsi = features.features["rsi"] {
            if rsi < 30 {
                score += 0.05
            } else if rsi > 70 {
                score -= 0.05
            }
        }

        if let macd = features.features["macd"] {
            if macd > 0 {
                score += 0.05
            } else {
                score -= 0.05
            }
        }

        return max(0.0, min(1.0, score))
    }

    private func calculateTechnicalScore(patterns: [DetectedPattern], features: FeatureSet) -> Double {
        var score = 0.5

        var bullishCount = 0
        var bearishCount = 0

        for pattern in patterns {
            let patternName = pattern.patternType.rawValue
            if patternName.contains("bull") || patternName.contains("ascending") || patternName.contains("cup") {
                bullishCount += 1
            } else if patternName.contains("bear") || patternName.contains("descending") || patternName.contains("head") {
                bearishCount += 1
            }
        }

        score += Double(bullishCount) * 0.1
        score -= Double(bearishCount) * 0.1

        return max(0.0, min(1.0, score))
    }

    private func calculateFundamentalScore(symbol: String) -> Double {
        let majorCoins = ["BTC", "ETH", "SOL", "ADA", "DOT"]
        let highVolumeCoins = ["BTC", "ETH", "BNB", "USDT", "SOL"]

        var score = 0.5

        if majorCoins.contains(symbol) {
            score += 0.3
        }

        if highVolumeCoins.contains(symbol) {
            score += 0.2
        }

        return max(0.0, min(1.0, score))
    }

    private func determineRiskLevel(volatility: Double, confidence: Double, patterns: [DetectedPattern]) -> RiskLevel {
        let riskScore = volatility + (1.0 - confidence)

        if riskScore < 0.4 {
            return .low
        } else if riskScore < 0.7 {
            return .medium
        } else {
            return .high
        }
    }

    private func getCategoryForSymbol(_ symbol: String) -> CoinCategory {
        let layer1Coins = ["BTC", "ETH", "ADA", "DOT", "SOL", "AVAX", "ATOM", "NEAR"]
        let defiCoins = ["UNI", "AAVE", "COMP", "MKR", "SNX", "CRV", "1INCH"]
        let gamingCoins = ["AXS", "SAND", "MANA", "GALA", "ENJ"]
        let memeCoins = ["DOGE", "SHIB", "PEPE", "FLOKI", "BONK", "WIF", "BOME"]

        if layer1Coins.contains(symbol) { return .layer1 }
        if defiCoins.contains(symbol) { return .defi }
        if gamingCoins.contains(symbol) { return .gaming }
        if memeCoins.contains(symbol) { return .meme }

        return .infrastructure
    }

    private func extractRealMarketData(historicalDataPoints: Any, baseSymbol: String) -> (marketCap: Double, volume24h: Double, priceChange24h: Double, priceChange7d: Double, priceChange30d: Double) {
        guard let array = historicalDataPoints as? [Any] else {
            logger.debug(component: "MLScoringEngine", event: "Failed to cast to array", data: ["baseSymbol": baseSymbol])
            return (1_000_000_000, 10_000_000, 0.0, 0.0, 0.0)
        }

        logger.debug(component: "MLScoringEngine", event: "Extracting market data", data: ["arrayCount": String(array.count), "baseSymbol": baseSymbol])

        var closes: [Double] = []
        var volumes: [Double] = []

        for item in array {
            let mirror = Mirror(reflecting: item)
            for child in mirror.children {
                if child.label == "close", let val = child.value as? Double {
                    closes.append(val)
                }
                if child.label == "volume", let val = child.value as? Double {
                    volumes.append(val)
                }
            }
        }

        guard closes.count >= 2 else {
            return (1_000_000_000, 10_000_000, 0.0, 0.0, 0.0)
        }

        let latestClose = closes.last!
        let previous24h = closes.count > 24 ? closes[closes.count - 25] : closes[0]
        let previous7d = closes.count > 168 ? closes[closes.count - 169] : closes[0]
        let previous30d = closes[0]

        let priceChange24h = (latestClose - previous24h) / previous24h
        let priceChange7d = (latestClose - previous7d) / previous7d
        let priceChange30d = (latestClose - previous30d) / previous30d

        let avgVolume24h = volumes.isEmpty ? 10_000_000 : (volumes.reduce(0, +) / Double(volumes.count))
        let circulatingSupply = getCirculatingSupply(symbol: baseSymbol)
        let estimatedMarketCap = latestClose * circulatingSupply

        logger.debug(component: "MLScoringEngine", event: "Extracted market data", data: [
            "marketCap": String(estimatedMarketCap),
            "volume24h": String(avgVolume24h),
            "priceChange24h": String(priceChange24h),
            "baseSymbol": baseSymbol
        ])

        return (
            marketCap: estimatedMarketCap,
            volume24h: avgVolume24h,
            priceChange24h: priceChange24h,
            priceChange7d: priceChange7d,
            priceChange30d: priceChange30d
        )
    }

    private func getCirculatingSupply(symbol: String) -> Double {
        let supplies: [String: Double] = [
            "BTC": 21_000_000, "ETH": 120_000_000, "ADA": 45_000_000_000,
            "DOT": 1_000_000_000, "LINK": 1_000_000_000, "SOL": 500_000_000,
            "AVAX": 720_000_000, "MATIC": 10_000_000_000, "DOGE": 145_000_000_000,
            "SHIB": 589_000_000_000_000_000, "FIL": 2_000_000_000, "AR": 50_000_000,
            "SC": 55_000_000_000_000, "ATOM": 350_000_000, "NEAR": 1_000_000_000,
            "FTM": 3_175_000_000, "ALGO": 8_000_000_000
        ]
        return supplies[symbol] ?? 1_000_000_000
    }

}
