import Foundation
import Utils

public protocol CoinScoringEngineProtocol {
    func scoreAllCoins() async throws -> [CoinScore]
    func scoreCoin(symbol: String) async throws -> CoinScore
    func updateCoinScores() async throws
    func getTopCoins(limit: Int, category: CoinCategory?) async throws -> [CoinScore]
    func getCoinsByRiskLevel(_ riskLevel: RiskLevel) async throws -> [CoinScore]
}

public class CoinScoringEngine: CoinScoringEngineProtocol, @unchecked Sendable {
    private let config: SmartVestorConfig
    private let persistence: PersistenceProtocol
    private let marketDataProvider: MarketDataProviderProtocol
    private let logger: StructuredLogger

    private var cachedScores: [String: CoinScore] = [:]
    private var cachedMarketData: [String: MarketData] = [:]
    private var cachedHistoricalData: [String: [MarketDataPoint]] = [:]
    private var lastUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 1800 // 30 minutes (reduced for more frequent updates)

    public init(
        config: SmartVestorConfig,
        persistence: PersistenceProtocol,
        marketDataProvider: MarketDataProviderProtocol
    ) {
        self.config = config
        self.persistence = persistence
        self.marketDataProvider = marketDataProvider
        self.logger = StructuredLogger()
    }

    public func scoreAllCoins() async throws -> [CoinScore] {
        logger.info(component: "CoinScoringEngine", event: "Scoring all coins")

        if shouldUseCachedScores() {
            logger.info(component: "CoinScoringEngine", event: "Using cached scores")
            return Array(cachedScores.values).sorted { $0.totalScore > $1.totalScore }
        }

        let symbols = await getDynamicSupportedSymbols()

        // Batch fetch all market data upfront
        let marketDataMap = try await batchFetchMarketData(symbols: symbols)
        let historicalDataMap = try await batchFetchHistoricalData(symbols: symbols, days: 30)
        let shortHistoricalDataMap = try await batchFetchHistoricalData(symbols: symbols, days: 7)

        var allScores = try await withThrowingTaskGroup(of: CoinScore?.self) { group in
            var results: [CoinScore] = []

            for symbol in symbols {
                group.addTask { [symbol] in
                    do {
                        let score = try await self.scoreCoinOptimized(
                            symbol: symbol,
                            marketData: marketDataMap[symbol],
                            historicalData: historicalDataMap[symbol],
                            shortHistoricalData: shortHistoricalDataMap[symbol]
                        )
                        return score
                    } catch {
                        self.logger.warn(component: "CoinScoringEngine", event: "Failed to score coin", data: [
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
                    cachedScores[score.symbol] = score
                }
            }

            return results
        }

        allScores.sort { $0.totalScore > $1.totalScore }
        lastUpdate = Date()

        logger.info(component: "CoinScoringEngine", event: "Coin scoring completed", data: [
            "total_coins": String(allScores.count),
            "top_coin": allScores.first?.symbol ?? "none"
        ])

        return allScores
    }

    public func scoreCoin(symbol: String) async throws -> CoinScore {
        logger.info(component: "CoinScoringEngine", event: "Scoring coin", data: [
            "symbol": symbol
        ])

        let technicalScore = try await calculateTechnicalScore(symbol: symbol)
        let fundamentalScore = try await calculateFundamentalScore(symbol: symbol)
        let momentumScore = try await calculateMomentumScore(symbol: symbol)
        let volatilityScore = try await calculateVolatilityScore(symbol: symbol)
        let liquidityScore = try await calculateLiquidityScore(symbol: symbol)

        let totalScore = calculateTotalScore(
            technical: technicalScore,
            fundamental: fundamentalScore,
            momentum: momentumScore,
            volatility: volatilityScore,
            liquidity: liquidityScore
        )

        let category = getCategoryForSymbol(symbol)
        let riskLevel = determineRiskLevel(
            volatility: volatilityScore,
            marketCap: try await getMarketCap(symbol: symbol),
            liquidity: liquidityScore
        )

        let marketData = try await getMarketData(symbol: symbol)

        let score = CoinScore(
            symbol: symbol,
            totalScore: totalScore,
            technicalScore: technicalScore,
            fundamentalScore: fundamentalScore,
            momentumScore: momentumScore,
            volatilityScore: volatilityScore,
            liquidityScore: liquidityScore,
            category: category,
            riskLevel: riskLevel,
            marketCap: marketData.marketCap,
            volume24h: marketData.volume24h,
            priceChange24h: marketData.priceChange24h,
            priceChange7d: marketData.priceChange7d,
            priceChange30d: marketData.priceChange30d
        )

        logger.info(component: "CoinScoringEngine", event: "Coin scored", data: [
            "symbol": symbol,
            "total_score": String(totalScore),
            "risk_level": riskLevel.rawValue
        ])

        return score
    }

    public func updateCoinScores() async throws {
        logger.info(component: "CoinScoringEngine", event: "Updating coin scores")

        clearAllCaches()

        _ = try await scoreAllCoins()

        logger.info(component: "CoinScoringEngine", event: "Coin scores updated")
    }

    private func clearAllCaches() {
        cachedScores.removeAll()
        cachedMarketData.removeAll()
        cachedHistoricalData.removeAll()
        lastUpdate = nil
    }

    public func getTopCoins(limit: Int, category: CoinCategory?) async throws -> [CoinScore] {
        let allScores = try await scoreAllCoins()

        let filteredScores = if let category = category {
            allScores.filter { $0.category == category }
        } else {
            allScores
        }

        return Array(filteredScores.prefix(limit))
    }

    public func getCoinsByRiskLevel(_ riskLevel: RiskLevel) async throws -> [CoinScore] {
        let allScores = try await scoreAllCoins()
        return allScores.filter { $0.riskLevel == riskLevel }
    }

    // MARK: - Private Methods

    private func shouldUseCachedScores() -> Bool {
        guard let lastUpdate = lastUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < cacheValidityDuration
    }

    private func batchFetchMarketData(symbols: [String]) async throws -> [String: MarketData] {
        logger.info(component: "CoinScoringEngine", event: "Batch fetching market data", data: [
            "symbol_count": String(symbols.count)
        ])

        // Check cache first
        var marketDataMap: [String: MarketData] = [:]
        var symbolsToFetch: [String] = []

        for symbol in symbols {
            if let cachedData = cachedMarketData[symbol] {
                marketDataMap[symbol] = cachedData
            } else {
                symbolsToFetch.append(symbol)
            }
        }

        // Only fetch missing data
        if !symbolsToFetch.isEmpty {
            let currentPrices = try await marketDataProvider.getCurrentPrices(symbols: symbolsToFetch)
            let volumeData = try await marketDataProvider.getVolumeData(symbols: symbolsToFetch)

            for symbol in symbolsToFetch {
                let currentPrice = currentPrices[symbol] ?? 0.0
                let volume = volumeData[symbol] ?? 0.0
                let marketCap = currentPrice * getCirculatingSupply(symbol: symbol)

                let symbolHash = abs(symbol.hashValue)
                let priceChange24h = (Double(symbolHash % 200) / 200.0 - 0.5) * 0.08
                let priceChange7d = (Double((symbolHash + 100) % 200) / 200.0 - 0.5) * 0.15
                let priceChange30d = (Double((symbolHash + 200) % 200) / 200.0 - 0.5) * 0.30

                let marketData = MarketData(
                    symbol: symbol,
                    price: currentPrice,
                    marketCap: marketCap,
                    volume24h: volume,
                    priceChange24h: priceChange24h,
                    priceChange7d: priceChange7d,
                    priceChange30d: priceChange30d
                )

                marketDataMap[symbol] = marketData
                cachedMarketData[symbol] = marketData
            }
        }

        return marketDataMap
    }

    private func batchFetchHistoricalData(symbols: [String], days: Int) async throws -> [String: [MarketDataPoint]] {
        logger.info(component: "CoinScoringEngine", event: "Batch fetching historical data", data: [
            "symbol_count": String(symbols.count),
            "days": String(days)
        ])

        // Check cache first
        var historicalDataMap: [String: [MarketDataPoint]] = [:]
        var symbolsToFetch: [String] = []

        let cacheKey = "\(days)d"

        for symbol in symbols {
            let fullCacheKey = "\(symbol)_\(cacheKey)"
            if let cachedData = cachedHistoricalData[fullCacheKey] {
                historicalDataMap[symbol] = cachedData
            } else {
                symbolsToFetch.append(symbol)
            }
        }

        // Only fetch missing data
        if !symbolsToFetch.isEmpty {
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!

            let fetchedData = try await marketDataProvider.getHistoricalData(
                startDate: startDate,
                endDate: endDate,
                symbols: symbolsToFetch
            )

            for symbol in symbolsToFetch {
                if let data = fetchedData[symbol] {
                    historicalDataMap[symbol] = data
                    cachedHistoricalData["\(symbol)_\(cacheKey)"] = data
                }
            }
        }

        return historicalDataMap
    }

    private func scoreCoinOptimized(
        symbol: String,
        marketData: MarketData?,
        historicalData: [MarketDataPoint]?,
        shortHistoricalData: [MarketDataPoint]?
    ) async throws -> CoinScore {
        guard let marketData = marketData,
              let historicalData = historicalData,
              let shortHistoricalData = shortHistoricalData else {
            throw MarketDataError.apiError("Missing market data for \(symbol)")
        }

        let technicalScore = calculateTechnicalScoreOptimized(historicalData: historicalData)
        let fundamentalScore = calculateFundamentalScoreOptimized(symbol: symbol, marketData: marketData)
        let momentumScore = calculateMomentumScoreOptimized(marketData: marketData, historicalData: historicalData)
        let volatilityScore = calculateVolatilityScoreOptimized(historicalData: historicalData)
        let liquidityScore = calculateLiquidityScoreOptimized(marketData: marketData, historicalData: shortHistoricalData)

        let totalScore = calculateTotalScore(
            technical: technicalScore,
            fundamental: fundamentalScore,
            momentum: momentumScore,
            volatility: volatilityScore,
            liquidity: liquidityScore
        )

        let category = getCategoryForSymbol(symbol)
        let riskLevel = determineRiskLevel(
            volatility: volatilityScore,
            marketCap: marketData.marketCap,
            liquidity: liquidityScore
        )

        let score = CoinScore(
            symbol: symbol,
            totalScore: totalScore,
            technicalScore: technicalScore,
            fundamentalScore: fundamentalScore,
            momentumScore: momentumScore,
            volatilityScore: volatilityScore,
            liquidityScore: liquidityScore,
            category: category,
            riskLevel: riskLevel,
            marketCap: marketData.marketCap,
            volume24h: marketData.volume24h,
            priceChange24h: marketData.priceChange24h,
            priceChange7d: marketData.priceChange7d,
            priceChange30d: marketData.priceChange30d
        )

        return score
    }

    private func getDynamicSupportedSymbols() async -> [String] {
        do {
            let apiSymbols = try await RobinhoodInstrumentsAPI.shared.fetchSupportedSymbols(logger: logger)
            return apiSymbols
        } catch {
            logger.warn(component: "CoinScoringEngine", event: "robinhood_api_failed", data: [
                "error": error.localizedDescription,
                "message": "Falling back to static list"
            ])
            return [
                "AAVE", "ADA", "ARB", "ASTER", "AVAX", "BCH", "BNB", "BONK",
                "BTC", "COMP", "CRV", "DOGE", "ETC", "ETH", "FLOKI", "HBAR",
                "HYPE", "LINK", "LTC", "MEW", "MOODENG", "ONDO", "OP", "PENGU",
                "PEPE", "PNUT", "POPCAT", "SHIB", "SOL", "SUI", "TON", "TRUMP",
                "UNI", "USDC", "XLM", "XPL", "XRP", "XTZ", "WLFI", "WIF",
                "VIRTUAL", "ZORA"
            ]
        }
    }

    private func calculateTechnicalScore(symbol: String) async throws -> Double {
        _ = try await getMarketData(symbol: symbol)
        let historicalData = try await getHistoricalData(symbol: symbol, days: 30)

        let rsiScore = calculateRSIScore(prices: historicalData.map { $0.close })
        let macdScore = calculateMACDScore(prices: historicalData.map { $0.close })
        let bollingerScore = calculateBollingerScore(prices: historicalData.map { $0.close })
        let supportResistanceScore = calculateSupportResistanceScore(
            prices: historicalData.map { $0.close },
            highs: historicalData.map { $0.high },
            lows: historicalData.map { $0.low }
        )
        let trendScore = calculateTrendScore(prices: historicalData.map { $0.close })

        let technicalScore = calculateCompositeZScore(scores: [
            rsiScore, macdScore, bollingerScore, supportResistanceScore, trendScore
        ])

        logger.debug(component: "CoinScoringEngine", event: "Technical score calculated", data: [
            "symbol": symbol,
            "technical_score": String(technicalScore),
            "rsi_score": String(rsiScore),
            "macd_score": String(macdScore),
            "bollinger_score": String(bollingerScore),
            "trend_score": String(trendScore)
        ])

        return technicalScore
    }

    private func calculateFundamentalScore(symbol: String) async throws -> Double {
        let marketData = try await getMarketData(symbol: symbol)
        let category = getCategoryForSymbol(symbol)

        let marketCapScore = calculateMarketCapScore(marketCap: marketData.marketCap)
        let volumeScore = calculateVolumeScore(volume: marketData.volume24h, marketCap: marketData.marketCap)
        let categoryScore = calculateCategoryScore(category: category)
        let adoptionScore = calculateAdoptionScore(symbol: symbol, category: category)
        let developmentScore = calculateDevelopmentScore(symbol: symbol)
        let tokenomicsScore = calculateTokenomicsStabilityScore(symbol: symbol)

        let fundamentalScore = calculateCompositeZScore(scores: [
            marketCapScore, volumeScore, categoryScore, adoptionScore, developmentScore, tokenomicsScore
        ])

        logger.debug(component: "CoinScoringEngine", event: "Fundamental score calculated", data: [
            "symbol": symbol,
            "fundamental_score": String(fundamentalScore),
            "market_cap_score": String(marketCapScore),
            "volume_score": String(volumeScore),
            "category_score": String(categoryScore),
            "tokenomics_score": String(tokenomicsScore)
        ])

        return fundamentalScore
    }

    private func calculateMomentumScore(symbol: String) async throws -> Double {
        let marketData = try await getMarketData(symbol: symbol)
        let historicalData = try await getHistoricalData(symbol: symbol, days: 30)

        let priceMomentum = calculatePriceMomentum(
            priceChange24h: marketData.priceChange24h,
            priceChange7d: marketData.priceChange7d,
            priceChange30d: marketData.priceChange30d
        )

        let volumeMomentum = calculateVolumeMomentum(historicalData: historicalData)
        let relativeStrengthVsBTC = try await calculateRelativeStrengthVsBTC(
            symbol: symbol,
            historicalData: historicalData
        )
        let relativeStrengthVsSector = try await calculateRelativeStrengthVsSector(
            symbol: symbol,
            historicalData: historicalData
        )

        let momentumScore = calculateCompositeZScore(scores: [
            priceMomentum, volumeMomentum, relativeStrengthVsBTC, relativeStrengthVsSector
        ])

        logger.debug(component: "CoinScoringEngine", event: "Momentum score calculated", data: [
            "symbol": symbol,
            "momentum_score": String(momentumScore),
            "price_momentum": String(priceMomentum),
            "volume_momentum": String(volumeMomentum),
            "relative_strength_btc": String(relativeStrengthVsBTC),
            "relative_strength_sector": String(relativeStrengthVsSector)
        ])

        return momentumScore
    }

    private func calculateVolatilityScore(symbol: String) async throws -> Double {
        let historicalData = try await getHistoricalData(symbol: symbol, days: 30)
        let returns = calculateReturns(prices: historicalData.map { $0.close })
        let volatility = calculateVolatility(returns: returns)

        let volatilityScore = calculateVolatilityExclusionScore(volatility: volatility)

        logger.debug(component: "CoinScoringEngine", event: "Volatility score calculated", data: [
            "symbol": symbol,
            "volatility": String(volatility),
            "volatility_score": String(volatilityScore)
        ])

        return volatilityScore
    }

    private func calculateLiquidityScore(symbol: String) async throws -> Double {
        let marketData = try await getMarketData(symbol: symbol)
        let historicalData = try await getHistoricalData(symbol: symbol, days: 7)

        let volumeScore = calculateVolumeLiquidityScore(volume: marketData.volume24h)
        let spreadScore = try await calculateCrossExchangeSpreadScore(symbol: symbol)
        let depthScore = try await calculateOrderBookDepthScore(symbol: symbol, tradeSize: 10000.0)
        let consistencyScore = calculateLiquidityConsistencyScore(historicalData: historicalData)
        let slippageScore = try await calculateSlippageScore(symbol: symbol, tradeSize: 10000.0)

        let liquidityScore = calculateCompositeZScore(scores: [
            volumeScore, spreadScore, depthScore, consistencyScore, slippageScore
        ])

        logger.debug(component: "CoinScoringEngine", event: "Liquidity score calculated", data: [
            "symbol": symbol,
            "liquidity_score": String(liquidityScore),
            "volume_score": String(volumeScore),
            "spread_score": String(spreadScore),
            "depth_score": String(depthScore),
            "slippage_score": String(slippageScore)
        ])

        return liquidityScore
    }

    // MARK: - Optimized Calculation Methods (No API Calls)

    private func calculateTechnicalScoreOptimized(historicalData: [MarketDataPoint]) -> Double {
        let rsiScore = calculateRSIScore(prices: historicalData.map { $0.close })
        let macdScore = calculateMACDScore(prices: historicalData.map { $0.close })
        let bollingerScore = calculateBollingerScore(prices: historicalData.map { $0.close })
        let supportResistanceScore = calculateSupportResistanceScore(
            prices: historicalData.map { $0.close },
            highs: historicalData.map { $0.high },
            lows: historicalData.map { $0.low }
        )
        let trendScore = calculateTrendScore(prices: historicalData.map { $0.close })

        return calculateCompositeZScore(scores: [
            rsiScore, macdScore, bollingerScore, supportResistanceScore, trendScore
        ])
    }

    private func calculateFundamentalScoreOptimized(symbol: String, marketData: MarketData) -> Double {
        let category = getCategoryForSymbol(symbol)

        let marketCapScore = calculateMarketCapScore(marketCap: marketData.marketCap)
        let volumeScore = calculateVolumeScore(volume: marketData.volume24h, marketCap: marketData.marketCap)
        let categoryScore = calculateCategoryScore(category: category)
        let adoptionScore = calculateAdoptionScore(symbol: symbol, category: category)
        let developmentScore = calculateDevelopmentScore(symbol: symbol)
        let tokenomicsScore = calculateTokenomicsStabilityScore(symbol: symbol)

        return calculateCompositeZScore(scores: [
            marketCapScore, volumeScore, categoryScore, adoptionScore, developmentScore, tokenomicsScore
        ])
    }

    private func calculateMomentumScoreOptimized(marketData: MarketData, historicalData: [MarketDataPoint]) -> Double {
        let priceMomentum = calculatePriceMomentum(
            priceChange24h: marketData.priceChange24h,
            priceChange7d: marketData.priceChange7d,
            priceChange30d: marketData.priceChange30d
        )

        let volumeMomentum = calculateVolumeMomentum(historicalData: historicalData)

        // Simplified relative strength calculations to avoid additional API calls
        let relativeStrengthVsBTC = calculateSimplifiedRelativeStrength(historicalData: historicalData)
        let relativeStrengthVsSector = calculateSimplifiedRelativeStrength(historicalData: historicalData)

        return calculateCompositeZScore(scores: [
            priceMomentum, volumeMomentum, relativeStrengthVsBTC, relativeStrengthVsSector
        ])
    }

    private func calculateVolatilityScoreOptimized(historicalData: [MarketDataPoint]) -> Double {
        let returns = calculateReturns(prices: historicalData.map { $0.close })
        let volatility = calculateVolatility(returns: returns)
        return calculateVolatilityExclusionScore(volatility: volatility)
    }

    private func calculateLiquidityScoreOptimized(marketData: MarketData, historicalData: [MarketDataPoint]) -> Double {
        let volumeScore = calculateVolumeLiquidityScore(volume: marketData.volume24h)

        // Simplified calculations to avoid additional API calls
        let spreadScore = calculateSimplifiedSpreadScore(symbol: marketData.symbol)
        let depthScore = calculateSimplifiedDepthScore(volume: marketData.volume24h)
        let consistencyScore = calculateLiquidityConsistencyScore(historicalData: historicalData)
        let slippageScore = calculateSimplifiedSlippageScore(volume: marketData.volume24h)

        return calculateCompositeZScore(scores: [
            volumeScore, spreadScore, depthScore, consistencyScore, slippageScore
        ])
    }

    private func calculateSimplifiedRelativeStrength(historicalData: [MarketDataPoint]) -> Double {
        guard historicalData.count >= 2 else { return 0.5 }

        let prices = historicalData.map { $0.close }
        let recentPerformance = (prices.last! - prices.first!) / prices.first!

        // Normalize to 0-1 range
        return min(1.0, max(0.0, (recentPerformance + 0.5) / 1.0))
    }

    private func calculateSimplifiedSpreadScore(symbol: String) -> Double {
        // Use symbol hash to generate deterministic spread score
        let symbolHash = abs(symbol.hashValue)
        let baseScore = Double(symbolHash % 100) / 100.0

        // Major coins get better spread scores
        let majorCoins = ["BTC", "ETH", "SOL", "ADA", "DOT", "LINK"]
        let multiplier = majorCoins.contains(symbol) ? 1.2 : 0.8

        return min(1.0, baseScore * multiplier)
    }

    private func calculateSimplifiedDepthScore(volume: Double) -> Double {
        // Higher volume = better depth
        let normalizedVolume = min(1.0, volume / 1_000_000_000) // Normalize to 1B
        return sqrt(normalizedVolume) // Square root for diminishing returns
    }

    private func calculateSimplifiedSlippageScore(volume: Double) -> Double {
        // Higher volume = lower slippage
        let normalizedVolume = min(1.0, volume / 1_000_000_000) // Normalize to 1B
        return sqrt(normalizedVolume) // Square root for diminishing returns
    }

    private func calculateTotalScore(
        technical: Double,
        fundamental: Double,
        momentum: Double,
        volatility: Double,
        liquidity: Double
    ) -> Double {
        let weights = getScoreWeights()

        let totalScore = (technical * weights.technical) +
                        (fundamental * weights.fundamental) +
                        (momentum * weights.momentum) +
                        (volatility * weights.volatility) +
                        (liquidity * weights.liquidity)

        return min(1.0, max(0.0, totalScore))
    }

    private func getScoreWeights() -> (technical: Double, fundamental: Double, momentum: Double, volatility: Double, liquidity: Double) {
        return (0.20, 0.35, 0.20, 0.10, 0.15)
    }

    private func determineRiskLevel(volatility: Double, marketCap: Double, liquidity: Double) -> RiskLevel {
        let volatilityRisk = volatility > 0.1 ? 2 : (volatility > 0.05 ? 1 : 0)
        let marketCapRisk = marketCap < 100_000_000 ? 2 : (marketCap < 1_000_000_000 ? 1 : 0)
        let liquidityRisk = liquidity < 0.3 ? 2 : (liquidity < 0.6 ? 1 : 0)

        let totalRisk = volatilityRisk + marketCapRisk + liquidityRisk

        switch totalRisk {
        case 0...1: return .low
        case 2...3: return .medium
        case 4...5: return .high
        default: return .veryHigh
        }
    }

    // MARK: - Technical Analysis Methods

    private func calculateRSIScore(prices: [Double]) -> Double {
        guard prices.count >= 14 else { return 0.5 }

        let returns = calculateReturns(prices: prices)
        let gains = returns.map { max($0, 0) }
        let losses = returns.map { max(-$0, 0) }

        let avgGain = gains.prefix(14).reduce(0, +) / 14.0
        let avgLoss = losses.prefix(14).reduce(0, +) / 14.0

        guard avgLoss > 0 else { return 1.0 }

        let rs = avgGain / avgLoss
        let rsi = 100.0 - (100.0 / (1.0 + rs))

        // RSI score: 0.5 at 50, 1.0 at 30-70, 0.0 at extremes
        if rsi >= 30 && rsi <= 70 {
            return 1.0
        } else if rsi >= 20 && rsi <= 80 {
            return 0.8
        } else {
            return 0.3
        }
    }

    private func calculateMACDScore(prices: [Double]) -> Double {
        guard prices.count >= 26 else { return 0.5 }

        let ema12 = calculateEMA(prices: prices, period: 12)
        let ema26 = calculateEMA(prices: prices, period: 26)

        guard ema12.count == ema26.count else { return 0.5 }

        let macdLine = zip(ema12, ema26).map { $0 - $1 }
        let signalLine = calculateEMA(prices: macdLine, period: 9)

        guard macdLine.count >= 9 && signalLine.count >= 1 else { return 0.5 }

        let currentMACD = macdLine.last!
        let currentSignal = signalLine.last!
        let histogram = currentMACD - currentSignal

        // MACD score based on histogram and crossover
        if histogram > 0 && currentMACD > currentSignal {
            return 1.0
        } else if histogram < 0 && currentMACD < currentSignal {
            return 0.2
        } else {
            return 0.6
        }
    }

    private func calculateBollingerScore(prices: [Double]) -> Double {
        guard prices.count >= 20 else { return 0.5 }

        let sma = calculateSMA(prices: prices, period: 20)
        let stdDev = calculateStandardDeviation(prices: prices, period: 20)

        guard let currentPrice = prices.last,
              let currentSMA = sma.last,
              let currentStdDev = stdDev.last else { return 0.5 }

        let upperBand = currentSMA + (2 * currentStdDev)
        let lowerBand = currentSMA - (2 * currentStdDev)

        // Bollinger score: 1.0 when price is near middle, 0.0 at bands
        if currentPrice >= lowerBand && currentPrice <= upperBand {
            let distanceFromMiddle = abs(currentPrice - currentSMA) / (upperBand - lowerBand)
            return 1.0 - distanceFromMiddle
        } else {
            return 0.1
        }
    }

    private func calculateSupportResistanceScore(
        prices: [Double],
        highs: [Double],
        lows: [Double]
    ) -> Double {
        guard prices.count >= 20 else { return 0.5 }

        let currentPrice = prices.last!
        let recentHighs = highs.suffix(20)
        let recentLows = lows.suffix(20)

        let resistanceLevels = findResistanceLevels(highs: Array(recentHighs))
        let supportLevels = findSupportLevels(lows: Array(recentLows))

        let resistanceScore = calculateLevelScore(price: currentPrice, levels: resistanceLevels, isResistance: true)
        let supportScore = calculateLevelScore(price: currentPrice, levels: supportLevels, isResistance: false)

        return (resistanceScore + supportScore) / 2.0
    }

    private func calculateTrendScore(prices: [Double]) -> Double {
        guard prices.count >= 20 else { return 0.5 }

        let shortMA = calculateSMA(prices: prices, period: 10)
        let longMA = calculateSMA(prices: prices, period: 20)

        guard shortMA.count >= 1 && longMA.count >= 1 else { return 0.5 }

        let currentShortMA = shortMA.last!
        let currentLongMA = longMA.last!

        if currentShortMA > currentLongMA {
            return 1.0
        } else if currentShortMA < currentLongMA {
            return 0.2
        } else {
            return 0.6
        }
    }

    // MARK: - Fundamental Analysis Methods

    private func calculateMarketCapScore(marketCap: Double) -> Double {
        let baseScore: Double
        if marketCap >= 100_000_000_000 {
            baseScore = 1.0
        } else if marketCap >= 10_000_000_000 {
            baseScore = 0.9
        } else if marketCap >= 1_000_000_000 {
            baseScore = 0.8
        } else if marketCap >= 100_000_000 {
            baseScore = 0.6
        } else if marketCap >= 10_000_000 {
            baseScore = 0.4
        } else {
            baseScore = 0.2
        }

        // Add some variation based on market cap magnitude
        let magnitudeFactor = log10(max(1, marketCap)) / 12.0 // Normalize to 0-1 range
        return min(1.0, baseScore + magnitudeFactor * 0.1)
    }

    private func calculateVolumeScore(volume: Double, marketCap: Double) -> Double {
        let volumeRatio = volume / marketCap

        if volumeRatio >= 0.1 {
            return 1.0
        } else if volumeRatio >= 0.05 {
            return 0.8
        } else if volumeRatio >= 0.02 {
            return 0.6
        } else if volumeRatio >= 0.01 {
            return 0.4
        } else {
            return 0.2
        }
    }

    private func calculateCategoryScore(category: CoinCategory) -> Double {
        switch category {
        case .layer1: return 1.0
        case .defi: return 0.9
        case .infrastructure: return 0.8
        case .layer2: return 0.7
        case .gaming: return 0.6
        case .nft: return 0.5
        case .ai: return 0.8
        case .storage: return 0.6
        case .privacy: return 0.4
        case .meme: return 0.2
        }
    }

    private func calculateAdoptionScore(symbol: String, category: CoinCategory) -> Double {
        let baseScore: Double
        switch symbol {
        case "BTC", "ETH": baseScore = 1.0
        case "ADA", "SOL", "AVAX": baseScore = 0.8
        case "DOT", "LINK", "UNI": baseScore = 0.7
        case "AAVE", "COMP", "MKR": baseScore = 0.6
        default: baseScore = 0.4
        }

        // Add symbol-specific variation based on hash
        let symbolHash = symbol.hashValue
        let variation = Double(abs(symbolHash) % 100) / 100.0 * 0.2 // 0-20% variation
        return min(1.0, baseScore + variation)
    }

    private func calculateDevelopmentScore(symbol: String) -> Double {
        let baseScore: Double
        switch symbol {
        case "ETH", "ADA", "DOT": baseScore = 1.0
        case "SOL", "AVAX", "LINK": baseScore = 0.8
        case "UNI", "AAVE", "COMP": baseScore = 0.7
        default: baseScore = 0.5
        }

        // Add symbol-specific variation
        let symbolHash = symbol.hashValue
        let variation = Double(abs(symbolHash) % 50) / 50.0 * 0.15 // 0-15% variation
        return min(1.0, baseScore + variation)
    }

    // MARK: - Momentum Analysis Methods

    private func calculatePriceMomentum(
        priceChange24h: Double,
        priceChange7d: Double,
        priceChange30d: Double
    ) -> Double {
        let momentum24h = priceChange24h > 0 ? 1.0 : 0.0
        let momentum7d = priceChange7d > 0 ? 1.0 : 0.0
        let momentum30d = priceChange30d > 0 ? 1.0 : 0.0

        return (momentum24h + momentum7d + momentum30d) / 3.0
    }

    private func calculateVolumeMomentum(historicalData: [MarketDataPoint]) -> Double {
        guard historicalData.count >= 7 else { return 0.5 }

        let recentVolume = historicalData.suffix(3).map { $0.volume }.reduce(0, +) / 3.0
        let olderVolume = historicalData.prefix(4).map { $0.volume }.reduce(0, +) / 4.0

        if olderVolume > 0 {
            let volumeRatio = recentVolume / olderVolume
            return min(1.0, volumeRatio)
        }

        return 0.5
    }

    private func calculateRelativeStrength(
        symbol: String,
        historicalData: [MarketDataPoint]
    ) -> Double {
        // This would compare against a benchmark like BTC or market average
        return 0.5
    }

    // MARK: - Volatility Analysis Methods

    private func calculateVolatilityExclusionScore(volatility: Double) -> Double {
        // Use volatility as exclusion threshold rather than scoring bias
        // High volatility gets penalized, but not as heavily as before

        if volatility <= 0.05 {
            return 1.0
        } else if volatility <= 0.08 {
            return 0.9
        } else if volatility <= 0.12 {
            return 0.7
        } else if volatility <= 0.20 {
            return 0.5
        } else {
            return 0.2
        }
    }

    // MARK: - Liquidity Analysis Methods

    private func calculateVolumeLiquidityScore(volume: Double) -> Double {
        if volume >= 100_000_000 {
            return 1.0
        } else if volume >= 50_000_000 {
            return 0.8
        } else if volume >= 10_000_000 {
            return 0.6
        } else if volume >= 1_000_000 {
            return 0.4
        } else {
            return 0.2
        }
    }

    private func calculateSpreadScore(symbol: String) -> Double {
        // This would integrate with real spread data from exchanges
        return 0.7
    }

    private func calculateDepthScore(symbol: String) -> Double {
        // This would integrate with real order book depth data
        return 0.6
    }

    private func calculateLiquidityConsistencyScore(historicalData: [MarketDataPoint]) -> Double {
        guard historicalData.count >= 7 else { return 0.5 }

        let volumes = historicalData.map { $0.volume }
        let meanVolume = volumes.reduce(0, +) / Double(volumes.count)
        let variance = volumes.map { pow($0 - meanVolume, 2) }.reduce(0, +) / Double(volumes.count)
        let coefficientOfVariation = sqrt(variance) / meanVolume

        // Lower coefficient of variation = more consistent liquidity = higher score
        return max(0.0, 1.0 - coefficientOfVariation)
    }

    // MARK: - Helper Methods

    private func getCategoryForSymbol(_ symbol: String) -> CoinCategory {
    let categoryMap: [String: CoinCategory] = [
            "BTC": .layer1, "ETH": .layer1, "SOL": .layer1, "AVAX": .layer1,
            "ADA": .layer1, "BCH": .layer1, "ETC": .layer1, "LTC": .layer1,
            "XRP": .layer1, "XLM": .layer1, "HBAR": .layer1, "SUI": .layer1,
            "TON": .layer1, "XTZ": .layer1, "BNB": .layer1, "DOGE": .meme,
            "ARB": .layer2, "OP": .layer2,
            "UNI": .defi, "AAVE": .defi, "COMP": .defi, "CRV": .defi,
            "LINK": .infrastructure, "ONDO": .infrastructure, "BAND": .infrastructure,
            "VIRTUAL": .gaming, "FLOKI": .gaming, "ZORA": .nft, "APE": .nft,
            "SHIB": .meme, "PEPE": .meme, "BONK": .meme, "WIF": .meme,
            "MEW": .meme, "MOODENG": .meme, "PENGU": .meme, "PNUT": .meme,
            "POPCAT": .meme, "TRUMP": .meme, "HYPE": .meme, "WLFI": .meme,
            "XPL": .meme, "ASTER": .meme,
        "FET": .ai, "AGIX": .ai, "OCEAN": .ai,
    "USDC": .infrastructure
        ]

        return categoryMap[symbol] ?? .meme // Default to meme for new coins
    }

    private func getCoinsForCategory(_ category: CoinCategory) -> [String] {
        let coinsByCategory: [CoinCategory: [String]] = [
            .layer1: ["BTC", "ETH", "SOL", "AVAX", "ATOM", "NEAR", "FTM", "ALGO", "ICP"],
            .layer2: ["MATIC", "ARB", "OP"],
            .defi: ["UNI", "AAVE", "COMP", "MKR", "SNX"],
            .infrastructure: ["LINK", "GRT", "BAND", "API3"],
            .gaming: ["AXS", "SAND", "MANA", "GALA", "ENJ"],
            .nft: ["LOOKS", "RARE", "APE"],
            .privacy: ["XMR", "ZEC", "DASH"],
            .meme: ["DOGE", "SHIB", "PEPE", "FLOKI", "BONK", "WIF", "BOME", "POPCAT", "MEW", "MYRO"],
            .ai: ["FET", "AGIX", "OCEAN"],
            .storage: ["FIL", "AR", "SC"]
        ]

        return coinsByCategory[category] ?? []
    }

    private func getMarketData(symbol: String) async throws -> MarketData {
        let currentPrices = try await marketDataProvider.getCurrentPrices(symbols: [symbol])
        let volumeData = try await marketDataProvider.getVolumeData(symbols: [symbol])

        let currentPrice = currentPrices[symbol] ?? 0.0
        let volume = volumeData[symbol] ?? 0.0

        // Mock market cap calculation
        let marketCap = currentPrice * getCirculatingSupply(symbol: symbol)

        // Generate deterministic price changes based on symbol
        let symbolHash = abs(symbol.hashValue)
        let priceChange24h = (Double(symbolHash % 200) / 200.0 - 0.5) * 0.08 // -4% to +4%
        let priceChange7d = (Double((symbolHash + 100) % 200) / 200.0 - 0.5) * 0.15 // -7.5% to +7.5%
        let priceChange30d = (Double((symbolHash + 200) % 200) / 200.0 - 0.5) * 0.30 // -15% to +15%

        return MarketData(
            symbol: symbol,
            price: currentPrice,
            marketCap: marketCap,
            volume24h: volume,
            priceChange24h: priceChange24h,
            priceChange7d: priceChange7d,
            priceChange30d: priceChange30d
        )
    }

    private func getHistoricalData(symbol: String, days: Int) async throws -> [MarketDataPoint] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!

        let marketData = try await marketDataProvider.getHistoricalData(
            startDate: startDate,
            endDate: endDate,
            symbols: [symbol]
        )

        return marketData[symbol] ?? []
    }

    private func getMarketCap(symbol: String) async throws -> Double {
        let marketData = try await getMarketData(symbol: symbol)
        return marketData.marketCap
    }

    private func getCirculatingSupply(symbol: String) -> Double {
        let supplyMap: [String: Double] = [
            "BTC": 19_500_000,
            "ETH": 120_000_000,
            "ADA": 35_000_000_000,
            "DOT": 1_200_000_000,
            "LINK": 1_000_000_000,
            "SOL": 400_000_000,
            "AVAX": 300_000_000,
            "MATIC": 10_000_000_000,
            "ARB": 1_000_000_000,
            "OP": 1_000_000_000
        ]

        return supplyMap[symbol] ?? 1_000_000_000
    }

    private func calculateReturns(prices: [Double]) -> [Double] {
        guard prices.count > 1 else { return [] }

        var returns: [Double] = []
        for i in 1..<prices.count {
            let returnValue = (prices[i] - prices[i-1]) / prices[i-1]
            returns.append(returnValue)
        }
        return returns
    }

    private func calculateVolatility(returns: [Double]) -> Double {
        guard returns.count > 1 else { return 0.0 }

        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(returns.count)
        return sqrt(variance)
    }

    private func calculateSMA(prices: [Double], period: Int) -> [Double] {
        guard prices.count >= period else { return [] }

        var sma: [Double] = []
        for i in (period-1)..<prices.count {
            let sum = prices[(i-period+1)...i].reduce(0, +)
            sma.append(sum / Double(period))
        }
        return sma
    }

    private func calculateEMA(prices: [Double], period: Int) -> [Double] {
        guard prices.count >= period else { return [] }

        let multiplier = 2.0 / (Double(period) + 1.0)
        var ema: [Double] = []

        // First EMA is SMA
        let firstSMA = prices.prefix(period).reduce(0, +) / Double(period)
        ema.append(firstSMA)

        for i in period..<prices.count {
            let currentEMA = (prices[i] * multiplier) + (ema.last! * (1.0 - multiplier))
            ema.append(currentEMA)
        }

        return ema
    }

    private func calculateStandardDeviation(prices: [Double], period: Int) -> [Double] {
        guard prices.count >= period else { return [] }

        var stdDev: [Double] = []
        for i in (period-1)..<prices.count {
            let periodPrices = Array(prices[(i-period+1)...i])
            let mean = periodPrices.reduce(0, +) / Double(period)
            let variance = periodPrices.map { pow($0 - mean, 2) }.reduce(0, +) / Double(period)
            stdDev.append(sqrt(variance))
        }
        return stdDev
    }

    private func findResistanceLevels(highs: [Double]) -> [Double] {
        // Simplified resistance level detection
        let sortedHighs = highs.sorted(by: >)
        return Array(sortedHighs.prefix(3))
    }

    private func findSupportLevels(lows: [Double]) -> [Double] {
        // Simplified support level detection
        let sortedLows = lows.sorted(by: <)
        return Array(sortedLows.prefix(3))
    }

    private func calculateLevelScore(price: Double, levels: [Double], isResistance: Bool) -> Double {
        guard !levels.isEmpty else { return 0.5 }

        let closestLevel = levels.min { abs($0 - price) < abs($1 - price) }!
        _ = abs(price - closestLevel) / price

        if isResistance {
            return price < closestLevel ? 1.0 : 0.0
        } else {
            return price > closestLevel ? 1.0 : 0.0
        }
    }

    // MARK: - Enhanced Scoring Methods

    private func calculateCompositeZScore(scores: [Double]) -> Double {
        guard scores.count > 1 else { return scores.first ?? 0.5 }

        // Use weighted average with position-based weights to create differentiation
        let weights = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5] // Increasing weights for each component
        let weightedScores = scores.enumerated().map { index, score in
            let weight = index < weights.count ? weights[index] : (weights.last ?? 1.5)
            return score * weight
        }

        let weightedSum = weightedScores.reduce(0, +)
        let totalWeight = weights.prefix(scores.count).reduce(0, +)
        let weightedAverage = weightedSum / totalWeight

        // Add some variation based on the individual score differences
        guard let maxScore = scores.max(), let minScore = scores.min() else { return weightedAverage }
        let scoreRange = maxScore - minScore
        let variationFactor = min(0.1, scoreRange * 2) // Cap variation at 10%

        let finalScore = weightedAverage + variationFactor
        return min(1.0, max(0.0, finalScore))
    }

    private func calculateTokenomicsStabilityScore(symbol: String) -> Double {
        let tokenomicsData = getTokenomicsData(symbol: symbol)

        let inflationPenalty = calculateInflationPenalty(inflationRate: tokenomicsData.inflationRate)
        let emissionScheduleScore = calculateEmissionScheduleScore(emissionSchedule: tokenomicsData.emissionSchedule)
        let maxSupplyScore = calculateMaxSupplyScore(maxSupply: tokenomicsData.maxSupply, currentSupply: tokenomicsData.currentSupply)
        let utilityScore = calculateUtilityScore(symbol: symbol)

        return (inflationPenalty + emissionScheduleScore + maxSupplyScore + utilityScore) / 4.0
    }

    private func calculateRelativeStrengthVsBTC(symbol: String, historicalData: [MarketDataPoint]) async throws -> Double {
        let btcData = try await getHistoricalData(symbol: "BTC", days: 30)

        guard historicalData.count >= 7 && btcData.count >= 7 else { return 0.5 }

        let coinReturns = calculateReturns(prices: historicalData.map { $0.price })
        let btcReturns = calculateReturns(prices: btcData.map { $0.price })

        let coinMomentum = coinReturns.reduce(0, +) / Double(coinReturns.count)
        let btcMomentum = btcReturns.reduce(0, +) / Double(btcReturns.count)

        let relativeStrength = coinMomentum - btcMomentum

        if relativeStrength > 0.05 {
            return 1.0
        } else if relativeStrength > 0.02 {
            return 0.8
        } else if relativeStrength > -0.02 {
            return 0.6
        } else if relativeStrength > -0.05 {
            return 0.4
        } else {
            return 0.2
        }
    }

    private func calculateRelativeStrengthVsSector(symbol: String, historicalData: [MarketDataPoint]) async throws -> Double {
        let category = getCategoryForSymbol(symbol)
        let sectorCoins = getCoinsForCategory(category)

        var sectorReturns: [Double] = []

        for sectorCoin in sectorCoins.prefix(5) {
            if let sectorData = try? await getHistoricalData(symbol: sectorCoin, days: 30) {
                let returns = calculateReturns(prices: sectorData.map { $0.price })
                sectorReturns.append(contentsOf: returns)
            }
        }

        guard !sectorReturns.isEmpty else { return 0.5 }

        let coinReturns = calculateReturns(prices: historicalData.map { $0.price })
        let coinMomentum = coinReturns.reduce(0, +) / Double(coinReturns.count)
        let sectorMomentum = sectorReturns.reduce(0, +) / Double(sectorReturns.count)

        let relativeStrength = coinMomentum - sectorMomentum

        if relativeStrength > 0.03 {
            return 1.0
        } else if relativeStrength > 0.01 {
            return 0.8
        } else if relativeStrength > -0.01 {
            return 0.6
        } else if relativeStrength > -0.03 {
            return 0.4
        } else {
            return 0.2
        }
    }

    private func calculateCrossExchangeSpreadScore(symbol: String) async throws -> Double {
        let exchanges = ["kraken", "coinbase", "gemini"]
        var spreads: [Double] = []

        for exchange in exchanges {
            let spread = try await getSpreadForExchange(symbol: symbol, exchange: exchange)
            spreads.append(spread)
        }

        guard !spreads.isEmpty else { return 0.5 }

        let avgSpread = spreads.reduce(0, +) / Double(spreads.count)
        let spreadVariance = spreads.map { pow($0 - avgSpread, 2) }.reduce(0, +) / Double(spreads.count)
        let spreadUniformity = 1.0 - min(1.0, spreadVariance * 1000)

        let spreadScore = avgSpread < 0.001 ? 1.0 : (avgSpread < 0.002 ? 0.8 : (avgSpread < 0.005 ? 0.6 : 0.3))

        return (spreadScore + spreadUniformity) / 2.0
    }

    private func calculateOrderBookDepthScore(symbol: String, tradeSize: Double) async throws -> Double {
        let exchanges = ["kraken", "coinbase", "gemini"]
        var depthScores: [Double] = []

        for exchange in exchanges {
            let depth = try await getOrderBookDepth(symbol: symbol, exchange: exchange, tradeSize: tradeSize)
            let depthScore = depth > tradeSize * 2 ? 1.0 : (depth > tradeSize ? 0.8 : (depth > tradeSize * 0.5 ? 0.6 : 0.3))
            depthScores.append(depthScore)
        }

        return depthScores.reduce(0, +) / Double(depthScores.count)
    }

    private func calculateSlippageScore(symbol: String, tradeSize: Double) async throws -> Double {
        let exchanges = ["kraken", "coinbase", "gemini"]
        var slippageScores: [Double] = []

        for exchange in exchanges {
            let slippage = try await getExpectedSlippage(symbol: symbol, exchange: exchange, tradeSize: tradeSize)
            let slippageScore = slippage < 0.001 ? 1.0 : (slippage < 0.002 ? 0.8 : (slippage < 0.005 ? 0.6 : 0.3))
            slippageScores.append(slippageScore)
        }

        return slippageScores.reduce(0, +) / Double(slippageScores.count)
    }

    // MARK: - Tokenomics Helper Methods

    private func getTokenomicsData(symbol: String) -> TokenomicsData {
        let tokenomicsMap: [String: TokenomicsData] = [
            "BTC": TokenomicsData(inflationRate: 0.017, emissionSchedule: .fixed, maxSupply: 21_000_000, currentSupply: 19_500_000, utility: .storeOfValue),
            "ETH": TokenomicsData(inflationRate: 0.0, emissionSchedule: .deflationary, maxSupply: nil, currentSupply: 120_000_000, utility: .platform),
            "SOL": TokenomicsData(inflationRate: 0.08, emissionSchedule: .decreasing, maxSupply: nil, currentSupply: 400_000_000, utility: .platform),
            "AVAX": TokenomicsData(inflationRate: 0.05, emissionSchedule: .decreasing, maxSupply: 720_000_000, currentSupply: 300_000_000, utility: .platform),
            "ADA": TokenomicsData(inflationRate: 0.0, emissionSchedule: .fixed, maxSupply: 45_000_000_000, currentSupply: 35_000_000_000, utility: .platform),
            "DOT": TokenomicsData(inflationRate: 0.10, emissionSchedule: .decreasing, maxSupply: nil, currentSupply: 1_200_000_000, utility: .platform),
            "LINK": TokenomicsData(inflationRate: 0.0, emissionSchedule: .fixed, maxSupply: 1_000_000_000, currentSupply: 1_000_000_000, utility: .oracle),
            "UNI": TokenomicsData(inflationRate: 0.0, emissionSchedule: .fixed, maxSupply: 1_000_000_000, currentSupply: 1_000_000_000, utility: .defi),
            "AAVE": TokenomicsData(inflationRate: 0.0, emissionSchedule: .fixed, maxSupply: 16_000_000, currentSupply: 16_000_000, utility: .defi),
            "COMP": TokenomicsData(inflationRate: 0.0, emissionSchedule: .fixed, maxSupply: 10_000_000, currentSupply: 10_000_000, utility: .defi)
        ]

        return tokenomicsMap[symbol] ?? TokenomicsData(inflationRate: 0.05, emissionSchedule: .unknown, maxSupply: nil, currentSupply: 1_000_000_000, utility: .unknown)
    }

    private func calculateInflationPenalty(inflationRate: Double) -> Double {
        if inflationRate <= 0.0 {
            return 1.0
        } else if inflationRate <= 0.02 {
            return 0.9
        } else if inflationRate <= 0.05 {
            return 0.7
        } else if inflationRate <= 0.10 {
            return 0.5
        } else {
            return 0.2
        }
    }

    private func calculateEmissionScheduleScore(emissionSchedule: EmissionSchedule) -> Double {
        switch emissionSchedule {
        case .fixed: return 1.0
        case .deflationary: return 1.0
        case .decreasing: return 0.8
        case .increasing: return 0.3
        case .unknown: return 0.5
        }
    }

    private func calculateMaxSupplyScore(maxSupply: Double?, currentSupply: Double) -> Double {
        guard let maxSupply = maxSupply else { return 0.7 }

        let utilizationRatio = currentSupply / maxSupply

        if utilizationRatio < 0.5 {
            return 1.0
        } else if utilizationRatio < 0.8 {
            return 0.8
        } else if utilizationRatio < 0.95 {
            return 0.6
        } else {
            return 0.3
        }
    }

    private func calculateUtilityScore(symbol: String) -> Double {
        let tokenomicsData = getTokenomicsData(symbol: symbol)

        switch tokenomicsData.utility {
        case .storeOfValue: return 1.0
        case .platform: return 0.9
        case .defi: return 0.8
        case .oracle: return 0.7
        case .gaming: return 0.6
        case .nft: return 0.5
        case .meme: return 0.2
        case .unknown: return 0.5
        }
    }

    // MARK: - Exchange Data Helper Methods (Mock implementations)

    private func getSpreadForExchange(symbol: String, exchange: String) async throws -> Double {
        return Double.random(in: 0.0005...0.003)
    }

    private func getOrderBookDepth(symbol: String, exchange: String, tradeSize: Double) async throws -> Double {
        return tradeSize * Double.random(in: 1.5...5.0)
    }

    private func getExpectedSlippage(symbol: String, exchange: String, tradeSize: Double) async throws -> Double {
        return Double.random(in: 0.0005...0.002)
    }
}

// MARK: - Supporting Data Structures

public struct TokenomicsData {
    public let inflationRate: Double
    public let emissionSchedule: EmissionSchedule
    public let maxSupply: Double?
    public let currentSupply: Double
    public let utility: TokenUtility
}

public enum EmissionSchedule: String, Codable {
    case fixed = "fixed"
    case deflationary = "deflationary"
    case decreasing = "decreasing"
    case increasing = "increasing"
    case unknown = "unknown"
}

public enum TokenUtility: String, Codable {
    case storeOfValue = "store_of_value"
    case platform = "platform"
    case defi = "defi"
    case oracle = "oracle"
    case gaming = "gaming"
    case nft = "nft"
    case meme = "meme"
    case unknown = "unknown"
}

public struct MarketData: Codable, Sendable {
    public let symbol: String
    public let price: Double
    public let marketCap: Double
    public let volume24h: Double
    public let priceChange24h: Double
    public let priceChange7d: Double
    public let priceChange30d: Double

    public init(
        symbol: String,
        price: Double,
        marketCap: Double,
        volume24h: Double,
        priceChange24h: Double,
        priceChange7d: Double,
        priceChange30d: Double
    ) {
        self.symbol = symbol
        self.price = price
        self.marketCap = marketCap
        self.volume24h = volume24h
        self.priceChange24h = priceChange24h
        self.priceChange7d = priceChange7d
        self.priceChange30d = priceChange30d
    }
}
