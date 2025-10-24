import Foundation
import Testing
@testable import Core
@testable import Utils

@Suite("TradeSimulator Tests")
struct TradeSimulatorTests {

    @Test("Initial configuration sets correct balance")
    func initialConfiguration() async {
        let config = TradeSimulator.Configuration(
            initialBalance: 5000,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.1
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let stats = await simulator.statistics()
        #expect(stats.currentBalance == 5000)
        #expect(stats.totalTrades == 0)
        #expect(stats.successfulTrades == 0)
        #expect(stats.totalProfit == 0)
        #expect(stats.successRate == 0.0)
    }

    @Test("Default configuration uses 10,000 USD")
    func defaultConfiguration() async {
        let config = TradeSimulator.Configuration()
        let simulator = TradeSimulator(config: config, logger: nil)

        let stats = await simulator.statistics()
        #expect(stats.currentBalance == 10_000)
    }

    @Test("Simulating profitable trade increases balance")
    func profitableTrade() async {
        let config = TradeSimulator.Configuration(
            initialBalance: 10_000,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.1
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let analysis = SpreadAnalysis(
            symbol: "BTC-USD",
            buyExchange: "Coinbase",
            sellExchange: "Kraken",
            buyPrice: 50_000,
            sellPrice: 50_500,
            spreadPercentage: 0.01,
            latencyMilliseconds: 100,
            isProfitable: true
        )

        await simulator.simulateTrade(analysis)

        let stats = await simulator.statistics()
        #expect(stats.totalTrades == 1)
        #expect(stats.successfulTrades == 1)
        #expect(stats.totalProfit > 0)
        #expect(stats.currentBalance > 10_000)
        #expect(stats.successRate == 1.0)
    }

    @Test("Simulating unprofitable trade decreases balance")
    func unprofitableTrade() async {
        let config = TradeSimulator.Configuration(
            initialBalance: 10_000,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.1
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let analysis = SpreadAnalysis(
            symbol: "ETH-USD",
            buyExchange: "Coinbase",
            sellExchange: "Kraken",
            buyPrice: 3_000,
            sellPrice: 2_990,
            spreadPercentage: -0.0033,
            latencyMilliseconds: 50,
            isProfitable: true
        )

        await simulator.simulateTrade(analysis)

        let stats = await simulator.statistics()
        #expect(stats.totalTrades == 1)
        #expect(stats.successfulTrades == 0)
        #expect(stats.totalProfit < 0)
        #expect(stats.currentBalance < 10_000)
        #expect(stats.successRate == 0.0)
    }

    @Test("Non-profitable spread is ignored")
    func nonProfitableSpreadIgnored() async {
        let config = TradeSimulator.Configuration()
        let simulator = TradeSimulator(config: config, logger: nil)

        let analysis = SpreadAnalysis(
            symbol: "BTC-USD",
            buyExchange: "Coinbase",
            sellExchange: "Kraken",
            buyPrice: 50_000,
            sellPrice: 50_100,
            spreadPercentage: 0.002,
            latencyMilliseconds: 100,
            isProfitable: false
        )

        await simulator.simulateTrade(analysis)

        let stats = await simulator.statistics()
        #expect(stats.totalTrades == 0)
        #expect(stats.currentBalance == 10_000)
    }

    @Test("Multiple trades update statistics correctly")
    func multipleTrades() async {
        let config = TradeSimulator.Configuration(
            initialBalance: 10_000,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.1
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let profitable1 = SpreadAnalysis(
            symbol: "BTC-USD",
            buyExchange: "Coinbase",
            sellExchange: "Kraken",
            buyPrice: 50_000,
            sellPrice: 50_500,
            spreadPercentage: 0.01,
            latencyMilliseconds: 100,
            isProfitable: true
        )

        let profitable2 = SpreadAnalysis(
            symbol: "ETH-USD",
            buyExchange: "Kraken",
            sellExchange: "Coinbase",
            buyPrice: 3_000,
            sellPrice: 3_050,
            spreadPercentage: 0.0167,
            latencyMilliseconds: 80,
            isProfitable: true
        )

        let unprofitable = SpreadAnalysis(
            symbol: "LTC-USD",
            buyExchange: "Coinbase",
            sellExchange: "Kraken",
            buyPrice: 100,
            sellPrice: 99,
            spreadPercentage: -0.01,
            latencyMilliseconds: 120,
            isProfitable: true
        )

        await simulator.simulateTrade(profitable1)
        await simulator.simulateTrade(profitable2)
        await simulator.simulateTrade(unprofitable)

        let stats = await simulator.statistics()
        #expect(stats.totalTrades == 3)
        #expect(stats.successfulTrades == 2)
        #expect(stats.successRate == 2.0 / 3.0)
    }

    @Test("Reset restores initial state")
    func resetState() async {
        let config = TradeSimulator.Configuration(
            initialBalance: 10_000,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.1
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let analysis = SpreadAnalysis(
            symbol: "BTC-USD",
            buyExchange: "Coinbase",
            sellExchange: "Kraken",
            buyPrice: 50_000,
            sellPrice: 50_500,
            spreadPercentage: 0.01,
            latencyMilliseconds: 100,
            isProfitable: true
        )

        await simulator.simulateTrade(analysis)

        var stats = await simulator.statistics()
        #expect(stats.totalTrades == 1)
        #expect(stats.currentBalance != 10_000)

        await simulator.reset()

        stats = await simulator.statistics()
        #expect(stats.totalTrades == 0)
        #expect(stats.successfulTrades == 0)
        #expect(stats.totalProfit == 0)
        #expect(stats.currentBalance == 10_000)
        #expect(stats.successRate == 0.0)
    }

    @Test("Fees are correctly applied to trades")
    func feesApplied() async {
        let feePercentage: Decimal = 0.002
        let config = TradeSimulator.Configuration(
            initialBalance: 10_000,
            feePercentagePerTrade: feePercentage,
            tradeAllocationPercentage: 1.0
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let buyPrice: Decimal = 1000
        let sellPrice: Decimal = 1100

        let analysis = SpreadAnalysis(
            symbol: "TEST-USD",
            buyExchange: "ExchangeA",
            sellExchange: "ExchangeB",
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            spreadPercentage: 0.1,
            latencyMilliseconds: 50,
            isProfitable: true
        )

        await simulator.simulateTrade(analysis)

        let tradeAmount: Decimal = 10_000
        let buyFee = tradeAmount * feePercentage
        let amountAfterBuyFee = tradeAmount - buyFee
        let cryptoAmount = amountAfterBuyFee / buyPrice
        let sellProceeds = cryptoAmount * sellPrice
        let sellFee = sellProceeds * feePercentage
        let netProceeds = sellProceeds - sellFee
        let expectedProfit = netProceeds - tradeAmount
        let expectedBalance = 10_000 + expectedProfit

        let stats = await simulator.statistics()
        #expect(stats.totalProfit == expectedProfit)
        #expect(stats.currentBalance == expectedBalance)
    }

    @Test("Trade allocation percentage limits position size")
    func tradeAllocation() async {
        let config = TradeSimulator.Configuration(
            initialBalance: 10_000,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.2
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let analysis = SpreadAnalysis(
            symbol: "BTC-USD",
            buyExchange: "Coinbase",
            sellExchange: "Kraken",
            buyPrice: 50_000,
            sellPrice: 51_000,
            spreadPercentage: 0.02,
            latencyMilliseconds: 100,
            isProfitable: true
        )

        await simulator.simulateTrade(analysis)

        let stats = await simulator.statistics()
        let maxPossibleLoss = 10_000 * 0.2 * 0.001 * 2
        #expect(abs(stats.currentBalance - 10_000) < 10_000 * 0.2 + Decimal(maxPossibleLoss))
    }

    @Test("Statistics calculation with no trades")
    func statisticsWithNoTrades() async {
        let simulator = TradeSimulator(
            config: TradeSimulator.Configuration(),
            logger: nil
        )

        let stats = await simulator.statistics()
        #expect(stats.totalTrades == 0)
        #expect(stats.successfulTrades == 0)
        #expect(stats.totalProfit == 0)
        #expect(stats.successRate == 0.0)
    }

    @Test("Virtual balance updates correctly after profitable trade")
    func virtualBalanceAfterProfitableTrade() async {
        let initialBalance: Decimal = 10_000
        let config = TradeSimulator.Configuration(
            initialBalance: initialBalance,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.1
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let buyPrice: Decimal = 1000
        let sellPrice: Decimal = 1050
        let tradeAmount = initialBalance * 0.1

        let buyFee = tradeAmount * 0.001
        let amountAfterBuyFee = tradeAmount - buyFee
        let cryptoAmount = amountAfterBuyFee / buyPrice
        let sellProceeds = cryptoAmount * sellPrice
        let sellFee = sellProceeds * 0.001
        let netProceeds = sellProceeds - sellFee
        let expectedProfit = netProceeds - tradeAmount
        let expectedBalance = initialBalance + expectedProfit

        let analysis = SpreadAnalysis(
            symbol: "TEST-USD",
            buyExchange: "ExchangeA",
            sellExchange: "ExchangeB",
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            spreadPercentage: 0.05,
            latencyMilliseconds: 50,
            isProfitable: true
        )

        await simulator.simulateTrade(analysis)

        let stats = await simulator.statistics()
        #expect(stats.currentBalance == expectedBalance)
        #expect(stats.totalProfit == expectedProfit)
        #expect(stats.currentBalance > initialBalance)
    }

    @Test("Virtual balance updates correctly after losing trade")
    func virtualBalanceAfterLosingTrade() async {
        let initialBalance: Decimal = 10_000
        let config = TradeSimulator.Configuration(
            initialBalance: initialBalance,
            feePercentagePerTrade: 0.002,
            tradeAllocationPercentage: 0.2
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let buyPrice: Decimal = 1000
        let sellPrice: Decimal = 950
        let tradeAmount = initialBalance * 0.2

        let buyFee = tradeAmount * 0.002
        let amountAfterBuyFee = tradeAmount - buyFee
        let cryptoAmount = amountAfterBuyFee / buyPrice
        let sellProceeds = cryptoAmount * sellPrice
        let sellFee = sellProceeds * 0.002
        let netProceeds = sellProceeds - sellFee
        let expectedLoss = netProceeds - tradeAmount
        let expectedBalance = initialBalance + expectedLoss

        let analysis = SpreadAnalysis(
            symbol: "TEST-USD",
            buyExchange: "ExchangeA",
            sellExchange: "ExchangeB",
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            spreadPercentage: -0.05,
            latencyMilliseconds: 50,
            isProfitable: true
        )

        await simulator.simulateTrade(analysis)

        let stats = await simulator.statistics()
        #expect(stats.currentBalance == expectedBalance)
        #expect(stats.totalProfit == expectedLoss)
        #expect(stats.currentBalance < initialBalance)
        #expect(stats.totalProfit < 0)
    }

    @Test("Virtual balance accumulates across multiple trades")
    func balanceAccumulationAcrossMultipleTrades() async {
        let initialBalance: Decimal = 10_000
        let config = TradeSimulator.Configuration(
            initialBalance: initialBalance,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.1
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let trade1 = SpreadAnalysis(
            symbol: "BTC-USD",
            buyExchange: "A",
            sellExchange: "B",
            buyPrice: 50_000,
            sellPrice: 50_500,
            spreadPercentage: 0.01,
            latencyMilliseconds: 50,
            isProfitable: true
        )

        let trade2 = SpreadAnalysis(
            symbol: "ETH-USD",
            buyExchange: "A",
            sellExchange: "B",
            buyPrice: 3_000,
            sellPrice: 3_050,
            spreadPercentage: 0.0167,
            latencyMilliseconds: 60,
            isProfitable: true
        )

        let trade3 = SpreadAnalysis(
            symbol: "LTC-USD",
            buyExchange: "A",
            sellExchange: "B",
            buyPrice: 100,
            sellPrice: 101,
            spreadPercentage: 0.01,
            latencyMilliseconds: 70,
            isProfitable: true
        )

        await simulator.simulateTrade(trade1)
        let stats1 = await simulator.statistics()

        await simulator.simulateTrade(trade2)
        let stats2 = await simulator.statistics()

        await simulator.simulateTrade(trade3)
        let stats3 = await simulator.statistics()

        #expect(stats1.currentBalance != initialBalance)
        #expect(stats2.currentBalance != stats1.currentBalance)
        #expect(stats3.currentBalance != stats2.currentBalance)

        #expect(stats1.totalProfit != 0)
        #expect(stats2.totalProfit != stats1.totalProfit)
        #expect(stats3.totalProfit != stats2.totalProfit)

        #expect(stats3.currentBalance == initialBalance + stats3.totalProfit)
    }

    @Test("Virtual balance with mixed profitable and unprofitable trades")
    func mixedTradesBalanceUpdate() async {
        let initialBalance: Decimal = 10_000
        let config = TradeSimulator.Configuration(
            initialBalance: initialBalance,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.1
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let profitableTrade = SpreadAnalysis(
            symbol: "BTC-USD",
            buyExchange: "A",
            sellExchange: "B",
            buyPrice: 50_000,
            sellPrice: 51_000,
            spreadPercentage: 0.02,
            latencyMilliseconds: 50,
            isProfitable: true
        )

        let unprofitableTrade = SpreadAnalysis(
            symbol: "ETH-USD",
            buyExchange: "A",
            sellExchange: "B",
            buyPrice: 3_000,
            sellPrice: 2_950,
            spreadPercentage: -0.0167,
            latencyMilliseconds: 60,
            isProfitable: true
        )

        await simulator.simulateTrade(profitableTrade)
        let statsAfterProfit = await simulator.statistics()

        await simulator.simulateTrade(unprofitableTrade)
        let statsAfterLoss = await simulator.statistics()

        #expect(statsAfterProfit.currentBalance > initialBalance)
        #expect(statsAfterLoss.currentBalance < statsAfterProfit.currentBalance)

        let netProfit = statsAfterLoss.totalProfit
        #expect(statsAfterLoss.currentBalance == initialBalance + netProfit)
    }

    @Test("Virtual balance remains unchanged when trade is not executed")
    func balanceUnchangedWhenTradeNotExecuted() async {
        let initialBalance: Decimal = 10_000
        let config = TradeSimulator.Configuration(
            initialBalance: initialBalance,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.1
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let unprofitableSpread = SpreadAnalysis(
            symbol: "BTC-USD",
            buyExchange: "A",
            sellExchange: "B",
            buyPrice: 50_000,
            sellPrice: 50_100,
            spreadPercentage: 0.002,
            latencyMilliseconds: 50,
            isProfitable: false
        )

        await simulator.simulateTrade(unprofitableSpread)

        let stats = await simulator.statistics()
        #expect(stats.currentBalance == initialBalance)
        #expect(stats.totalProfit == 0)
        #expect(stats.totalTrades == 0)
    }

    @Test("Virtual balance precision maintained with decimal calculations")
    func balancePrecisionMaintained() async {
        let initialBalance: Decimal = 10_000.123456
        let config = TradeSimulator.Configuration(
            initialBalance: initialBalance,
            feePercentagePerTrade: 0.0015,
            tradeAllocationPercentage: 0.1
        )
        let simulator = TradeSimulator(config: config, logger: nil)

        let buyPrice: Decimal = Decimal(string: "1234.56789012")!
        let sellPrice: Decimal = Decimal(string: "1250.12345678")!

        let analysis = SpreadAnalysis(
            symbol: "TEST-USD",
            buyExchange: "A",
            sellExchange: "B",
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            spreadPercentage: (sellPrice - buyPrice) / buyPrice,
            latencyMilliseconds: 50,
            isProfitable: true
        )

        await simulator.simulateTrade(analysis)

        let stats = await simulator.statistics()

        #expect(stats.currentBalance != initialBalance)
        #expect(stats.currentBalance == initialBalance + stats.totalProfit)

        let balanceString = NSDecimalNumber(decimal: stats.currentBalance).stringValue
        #expect(balanceString.contains("."))
    }

    @Test("High allocation percentage impacts balance more")
    func highAllocationImpact() async {
        let initialBalance: Decimal = 10_000

        let lowAllocationConfig = TradeSimulator.Configuration(
            initialBalance: initialBalance,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.05
        )
        let lowAllocationSim = TradeSimulator(config: lowAllocationConfig, logger: nil)

        let highAllocationConfig = TradeSimulator.Configuration(
            initialBalance: initialBalance,
            feePercentagePerTrade: 0.001,
            tradeAllocationPercentage: 0.5
        )
        let highAllocationSim = TradeSimulator(config: highAllocationConfig, logger: nil)

        let analysis = SpreadAnalysis(
            symbol: "BTC-USD",
            buyExchange: "A",
            sellExchange: "B",
            buyPrice: 50_000,
            sellPrice: 50_500,
            spreadPercentage: 0.01,
            latencyMilliseconds: 50,
            isProfitable: true
        )

        await lowAllocationSim.simulateTrade(analysis)
        await highAllocationSim.simulateTrade(analysis)

        let lowStats = await lowAllocationSim.statistics()
        let highStats = await highAllocationSim.statistics()

        #expect(abs(highStats.totalProfit) > abs(lowStats.totalProfit))
    }

    @Test("Zero fees maximize profit")
    func zeroFeesMaximizeProfit() async {
        let initialBalance: Decimal = 10_000

        let noFeeConfig = TradeSimulator.Configuration(
            initialBalance: initialBalance,
            feePercentagePerTrade: 0.0,
            tradeAllocationPercentage: 0.1
        )
        let noFeeSim = TradeSimulator(config: noFeeConfig, logger: nil)

        let withFeeConfig = TradeSimulator.Configuration(
            initialBalance: initialBalance,
            feePercentagePerTrade: 0.002,
            tradeAllocationPercentage: 0.1
        )
        let withFeeSim = TradeSimulator(config: withFeeConfig, logger: nil)

        let analysis = SpreadAnalysis(
            symbol: "BTC-USD",
            buyExchange: "A",
            sellExchange: "B",
            buyPrice: 50_000,
            sellPrice: 50_500,
            spreadPercentage: 0.01,
            latencyMilliseconds: 50,
            isProfitable: true
        )

        await noFeeSim.simulateTrade(analysis)
        await withFeeSim.simulateTrade(analysis)

        let noFeeStats = await noFeeSim.statistics()
        let withFeeStats = await withFeeSim.statistics()

        #expect(noFeeStats.totalProfit > withFeeStats.totalProfit)
        #expect(noFeeStats.currentBalance > withFeeStats.currentBalance)
    }
}
