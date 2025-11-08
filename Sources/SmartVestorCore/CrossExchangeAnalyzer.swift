import Foundation
import Utils
import Core

public protocol CrossExchangeAnalyzerProtocol {
    func analyzeSpreads(for assets: [String]) async throws -> [String: SpreadAnalysis]
    func findBestExchange(for asset: String) async throws -> String?
    func calculateTotalCost(asset: String, exchange: String, quantity: Double) async throws -> Double
}

public class CrossExchangeAnalyzer: CrossExchangeAnalyzerProtocol {
    private let config: SmartVestorConfig
    private let exchangeConnectors: [String: ExchangeConnectorProtocol]
    private let logger: StructuredLogger

    public init(
        config: SmartVestorConfig,
        exchangeConnectors: [String: ExchangeConnectorProtocol]
    ) {
        self.config = config
        self.exchangeConnectors = exchangeConnectors
        self.logger = StructuredLogger()
    }

    public func analyzeSpreads(for assets: [String]) async throws -> [String: SpreadAnalysis] {
        logger.info(component: "CrossExchangeAnalyzer", event: "Analyzing spreads for assets", data: [
            "assets": assets.joined(separator: ",")
        ])

        var spreadAnalyses: [String: SpreadAnalysis] = [:]

        for asset in assets {
            do {
                let analysis = try await analyzeAssetSpread(asset)
                spreadAnalyses[asset] = analysis

                logger.info(component: "CrossExchangeAnalyzer", event: "Spread analysis completed for asset", data: [
                    "asset": asset,
                    "best_exchange": analysis.bestExchange,
                    "total_cost": String(analysis.totalCost),
                    "meets_fee_cap": String(analysis.meetsFeeCap)
                ])
            } catch {
                logger.error(component: "CrossExchangeAnalyzer", event: "Failed to analyze spread for asset", data: [
                    "asset": asset,
                    "error": error.localizedDescription
                ])
            }
        }

        return spreadAnalyses
    }

    private func analyzeAssetSpread(_ asset: String) async throws -> SpreadAnalysis {
        let pair = "\(asset)USDC"
        var exchangeSpreads: [String: ExchangeSpread] = [:]

        for exchangeConfig in config.exchanges where exchangeConfig.enabled {
            guard let connector = exchangeConnectors[exchangeConfig.name] else {
                continue
            }

            do {
                let coreOrderBook = try await connector.getOrderBook(symbol: pair)
                let orderBook = OrderBook(from: coreOrderBook, symbol: pair)
                let spread = try calculateExchangeSpread(
                    orderBook: orderBook,
                    exchange: exchangeConfig.name,
                    asset: asset
                )
                exchangeSpreads[exchangeConfig.name] = spread
            } catch {
                logger.warn(component: "CrossExchangeAnalyzer", event: "Failed to get order book for exchange", data: [
                    "exchange": exchangeConfig.name,
                    "asset": asset,
                    "error": error.localizedDescription
                ])
            }
        }

        guard !exchangeSpreads.isEmpty else {
            throw SmartVestorError.exchangeError("No exchange data available for \(asset)")
        }

        guard let bestExchangePair = exchangeSpreads.min(by: { $0.value.totalCost < $1.value.totalCost }),
              let bestSpread = exchangeSpreads[bestExchangePair.key] else {
            throw SmartVestorError.exchangeError("Unable to determine best exchange for \(asset)")
        }
        let bestExchange = bestExchangePair.key
        let spreadPercentage = (bestSpread.totalCost / bestSpread.price) * 100

        return SpreadAnalysis(
            pair: pair,
            exchanges: exchangeSpreads,
            bestExchange: bestExchange,
            totalCost: bestSpread.totalCost,
            spreadPercentage: spreadPercentage,
            meetsFeeCap: spreadPercentage <= (config.feeCap * 100)
        )
    }

    private func calculateExchangeSpread(
        orderBook: OrderBook,
        exchange: String,
        asset: String
    ) throws -> ExchangeSpread {
        guard let bestBid = orderBook.bids.first,
              let bestAsk = orderBook.asks.first else {
            throw SmartVestorError.exchangeError("Invalid order book for \(exchange)")
        }

        let midPrice = (bestBid.price + bestAsk.price) / 2.0
        let spread = bestAsk.price - bestBid.price
        let spreadPercentage = (spread / midPrice) * 100

        let makerFee = getMakerFee(for: exchange)
        let takerFee = getTakerFee(for: exchange)
        let expectedSlippage = calculateExpectedSlippage(spreadPercentage: spreadPercentage)

        let totalCost = midPrice + (midPrice * makerFee) + (midPrice * expectedSlippage)

        return ExchangeSpread(
            price: midPrice,
            makerFee: makerFee,
            takerFee: takerFee,
            expectedSlippage: expectedSlippage,
            totalCost: totalCost
        )
    }

    private func getMakerFee(for exchange: String) -> Double {
        switch exchange.lowercased() {
        case "kraken":
            return 0.0016
        case "coinbase":
            return 0.005
        case "gemini":
            return 0.0025
        case "binance":
            return 0.001
        default:
            return 0.002
        }
    }

    private func getTakerFee(for exchange: String) -> Double {
        switch exchange.lowercased() {
        case "kraken":
            return 0.0026
        case "coinbase":
            return 0.005
        case "gemini":
            return 0.0035
        case "binance":
            return 0.001
        default:
            return 0.003
        }
    }

    private func calculateExpectedSlippage(spreadPercentage: Double) -> Double {
        if spreadPercentage < 0.1 {
            return 0.0001
        } else if spreadPercentage < 0.5 {
            return 0.0005
        } else if spreadPercentage < 1.0 {
            return 0.001
        } else {
            return 0.002
        }
    }

    public func findBestExchange(for asset: String) async throws -> String? {
        let analysis = try await analyzeAssetSpread(asset)
        return analysis.meetsFeeCap ? analysis.bestExchange : nil
    }

    public func calculateTotalCost(asset: String, exchange: String, quantity: Double) async throws -> Double {
        let pair = "\(asset)USDC"

        guard let connector = exchangeConnectors[exchange] else {
            throw SmartVestorError.exchangeError("No connector available for exchange: \(exchange)")
        }

        let coreOrderBook = try await connector.getOrderBook(symbol: pair)
        let orderBook = OrderBook(from: coreOrderBook, symbol: pair)
        let spread = try calculateExchangeSpread(orderBook: orderBook, exchange: exchange, asset: asset)

        return spread.totalCost * quantity
    }
}

public class MockCrossExchangeAnalyzer: CrossExchangeAnalyzerProtocol {
    private let mockSpreads: [String: SpreadAnalysis]

    public init(mockSpreads: [String: SpreadAnalysis] = [:]) {
        self.mockSpreads = mockSpreads
    }

    public func analyzeSpreads(for assets: [String]) async throws -> [String: SpreadAnalysis] {
        var result: [String: SpreadAnalysis] = [:]

        for asset in assets {
            if let mockSpread = mockSpreads[asset] {
                result[asset] = mockSpread
            } else {
                let mockAnalysis = createMockSpreadAnalysis(for: asset)
                result[asset] = mockAnalysis
            }
        }

        return result
    }

    public func findBestExchange(for asset: String) async throws -> String? {
        let analysis = try await analyzeSpreads(for: [asset])
        return analysis[asset]?.bestExchange
    }

    public func calculateTotalCost(asset: String, exchange: String, quantity: Double) async throws -> Double {
        let analysis = try await analyzeSpreads(for: [asset])
        guard let spreadAnalysis = analysis[asset] else {
            throw SmartVestorError.exchangeError("No analysis available for \(asset)")
        }

        return spreadAnalysis.totalCost * quantity
    }

    private func createMockSpreadAnalysis(for asset: String) -> SpreadAnalysis {
        let mockPrice = generateMockPrice(for: asset)
        let makerFee = 0.001
        let expectedSlippage = 0.0005
        let totalCost = mockPrice + (mockPrice * makerFee) + (mockPrice * expectedSlippage)

        let exchangeSpread = ExchangeSpread(
            price: mockPrice,
            makerFee: makerFee,
            takerFee: 0.002,
            expectedSlippage: expectedSlippage,
            totalCost: totalCost
        )

        return SpreadAnalysis(
            pair: "\(asset)USDC",
            exchanges: ["kraken": exchangeSpread],
            bestExchange: "kraken",
            totalCost: totalCost,
            spreadPercentage: (totalCost / mockPrice) * 100,
            meetsFeeCap: true
        )
    }

    private func generateMockPrice(for asset: String) -> Double {
        switch asset {
        case "BTC":
            return Double.random(in: 40000...50000)
        case "ETH":
            return Double.random(in: 2500...3500)
        case "ADA":
            return Double.random(in: 0.4...0.6)
        case "DOT":
            return Double.random(in: 6...10)
        case "LINK":
            return Double.random(in: 12...18)
        default:
            return Double.random(in: 50...150)
        }
    }
}

public struct OrderBook: Codable {
    public let symbol: String
    public let bids: [OrderBookEntry]
    public let asks: [OrderBookEntry]
    public let timestamp: Date

    public init(symbol: String, bids: [OrderBookEntry], asks: [OrderBookEntry], timestamp: Date = Date()) {
        self.symbol = symbol
        self.bids = bids
        self.asks = asks
        self.timestamp = timestamp
    }
}

public struct OrderBookEntry: Codable {
    public let price: Double
    public let quantity: Double

    public init(price: Double, quantity: Double) {
        self.price = price
        self.quantity = quantity
    }
}

// MARK: - Conversion Extensions

extension OrderBook {
    init(from coreOrderBook: Core.OrderBook, symbol: String) {
        self.symbol = symbol
        self.bids = coreOrderBook.bids.map { OrderBookEntry(price: $0.price, quantity: $0.quantity) }
        self.asks = coreOrderBook.asks.map { OrderBookEntry(price: $0.price, quantity: $0.quantity) }
        self.timestamp = Date()
    }
}
