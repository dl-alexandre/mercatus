import Foundation

public protocol AdvancedAllocationManagerProtocol {
    func createDynamicAllocationPlan(amount: Double, timeHorizon: TimeHorizon) async throws -> DynamicAllocationPlan
    func analyzeInterWeekTrends() async throws -> InterWeekAnalysis
    func calculateVolatilityTiming() async throws -> VolatilityTiming
    func scoreCoins() async throws -> [CoinScore]
    func executeDynamicRebalancing() async throws -> RebalancingResult
}

public enum TimeHorizon: String, Codable, CaseIterable {
    case shortTerm = "short_term"      // 1-4 weeks
    case mediumTerm = "medium_term"    // 1-3 months
    case longTerm = "long_term"        // 3-12 months
    case strategic = "strategic"       // 1+ years
}

public struct DynamicAllocationPlan: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let timeHorizon: TimeHorizon
    public let totalAmount: Double
    public let coreAllocation: CoreAllocation
    public let tacticalAllocation: TacticalAllocation
    public let satelliteAllocation: SatelliteAllocation
    public let cashReserve: Double
    public let rebalancingSchedule: RebalancingSchedule
    public let riskMetrics: RiskMetrics
    public let rationale: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        timeHorizon: TimeHorizon,
        totalAmount: Double,
        coreAllocation: CoreAllocation,
        tacticalAllocation: TacticalAllocation,
        satelliteAllocation: SatelliteAllocation,
        cashReserve: Double,
        rebalancingSchedule: RebalancingSchedule,
        riskMetrics: RiskMetrics,
        rationale: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.timeHorizon = timeHorizon
        self.totalAmount = totalAmount
        self.coreAllocation = coreAllocation
        self.tacticalAllocation = tacticalAllocation
        self.satelliteAllocation = satelliteAllocation
        self.cashReserve = cashReserve
        self.rebalancingSchedule = rebalancingSchedule
        self.riskMetrics = riskMetrics
        self.rationale = rationale
    }
}

public struct CoreAllocation: Codable {
    public let btc: Double
    public let eth: Double
    public let totalPercentage: Double

    public init(btc: Double, eth: Double) {
        self.btc = btc
        self.eth = eth
        self.totalPercentage = btc + eth
    }
}

public struct TacticalAllocation: Codable {
    public let coins: [TacticalCoin]
    public let totalPercentage: Double
    public let rotationFrequency: RotationFrequency

    public init(coins: [TacticalCoin], totalPercentage: Double, rotationFrequency: RotationFrequency) {
        self.coins = coins
        self.totalPercentage = totalPercentage
        self.rotationFrequency = rotationFrequency
    }
}

public struct TacticalCoin: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let percentage: Double
    public let exchange: String
    public let score: Double
    public let category: CoinCategory
    public let expectedVolatility: Double
    public let momentum: Double
    public let liquidity: Double

    public init(
        id: UUID = UUID(),
        symbol: String,
        percentage: Double,
        exchange: String,
        score: Double,
        category: CoinCategory,
        expectedVolatility: Double,
        momentum: Double,
        liquidity: Double
    ) {
        self.id = id
        self.symbol = symbol
        self.percentage = percentage
        self.exchange = exchange
        self.score = score
        self.category = category
        self.expectedVolatility = expectedVolatility
        self.momentum = momentum
        self.liquidity = liquidity
    }
}

public enum CoinCategory: String, Codable, CaseIterable, Sendable {
    case layer1 = "layer1"           // Ethereum, Solana, Avalanche, etc.
    case layer2 = "layer2"           // Polygon, Arbitrum, Optimism, etc.
    case defi = "defi"              // Uniswap, Aave, Compound, etc.
    case gaming = "gaming"          // Axie Infinity, Sandbox, etc.
    case nft = "nft"                // OpenSea, LooksRare, etc.
    case infrastructure = "infrastructure" // Chainlink, The Graph, etc.
    case privacy = "privacy"        // Monero, Zcash, etc.
    case meme = "meme"              // Dogecoin, Shiba Inu, etc.
    case ai = "ai"                  // Fetch.ai, SingularityNET, etc.
    case storage = "storage"        // Filecoin, Arweave, etc.
}

public enum RotationFrequency: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"
}

public struct SatelliteAllocation: Codable {
    public let coins: [SatelliteCoin]
    public let totalPercentage: Double
    public let maxPositionSize: Double

    public init(coins: [SatelliteCoin], totalPercentage: Double, maxPositionSize: Double) {
        self.coins = coins
        self.totalPercentage = totalPercentage
        self.maxPositionSize = maxPositionSize
    }
}

public struct SatelliteCoin: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let percentage: Double
    public let exchange: String
    public let score: Double
    public let category: CoinCategory
    public let riskLevel: RiskLevel
    public let marketCap: Double
    public let volume24h: Double

    public init(
        id: UUID = UUID(),
        symbol: String,
        percentage: Double,
        exchange: String,
        score: Double,
        category: CoinCategory,
        riskLevel: RiskLevel,
        marketCap: Double,
        volume24h: Double
    ) {
        self.id = id
        self.symbol = symbol
        self.percentage = percentage
        self.exchange = exchange
        self.score = score
        self.category = category
        self.riskLevel = riskLevel
        self.marketCap = marketCap
        self.volume24h = volume24h
    }
}

public enum RiskLevel: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case veryHigh = "very_high"
}

public struct RebalancingSchedule: Codable {
    public let frequency: RebalancingFrequency
    public let triggerThreshold: Double
    public let maxDeviation: Double
    public let volatilityThreshold: Double

    public init(
        frequency: RebalancingFrequency,
        triggerThreshold: Double,
        maxDeviation: Double,
        volatilityThreshold: Double
    ) {
        self.frequency = frequency
        self.triggerThreshold = triggerThreshold
        self.maxDeviation = maxDeviation
        self.volatilityThreshold = volatilityThreshold
    }
}

public enum RebalancingFrequency: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"
    case onDemand = "on_demand"
}

public struct RiskMetrics: Codable {
    public let portfolioVolatility: Double
    public let sharpeRatio: Double
    public let maxDrawdown: Double
    public let var95: Double
    public let expectedReturn: Double
    public let correlationMatrix: [String: [String: Double]]

    public init(
        portfolioVolatility: Double,
        sharpeRatio: Double,
        maxDrawdown: Double,
        var95: Double,
        expectedReturn: Double,
        correlationMatrix: [String: [String: Double]]
    ) {
        self.portfolioVolatility = portfolioVolatility
        self.sharpeRatio = sharpeRatio
        self.maxDrawdown = maxDrawdown
        self.var95 = var95
        self.expectedReturn = expectedReturn
        self.correlationMatrix = correlationMatrix
    }
}

public struct InterWeekAnalysis: Codable {
    public let weekNumber: Int
    public let startDate: Date
    public let endDate: Date
    public let marketRegime: MarketRegime
    public let sectorPerformance: [CoinCategory: Double]
    public let volatilityClusters: [VolatilityCluster]
    public let momentumShifts: [MomentumShift]
    public let correlationChanges: [CorrelationChange]
    public let liquidityChanges: [LiquidityChange]

    public init(
        weekNumber: Int,
        startDate: Date,
        endDate: Date,
        marketRegime: MarketRegime,
        sectorPerformance: [CoinCategory: Double],
        volatilityClusters: [VolatilityCluster],
        momentumShifts: [MomentumShift],
        correlationChanges: [CorrelationChange],
        liquidityChanges: [LiquidityChange]
    ) {
        self.weekNumber = weekNumber
        self.startDate = startDate
        self.endDate = endDate
        self.marketRegime = marketRegime
        self.sectorPerformance = sectorPerformance
        self.volatilityClusters = volatilityClusters
        self.momentumShifts = momentumShifts
        self.correlationChanges = correlationChanges
        self.liquidityChanges = liquidityChanges
    }
}

public enum MarketRegime: String, Codable, CaseIterable {
    case bull = "bull"
    case bear = "bear"
    case sideways = "sideways"
    case highVolatility = "high_volatility"
    case lowVolatility = "low_volatility"
    case trending = "trending"
    case meanReverting = "mean_reverting"
}

public struct VolatilityCluster: Codable, Identifiable {
    public let id: UUID
    public let coins: [String]
    public let averageVolatility: Double
    public let clusterStrength: Double
    public let startTime: Date
    public let endTime: Date?

    public init(
        id: UUID = UUID(),
        coins: [String],
        averageVolatility: Double,
        clusterStrength: Double,
        startTime: Date,
        endTime: Date? = nil
    ) {
        self.id = id
        self.coins = coins
        self.averageVolatility = averageVolatility
        self.clusterStrength = clusterStrength
        self.startTime = startTime
        self.endTime = endTime
    }
}

public struct MomentumShift: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let oldMomentum: Double
    public let newMomentum: Double
    public let shiftStrength: Double
    public let timestamp: Date
    public let category: CoinCategory

    public init(
        id: UUID = UUID(),
        symbol: String,
        oldMomentum: Double,
        newMomentum: Double,
        shiftStrength: Double,
        timestamp: Date,
        category: CoinCategory
    ) {
        self.id = id
        self.symbol = symbol
        self.oldMomentum = oldMomentum
        self.newMomentum = newMomentum
        self.shiftStrength = shiftStrength
        self.timestamp = timestamp
        self.category = category
    }
}

public struct CorrelationChange: Codable, Identifiable {
    public let id: UUID
    public let pair: String
    public let oldCorrelation: Double
    public let newCorrelation: Double
    public let changeMagnitude: Double
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        pair: String,
        oldCorrelation: Double,
        newCorrelation: Double,
        changeMagnitude: Double,
        timestamp: Date
    ) {
        self.id = id
        self.pair = pair
        self.oldCorrelation = oldCorrelation
        self.newCorrelation = newCorrelation
        self.changeMagnitude = changeMagnitude
        self.timestamp = timestamp
    }
}

public struct LiquidityChange: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let oldLiquidity: Double
    public let newLiquidity: Double
    public let changePercentage: Double
    public let timestamp: Date
    public let exchange: String

    public init(
        id: UUID = UUID(),
        symbol: String,
        oldLiquidity: Double,
        newLiquidity: Double,
        changePercentage: Double,
        timestamp: Date,
        exchange: String
    ) {
        self.id = id
        self.symbol = symbol
        self.oldLiquidity = oldLiquidity
        self.newLiquidity = newLiquidity
        self.changePercentage = changePercentage
        self.timestamp = timestamp
        self.exchange = exchange
    }
}

public struct VolatilityTiming: Codable {
    public let currentVolatility: Double
    public let volatilityPercentile: Double
    public let expectedVolatility: Double
    public let volatilityTrend: VolatilityTrend
    public let optimalAllocationTiming: [AllocationTiming]
    public let riskAdjustedAllocation: Double

    public init(
        currentVolatility: Double,
        volatilityPercentile: Double,
        expectedVolatility: Double,
        volatilityTrend: VolatilityTrend,
        optimalAllocationTiming: [AllocationTiming],
        riskAdjustedAllocation: Double
    ) {
        self.currentVolatility = currentVolatility
        self.volatilityPercentile = volatilityPercentile
        self.expectedVolatility = expectedVolatility
        self.volatilityTrend = volatilityTrend
        self.optimalAllocationTiming = optimalAllocationTiming
        self.riskAdjustedAllocation = riskAdjustedAllocation
    }
}

public enum VolatilityTrend: String, Codable, CaseIterable {
    case increasing = "increasing"
    case decreasing = "decreasing"
    case stable = "stable"
    case volatile = "volatile"
}

public struct AllocationTiming: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let optimalTime: Date
    public let confidence: Double
    public let expectedVolatility: Double
    public let allocationPercentage: Double
    public let rationale: String

    public init(
        id: UUID = UUID(),
        symbol: String,
        optimalTime: Date,
        confidence: Double,
        expectedVolatility: Double,
        allocationPercentage: Double,
        rationale: String
    ) {
        self.id = id
        self.symbol = symbol
        self.optimalTime = optimalTime
        self.confidence = confidence
        self.expectedVolatility = expectedVolatility
        self.allocationPercentage = allocationPercentage
        self.rationale = rationale
    }
}

public struct CoinScore: Codable, Identifiable, Sendable {
    public let id: UUID
    public let symbol: String
    public let totalScore: Double
    public let technicalScore: Double
    public let fundamentalScore: Double
    public let momentumScore: Double
    public let volatilityScore: Double
    public let liquidityScore: Double
    public let category: CoinCategory
    public let riskLevel: RiskLevel
    public let marketCap: Double
    public let volume24h: Double
    public let priceChange24h: Double
    public let priceChange7d: Double
    public let priceChange30d: Double
    public let lastUpdated: Date

    public init(
        id: UUID = UUID(),
        symbol: String,
        totalScore: Double,
        technicalScore: Double,
        fundamentalScore: Double,
        momentumScore: Double,
        volatilityScore: Double,
        liquidityScore: Double,
        category: CoinCategory,
        riskLevel: RiskLevel,
        marketCap: Double,
        volume24h: Double,
        priceChange24h: Double,
        priceChange7d: Double,
        priceChange30d: Double,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.totalScore = totalScore
        self.technicalScore = technicalScore
        self.fundamentalScore = fundamentalScore
        self.momentumScore = momentumScore
        self.volatilityScore = volatilityScore
        self.liquidityScore = liquidityScore
        self.category = category
        self.riskLevel = riskLevel
        self.marketCap = marketCap
        self.volume24h = volume24h
        self.priceChange24h = priceChange24h
        self.priceChange7d = priceChange7d
        self.priceChange30d = priceChange30d
        self.lastUpdated = lastUpdated
    }
}

public struct RebalancingResult: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let trigger: RebalancingTrigger
    public let changes: [RebalancingChange]
    public let expectedImprovement: Double
    public let riskReduction: Double
    public let executionCost: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        trigger: RebalancingTrigger,
        changes: [RebalancingChange],
        expectedImprovement: Double,
        riskReduction: Double,
        executionCost: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.trigger = trigger
        self.changes = changes
        self.expectedImprovement = expectedImprovement
        self.riskReduction = riskReduction
        self.executionCost = executionCost
    }
}

public enum RebalancingTrigger: String, Codable, CaseIterable {
    case timeBased = "time_based"
    case thresholdBreach = "threshold_breach"
    case volatilitySpike = "volatility_spike"
    case correlationChange = "correlation_change"
    case momentumShift = "momentum_shift"
    case liquidityChange = "liquidity_change"
}

public struct RebalancingChange: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public let oldPercentage: Double
    public let newPercentage: Double
    public let changeAmount: Double
    public let exchange: String
    public let rationale: String

    public init(
        id: UUID = UUID(),
        symbol: String,
        oldPercentage: Double,
        newPercentage: Double,
        changeAmount: Double,
        exchange: String,
        rationale: String
    ) {
        self.id = id
        self.symbol = symbol
        self.oldPercentage = oldPercentage
        self.newPercentage = newPercentage
        self.changeAmount = changeAmount
        self.exchange = exchange
        self.rationale = rationale
    }
}
