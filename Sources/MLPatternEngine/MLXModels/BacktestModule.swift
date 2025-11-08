import Foundation
import Utils

public struct BacktestResult {
    public let totalReturn: Double
    public let sharpeRatio: Double
    public let maxDrawdown: Double
    public let winRate: Double
    public let totalTrades: Int
    public let profitableTrades: Int
    public let averageReturn: Double
    public let volatility: Double
    public let startDate: Date
    public let endDate: Date

    public init(totalReturn: Double, sharpeRatio: Double, maxDrawdown: Double, winRate: Double, totalTrades: Int, profitableTrades: Int, averageReturn: Double, volatility: Double, startDate: Date, endDate: Date) {
        self.totalReturn = totalReturn
        self.sharpeRatio = sharpeRatio
        self.maxDrawdown = maxDrawdown
        self.winRate = winRate
        self.totalTrades = totalTrades
        self.profitableTrades = profitableTrades
        self.averageReturn = averageReturn
        self.volatility = volatility
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct Trade {
    public let entryPrice: Double
    public let exitPrice: Double
    public let entryTime: Date
    public let exitTime: Date
    public let position: Position
    public let tradeReturn: Double

    public enum Position {
        case long
        case short
    }

    public init(entryPrice: Double, exitPrice: Double, entryTime: Date, exitTime: Date, position: Position) {
        self.entryPrice = entryPrice
        self.exitPrice = exitPrice
        self.entryTime = entryTime
        self.exitTime = exitTime
        self.position = position

        switch position {
        case .long:
            self.tradeReturn = (exitPrice - entryPrice) / entryPrice
        case .short:
            self.tradeReturn = (entryPrice - exitPrice) / entryPrice
        }
    }
}

public class ProfitabilityBacktest {
    private let logger: StructuredLogger
    private let initialCapital: Double
    private let transactionCost: Double

    public init(logger: StructuredLogger, initialCapital: Double = 10000.0, transactionCost: Double = 0.001) {
        self.logger = logger
        self.initialCapital = initialCapital
        self.transactionCost = transactionCost
    }

    public func backtest(predictions: [Double], actualPrices: [Double], timestamps: [Date], confidenceThreshold: Double = 0.6, stopLoss: Double = 0.05, takeProfit: Double = 0.10) throws -> BacktestResult {
        guard predictions.count == actualPrices.count && predictions.count == timestamps.count else {
            throw BacktestError.invalidInput("Predictions, prices, and timestamps must have same length")
        }

        var trades: [Trade] = []
        var currentPosition: Trade? = nil
        var equity: [Double] = [initialCapital]
        var returns: [Double] = []

        for i in 1..<predictions.count {
            let predictedReturn = predictions[i] - actualPrices[i-1]
            let currentPrice = actualPrices[i]
            let timestamp = timestamps[i]

            if let position = currentPosition {
                let positionReturn = position.position == .long ?
                    (currentPrice - position.entryPrice) / position.entryPrice :
                    (position.entryPrice - currentPrice) / position.entryPrice

                let shouldExit =
                    positionReturn <= -stopLoss ||
                    positionReturn >= takeProfit ||
                    i == predictions.count - 1

                if shouldExit {
                    let trade = Trade(
                        entryPrice: position.entryPrice,
                        exitPrice: currentPrice,
                        entryTime: position.entryTime,
                        exitTime: timestamp,
                        position: position.position
                    )
                    trades.append(trade)

                    let netReturn = trade.tradeReturn - transactionCost * 2
                    returns.append(netReturn)
                    equity.append(equity.last! * (1.0 + netReturn))

                    currentPosition = nil
                }
            } else {
                if abs(predictedReturn) > confidenceThreshold {
                    let position: Trade.Position = predictedReturn > 0 ? .long : .short
                    currentPosition = Trade(
                        entryPrice: currentPrice,
                        exitPrice: currentPrice,
                        entryTime: timestamp,
                        exitTime: timestamp,
                        position: position
                    )
                }
            }
        }

        if let position = currentPosition {
            let lastPrice = actualPrices.last!
            let trade = Trade(
                entryPrice: position.entryPrice,
                exitPrice: lastPrice,
                entryTime: position.entryTime,
                exitTime: timestamps.last!,
                position: position.position
            )
            trades.append(trade)
            let netReturn = trade.tradeReturn - transactionCost * 2
            returns.append(netReturn)
        }

        let totalReturn = (equity.last! - initialCapital) / initialCapital
        let profitableTrades = trades.filter { $0.tradeReturn > 0 }.count
        let winRate = trades.isEmpty ? 0.0 : Double(profitableTrades) / Double(trades.count)
        let averageReturn = returns.isEmpty ? 0.0 : returns.reduce(0, +) / Double(returns.count)

        let returnStdDev = returns.isEmpty ? 0.0 : sqrt(returns.map { pow($0 - averageReturn, 2) }.reduce(0, +) / Double(returns.count))
        let sharpeRatio = returnStdDev == 0 ? 0.0 : (averageReturn / returnStdDev) * sqrt(252.0)

        let peak = equity.enumerated().max(by: { $0.element < $1.element })?.element ?? initialCapital
        let maxDrawdown = equity.map { (peak - $0) / peak }.max() ?? 0.0

        logger.info(component: "ProfitabilityBacktest", event: "Backtest completed", data: [
            "totalReturn": String(totalReturn),
            "totalTrades": String(trades.count),
            "winRate": String(winRate),
            "sharpeRatio": String(sharpeRatio)
        ])

        return BacktestResult(
            totalReturn: totalReturn,
            sharpeRatio: sharpeRatio,
            maxDrawdown: maxDrawdown,
            winRate: winRate,
            totalTrades: trades.count,
            profitableTrades: profitableTrades,
            averageReturn: averageReturn,
            volatility: returnStdDev,
            startDate: timestamps.first!,
            endDate: timestamps.last!
        )
    }
}

public enum BacktestError: Error {
    case invalidInput(String)

    public var localizedDescription: String {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        }
    }
}
