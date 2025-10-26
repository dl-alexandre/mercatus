import Foundation
import Testing
@testable import Core

@Suite
struct SpreadDetectorTests {
    @Test
    func emitsProfitableSpreadWhenThresholdsMet() async throws {
        let detector = SpreadDetector(
            config: makeConfig(minSpread: 0.01, maxLatency: 50),
            logger: nil
        )

        let stream = await detector.analysisStream()
        var iterator = stream.makeAsyncIterator()

        let binanceQuote = NormalizedPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "99.00")!,
            ask: Decimal(string: "100.00")!,
            rawTimestamp: Date(),
            normalizedTime: 1.000
        )

        let coinbaseQuote = NormalizedPriceData(
            exchange: "Coinbase",
            symbol: "BTC-USD",
            bid: Decimal(string: "101.50")!,
            ask: Decimal(string: "102.00")!,
            rawTimestamp: Date().addingTimeInterval(0.01),
            normalizedTime: 1.010
        )

        await detector.ingest(binanceQuote)
        await detector.ingest(coinbaseQuote)

        let analysis = try #require(await iterator.next())

        #expect(analysis.symbol == "BTC-USD")
        #expect(analysis.buyExchange == "Binance")
        #expect(analysis.sellExchange == "Coinbase")
        #expect(analysis.buyPrice == Decimal(string: "100.00"))
        #expect(analysis.sellPrice == Decimal(string: "101.50"))
        #expect(analysis.spreadPercentage == Decimal(string: "0.015"))
        #expect(abs(analysis.latencyMilliseconds - 10.0) < 1e-6)
        #expect(analysis.isProfitable)
    }

    @Test
    func marksSpreadUnprofitableWhenLatencyTooHigh() async throws {
        let detector = SpreadDetector(
            config: makeConfig(minSpread: 0.01, maxLatency: 50),
            logger: nil
        )

        let stream = await detector.analysisStream()
        var iterator = stream.makeAsyncIterator()

        let binanceQuote = NormalizedPriceData(
            exchange: "Binance",
            symbol: "ETH-USD",
            bid: Decimal(string: "2000.00")!,
            ask: Decimal(string: "2001.00")!,
            rawTimestamp: Date(),
            normalizedTime: 5.000
        )

        let coinbaseQuote = NormalizedPriceData(
            exchange: "Coinbase",
            symbol: "ETH-USD",
            bid: Decimal(string: "2004.00")!,
            ask: Decimal(string: "2005.00")!,
            rawTimestamp: Date().addingTimeInterval(0.2),
            normalizedTime: 5.200
        )

        await detector.ingest(binanceQuote)
        await detector.ingest(coinbaseQuote)

        let analysis = try #require(await iterator.next())

        #expect(analysis.symbol == "ETH-USD")
        #expect(analysis.isProfitable == false)
        #expect(abs(analysis.latencyMilliseconds - 200.0) < 1e-6)
        #expect(analysis.buyExchange == "Binance")
        #expect(analysis.sellExchange == "Coinbase")
        let spread = NSDecimalNumber(decimal: analysis.spreadPercentage).doubleValue
        #expect(abs(spread - 0.0014992503748125937) < 1e-12)
    }

    @Test
    func marksSpreadUnprofitableWhenBelowThreshold() async throws {
        let detector = SpreadDetector(
            config: makeConfig(minSpread: 0.02, maxLatency: 100),
            logger: nil
        )

        let stream = await detector.analysisStream()
        var iterator = stream.makeAsyncIterator()

        let quote1 = NormalizedPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "100.00")!,
            ask: Decimal(string: "100.50")!,
            rawTimestamp: Date(),
            normalizedTime: 1.000
        )

        let quote2 = NormalizedPriceData(
            exchange: "Coinbase",
            symbol: "BTC-USD",
            bid: Decimal(string: "101.00")!,
            ask: Decimal(string: "101.50")!,
            rawTimestamp: Date().addingTimeInterval(0.01),
            normalizedTime: 1.010
        )

        await detector.ingest(quote1)
        await detector.ingest(quote2)

        let analysis = try #require(await iterator.next())

        let spread = NSDecimalNumber(decimal: analysis.spreadPercentage).doubleValue
        #expect(spread < 0.02)
        #expect(analysis.isProfitable == false)
    }

    @Test
    func calculatesSpreadPercentageCorrectly() async throws {
        let detector = SpreadDetector(
            config: makeConfig(minSpread: 0.01, maxLatency: 100),
            logger: nil
        )

        let stream = await detector.analysisStream()
        var iterator = stream.makeAsyncIterator()

        let buyPrice: Decimal = 1000
        let sellPrice: Decimal = 1020
        let expectedSpread = (sellPrice - buyPrice) / buyPrice

        let quote1 = NormalizedPriceData(
            exchange: "Binance",
            symbol: "ETH-USD",
            bid: Decimal(string: "999.00")!,
            ask: buyPrice,
            rawTimestamp: Date(),
            normalizedTime: 1.000
        )

        let quote2 = NormalizedPriceData(
            exchange: "Coinbase",
            symbol: "ETH-USD",
            bid: sellPrice,
            ask: Decimal(string: "1021.00")!,
            rawTimestamp: Date(),
            normalizedTime: 1.005
        )

        await detector.ingest(quote1)
        await detector.ingest(quote2)

        let analysis = try #require(await iterator.next())

        #expect(analysis.spreadPercentage == expectedSpread)
        #expect(analysis.buyPrice == buyPrice)
        #expect(analysis.sellPrice == sellPrice)
    }

    @Test
    func ignoresQuotesFromSameExchange() async throws {
        let detector = SpreadDetector(
            config: makeConfig(minSpread: 0.01, maxLatency: 100),
            logger: nil
        )

        let stream = await detector.analysisStream()
        var iterator = stream.makeAsyncIterator()

        let binanceQuote1 = NormalizedPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "100.00")!,
            ask: Decimal(string: "100.50")!,
            rawTimestamp: Date(),
            normalizedTime: 1.000
        )

        let binanceQuote2 = NormalizedPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "105.00")!,
            ask: Decimal(string: "105.50")!,
            rawTimestamp: Date(),
            normalizedTime: 1.010
        )

        let coinbaseQuote = NormalizedPriceData(
            exchange: "Coinbase",
            symbol: "BTC-USD",
            bid: Decimal(string: "102.00")!,
            ask: Decimal(string: "102.50")!,
            rawTimestamp: Date(),
            normalizedTime: 1.020
        )

        await detector.ingest(binanceQuote1)
        await detector.ingest(binanceQuote2)
        await detector.ingest(coinbaseQuote)

        let analysis = try #require(await iterator.next())
        #expect(analysis.buyExchange == "Coinbase")
        #expect(analysis.sellExchange == "Binance")
        #expect(analysis.buyPrice == Decimal(string: "102.50"))
        #expect(analysis.sellPrice == Decimal(string: "105.00"))
    }

    @Test
    func handlesMultipleTradingPairs() async throws {
        let detector = SpreadDetector(
            config: makeConfig(minSpread: 0.01, maxLatency: 100),
            logger: nil
        )

        let stream = await detector.analysisStream()
        var iterator = stream.makeAsyncIterator()

        let btcQuote1 = NormalizedPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "50000.00")!,
            ask: Decimal(string: "50100.00")!,
            rawTimestamp: Date(),
            normalizedTime: 1.000
        )

        let btcQuote2 = NormalizedPriceData(
            exchange: "Coinbase",
            symbol: "BTC-USD",
            bid: Decimal(string: "50700.00")!,
            ask: Decimal(string: "50800.00")!,
            rawTimestamp: Date(),
            normalizedTime: 1.010
        )

        let ethQuote1 = NormalizedPriceData(
            exchange: "Binance",
            symbol: "ETH-USD",
            bid: Decimal(string: "3000.00")!,
            ask: Decimal(string: "3010.00")!,
            rawTimestamp: Date(),
            normalizedTime: 1.020
        )

        let ethQuote2 = NormalizedPriceData(
            exchange: "Coinbase",
            symbol: "ETH-USD",
            bid: Decimal(string: "3050.00")!,
            ask: Decimal(string: "3060.00")!,
            rawTimestamp: Date(),
            normalizedTime: 1.030
        )

        await detector.ingest(btcQuote1)
        await detector.ingest(btcQuote2)
        await detector.ingest(ethQuote1)
        await detector.ingest(ethQuote2)

        let btcAnalysis = try #require(await iterator.next())
        let ethAnalysis = try #require(await iterator.next())

        #expect(btcAnalysis.symbol == "BTC-USD")
        #expect(ethAnalysis.symbol == "ETH-USD")
    }

    @Test
    func updatesQuotesForSameExchange() async throws {
        let detector = SpreadDetector(
            config: makeConfig(minSpread: 0.01, maxLatency: 100),
            logger: nil
        )

        let stream = await detector.analysisStream()
        var iterator = stream.makeAsyncIterator()

        let quote1 = NormalizedPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "100.00")!,
            ask: Decimal(string: "100.50")!,
            rawTimestamp: Date(),
            normalizedTime: 1.000
        )

        let quote2 = NormalizedPriceData(
            exchange: "Coinbase",
            symbol: "BTC-USD",
            bid: Decimal(string: "101.00")!,
            ask: Decimal(string: "101.50")!,
            rawTimestamp: Date(),
            normalizedTime: 1.010
        )

        let quote3 = NormalizedPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "99.50")!,
            ask: Decimal(string: "100.00")!,
            rawTimestamp: Date(),
            normalizedTime: 1.020
        )

        await detector.ingest(quote1)
        await detector.ingest(quote2)

        let analysis1 = try #require(await iterator.next())

        await detector.ingest(quote3)

        let analysis2 = try #require(await iterator.next())

        #expect(analysis1.buyPrice == Decimal(string: "100.50"))
        #expect(analysis2.buyPrice == Decimal(string: "100.00"))
    }

    @Test
    func calculatesLatencyFromNormalizedTimes() async throws {
        let detector = SpreadDetector(
            config: makeConfig(minSpread: 0.01, maxLatency: 200),
            logger: nil
        )

        let stream = await detector.analysisStream()
        var iterator = stream.makeAsyncIterator()

        let quote1 = NormalizedPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "100.00")!,
            ask: Decimal(string: "100.50")!,
            rawTimestamp: Date(),
            normalizedTime: 5.000
        )

        let quote2 = NormalizedPriceData(
            exchange: "Coinbase",
            symbol: "BTC-USD",
            bid: Decimal(string: "102.00")!,
            ask: Decimal(string: "102.50")!,
            rawTimestamp: Date(),
            normalizedTime: 5.123
        )

        await detector.ingest(quote1)
        await detector.ingest(quote2)

        let analysis = try #require(await iterator.next())

        #expect(abs(analysis.latencyMilliseconds - 123.0) < 1e-6)
    }

    @Test
    func handlesZeroPriceGracefully() async throws {
        let detector = SpreadDetector(
            config: makeConfig(minSpread: 0.01, maxLatency: 100),
            logger: nil
        )

        let stream = await detector.analysisStream()
        var iterator = stream.makeAsyncIterator()

        let zeroQuote = NormalizedPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "0.00")!,
            ask: Decimal(string: "0.00")!,
            rawTimestamp: Date(),
            normalizedTime: 1.000
        )

        let validQuote1 = NormalizedPriceData(
            exchange: "Coinbase",
            symbol: "BTC-USD",
            bid: Decimal(string: "100.00")!,
            ask: Decimal(string: "101.00")!,
            rawTimestamp: Date(),
            normalizedTime: 1.010
        )

        let validQuote2 = NormalizedPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "99.00")!,
            ask: Decimal(string: "99.50")!,
            rawTimestamp: Date(),
            normalizedTime: 1.020
        )

        await detector.ingest(zeroQuote)
        await detector.ingest(validQuote1)
        await detector.ingest(validQuote2)

        let analysis = try #require(await iterator.next())
        #expect(analysis.buyPrice > 0)
        #expect(analysis.sellPrice > 0)
    }

    @Test
    func selectsBestBuyAndSellExchanges() async throws {
        let detector = SpreadDetector(
            config: makeConfig(minSpread: 0.01, maxLatency: 100),
            logger: nil
        )

        let stream = await detector.analysisStream()
        var iterator = stream.makeAsyncIterator()

        let binanceQuote = NormalizedPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "100.00")!,
            ask: Decimal(string: "100.50")!,
            rawTimestamp: Date(),
            normalizedTime: 1.000
        )

        let coinbaseQuote = NormalizedPriceData(
            exchange: "Coinbase",
            symbol: "BTC-USD",
            bid: Decimal(string: "102.00")!,
            ask: Decimal(string: "102.50")!,
            rawTimestamp: Date(),
            normalizedTime: 1.010
        )

        let krakenQuote = NormalizedPriceData(
            exchange: "Kraken",
            symbol: "BTC-USD",
            bid: Decimal(string: "101.00")!,
            ask: Decimal(string: "101.80")!,
            rawTimestamp: Date(),
            normalizedTime: 1.020
        )

        await detector.ingest(binanceQuote)
        await detector.ingest(coinbaseQuote)

        let analysis1 = try #require(await iterator.next())

        await detector.ingest(krakenQuote)

        let analysis2 = try #require(await iterator.next())

        #expect(analysis1.buyExchange == "Binance")
        #expect(analysis1.sellExchange == "Coinbase")
        #expect(analysis1.buyPrice == Decimal(string: "100.50"))
        #expect(analysis1.sellPrice == Decimal(string: "102.00"))

        #expect(analysis2.buyExchange == "Binance")
        #expect(analysis2.sellExchange == "Coinbase")
    }

    private func makeConfig(minSpread: Double, maxLatency: Double) -> ArbitrageConfig {
        ArbitrageConfig(
            binanceCredentials: .init(apiKey: "key", apiSecret: "secret"),
            coinbaseCredentials: .init(apiKey: "key", apiSecret: "secret"),
            krakenCredentials: .init(apiKey: "key", apiSecret: "secret"),
            geminiCredentials: .init(apiKey: "key", apiSecret: "secret"),
            tradingPairs: [TradingPair(base: "BTC", quote: "USD")],
            thresholds: .init(
                minimumSpreadPercentage: minSpread,
                maximumLatencyMilliseconds: maxLatency
            ),
            defaults: .init(virtualUSDStartingBalance: 10_000)
        )
    }
}
