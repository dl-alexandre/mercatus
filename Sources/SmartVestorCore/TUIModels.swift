import Foundation

public struct TUIUpdate: Codable, @unchecked Sendable {
    public let timestamp: Date
    public let type: UpdateType
    public let state: AutomationState
    public let data: TUIData
    public let sequenceNumber: Int64

    public enum UpdateType: String, Codable {
        case stateChange
        case tradeExecuted
        case depositDetected
        case errorOccurred
        case heartbeat
        case fullRefresh
    }

    public init(timestamp: Date = Date(), type: UpdateType, state: AutomationState, data: TUIData, sequenceNumber: Int64) {
        self.timestamp = timestamp
        self.type = type
        self.state = state
        self.data = data
        self.sequenceNumber = sequenceNumber
    }
}

public struct TUIData: Codable, @unchecked Sendable {
    public let recentTrades: [InvestmentTransaction]
    public let balances: [Holding]
    public let circuitBreakerOpen: Bool
    public let lastExecutionTime: Date?
    public let nextExecutionTime: Date?
    public let totalPortfolioValue: Double
    public let errorCount: Int
    public let prices: [String: Double]
    public let swapEvaluations: [SwapEvaluation]

    public init(
        recentTrades: [InvestmentTransaction],
        balances: [Holding],
        circuitBreakerOpen: Bool,
        lastExecutionTime: Date?,
        nextExecutionTime: Date?,
        totalPortfolioValue: Double,
        errorCount: Int,
        prices: [String: Double] = [:],
        swapEvaluations: [SwapEvaluation] = []
    ) {
        self.recentTrades = recentTrades
        self.balances = balances
        self.circuitBreakerOpen = circuitBreakerOpen
        self.lastExecutionTime = lastExecutionTime
        self.nextExecutionTime = nextExecutionTime
        self.totalPortfolioValue = totalPortfolioValue
        self.errorCount = errorCount
        self.prices = prices
        self.swapEvaluations = swapEvaluations
    }
}
