import Foundation
import Utils
import Core

public protocol SwapAnalyzerProtocol {
    func evaluateSwap(
        fromAsset: String,
        toAsset: String,
        quantity: Double,
        exchange: String
    ) async throws -> SwapEvaluation

    func findOptimalSwaps(
        currentHoldings: [Holding],
        targetAllocation: AdjustedAllocation,
        exchanges: [String]
    ) async throws -> [SwapEvaluation]

    func shouldExecuteSwap(_ evaluation: SwapEvaluation) -> Bool
}

public class SwapAnalyzer: SwapAnalyzerProtocol {
    private let config: SmartVestorConfig
    private let exchangeConnectors: [String: ExchangeConnectorProtocol]
    private let crossExchangeAnalyzer: CrossExchangeAnalyzerProtocol?
    private let coinScoringEngine: CoinScoringEngineProtocol?
    private let persistence: PersistenceProtocol?
    private let logger: StructuredLogger
    private let marketDataProvider: MarketDataProviderProtocol?

    public init(
        config: SmartVestorConfig,
        exchangeConnectors: [String: ExchangeConnectorProtocol],
        crossExchangeAnalyzer: CrossExchangeAnalyzerProtocol? = nil,
        coinScoringEngine: CoinScoringEngineProtocol? = nil,
        persistence: PersistenceProtocol? = nil,
        marketDataProvider: MarketDataProviderProtocol? = nil
    ) {
        self.config = config
        self.exchangeConnectors = exchangeConnectors
        self.crossExchangeAnalyzer = crossExchangeAnalyzer
        self.coinScoringEngine = coinScoringEngine
        self.persistence = persistence
        self.marketDataProvider = marketDataProvider
        self.logger = StructuredLogger()
    }

    public func evaluateSwap(
        fromAsset: String,
        toAsset: String,
        quantity: Double,
        exchange: String
    ) async throws -> SwapEvaluation {
        logger.info(component: "SwapAnalyzer", event: "Evaluating swap", data: [
            "fromAsset": fromAsset,
            "toAsset": toAsset,
            "quantity": String(quantity),
            "exchange": exchange
        ])

        let swapCost = try await calculateSwapCost(
            fromAsset: fromAsset,
            toAsset: toAsset,
            quantity: quantity,
            exchange: exchange
        )

        let swapBenefit = try await calculateSwapBenefit(
            fromAsset: fromAsset,
            toAsset: toAsset,
            quantity: quantity,
            currentValueUSD: quantity * swapCost.totalCostUSD / (swapCost.costPercentage / 100.0 + 1.0)
        )

        let netValue = swapBenefit.totalBenefitUSD - swapCost.totalCostUSD
        let swapConfig = config.swapAnalysis ?? SwapAnalysisConfig()

        let isWorthwhile = netValue >= swapConfig.minProfitThreshold &&
                          swapBenefit.benefitPercentage >= swapConfig.minProfitPercentage &&
                          swapBenefit.benefitPercentage >= swapCost.costPercentage * swapConfig.safetyMultiplier &&
                          swapCost.costPercentage <= swapConfig.maxCostPercentage

        let confidence = calculateConfidence(
            cost: swapCost,
            benefit: swapBenefit,
            fromAsset: fromAsset,
            toAsset: toAsset,
            exchange: exchange
        )

        let fromPrice = try await getAssetPrice(asset: fromAsset, exchange: exchange)
        let toPrice = try await getAssetPrice(asset: toAsset, exchange: exchange)
        let sellValue = quantity * fromPrice
        let sellProceeds = sellValue - swapCost.sellFee - swapCost.sellSpread - swapCost.sellSlippage
        let buyValueAfterCosts = sellProceeds - swapCost.buyFee - swapCost.buySpread - swapCost.buySlippage
        let estimatedToQuantity = max(0.0, buyValueAfterCosts / toPrice)

        let evaluation = SwapEvaluation(
            fromAsset: fromAsset,
            toAsset: toAsset,
            fromQuantity: quantity,
            estimatedToQuantity: estimatedToQuantity,
            totalCost: swapCost,
            potentialBenefit: swapBenefit,
            netValue: netValue,
            isWorthwhile: isWorthwhile,
            confidence: confidence,
            exchange: exchange
        )

        logger.info(component: "SwapAnalyzer", event: "Swap evaluation completed", data: [
            "fromAsset": fromAsset,
            "toAsset": toAsset,
            "netValue": String(netValue),
            "isWorthwhile": String(isWorthwhile),
            "confidence": String(confidence)
        ])

        return evaluation
    }

    public func findOptimalSwaps(
        currentHoldings: [Holding],
        targetAllocation: AdjustedAllocation,
        exchanges: [String]
    ) async throws -> [SwapEvaluation] {
        logger.info(component: "SwapAnalyzer", event: "Finding optimal swaps", data: [
            "holdings_count": String(currentHoldings.count),
            "exchanges": exchanges.joined(separator: ",")
        ])

        var evaluations: [SwapEvaluation] = []
        let swapConfig = config.swapAnalysis ?? SwapAnalysisConfig()

        guard swapConfig.enabled else {
            return evaluations
        }

        let prices = try await getCurrentPrices(assets: Array(Set(currentHoldings.map { $0.asset })))

        let totalPortfolioValue = currentHoldings.reduce(0.0) { total, holding in
            let price = prices[holding.asset] ?? 0.0
            return total + (holding.total * price)
        }

        var targetWeights: [String: Double] = [:]
        targetWeights["BTC"] = targetAllocation.btc
        targetWeights["ETH"] = targetAllocation.eth
        for altcoin in targetAllocation.altcoins {
            targetWeights[altcoin.symbol] = altcoin.percentage
        }

        for holding in currentHoldings {
            let currentValue = holding.total * (prices[holding.asset] ?? 0.0)
            let currentWeight = totalPortfolioValue > 0 ? currentValue / totalPortfolioValue : 0.0
            let targetWeight = targetWeights[holding.asset] ?? 0.0

            if currentWeight > targetWeight * 1.1 {
                let excessValue = currentValue - (totalPortfolioValue * targetWeight)
                let excessQuantity = excessValue / (prices[holding.asset] ?? 1.0)

                for (symbol, targetWt) in targetWeights where symbol != holding.asset {
                    let currentWt = currentHoldings
                        .first { $0.asset == symbol }
                        .map { ($0.total * (prices[symbol] ?? 0.0)) / totalPortfolioValue } ?? 0.0

                    if currentWt < targetWt * 0.9 {
                        let neededValue = (totalPortfolioValue * targetWt) - (currentHoldings
                            .first { $0.asset == symbol }
                            .map { $0.total * (prices[symbol] ?? 0.0) } ?? 0.0)

                        if excessValue >= neededValue * 0.8 {
                            for exchange in exchanges {
                                guard exchangeConnectors[exchange] != nil else { continue }
                                do {
                                    let evaluation = try await evaluateSwap(
                                        fromAsset: holding.asset,
                                        toAsset: symbol,
                                        quantity: min(excessQuantity, neededValue / (prices[holding.asset] ?? 1.0)),
                                        exchange: exchange
                                    )

                                    if evaluation.isWorthwhile {
                                        evaluations.append(evaluation)
                                    }
                                } catch {
                                    logger.warn(component: "SwapAnalyzer", event: "Failed to evaluate swap", data: [
                                        "fromAsset": holding.asset,
                                        "toAsset": symbol,
                                        "exchange": exchange,
                                        "error": error.localizedDescription
                                    ])
                                }
                            }
                        }
                    }
                }
            }
        }

        evaluations.sort { $0.netValue > $1.netValue }
        let maxSwaps = min(evaluations.count, swapConfig.maxSwapsPerCycle)

        return Array(evaluations.prefix(maxSwaps))
    }

    public func shouldExecuteSwap(_ evaluation: SwapEvaluation) -> Bool {
        let swapConfig = config.swapAnalysis ?? SwapAnalysisConfig()

        guard evaluation.isWorthwhile else { return false }
        guard evaluation.netValue >= swapConfig.minProfitThreshold else { return false }
        guard evaluation.potentialBenefit.benefitPercentage >=
              evaluation.totalCost.costPercentage * swapConfig.safetyMultiplier else {
            return false
        }
        guard evaluation.totalCost.costPercentage <= swapConfig.maxCostPercentage else {
            return false
        }
        guard evaluation.confidence >= swapConfig.minConfidence else { return false }

        return true
    }

    private func calculateSwapCost(
        fromAsset: String,
        toAsset: String,
        quantity: Double,
        exchange: String
    ) async throws -> SwapCost {
        guard let connector = exchangeConnectors[exchange] else {
            throw SmartVestorError.exchangeError("No connector available for exchange: \(exchange)")
        }

        let fromPair = "\(fromAsset)USDC"
        let toPair = "\(toAsset)USDC"

        let fromOrderBook = try await connector.getOrderBook(symbol: fromPair)
        let toOrderBook = try await connector.getOrderBook(symbol: toPair)

        let fromBestBid = fromOrderBook.bids.first?.price ?? 0.0
        let fromBestAsk = fromOrderBook.asks.first?.price ?? 0.0
        let fromMid = (fromBestBid + fromBestAsk) / 2.0
        let fromSpread = fromBestAsk - fromBestBid
        let fromSpreadPercentage = fromMid > 0 ? (fromSpread / fromMid) : 0.0

        let toBestBid = toOrderBook.bids.first?.price ?? 0.0
        let toBestAsk = toOrderBook.asks.first?.price ?? 0.0
        let toMid = (toBestBid + toBestAsk) / 2.0
        let toSpread = toBestAsk - toBestBid
        let toSpreadPercentage = toMid > 0 ? (toSpread / toMid) : 0.0

        let makerFee = getMakerFee(for: exchange)
        let _ = getTakerFee(for: exchange)

        let sellPrice = fromBestBid
        let sellValue = quantity * sellPrice
        let sellFee = sellValue * makerFee
        let sellSpreadCost = sellValue * fromSpreadPercentage * 0.5
        let sellSlippage = calculateSlippage(
            orderBook: fromOrderBook,
            quantity: quantity,
            side: .sell
        ) * sellValue

        let buyValue = sellValue - sellFee - sellSpreadCost - sellSlippage
        let buyPrice = toBestAsk
        let buyQuantity = buyValue / buyPrice
        let buyFee = buyValue * makerFee
        let buySpreadCost = buyValue * toSpreadPercentage * 0.5
        let buySlippage = calculateSlippage(
            orderBook: toOrderBook,
            quantity: buyQuantity,
            side: .buy
        ) * buyValue

        let totalCostUSD = sellFee + sellSpreadCost + sellSlippage + buyFee + buySpreadCost + buySlippage
        let costPercentage = sellValue > 0 ? (totalCostUSD / sellValue) * 100.0 : 0.0

        return SwapCost(
            sellFee: sellFee,
            buyFee: buyFee,
            sellSpread: sellSpreadCost,
            buySpread: buySpreadCost,
            sellSlippage: sellSlippage,
            buySlippage: buySlippage,
            totalCostUSD: totalCostUSD,
            costPercentage: costPercentage
        )
    }

    private func calculateSwapBenefit(
        fromAsset: String,
        toAsset: String,
        quantity: Double,
        currentValueUSD: Double
    ) async throws -> SwapBenefit {
        let fromExpectedReturn = try await getExpectedReturn(asset: fromAsset)
        let toExpectedReturn = try await getExpectedReturn(asset: toAsset)

        let expectedReturnDifferential = toExpectedReturn - fromExpectedReturn

        let currentPortfolioReturn = try await getCurrentPortfolioReturn()
        let projectedPortfolioReturn = try await getProjectedPortfolioReturn(
            fromAsset: fromAsset,
            toAsset: toAsset,
            fromWeight: try await getAssetWeight(asset: fromAsset),
            toWeight: try await getAssetWeight(asset: toAsset),
            returnDifferential: expectedReturnDifferential
        )

        let portfolioImprovement = projectedPortfolioReturn - currentPortfolioReturn

        let allocationAlignment = try await calculateAllocationAlignment(
            fromAsset: fromAsset,
            toAsset: toAsset
        )

        let totalBenefitUSD = currentValueUSD * expectedReturnDifferential + (currentValueUSD * portfolioImprovement)
        let benefitPercentage = expectedReturnDifferential + portfolioImprovement

        let riskReduction: Double? = try? await calculateRiskReduction(
            fromAsset: fromAsset,
            toAsset: toAsset
        )

        return SwapBenefit(
            expectedReturnDifferential: expectedReturnDifferential,
            portfolioImprovement: portfolioImprovement,
            riskReduction: riskReduction,
            allocationAlignment: allocationAlignment,
            totalBenefitUSD: totalBenefitUSD,
            benefitPercentage: benefitPercentage
        )
    }

    private func calculateNetValue(cost: SwapCost, benefit: SwapBenefit) -> Double {
        return benefit.totalBenefitUSD - cost.totalCostUSD
    }

    private func calculateConfidence(
        cost: SwapCost,
        benefit: SwapBenefit,
        fromAsset: String,
        toAsset: String,
        exchange: String
    ) -> Double {
        var confidence: Double = 0.5

        if cost.costPercentage < 1.0 {
            confidence += 0.2
        } else if cost.costPercentage < 2.0 {
            confidence += 0.1
        }

        if benefit.benefitPercentage > 0.01 {
            confidence += 0.15
        } else if benefit.benefitPercentage > 0.005 {
            confidence += 0.1
        }

        if benefit.allocationAlignment > 0.1 {
            confidence += 0.1
        }

        if exchangeConnectors[exchange] != nil {
            confidence += 0.05
        }

        return min(1.0, confidence)
    }

    private func getMakerFee(for exchange: String) -> Double {
        if let exchangeConfig = config.exchanges.first(where: { $0.name.lowercased() == exchange.lowercased() }) {
            return exchangeConfig.rateLimit.requestsPerSecond > 0 ? 0.001 : 0.002
        }

        switch exchange.lowercased() {
        case "kraken": return 0.0016
        case "coinbase": return 0.005
        case "gemini": return 0.0025
        case "robinhood": return 0.0
        case "binance": return 0.001
        default: return 0.002
        }
    }

    private func getTakerFee(for exchange: String) -> Double {
        switch exchange.lowercased() {
        case "kraken": return 0.0026
        case "coinbase": return 0.005
        case "gemini": return 0.0035
        case "robinhood": return 0.0
        case "binance": return 0.001
        default: return 0.003
        }
    }

    private func calculateSlippage(
        orderBook: Core.OrderBook,
        quantity: Double,
        side: OrderSide
    ) -> Double {
        let entries = side == .buy ? orderBook.asks : orderBook.bids
        var remaining = quantity
        var totalCost = 0.0

        for entry in entries {
            let filled = min(remaining, entry.quantity)
            totalCost += filled * entry.price
            remaining -= filled
            if remaining <= 0 { break }
        }

        if quantity <= 0 { return 0.0 }

        let averagePrice = totalCost / quantity
        let bestPrice = entries.first?.price ?? averagePrice
        let slippage = bestPrice > 0 ? abs(averagePrice - bestPrice) / bestPrice : 0.0

        return slippage
    }

    private func getAssetPrice(asset: String, exchange: String) async throws -> Double {
        if let provider = marketDataProvider {
            let prices = try await provider.getCurrentPrices(symbols: [asset])
            return prices[asset] ?? 0.0
        }

        if let connector = exchangeConnectors[exchange] {
            let pair = "\(asset)USDC"
            let orderBook = try await connector.getOrderBook(symbol: pair)
            let bestBid = orderBook.bids.first?.price ?? 0.0
            let bestAsk = orderBook.asks.first?.price ?? 0.0
            return (bestBid + bestAsk) / 2.0
        }

        return 0.0
    }

    private func getCurrentPrices(assets: [String]) async throws -> [String: Double] {
        if let provider = marketDataProvider {
            return try await provider.getCurrentPrices(symbols: assets)
        }

        var prices: [String: Double] = [:]
        for asset in assets {
            for (exchange, _) in exchangeConnectors {
                if let price = try? await getAssetPrice(asset: asset, exchange: exchange), price > 0 {
                    prices[asset] = price
                    break
                }
            }
        }

        return prices
    }

    private func getExpectedReturn(asset: String) async throws -> Double {
        if let scoringEngine = coinScoringEngine {
            let score = try await scoringEngine.scoreCoin(symbol: asset)

            let baseReturn = 0.12
            let momentumAdjustment = score.momentumScore > 0.7 ? 1.2 : 1.0
            let technicalAdjustment = score.technicalScore > 0.7 ? 1.1 : 1.0
            let fundamentalAdjustment = score.fundamentalScore > 0.7 ? 1.15 : 1.0

            return baseReturn * momentumAdjustment * technicalAdjustment * fundamentalAdjustment
        }

        if let provider = marketDataProvider {
            let historicalData = try? await provider.getHistoricalData(
                startDate: Date().addingTimeInterval(-7 * 24 * 3600),
                endDate: Date(),
                symbols: [asset]
            )

            if let dataPoints = historicalData?[asset], dataPoints.count >= 2 {
                let firstPrice = dataPoints.first?.price ?? 0.0
                let lastPrice = dataPoints.last?.price ?? 0.0
                if firstPrice > 0 {
                    return (lastPrice - firstPrice) / firstPrice
                }
            }
        }

        return 0.0
    }

    private func getCurrentPortfolioReturn() async throws -> Double {
        guard let persistence = persistence else { return 0.0 }

        let holdings = try persistence.getAllAccounts()
        guard !holdings.isEmpty else { return 0.0 }

        var totalValue = 0.0
        var weightedReturn = 0.0

        let prices = try await getCurrentPrices(assets: Array(Set(holdings.map { $0.asset })))

        for holding in holdings {
            let price = prices[holding.asset] ?? 0.0
            let value = holding.total * price
            totalValue += value

            let expectedReturn = try await getExpectedReturn(asset: holding.asset)
            weightedReturn += value * expectedReturn
        }

        return totalValue > 0 ? weightedReturn / totalValue : 0.0
    }

    private func getProjectedPortfolioReturn(
        fromAsset: String,
        toAsset: String,
        fromWeight: Double,
        toWeight: Double,
        returnDifferential: Double
    ) async throws -> Double {
        let currentReturn = try await getCurrentPortfolioReturn()
        return currentReturn + (returnDifferential * (fromWeight + toWeight) / 2.0)
    }

    private func getAssetWeight(asset: String) async throws -> Double {
        guard let persistence = persistence else { return 0.0 }

        let holdings = try persistence.getAllAccounts()
        let prices = try await getCurrentPrices(assets: Array(Set(holdings.map { $0.asset })))

        let totalValue = holdings.reduce(0.0) { total, h in
            total + (h.total * (prices[h.asset] ?? 0.0))
        }

        let assetValue = holdings
            .first { $0.asset == asset }
            .map { $0.total * (prices[asset] ?? 0.0) } ?? 0.0

        return totalValue > 0 ? assetValue / totalValue : 0.0
    }

    private func calculateAllocationAlignment(
        fromAsset: String,
        toAsset: String
    ) async throws -> Double {
        let targetAllocation = config.baseAllocation

        var fromTarget = 0.0
        var toTarget = 0.0

        if fromAsset == "BTC" {
            fromTarget = targetAllocation.btc
        } else if fromAsset == "ETH" {
            fromTarget = targetAllocation.eth
        } else {
            fromTarget = targetAllocation.altcoins / 10.0
        }

        if toAsset == "BTC" {
            toTarget = targetAllocation.btc
        } else if toAsset == "ETH" {
            toTarget = targetAllocation.eth
        } else {
            toTarget = targetAllocation.altcoins / 10.0
        }

        guard let persistence = persistence else { return 0.0 }

        let holdings = try persistence.getAllAccounts()
        let prices = try await getCurrentPrices(assets: Array(Set(holdings.map { $0.asset })))

        let totalValue = holdings.reduce(0.0) { total, h in
            total + (h.total * (prices[h.asset] ?? 0.0))
        }

        let fromValue = holdings
            .first { $0.asset == fromAsset }
            .map { $0.total * (prices[fromAsset] ?? 0.0) } ?? 0.0
        let toValue = holdings
            .first { $0.asset == toAsset }
            .map { $0.total * (prices[toAsset] ?? 0.0) } ?? 0.0

        let fromCurrent = totalValue > 0 ? fromValue / totalValue : 0.0
        let toCurrent = totalValue > 0 ? toValue / totalValue : 0.0

        let fromDeviation = abs(fromCurrent - fromTarget)
        let toDeviation = abs(toCurrent - toTarget)

        let projectedFromDeviation = max(0.0, fromDeviation - 0.05)
        let projectedToDeviation = max(0.0, toDeviation - 0.05)

        let improvement = (fromDeviation - projectedFromDeviation) + (toDeviation - projectedToDeviation)

        return improvement
    }

    private func calculateRiskReduction(
        fromAsset: String,
        toAsset: String
    ) async throws -> Double? {
        guard let scoringEngine = coinScoringEngine else { return nil }

        let fromScore = try? await scoringEngine.scoreCoin(symbol: fromAsset)
        let toScore = try? await scoringEngine.scoreCoin(symbol: toAsset)

        guard let from = fromScore, let to = toScore else { return nil }

        let fromRisk = from.volatilityScore * (from.riskLevel == .high || from.riskLevel == .veryHigh ? 1.5 : 1.0)
        let toRisk = to.volatilityScore * (to.riskLevel == .high || to.riskLevel == .veryHigh ? 1.5 : 1.0)

        return max(0.0, fromRisk - toRisk)
    }
}
