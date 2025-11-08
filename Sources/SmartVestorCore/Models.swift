import Foundation
import ArgumentParser

public struct SmartVestorConfig: Codable {
    public let allocationMode: AllocationMode
    public let baseAllocation: BaseAllocation
    public let volatilityThreshold: Double
    public let volatilityMultiplier: Double
    public let feeCap: Double
    public let depositAmount: Double
    public let depositTolerance: Double
    public let rsiThreshold: Double
    public let priceThreshold: Double
    public let movingAveragePeriod: Int
    public let exchanges: [ExchangeConfig]
    public let staking: StakingConfig
    public let simulation: SimulationConfig
    public let scoreBasedAllocation: ScoreBasedAllocationConfig?
    public let maxPortfolioRisk: Double?
    public let marketDataProvider: MarketDataProviderConfig?
    public let swapAnalysis: SwapAnalysisConfig?
    public let tigerbeetle: TigerBeetleConfig?

    public init(
        allocationMode: AllocationMode = .anchorBased,
        baseAllocation: BaseAllocation = BaseAllocation(btc: 0.4, eth: 0.3, altcoins: 0.3),
        volatilityThreshold: Double = 0.15,
        volatilityMultiplier: Double = 1.2,
        feeCap: Double = 0.003,
        depositAmount: Double = 100.0,
        depositTolerance: Double = 0.05,
        rsiThreshold: Double = 70.0,
        priceThreshold: Double = 1.10,
        movingAveragePeriod: Int = 30,
        exchanges: [ExchangeConfig] = [],
        staking: StakingConfig = StakingConfig(),
        simulation: SimulationConfig = SimulationConfig(),
        scoreBasedAllocation: ScoreBasedAllocationConfig? = nil,
        maxPortfolioRisk: Double? = nil,
        marketDataProvider: MarketDataProviderConfig? = nil,
        swapAnalysis: SwapAnalysisConfig? = nil,
        tigerbeetle: TigerBeetleConfig? = nil
    ) {
        self.allocationMode = allocationMode
        self.baseAllocation = baseAllocation
        self.volatilityThreshold = volatilityThreshold
        self.volatilityMultiplier = volatilityMultiplier
        self.feeCap = feeCap
        self.depositAmount = depositAmount
        self.depositTolerance = depositTolerance
        self.rsiThreshold = rsiThreshold
        self.priceThreshold = priceThreshold
        self.movingAveragePeriod = movingAveragePeriod
        self.exchanges = exchanges
        self.staking = staking
        self.simulation = simulation
        self.scoreBasedAllocation = scoreBasedAllocation
        self.maxPortfolioRisk = maxPortfolioRisk
        self.marketDataProvider = marketDataProvider
        self.swapAnalysis = swapAnalysis
        self.tigerbeetle = tigerbeetle
    }
}

public struct TigerBeetleConfig: Codable {
    public let enabled: Bool
    public let clusterId: UInt32
    public let replicaAddresses: [String]
    public let useTigerBeetleForTransactions: Bool
    public let useTigerBeetleForBalances: Bool
    public let liveToggleEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case clusterId
        case replicaAddresses
        case useTigerBeetleForTransactions
        case useTigerBeetleForBalances
        case liveToggleEnabled
    }

    public init(
        enabled: Bool = false,
        clusterId: UInt32 = 0,
        replicaAddresses: [String] = ["127.0.0.1:3001"],
        useTigerBeetleForTransactions: Bool = true,
        useTigerBeetleForBalances: Bool = true,
        liveToggleEnabled: Bool = true
    ) {
        self.enabled = enabled
        self.clusterId = clusterId
        self.replicaAddresses = replicaAddresses
        self.useTigerBeetleForTransactions = useTigerBeetleForTransactions
        self.useTigerBeetleForBalances = useTigerBeetleForBalances
        self.liveToggleEnabled = liveToggleEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        clusterId = try container.decode(UInt32.self, forKey: .clusterId)
        replicaAddresses = try container.decode([String].self, forKey: .replicaAddresses)
        useTigerBeetleForTransactions = try container.decode(Bool.self, forKey: .useTigerBeetleForTransactions)
        useTigerBeetleForBalances = try container.decode(Bool.self, forKey: .useTigerBeetleForBalances)
        liveToggleEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveToggleEnabled) ?? true
    }

    public func validate() throws {
        if enabled && replicaAddresses.isEmpty {
            throw SmartVestorError.configurationError("TigerBeetle enabled but replicaAddresses is empty")
        }
        if enabled && clusterId == 0 && !replicaAddresses.isEmpty {
            throw SmartVestorError.configurationError("TigerBeetle clusterId must be non-zero when enabled")
        }
    }
}

public struct BaseAllocation: Codable {
    public let btc: Double
    public let eth: Double
    public let altcoins: Double

    public init(btc: Double, eth: Double, altcoins: Double) {
        self.btc = btc
        self.eth = eth
        self.altcoins = altcoins
    }

    public var total: Double {
        return btc + eth + altcoins
    }

    public var isValid: Bool {
        return total <= 1.0 && btc >= 0 && eth >= 0 && altcoins >= 0
    }
}

public struct ExchangeConfig: Codable {
    public let name: String
    public let enabled: Bool
    public let apiKey: String?
    public let secretKey: String?
    public let passphrase: String?
    public let sandbox: Bool
    public let supportedNetworks: [String]
    public let rateLimit: RateLimitConfig

    public init(
        name: String,
        enabled: Bool = true,
        apiKey: String? = nil,
        secretKey: String? = nil,
        passphrase: String? = nil,
        sandbox: Bool = false,
        supportedNetworks: [String] = ["USDC-ETH", "USDC-SOL"],
        rateLimit: RateLimitConfig = RateLimitConfig()
    ) {
        self.name = name
        self.enabled = enabled
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.passphrase = passphrase
        self.sandbox = sandbox
        self.supportedNetworks = supportedNetworks
        self.rateLimit = rateLimit
    }
}

public struct RateLimitConfig: Codable {
    public let requestsPerSecond: Int
    public let burstLimit: Int
    public let globalCeiling: Int

    public init(
        requestsPerSecond: Int = 10,
        burstLimit: Int = 50,
        globalCeiling: Int = 100
    ) {
        self.requestsPerSecond = requestsPerSecond
        self.burstLimit = burstLimit
        self.globalCeiling = globalCeiling
    }
}

public struct StakingConfig: Codable {
    public let enabled: Bool
    public let allowedAssets: [String]
    public let minStakingAmount: Double
    public let autoCompound: Bool

    public init(
        enabled: Bool = true,
        allowedAssets: [String] = ["ETH", "SOL"],
        minStakingAmount: Double = 0.1,
        autoCompound: Bool = true
    ) {
        self.enabled = enabled
        self.allowedAssets = allowedAssets
        self.minStakingAmount = minStakingAmount
        self.autoCompound = autoCompound
    }
}

public struct SimulationConfig: Codable {
    public let enabled: Bool
    public let historicalDataPath: String?
    public let startDate: Date?
    public let endDate: Date?
    public let initialCapital: Double?
    public let transactionFee: Double?

    public init(
        enabled: Bool = false,
        historicalDataPath: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        initialCapital: Double? = nil,
        transactionFee: Double? = nil
    ) {
        self.enabled = enabled
        self.historicalDataPath = historicalDataPath
        self.startDate = startDate
        self.endDate = endDate
        self.initialCapital = initialCapital
        self.transactionFee = transactionFee
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case historicalDataPath
        case startDate
        case endDate
        case initialCapital
        case transactionFee
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        historicalDataPath = try container.decodeIfPresent(String.self, forKey: .historicalDataPath)
        initialCapital = try container.decodeIfPresent(Double.self, forKey: .initialCapital)
        transactionFee = try container.decodeIfPresent(Double.self, forKey: .transactionFee)

        if let startDateString = try? container.decodeIfPresent(String.self, forKey: .startDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            startDate = formatter.date(from: startDateString)
        } else {
            startDate = nil
        }

        if let endDateString = try? container.decodeIfPresent(String.self, forKey: .endDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            endDate = formatter.date(from: endDateString)
        } else {
            endDate = nil
        }
    }
}

public struct AllocationPlan: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let baseAllocation: BaseAllocation
    public let adjustedAllocation: AdjustedAllocation
    public let rationale: String
    public let volatilityAdjustment: VolatilityAdjustment?
    public let altcoinRotation: AltcoinRotation?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        baseAllocation: BaseAllocation,
        adjustedAllocation: AdjustedAllocation,
        rationale: String,
        volatilityAdjustment: VolatilityAdjustment? = nil,
        altcoinRotation: AltcoinRotation? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.baseAllocation = baseAllocation
        self.adjustedAllocation = adjustedAllocation
        self.rationale = rationale
        self.volatilityAdjustment = volatilityAdjustment
        self.altcoinRotation = altcoinRotation
    }
}

public struct AdjustedAllocation: Codable {
    public var btc: Double
    public var eth: Double
    public var altcoins: [AltcoinAllocation]

    public init(btc: Double, eth: Double, altcoins: [AltcoinAllocation]) {
        self.btc = btc
        self.eth = eth
        self.altcoins = altcoins
    }

    public var total: Double {
        return btc + eth + altcoins.reduce(0) { $0 + $1.percentage }
    }
}

public struct AltcoinAllocation: Codable, Identifiable {
    public let id: UUID
    public let symbol: String
    public var percentage: Double
    public let exchange: String
    public let spreadScore: Double

    public init(
        id: UUID = UUID(),
        symbol: String,
        percentage: Double,
        exchange: String,
        spreadScore: Double
    ) {
        self.id = id
        self.symbol = symbol
        self.percentage = percentage
        self.exchange = exchange
        self.spreadScore = spreadScore
    }
}

public struct VolatilityAdjustment: Codable {
    public let sevenDayVolatility: Double
    public let threshold: Double
    public let multiplier: Double
    public let applied: Bool

    public init(
        sevenDayVolatility: Double,
        threshold: Double,
        multiplier: Double,
        applied: Bool
    ) {
        self.sevenDayVolatility = sevenDayVolatility
        self.threshold = threshold
        self.multiplier = multiplier
        self.applied = applied
    }
}

public struct AltcoinRotation: Codable {
    public let selectedAltcoins: [String]
    public let spreadScores: [String: Double]
    public let rotationReason: String

    public init(
        selectedAltcoins: [String],
        spreadScores: [String: Double],
        rotationReason: String
    ) {
        self.selectedAltcoins = selectedAltcoins
        self.spreadScores = spreadScores
        self.rotationReason = rotationReason
    }
}

public struct Holding: Codable, Identifiable {
    public let id: UUID
    public let exchange: String
    public let asset: String
    public let available: Double
    public let pending: Double
    public let staked: Double
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        exchange: String,
        asset: String,
        available: Double,
        pending: Double = 0.0,
        staked: Double = 0.0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.exchange = exchange
        self.asset = asset
        self.available = available
        self.pending = pending
        self.staked = staked
        self.updatedAt = updatedAt
    }

    public var total: Double {
        return available + pending + staked
    }
}

public struct InvestmentTransaction: Codable, Identifiable {
    public let id: UUID
    public let type: TransactionType
    public let exchange: String
    public let asset: String
    public let quantity: Double
    public let price: Double
    public let fee: Double
    public let timestamp: Date
    public let metadata: [String: String]
    public let idempotencyKey: String

    public init(
        id: UUID = UUID(),
        type: TransactionType,
        exchange: String,
        asset: String,
        quantity: Double,
        price: Double,
        fee: Double,
        timestamp: Date = Date(),
        metadata: [String: String] = [:],
        idempotencyKey: String = UUID().uuidString
    ) {
        self.id = id
        self.type = type
        self.exchange = exchange
        self.asset = asset
        self.quantity = quantity
        self.price = price
        self.fee = fee
        self.timestamp = timestamp
        self.metadata = metadata
        self.idempotencyKey = idempotencyKey
    }

    public var totalCost: Double {
        return (quantity * price) + fee
    }

    public var effectiveFeePercentage: Double {
        return fee / (quantity * price)
    }
}

public enum TransactionType: String, Codable, CaseIterable {
    case deposit = "deposit"
    case withdrawal = "withdrawal"
    case buy = "buy"
    case sell = "sell"
    case stake = "stake"
    case unstake = "unstake"
    case reward = "reward"
    case fee = "fee"
}

public struct AuditEntry: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let component: String
    public let action: String
    public let details: [String: String]
    public let hash: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        component: String,
        action: String,
        details: [String: String],
        hash: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.component = component
        self.action = action
        self.details = details
        self.hash = hash
    }
}

public struct MarketCondition: Codable {
    public let rsi: Double
    public let priceVsMA30: Double
    public let isOverheated: Bool
    public let shouldDelay: Bool
    public let timestamp: Date

    public init(
        rsi: Double,
        priceVsMA30: Double,
        isOverheated: Bool,
        shouldDelay: Bool,
        timestamp: Date = Date()
    ) {
        self.rsi = rsi
        self.priceVsMA30 = priceVsMA30
        self.isOverheated = isOverheated
        self.shouldDelay = shouldDelay
        self.timestamp = timestamp
    }
}

public struct SpreadAnalysis: Codable {
    public let pair: String
    public let exchanges: [String: ExchangeSpread]
    public let bestExchange: String
    public let totalCost: Double
    public let spreadPercentage: Double
    public let meetsFeeCap: Bool

    public init(
        pair: String,
        exchanges: [String: ExchangeSpread],
        bestExchange: String,
        totalCost: Double,
        spreadPercentage: Double,
        meetsFeeCap: Bool
    ) {
        self.pair = pair
        self.exchanges = exchanges
        self.bestExchange = bestExchange
        self.totalCost = totalCost
        self.spreadPercentage = spreadPercentage
        self.meetsFeeCap = meetsFeeCap
    }
}

public struct ExchangeSpread: Codable {
    public let price: Double
    public let makerFee: Double
    public let takerFee: Double
    public let expectedSlippage: Double
    public let totalCost: Double

    public init(
        price: Double,
        makerFee: Double,
        takerFee: Double,
        expectedSlippage: Double,
        totalCost: Double
    ) {
        self.price = price
        self.makerFee = makerFee
        self.takerFee = takerFee
        self.expectedSlippage = expectedSlippage
        self.totalCost = totalCost
    }
}

public enum AutomationMode: String, CaseIterable, ExpressibleByArgument, Codable, Sendable {
    case continuous = "continuous"
    case weekly = "weekly"

    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}

public enum AllocationMode: String, Codable, CaseIterable {
    case anchorBased = "anchor_based"
    case scoreBased = "score_based"
    case hybrid = "hybrid"
}

public struct ScoreBasedAllocationConfig: Codable {
    public let maxPositions: Int
    public let minScore: Double
    public let maxPositionSize: Double
    public let diversificationTarget: Double
    public let rebalancingThreshold: Double
    public let enableDynamicSizing: Bool
    public let enableMomentumBoost: Bool
    public let enableRiskAdjustment: Bool

    public init(
        maxPositions: Int = 15,
        minScore: Double = 0.4,
        maxPositionSize: Double = 0.15,
        diversificationTarget: Double = 0.8,
        rebalancingThreshold: Double = 0.1,
        enableDynamicSizing: Bool = true,
        enableMomentumBoost: Bool = true,
        enableRiskAdjustment: Bool = true
    ) {
        self.maxPositions = maxPositions
        self.minScore = minScore
        self.maxPositionSize = maxPositionSize
        self.diversificationTarget = diversificationTarget
        self.rebalancingThreshold = rebalancingThreshold
        self.enableDynamicSizing = enableDynamicSizing
        self.enableMomentumBoost = enableMomentumBoost
        self.enableRiskAdjustment = enableRiskAdjustment
    }
}

public struct MarketDataProviderConfig: Codable {
    public let type: String
    public let coinGeckoAPIKey: String?
    public let coinMarketCapAPIKey: String?
    public let cryptoCompareAPIKey: String?
    public let binanceAPIKey: String?
    public let binanceSecretKey: String?
    public let coinbaseAPIKey: String?
    public let coinbaseSecretKey: String?
    public let providerOrder: [String]?
    public let rateLimitDelay: Double
    public let maxRetries: Int

    public init(
        type: String = "mock",
        coinGeckoAPIKey: String? = nil,
        coinMarketCapAPIKey: String? = nil,
        cryptoCompareAPIKey: String? = nil,
        binanceAPIKey: String? = nil,
        binanceSecretKey: String? = nil,
        coinbaseAPIKey: String? = nil,
        coinbaseSecretKey: String? = nil,
        providerOrder: [String]? = nil,
        rateLimitDelay: Double = 1.0,
        maxRetries: Int = 3
    ) {
        self.type = type
        self.coinGeckoAPIKey = coinGeckoAPIKey
        self.coinMarketCapAPIKey = coinMarketCapAPIKey
        self.cryptoCompareAPIKey = cryptoCompareAPIKey
        self.binanceAPIKey = binanceAPIKey
        self.binanceSecretKey = binanceSecretKey
        self.coinbaseAPIKey = coinbaseAPIKey
        self.coinbaseSecretKey = coinbaseSecretKey
        self.providerOrder = providerOrder
        self.rateLimitDelay = rateLimitDelay
        self.maxRetries = maxRetries
    }
}

public struct ExecutionResult: Codable {
    public let asset: String
    public let quantity: Double
    public let price: Double
    public let exchange: String
    public let success: Bool
    public let error: String?
    public let timestamp: Date
    public let orderId: String?

    public init(
        asset: String,
        quantity: Double,
        price: Double,
        exchange: String,
        success: Bool,
        error: String? = nil,
        timestamp: Date = Date(),
        orderId: String? = nil
    ) {
        self.asset = asset
        self.quantity = quantity
        self.price = price
        self.exchange = exchange
        self.success = success
        self.error = error
        self.timestamp = timestamp
        self.orderId = orderId
    }
}

public struct SwapCost: Codable {
    public let sellFee: Double
    public let buyFee: Double
    public let sellSpread: Double
    public let buySpread: Double
    public let sellSlippage: Double
    public let buySlippage: Double
    public let totalCostUSD: Double
    public let costPercentage: Double

    public init(
        sellFee: Double,
        buyFee: Double,
        sellSpread: Double,
        buySpread: Double,
        sellSlippage: Double,
        buySlippage: Double,
        totalCostUSD: Double,
        costPercentage: Double
    ) {
        self.sellFee = sellFee
        self.buyFee = buyFee
        self.sellSpread = sellSpread
        self.buySpread = buySpread
        self.sellSlippage = sellSlippage
        self.buySlippage = buySlippage
        self.totalCostUSD = totalCostUSD
        self.costPercentage = costPercentage
    }
}

public struct SwapBenefit: Codable {
    public let expectedReturnDifferential: Double
    public let portfolioImprovement: Double
    public let riskReduction: Double?
    public let allocationAlignment: Double
    public let totalBenefitUSD: Double
    public let benefitPercentage: Double

    public init(
        expectedReturnDifferential: Double,
        portfolioImprovement: Double,
        riskReduction: Double?,
        allocationAlignment: Double,
        totalBenefitUSD: Double,
        benefitPercentage: Double
    ) {
        self.expectedReturnDifferential = expectedReturnDifferential
        self.portfolioImprovement = portfolioImprovement
        self.riskReduction = riskReduction
        self.allocationAlignment = allocationAlignment
        self.totalBenefitUSD = totalBenefitUSD
        self.benefitPercentage = benefitPercentage
    }
}

public struct SwapEvaluation: Codable, Identifiable, @unchecked Sendable {
    public let id: UUID
    public let fromAsset: String
    public let toAsset: String
    public let fromQuantity: Double
    public let estimatedToQuantity: Double
    public let totalCost: SwapCost
    public let potentialBenefit: SwapBenefit
    public let netValue: Double
    public let isWorthwhile: Bool
    public let confidence: Double
    public let exchange: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        fromAsset: String,
        toAsset: String,
        fromQuantity: Double,
        estimatedToQuantity: Double,
        totalCost: SwapCost,
        potentialBenefit: SwapBenefit,
        netValue: Double,
        isWorthwhile: Bool,
        confidence: Double,
        exchange: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.fromAsset = fromAsset
        self.toAsset = toAsset
        self.fromQuantity = fromQuantity
        self.estimatedToQuantity = estimatedToQuantity
        self.totalCost = totalCost
        self.potentialBenefit = potentialBenefit
        self.netValue = netValue
        self.isWorthwhile = isWorthwhile
        self.confidence = confidence
        self.exchange = exchange
        self.timestamp = timestamp
    }
}

public struct SwapAnalysisConfig: Codable {
    public let enabled: Bool
    public let minProfitThreshold: Double
    public let minProfitPercentage: Double
    public let safetyMultiplier: Double
    public let maxCostPercentage: Double
    public let minConfidence: Double
    public let enableAutoSwaps: Bool
    public let maxSwapsPerCycle: Int

    public init(
        enabled: Bool = true,
        minProfitThreshold: Double = 1.0,
        minProfitPercentage: Double = 0.005,
        safetyMultiplier: Double = 1.2,
        maxCostPercentage: Double = 0.02,
        minConfidence: Double = 0.6,
        enableAutoSwaps: Bool = false,
        maxSwapsPerCycle: Int = 3
    ) {
        self.enabled = enabled
        self.minProfitThreshold = minProfitThreshold
        self.minProfitPercentage = minProfitPercentage
        self.safetyMultiplier = safetyMultiplier
        self.maxCostPercentage = maxCostPercentage
        self.minConfidence = minConfidence
        self.enableAutoSwaps = enableAutoSwaps
        self.maxSwapsPerCycle = maxSwapsPerCycle
    }
}
