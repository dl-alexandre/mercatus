import Foundation
import Utils
import MLPatternEngine
#if canImport(MLX)
import MLX
#endif

public protocol MLScoringEngineProtocol {
    func scoreAllCoins() async throws -> [CoinScore]
    func scoreCoin(symbol: String) async throws -> CoinScore
}

public enum MLScoringError: Error, LocalizedError {
    case invalidPrediction(String)
    case insufficientData(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPrediction(let message):
            return "Invalid prediction: \(message)"
        case .insufficientData(let message):
            return "Insufficient data: \(message)"
        }
    }
}

private struct CachedScore: Codable {
    let coinScore: CoinScore
    let timestamp: TimeInterval
}

public class MLScoringEngine: MLScoringEngineProtocol, @unchecked Sendable {
    private let mlEngine: MLPatternEngine
    private let logger: StructuredLogger
    private var cachedSupportedSymbols: [String]? = nil
    private let cacheTTL: TimeInterval = 300
    private var cache: [String: (score: CoinScore, timestamp: Date)] = [:]
    private let cacheQueue = DispatchQueue(label: "MLScoringEngine.cache", attributes: .concurrent)
    private let cacheURL: URL

    public init(
        mlEngine: MLPatternEngine,
        logger: StructuredLogger
    ) {
        self.mlEngine = mlEngine
        self.logger = logger
        self.cachedSupportedSymbols = nil

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
        cacheQueue.sync(flags: .barrier) {
            for (symbol, cachedScore) in cached {
                let age = now.timeIntervalSince1970 - cachedScore.timestamp
                if age < cacheTTL {
                    self.cache[symbol] = (cachedScore.coinScore, Date(timeIntervalSince1970: cachedScore.timestamp))
                }
            }
        }

        let count = cache.count
        logger.debug(component: "MLScoringEngine", event: "Loaded cache", data: ["count": String(count)])
    }

    private func saveCache() {
        let toSave = cacheQueue.sync { cache.mapValues { CachedScore(coinScore: $0.score, timestamp: $0.timestamp.timeIntervalSince1970) } }

        guard let data = try? JSONEncoder().encode(toSave) else { return }

        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL)
    }

    public func scoreAllCoins() async throws -> [CoinScore] {
        logger.info(component: "MLScoringEngine", event: "Starting ML-based scoring for all coins")
        let startTime = Date()

        #if canImport(MLX)
        var coinScores = try await Device.withDefaultDevice(Device.cpu) {
            try await scoreAllCoinsInternal()
        }
        #else
        var coinScores = try await scoreAllCoinsInternal()
        #endif

        coinScores.sort { $0.totalScore > $1.totalScore }

        let duration = Date().timeIntervalSince(startTime)
        logger.info(component: "MLScoringEngine", event: "ML scoring completed", data: [
            "total_coins": String(coinScores.count),
            "duration_seconds": String(duration),
            "average_duration_per_coin": String(duration / Double(max(coinScores.count, 1)))
        ])

        logScoringVerification(coinScores: coinScores)

        saveCache()

        return coinScores
    }

    private func scoreAllCoinsInternal() async throws -> [CoinScore] {
        let supportedSymbols = await getSupportedSymbols()
        logger.info(component: "MLScoringEngine", event: "Got supported symbols", data: [
            "count": String(supportedSymbols.count),
            "symbols": supportedSymbols.prefix(10).joined(separator: ", ")
        ])

        guard !supportedSymbols.isEmpty else {
            logger.warn(component: "MLScoringEngine", event: "No supported symbols found")
            return []
        }

        let symbolsWithUSD = supportedSymbols.map { "\($0)-USD" }

        _ = try await mlEngine.getLatestData(symbols: symbolsWithUSD)

        let coinScores = try await withThrowingTaskGroup(of: CoinScore?.self) { group in
            var results: [CoinScore] = []
            var failedSymbols: [String] = []

            for symbol in supportedSymbols {
                group.addTask { [symbol] in
                    do {
                        return try await self.scoreCoin(symbol: symbol)
                    } catch {
                        self.logger.debug(component: "MLScoringEngine", event: "Skipping coin with insufficient data", data: [
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
                } else {
                    failedSymbols.append("unknown")
                }
            }

            if !failedSymbols.isEmpty {
                self.logger.info(component: "MLScoringEngine", event: "Some coins skipped due to insufficient data", data: [
                    "skipped_count": String(failedSymbols.count),
                    "successful_count": String(results.count)
                ])
            }

            return results
        }

        return coinScores
    }

    private func getSupportedSymbols() async -> [String] {
        if let cached = cachedSupportedSymbols, !cached.isEmpty {
            logger.debug(component: "MLScoringEngine", event: "Using cached symbols", data: ["count": String(cached.count)])
            return cached
        }
        do {
            let apiSymbols = try await RobinhoodInstrumentsAPI.shared.fetchSupportedSymbols(logger: logger)
            if apiSymbols.isEmpty {
                logger.warn(component: "MLScoringEngine", event: "API returned empty symbols, using fallback")
                return getFallbackSymbols()
            }
            cachedSupportedSymbols = apiSymbols
            logger.info(component: "MLScoringEngine", event: "Fetched symbols from API", data: ["count": String(apiSymbols.count)])
            return apiSymbols
        } catch {
            logger.warn(component: "MLScoringEngine", event: "robinhood_api_failed", data: [
                "error": error.localizedDescription,
                "message": "Falling back to static list"
            ])
            return getFallbackSymbols()
        }
    }

    private func getFallbackSymbols() -> [String] {
        let fallback = [
            "AAVE", "ADA", "ARB", "ASTER", "AVAX", "BCH", "BNB", "BONK",
            "BTC", "COMP", "CRV", "DOGE", "ETC", "ETH", "FLOKI", "HBAR",
            "HYPE", "LINK", "LTC", "MEW", "MOODENG", "ONDO", "OP", "PENGU",
            "PEPE", "PNUT", "POPCAT", "SHIB", "SOL", "SUI", "TON", "TRUMP",
            "UNI", "USDC", "XLM", "XPL", "XRP", "XTZ", "WLFI", "WIF",
            "VIRTUAL", "ZORA"
        ]
        cachedSupportedSymbols = fallback
        logger.info(component: "MLScoringEngine", event: "Using fallback symbols", data: ["count": String(fallback.count)])
        return fallback
    }

    public func scoreCoin(symbol: String) async throws -> CoinScore {
        #if canImport(MLX)
        return try await Device.withDefaultDevice(Device.cpu) {
            try await scoreCoinInternal(symbol: symbol)
        }
        #else
        return try await scoreCoinInternal(symbol: symbol)
        #endif
    }

    private func scoreCoinInternal(symbol: String) async throws -> CoinScore {
        if let cached = cacheQueue.sync(execute: { cache[symbol] }), Date().timeIntervalSince(cached.timestamp) < cacheTTL {
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

        guard pricePrediction.prediction.isFinite && !pricePrediction.prediction.isNaN else {
            logger.warn(component: "MLScoringEngine", event: "Invalid price prediction (NaN/Inf)", data: [
                "symbol": symbol,
                "prediction": String(pricePrediction.prediction)
            ])
            throw MLScoringError.invalidPrediction("Price prediction is NaN or Inf")
        }

        let volatilityPrediction = try await mlEngine.getPrediction(
            for: symbolWithUSD,
            timeHorizon: 3600,
            modelType: .volatilityPrediction
        )

        guard volatilityPrediction.prediction.isFinite && !volatilityPrediction.prediction.isNaN else {
            logger.warn(component: "MLScoringEngine", event: "Invalid volatility prediction (NaN/Inf)", data: [
                "symbol": symbol,
                "prediction": String(volatilityPrediction.prediction)
            ])
            throw MLScoringError.invalidPrediction("Volatility prediction is NaN or Inf")
        }

        let patterns = try await mlEngine.detectPatterns(for: symbolWithUSD)

        let historicalDataPoints = try await mlEngine.getLatestData(symbols: [symbolWithUSD])
        let features = try await mlEngine.extractFeatures(
            for: symbolWithUSD,
            historicalData: historicalDataPoints
        )

        let (marketCap, volume24h, priceChange24h, priceChange7d, priceChange30d) = extractRealMarketData(historicalDataPoints: historicalDataPoints, baseSymbol: symbol)

        let volatilityScore = calculateVolatilityScore(volatility: volatilityPrediction.prediction)
        let technicalScore = calculateTechnicalScore(patterns: patterns, features: features)
        let fundamentalScore = calculateFundamentalScore(symbol: symbol)
        let liquidityScore = 0.7

        let currentPrice = getCurrentPrice(from: historicalDataPoints)
        let predictedPrice = pricePrediction.prediction
        let priceChangePercent = currentPrice > 0 ? (predictedPrice - currentPrice) / currentPrice : 0.0

        let priceConfidence = pricePrediction.confidence
        let bullishScore = calculateBullishScore(
            priceChangePercent: priceChangePercent,
            confidence: priceConfidence
        )

        let totalScore = (0.50 * bullishScore) +
                        (0.20 * volatilityScore) +
                        (0.15 * technicalScore) +
                        (0.10 * fundamentalScore) +
                        (0.05 * liquidityScore)

        let riskLevel = determineRiskLevel(
            volatility: volatilityPrediction.prediction,
            confidence: pricePrediction.confidence,
            patterns: patterns
        )

        let category = getCategoryForSymbol(symbol)

        let coinScore = CoinScore(
            symbol: symbol,
            totalScore: totalScore,
            technicalScore: technicalScore,
            fundamentalScore: fundamentalScore,
            momentumScore: bullishScore,
            volatilityScore: volatilityScore,
            liquidityScore: liquidityScore,
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
        "total_score": String(totalScore),
        "confidence": String(priceConfidence),
        "current_price": String(currentPrice),
        "predicted_price": String(predictedPrice),
        "price_change_percent": String(priceChangePercent * 100),
        "bullish_score": String(bullishScore)
        ])

        cacheQueue.sync(flags: .barrier) {
            self.cache[symbol] = (coinScore, Date())
        }

        return coinScore
    }



    private func calculateTechnicalScore(patterns: [DetectedPattern], features: FeatureSet) -> Double {
    var score = 0.6

    // Pattern recognition
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

        // RSI indicator
        if let rsi = features.features["rsi"] {
            if rsi < 30 {
                score += 0.2 // Oversold, bullish
            } else if rsi > 70 {
                score -= 0.2 // Overbought, bearish
            }
        }

        // MACD indicator
        if let macd = features.features["macd"] {
            if macd > 0 {
                score += 0.1 // Bullish signal
            } else {
                score -= 0.1 // Bearish signal
            }
        }

        let fftScore = calculateFFTScore(features: features)
        score += fftScore * 0.25

        return max(0.0, min(1.0, score))
    }

    private func calculateFFTScore(features: FeatureSet) -> Double {
        var fftScore = 0.5

        if let cycleStrength = features.features["fft_cycle_strength"] {
            fftScore += cycleStrength * 0.3
        }

        if let signalToNoise = features.features["fft_signal_to_noise"] {
            let snrScore = min(signalToNoise / 10.0, 0.2)
            fftScore += snrScore
        }

        if let dominantSignificance = features.features["fft_dominant_significance"] {
            fftScore += dominantSignificance * 0.2
        }

        if let dailyCycle = features.features["fft_daily_cycle_strength"], dailyCycle > 0.3 {
            fftScore += 0.15
        }

        if let weeklyCycle = features.features["fft_weekly_cycle_strength"], weeklyCycle > 0.3 {
            fftScore += 0.1
        }

        if let lowPower = features.features["fft_spectral_low_power"] {
            if lowPower > 0.5 {
                fftScore += 0.1
            }
        }

        return max(0.0, min(1.0, fftScore))
    }

    private func calculateVolatilityScore(volatility: Double) -> Double {
        return 1.0 - min(1.0, volatility)
    }

    private func calculateBullishScore(priceChangePercent: Double, confidence: Double) -> Double {
        let maxChange = 0.1
        let normalizedChange = max(-1.0, min(1.0, priceChangePercent / maxChange))
        let directionScore = (normalizedChange + 1.0) / 2.0
        return directionScore * confidence
    }

    private func getCurrentPrice(from historicalDataPoints: Any) -> Double {
        guard let array = historicalDataPoints as? [Any] else {
            return 0.0
        }

        var dataPoints: [(timestamp: Date, close: Double)] = []

        for item in array {
            let mirror = Mirror(reflecting: item)
            var timestamp: Date?
            var close: Double?

            for child in mirror.children {
                if child.label == "timestamp", let val = child.value as? Date {
                    timestamp = val
                } else if child.label == "close", let val = child.value as? Double {
                    close = val
                }
            }

            if let ts = timestamp, let cl = close {
                dataPoints.append((ts, cl))
            }
        }

        guard !dataPoints.isEmpty else {
            return 0.0
        }

        dataPoints.sort { $0.timestamp < $1.timestamp }
        return dataPoints.last?.close ?? 0.0
    }

    private func calculateFundamentalScore(symbol: String) -> Double {
        let majorCoins = ["BTC", "ETH", "SOL", "ADA", "DOT"]
        let highVolumeCoins = ["BTC", "ETH", "BNB", "USDT", "SOL"]
    let blueChipCoins = ["BTC", "ETH"] // Blue-chip assets receive premium

    let category = getCategoryForSymbol(symbol)

        // Base score by category (market strength and adoption)
        var score: Double
        switch category {
        case .layer1:
            score = 0.8
        case .layer2:
            score = 0.75
        case .defi:
            score = 0.7
        case .infrastructure:
            score = 0.6
        case .gaming:
            score = 0.5
        case .nft:
            score = 0.4
        case .meme:
            score = 0.3
        case .ai:
            score = 0.5
        case .storage:
            score = 0.5
        case .privacy:
            score = 0.5
        }

        // Additional bonuses
        if majorCoins.contains(symbol) {
            score += 0.2
        }

        if highVolumeCoins.contains(symbol) {
            score += 0.15
        }

        // Blue-chip premium
        if blueChipCoins.contains(symbol) {
            score += 0.1
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

    var dataPoints: [(timestamp: Date, close: Double, volume: Double)] = []

        for item in array {
        let mirror = Mirror(reflecting: item)
    var timestamp: Date?
    var close: Double?
    var volume: Double?

    for child in mirror.children {
    if child.label == "timestamp", let val = child.value as? Date {
    timestamp = val
    } else if child.label == "close", let val = child.value as? Double {
            close = val
            } else if child.label == "volume", let val = child.value as? Double {
                    volume = val
            }
    }

            if let ts = timestamp, let cl = close, let vol = volume {
            dataPoints.append((ts, cl, vol))
        }
    }

        guard !dataPoints.isEmpty else {
        return (1_000_000_000, 10_000_000, 0.0, 0.0, 0.0)
    }

        // Sort by timestamp ascending
    dataPoints.sort { $0.timestamp < $1.timestamp }

    let now = Date()
        let latestPoint = dataPoints.last!
    let latestClose = latestPoint.close

    // Find closest points to target times
    let findClosestPrice = { (targetTime: TimeInterval) -> Double in
    let targetDate = now.addingTimeInterval(-targetTime)
        var closestPoint = dataPoints[0]
            var minDiff = abs(closestPoint.timestamp.timeIntervalSince(targetDate))

    for point in dataPoints {
        let diff = abs(point.timestamp.timeIntervalSince(targetDate))
        if diff < minDiff {
            minDiff = diff
            closestPoint = point
            }
            }
            return closestPoint.close
        }

        let previous24h = findClosestPrice(24 * 3600) // 24 hours ago
        let previous7d = findClosestPrice(7 * 24 * 3600) // 7 days ago
        let previous30d = findClosestPrice(30 * 24 * 3600) // 30 days ago

        let priceChange24h = previous24h != 0 ? (latestClose - previous24h) / previous24h : 0.0
        let priceChange7d = previous7d != 0 ? (latestClose - previous7d) / previous7d : 0.0
        let priceChange30d = previous30d != 0 ? (latestClose - previous30d) / previous30d : 0.0

        let avgVolume24h = dataPoints.map { $0.volume }.reduce(0, +) / Double(dataPoints.count)
        let circulatingSupply = getCirculatingSupply(symbol: baseSymbol)
        let estimatedMarketCap = latestClose * circulatingSupply

        logger.debug(component: "MLScoringEngine", event: "Extracted market data", data: [
            "marketCap": String(estimatedMarketCap),
            "volume24h": String(avgVolume24h),
            "priceChange24h": String(priceChange24h),
            "priceChange7d": String(priceChange7d),
            "priceChange30d": String(priceChange30d),
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

    private func logScoringVerification(coinScores: [CoinScore]) {
        var verificationLog: [String] = []
        verificationLog.append("=== MLX Scoring Verification ===")

        for coin in coinScores.prefix(10) {
            let cached = cacheQueue.sync { cache[coin.symbol] }
            guard let cached = cached else { continue }

            let bullishScore = cached.score.momentumScore

            verificationLog.append(String(format: "%@: score=%.3f, bullish=%.3f",
                coin.symbol, coin.totalScore, bullishScore))
        }

        logger.info(component: "MLScoringEngine", event: "Scoring verification", data: [
            "verification": verificationLog.joined(separator: " | ")
        ])
    }

}
