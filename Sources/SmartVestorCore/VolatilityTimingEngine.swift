import Foundation
import Utils

public protocol VolatilityTimingEngineProtocol {
    func calculateOptimalAllocationTiming(amount: Double, timeHorizon: TimeHorizon) async throws -> [AllocationTiming]
    func analyzeVolatilityPatterns() async throws -> VolatilityPattern
    func determineAllocationSchedule(volatilityPattern: VolatilityPattern) async throws -> AllocationSchedule
    func executeTimedAllocation(timing: AllocationTiming, amount: Double) async throws -> AllocationResult
}

public struct VolatilityPattern: Codable {
    public let patternType: VolatilityPatternType
    public let dailyVolatility: [DayOfWeek: Double]
    public let hourlyVolatility: [Int: Double]
    public let seasonalVolatility: [Season: Double]
    public let marketRegimeVolatility: [MarketRegime: Double]
    public let confidence: Double
    public let lastUpdated: Date

    public init(
        patternType: VolatilityPatternType,
        dailyVolatility: [DayOfWeek: Double],
        hourlyVolatility: [Int: Double],
        seasonalVolatility: [Season: Double],
        marketRegimeVolatility: [MarketRegime: Double],
        confidence: Double,
        lastUpdated: Date = Date()
    ) {
        self.patternType = patternType
        self.dailyVolatility = dailyVolatility
        self.hourlyVolatility = hourlyVolatility
        self.seasonalVolatility = seasonalVolatility
        self.marketRegimeVolatility = marketRegimeVolatility
        self.confidence = confidence
        self.lastUpdated = lastUpdated
    }
}

public enum VolatilityPatternType: String, Codable, CaseIterable {
    case morningSpike = "morning_spike"        // High volatility in morning hours
    case eveningDip = "evening_dip"            // Low volatility in evening hours
    case weekendSurge = "weekend_surge"        // Higher volatility on weekends
    case weekdayStable = "weekday_stable"      // Stable volatility on weekdays
    case random = "random"                     // No clear pattern
    case cyclical = "cyclical"                 // Regular cyclical patterns
    case trending = "trending"                 // Trending volatility
    case meanReverting = "mean_reverting"      // Mean-reverting volatility
}

public enum DayOfWeek: String, Codable, CaseIterable {
    case monday = "monday"
    case tuesday = "tuesday"
    case wednesday = "wednesday"
    case thursday = "thursday"
    case friday = "friday"
    case saturday = "saturday"
    case sunday = "sunday"
}

public enum Season: String, Codable, CaseIterable {
    case spring = "spring"
    case summer = "summer"
    case fall = "fall"
    case winter = "winter"
}

public struct AllocationSchedule: Codable {
    public let totalAmount: Double
    public let allocations: [ScheduledAllocation]
    public let expectedVolatility: Double
    public let riskAdjustedReturn: Double
    public let executionStrategy: ExecutionStrategy

    public init(
        totalAmount: Double,
        allocations: [ScheduledAllocation],
        expectedVolatility: Double,
        riskAdjustedReturn: Double,
        executionStrategy: ExecutionStrategy
    ) {
        self.totalAmount = totalAmount
        self.allocations = allocations
        self.expectedVolatility = expectedVolatility
        self.riskAdjustedReturn = riskAdjustedReturn
        self.executionStrategy = executionStrategy
    }
}

public struct ScheduledAllocation: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let amount: Double
    public let percentage: Double
    public let scheduledTime: Date
    public let priority: AllocationPriority
    public let volatilityThreshold: Double
    public let maxSlippage: Double
    public let exchange: String
    public let rationale: String

    public init(
        id: UUID = UUID(),
        symbol: String,
        amount: Double,
        percentage: Double,
        scheduledTime: Date,
        priority: AllocationPriority,
        volatilityThreshold: Double,
        maxSlippage: Double,
        exchange: String,
        rationale: String
    ) {
        self.id = id
        self.symbol = symbol
        self.amount = amount
        self.percentage = percentage
        self.scheduledTime = scheduledTime
        self.priority = priority
        self.volatilityThreshold = volatilityThreshold
        self.maxSlippage = maxSlippage
        self.exchange = exchange
        self.rationale = rationale
    }
}

public enum AllocationPriority: String, Codable, CaseIterable {
    case critical = "critical"     // Must execute immediately
    case high = "high"            // Execute within 1 hour
    case medium = "medium"        // Execute within 4 hours
    case low = "low"              // Execute within 24 hours
    case flexible = "flexible"    // Execute when conditions are optimal
}

public enum ExecutionStrategy: String, Codable, CaseIterable {
    case immediate = "immediate"           // Execute all at once
    case staggered = "staggered"          // Execute in stages
    case volatilityBased = "volatility_based"  // Execute based on volatility
    case timeBased = "time_based"         // Execute at specific times
    case hybrid = "hybrid"                // Combination of strategies
}

public struct AllocationResult: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let requestedAmount: Double
    public let executedAmount: Double
    public let averagePrice: Double
    public let totalFees: Double
    public let executionTime: Date
    public let volatilityAtExecution: Double
    public let slippage: Double
    public let success: Bool
    public let error: String?

    public init(
        id: UUID = UUID(),
        symbol: String,
        requestedAmount: Double,
        executedAmount: Double,
        averagePrice: Double,
        totalFees: Double,
        executionTime: Date = Date(),
        volatilityAtExecution: Double,
        slippage: Double,
        success: Bool,
        error: String? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.requestedAmount = requestedAmount
        self.executedAmount = executedAmount
        self.averagePrice = averagePrice
        self.totalFees = totalFees
        self.executionTime = executionTime
        self.volatilityAtExecution = volatilityAtExecution
        self.slippage = slippage
        self.success = success
        self.error = error
    }
}

public class VolatilityTimingEngine: VolatilityTimingEngineProtocol {
    private let config: SmartVestorConfig
    private let persistence: PersistenceProtocol
    private let marketDataProvider: MarketDataProviderProtocol
    private let logger: StructuredLogger

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

    public func calculateOptimalAllocationTiming(amount: Double, timeHorizon: TimeHorizon) async throws -> [AllocationTiming] {
        logger.info(component: "VolatilityTimingEngine", event: "Calculating optimal allocation timing", data: [
            "amount": String(amount),
            "time_horizon": timeHorizon.rawValue
        ])

        let volatilityPattern = try await analyzeVolatilityPatterns()
        let allocationSchedule = try await determineAllocationSchedule(volatilityPattern: volatilityPattern)

        var timings: [AllocationTiming] = []

        for allocation in allocationSchedule.allocations {
            let timing = AllocationTiming(
                symbol: allocation.symbol,
                optimalTime: allocation.scheduledTime,
                confidence: calculateConfidence(
                    volatilityPattern: volatilityPattern,
                    scheduledTime: allocation.scheduledTime
                ),
                expectedVolatility: allocation.volatilityThreshold,
                allocationPercentage: allocation.percentage,
                rationale: allocation.rationale
            )
            timings.append(timing)
        }

        logger.info(component: "VolatilityTimingEngine", event: "Optimal allocation timing calculated", data: [
            "timings_count": String(timings.count),
            "pattern_type": volatilityPattern.patternType.rawValue
        ])

        return timings
    }

    public func analyzeVolatilityPatterns() async throws -> VolatilityPattern {
        logger.info(component: "VolatilityTimingEngine", event: "Analyzing volatility patterns")

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .month, value: -3, to: endDate)!

        let marketData = try await marketDataProvider.getHistoricalData(
            startDate: startDate,
            endDate: endDate,
            symbols: ["BTC", "ETH", "ADA", "DOT", "LINK", "SOL"]
        )

        let dailyVolatility = try await calculateDailyVolatility(marketData: marketData)
        let hourlyVolatility = try await calculateHourlyVolatility(marketData: marketData)
        let seasonalVolatility = try await calculateSeasonalVolatility(marketData: marketData)
        let marketRegimeVolatility = try await calculateMarketRegimeVolatility(marketData: marketData)

        let patternType = determineVolatilityPatternType(
            dailyVolatility: dailyVolatility,
            hourlyVolatility: hourlyVolatility
        )

        let confidence = calculatePatternConfidence(
            dailyVolatility: dailyVolatility,
            hourlyVolatility: hourlyVolatility
        )

        let pattern = VolatilityPattern(
            patternType: patternType,
            dailyVolatility: dailyVolatility,
            hourlyVolatility: hourlyVolatility,
            seasonalVolatility: seasonalVolatility,
            marketRegimeVolatility: marketRegimeVolatility,
            confidence: confidence
        )

        logger.info(component: "VolatilityTimingEngine", event: "Volatility pattern analysis completed", data: [
            "pattern_type": patternType.rawValue,
            "confidence": String(confidence)
        ])

        return pattern
    }

    public func determineAllocationSchedule(volatilityPattern: VolatilityPattern) async throws -> AllocationSchedule {
        logger.info(component: "VolatilityTimingEngine", event: "Determining allocation schedule", data: [
            "pattern_type": volatilityPattern.patternType.rawValue
        ])

        let totalAmount = 100000.0 // This would come from the actual allocation amount
        let allocations = try await createScheduledAllocations(
            totalAmount: totalAmount,
            volatilityPattern: volatilityPattern
        )

        let expectedVolatility = calculateExpectedVolatility(volatilityPattern: volatilityPattern)
        let riskAdjustedReturn = calculateRiskAdjustedReturn(
            volatilityPattern: volatilityPattern,
            expectedVolatility: expectedVolatility
        )

        let executionStrategy = determineExecutionStrategy(volatilityPattern: volatilityPattern)

        let schedule = AllocationSchedule(
            totalAmount: totalAmount,
            allocations: allocations,
            expectedVolatility: expectedVolatility,
            riskAdjustedReturn: riskAdjustedReturn,
            executionStrategy: executionStrategy
        )

        logger.info(component: "VolatilityTimingEngine", event: "Allocation schedule determined", data: [
            "allocations_count": String(allocations.count),
            "execution_strategy": executionStrategy.rawValue
        ])

        return schedule
    }

    public func executeTimedAllocation(timing: AllocationTiming, amount: Double) async throws -> AllocationResult {
        logger.info(component: "VolatilityTimingEngine", event: "Executing timed allocation", data: [
            "symbol": timing.symbol,
            "amount": String(amount),
            "scheduled_time": timing.optimalTime.description
        ])

        let currentVolatility = try await getCurrentVolatility(symbol: timing.symbol)
        let volatilityAtExecution = currentVolatility

        let shouldExecute = shouldExecuteAllocation(
            timing: timing,
            currentVolatility: currentVolatility
        )

        if !shouldExecute {
            logger.info(component: "VolatilityTimingEngine", event: "Allocation skipped due to volatility conditions", data: [
                "symbol": timing.symbol,
                "current_volatility": String(currentVolatility),
                "threshold": String(timing.expectedVolatility)
            ])

            return AllocationResult(
                symbol: timing.symbol,
                requestedAmount: amount,
                executedAmount: 0.0,
                averagePrice: 0.0,
                totalFees: 0.0,
                volatilityAtExecution: volatilityAtExecution,
                slippage: 0.0,
                success: false,
                error: "Volatility threshold not met"
            )
        }

        let executionResult = try await executeAllocation(
            symbol: timing.symbol,
            amount: amount,
            maxSlippage: 0.005
        )

        logger.info(component: "VolatilityTimingEngine", event: "Timed allocation executed", data: [
            "symbol": timing.symbol,
            "executed_amount": String(executionResult.executedAmount),
            "success": String(executionResult.success)
        ])

        return executionResult
    }

    // MARK: - Private Methods

    private func calculateDailyVolatility(marketData: [String: [MarketDataPoint]]) async throws -> [DayOfWeek: Double] {
        var dailyVolatility: [DayOfWeek: Double] = [:]

        for day in DayOfWeek.allCases {
            var dayReturns: [Double] = []

            for (_, data) in marketData {
                let dayData = data.filter {
                    Calendar.current.component(.weekday, from: $0.timestamp) == getWeekdayNumber(day)
                }

                if dayData.count > 1 {
                    let returns = calculateReturns(prices: dayData.map { $0.price })
                    dayReturns.append(contentsOf: returns)
                }
            }

            if !dayReturns.isEmpty {
                dailyVolatility[day] = calculateVolatility(returns: dayReturns)
            } else {
                dailyVolatility[day] = 0.03 // Default volatility
            }
        }

        return dailyVolatility
    }

    private func calculateHourlyVolatility(marketData: [String: [MarketDataPoint]]) async throws -> [Int: Double] {
        var hourlyVolatility: [Int: Double] = [:]

        for hour in 0..<24 {
            var hourReturns: [Double] = []

            for (_, data) in marketData {
                let hourData = data.filter {
                    Calendar.current.component(.hour, from: $0.timestamp) == hour
                }

                if hourData.count > 1 {
                    let returns = calculateReturns(prices: hourData.map { $0.price })
                    hourReturns.append(contentsOf: returns)
                }
            }

            if !hourReturns.isEmpty {
                hourlyVolatility[hour] = calculateVolatility(returns: hourReturns)
            } else {
                hourlyVolatility[hour] = 0.03 // Default volatility
            }
        }

        return hourlyVolatility
    }

    private func calculateSeasonalVolatility(marketData: [String: [MarketDataPoint]]) async throws -> [Season: Double] {
        var seasonalVolatility: [Season: Double] = [:]

        for season in Season.allCases {
            var seasonReturns: [Double] = []

            for (_, data) in marketData {
                let seasonData = data.filter {
                    getSeason(for: $0.timestamp) == season
                }

                if seasonData.count > 1 {
                    let returns = calculateReturns(prices: seasonData.map { $0.price })
                    seasonReturns.append(contentsOf: returns)
                }
            }

            if !seasonReturns.isEmpty {
                seasonalVolatility[season] = calculateVolatility(returns: seasonReturns)
            } else {
                seasonalVolatility[season] = 0.03 // Default volatility
            }
        }

        return seasonalVolatility
    }

    private func calculateMarketRegimeVolatility(marketData: [String: [MarketDataPoint]]) async throws -> [MarketRegime: Double] {
        var regimeVolatility: [MarketRegime: Double] = [:]

        for regime in MarketRegime.allCases {
            var regimeReturns: [Double] = []

            for (_, data) in marketData {
                let regimeData = data.filter {
                    determineMarketRegimeForTimestamp($0.timestamp, marketData: marketData) == regime
                }

                if regimeData.count > 1 {
                    let returns = calculateReturns(prices: regimeData.map { $0.price })
                    regimeReturns.append(contentsOf: returns)
                }
            }

            if !regimeReturns.isEmpty {
                regimeVolatility[regime] = calculateVolatility(returns: regimeReturns)
            } else {
                regimeVolatility[regime] = 0.03 // Default volatility
            }
        }

        return regimeVolatility
    }

    private func determineVolatilityPatternType(
        dailyVolatility: [DayOfWeek: Double],
        hourlyVolatility: [Int: Double]
    ) -> VolatilityPatternType {
        let weekendVolatility = (dailyVolatility[.saturday] ?? 0.0) + (dailyVolatility[.sunday] ?? 0.0)
        let weekdayVolatility = (dailyVolatility[.monday] ?? 0.0) + (dailyVolatility[.tuesday] ?? 0.0) +
                               (dailyVolatility[.wednesday] ?? 0.0) + (dailyVolatility[.thursday] ?? 0.0) +
                               (dailyVolatility[.friday] ?? 0.0)

        let morningVolatility = (hourlyVolatility[6] ?? 0.0) + (hourlyVolatility[7] ?? 0.0) +
                               (hourlyVolatility[8] ?? 0.0) + (hourlyVolatility[9] ?? 0.0)
        let eveningVolatility = (hourlyVolatility[18] ?? 0.0) + (hourlyVolatility[19] ?? 0.0) +
                               (hourlyVolatility[20] ?? 0.0) + (hourlyVolatility[21] ?? 0.0)

        if weekendVolatility > weekdayVolatility * 1.2 {
            return .weekendSurge
        } else if morningVolatility > eveningVolatility * 1.3 {
            return .morningSpike
        } else if eveningVolatility < morningVolatility * 0.7 {
            return .eveningDip
        } else if weekdayVolatility > weekendVolatility * 1.1 {
            return .weekdayStable
        } else {
            return .random
        }
    }

    private func calculatePatternConfidence(
        dailyVolatility: [DayOfWeek: Double],
        hourlyVolatility: [Int: Double]
    ) -> Double {
        let dailyVariance = calculateVariance(Array(dailyVolatility.values))
        let hourlyVariance = calculateVariance(Array(hourlyVolatility.values))

        let totalVariance = dailyVariance + hourlyVariance
        let confidence = max(0.0, min(1.0, 1.0 - (totalVariance / 0.01)))

        return confidence
    }

    private func createScheduledAllocations(
        totalAmount: Double,
        volatilityPattern: VolatilityPattern
    ) async throws -> [ScheduledAllocation] {
        var allocations: [ScheduledAllocation] = []

        let symbols = ["BTC", "ETH", "ADA", "DOT", "LINK", "SOL"]
        let percentages = [0.4, 0.3, 0.1, 0.1, 0.05, 0.05]

        for (index, symbol) in symbols.enumerated() {
            let amount = totalAmount * percentages[index]
            let scheduledTime = calculateOptimalTime(
                symbol: symbol,
                volatilityPattern: volatilityPattern
            )

            let allocation = ScheduledAllocation(
                symbol: symbol,
                amount: amount,
                percentage: percentages[index],
                scheduledTime: scheduledTime,
                priority: determinePriority(symbol: symbol, amount: amount),
                volatilityThreshold: calculateVolatilityThreshold(
                    symbol: symbol,
                    volatilityPattern: volatilityPattern
                ),
                maxSlippage: 0.005,
                exchange: selectBestExchange(for: symbol),
                rationale: generateRationale(
                    symbol: symbol,
                    scheduledTime: scheduledTime,
                    volatilityPattern: volatilityPattern
                )
            )

            allocations.append(allocation)
        }

        return allocations.sorted { $0.scheduledTime < $1.scheduledTime }
    }

    private func calculateOptimalTime(
        symbol: String,
        volatilityPattern: VolatilityPattern
    ) -> Date {
        let now = Date()
        let calendar = Calendar.current

        switch volatilityPattern.patternType {
        case .morningSpike:
            return calendar.date(byAdding: .hour, value: 2, to: now) ?? now
        case .eveningDip:
            return calendar.date(byAdding: .hour, value: 18, to: now) ?? now
        case .weekendSurge:
            let nextSaturday = calendar.nextDate(after: now, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime) ?? now
            return calendar.date(byAdding: .hour, value: 10, to: nextSaturday) ?? now
        case .weekdayStable:
            let nextWeekday = calendar.nextDate(after: now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? now
            return calendar.date(byAdding: .hour, value: 14, to: nextWeekday) ?? now
        default:
            return calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        }
    }

    private func determinePriority(symbol: String, amount: Double) -> AllocationPriority {
        switch symbol {
        case "BTC", "ETH":
            return .critical
        case "ADA", "DOT":
            return .high
        case "LINK", "SOL":
            return .medium
        default:
            return .low
        }
    }

    private func calculateVolatilityThreshold(
        symbol: String,
        volatilityPattern: VolatilityPattern
    ) -> Double {
        let baseThreshold = 0.03

        switch symbol {
        case "BTC", "ETH":
            return baseThreshold * 0.8
        case "ADA", "DOT":
            return baseThreshold * 1.2
        case "LINK", "SOL":
            return baseThreshold * 1.5
        default:
            return baseThreshold * 2.0
        }
    }

    private func selectBestExchange(for symbol: String) -> String {
        return "kraken"
    }

    private func generateRationale(
        symbol: String,
        scheduledTime: Date,
        volatilityPattern: VolatilityPattern
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        return "Allocation scheduled for \(formatter.string(from: scheduledTime)) based on \(volatilityPattern.patternType.rawValue) volatility pattern. Expected volatility: \(String(format: "%.2f", volatilityPattern.dailyVolatility[.monday] ?? 0.03))%"
    }

    private func calculateExpectedVolatility(volatilityPattern: VolatilityPattern) -> Double {
        let dailyValues = Array(volatilityPattern.dailyVolatility.values)
        return dailyValues.reduce(0, +) / Double(dailyValues.count)
    }

    private func calculateRiskAdjustedReturn(
        volatilityPattern: VolatilityPattern,
        expectedVolatility: Double
    ) -> Double {
        let baseReturn = 0.12
        let volatilityPenalty = expectedVolatility * 0.5
        return baseReturn - volatilityPenalty
    }

    private func determineExecutionStrategy(volatilityPattern: VolatilityPattern) -> ExecutionStrategy {
        switch volatilityPattern.patternType {
        case .morningSpike, .eveningDip:
            return .volatilityBased
        case .weekendSurge, .weekdayStable:
            return .timeBased
        case .cyclical, .trending:
            return .staggered
        case .meanReverting:
            return .hybrid
        default:
            return .immediate
        }
    }

    private func calculateConfidence(
        volatilityPattern: VolatilityPattern,
        scheduledTime: Date
    ) -> Double {
        let dayOfWeek = getDayOfWeek(for: scheduledTime)
        let hour = Calendar.current.component(.hour, from: scheduledTime)

        let dailyConfidence = volatilityPattern.dailyVolatility[dayOfWeek] ?? 0.03
        let hourlyConfidence = volatilityPattern.hourlyVolatility[hour] ?? 0.03

        return min(1.0, (dailyConfidence + hourlyConfidence) / 0.06)
    }

    private func shouldExecuteAllocation(
        timing: AllocationTiming,
        currentVolatility: Double
    ) -> Bool {
        return currentVolatility <= timing.expectedVolatility
    }

    private func executeAllocation(
        symbol: String,
        amount: Double,
        maxSlippage: Double
    ) async throws -> AllocationResult {
        // This would integrate with the actual execution engine
        let executedAmount = amount * Double.random(in: 0.95...1.0)
        let averagePrice = generateMockPrice(for: symbol)
        let totalFees = amount * 0.001
        let slippage = Double.random(in: 0.001...maxSlippage)

        return AllocationResult(
            symbol: symbol,
            requestedAmount: amount,
            executedAmount: executedAmount,
            averagePrice: averagePrice,
            totalFees: totalFees,
            volatilityAtExecution: 0.03,
            slippage: slippage,
            success: true
        )
    }

    private func getCurrentVolatility(symbol: String) async throws -> Double {
        return 0.03
    }

    // MARK: - Helper Methods

    private func getWeekdayNumber(_ day: DayOfWeek) -> Int {
        switch day {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    private func getDayOfWeek(for date: Date) -> DayOfWeek {
        let weekday = Calendar.current.component(.weekday, from: date)
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }

    private func getSeason(for date: Date) -> Season {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .fall
        default: return .winter
        }
    }

    private func determineMarketRegimeForTimestamp(
        _ timestamp: Date,
        marketData: [String: [MarketDataPoint]]
    ) -> MarketRegime {
        // Simplified market regime determination
        return .sideways
    }

    private func calculateVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0.0 }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return variance
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

    private func generateMockPrice(for symbol: String) -> Double {
        switch symbol {
        case "BTC": return Double.random(in: 40000...50000)
        case "ETH": return Double.random(in: 2500...3500)
        case "ADA": return Double.random(in: 0.4...0.6)
        case "DOT": return Double.random(in: 6...10)
        case "LINK": return Double.random(in: 12...18)
        case "SOL": return Double.random(in: 80...120)
        default: return Double.random(in: 1...100)
        }
    }
}
