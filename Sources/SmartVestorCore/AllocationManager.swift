import Foundation
import Utils

public protocol AllocationManagerProtocol {
    func createAllocationPlan(amount: Double) async throws -> AllocationPlan
    func calculateVolatilityAdjustment() async throws -> VolatilityAdjustment?
    func selectAltcoins() async throws -> AltcoinRotation?
}

public class AllocationManager: AllocationManagerProtocol {
    private let config: SmartVestorConfig
    private let persistence: PersistenceProtocol
    private let logger: StructuredLogger

    public init(config: SmartVestorConfig, persistence: PersistenceProtocol) {
        self.config = config
        self.persistence = persistence
        self.logger = StructuredLogger()
    }

    public func createAllocationPlan(amount: Double) async throws -> AllocationPlan {
        logger.info(component: "AllocationManager", event: "Creating allocation plan", data: [
            "amount": String(amount)
        ])

        let baseAllocation = config.baseAllocation
        var adjustedAllocation = AdjustedAllocation(
            btc: baseAllocation.btc,
            eth: baseAllocation.eth,
            altcoins: []
        )

        var rationale = "Base allocation: BTC \(Int(baseAllocation.btc * 100))%, ETH \(Int(baseAllocation.eth * 100))%, Altcoins \(Int(baseAllocation.altcoins * 100))%"

        let volatilityAdjustment = try await calculateVolatilityAdjustment()
        if let adjustment = volatilityAdjustment, adjustment.applied {
            let multiplier = adjustment.multiplier
            adjustedAllocation.btc = min(adjustedAllocation.btc * multiplier, 1.0)
            adjustedAllocation.eth = min(adjustedAllocation.eth * multiplier, 1.0)

            rationale += ". Volatility adjustment applied (7-day σ: \(Int(adjustment.sevenDayVolatility * 100))%, multiplier: \(multiplier))"
        }

        let altcoinRotation = try await selectAltcoins()
        if let rotation = altcoinRotation {
            let totalAltcoinPercentage = config.baseAllocation.altcoins
            let altcoinAllocations = rotation.selectedAltcoins.enumerated().map { index, symbol in
                let percentage = totalAltcoinPercentage / Double(rotation.selectedAltcoins.count)
                return AltcoinAllocation(
                    symbol: symbol,
                    percentage: percentage,
                    exchange: "kraken",
                    spreadScore: rotation.spreadScores[symbol] ?? 0.0
                )
            }
            adjustedAllocation.altcoins = altcoinAllocations

            rationale += ". Altcoin rotation: \(rotation.selectedAltcoins.joined(separator: ", "))"
        }

        let totalAllocation = adjustedAllocation.btc + adjustedAllocation.eth + adjustedAllocation.altcoins.reduce(0) { $0 + $1.percentage }
        if totalAllocation > 1.0 {
            let scaleFactor = 1.0 / totalAllocation
            adjustedAllocation.btc *= scaleFactor
            adjustedAllocation.eth *= scaleFactor
            for i in 0..<adjustedAllocation.altcoins.count {
                adjustedAllocation.altcoins[i].percentage *= scaleFactor
            }

            rationale += ". Scaled down to 100% total allocation"
        }

        let plan = AllocationPlan(
            baseAllocation: baseAllocation,
            adjustedAllocation: adjustedAllocation,
            rationale: rationale,
            volatilityAdjustment: volatilityAdjustment,
            altcoinRotation: altcoinRotation
        )

        logger.info(component: "AllocationManager", event: "Allocation plan created", data: [
            "plan_id": plan.id.uuidString,
            "btc_allocation": String(adjustedAllocation.btc),
            "eth_allocation": String(adjustedAllocation.eth),
            "altcoin_count": String(adjustedAllocation.altcoins.count)
        ])

        return plan
    }

    public func calculateVolatilityAdjustment() async throws -> VolatilityAdjustment? {
        logger.info(component: "AllocationManager", event: "Calculating volatility adjustment")

        let sevenDayVolatility = try await calculateSevenDayVolatility()
        let threshold = config.volatilityThreshold
        let multiplier = config.volatilityMultiplier

        let applied = sevenDayVolatility > threshold

        let adjustment = VolatilityAdjustment(
            sevenDayVolatility: sevenDayVolatility,
            threshold: threshold,
            multiplier: multiplier,
            applied: applied
        )

        logger.info(component: "AllocationManager", event: "Volatility adjustment calculated", data: [
            "seven_day_volatility": String(sevenDayVolatility),
            "threshold": String(threshold),
            "applied": String(applied)
        ])

        return adjustment
    }

    private func calculateSevenDayVolatility() async throws -> Double {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!

        let btcPrices = try await getHistoricalPrices(symbol: "BTC", startDate: startDate, endDate: endDate)
        let ethPrices = try await getHistoricalPrices(symbol: "ETH", startDate: startDate, endDate: endDate)

        let btcVolatility = calculateVolatility(prices: btcPrices)
        let ethVolatility = calculateVolatility(prices: ethPrices)

        return (btcVolatility + ethVolatility) / 2.0
    }

    private func getHistoricalPrices(symbol: String, startDate: Date, endDate: Date) async throws -> [Double] {
        let mockPrices = generateMockPrices(symbol: symbol, startDate: startDate, endDate: endDate)
        return mockPrices
    }

    private func generateMockPrices(symbol: String, startDate: Date, endDate: Date) -> [Double] {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 7
        var prices: [Double] = []

        let basePrice: Double
        switch symbol {
        case "BTC":
            basePrice = 45000.0
        case "ETH":
            basePrice = 3000.0
        default:
            basePrice = 100.0
        }

        var currentPrice = basePrice
        for _ in 0..<days {
            let change = Double.random(in: -0.05...0.05)
            currentPrice *= (1.0 + change)
            prices.append(currentPrice)
        }

        return prices
    }

    private func calculateVolatility(prices: [Double]) -> Double {
        guard prices.count > 1 else { return 0.0 }

        let returns = zip(prices.dropFirst(), prices).map { current, previous in
            (current - previous) / previous
        }

        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(returns.count)

        return sqrt(variance)
    }

    public func selectAltcoins() async throws -> AltcoinRotation? {
        logger.info(component: "AllocationManager", event: "Selecting altcoins for rotation")

        let spreadScores = try await calculateSpreadScores()
        let eligibleAltcoins = spreadScores.filter { $0.value > 0.0 && $0.value < 0.003 }

        guard !eligibleAltcoins.isEmpty else {
            logger.info(component: "AllocationManager", event: "No eligible altcoins found")
            return nil
        }

        let sortedAltcoins = eligibleAltcoins.sorted { $0.value > $1.value }
        let selectedCount = min(3, sortedAltcoins.count)
        let selectedAltcoins = Array(sortedAltcoins.prefix(selectedCount)).map { $0.key }

        let rotation = AltcoinRotation(
            selectedAltcoins: selectedAltcoins,
            spreadScores: spreadScores,
            rotationReason: "Selected top \(selectedCount) altcoins by spread score"
        )

        logger.info(component: "AllocationManager", event: "Altcoin rotation selected", data: [
            "selected_altcoins": selectedAltcoins.joined(separator: ","),
            "spread_scores": String(spreadScores.count)
        ])

        return rotation
    }

    private func calculateSpreadScores() async throws -> [String: Double] {
        let altcoins = ["ADA", "DOT", "LINK", "UNI", "AAVE", "COMP", "MKR", "SNX"]
        var spreadScores: [String: Double] = [:]

        for altcoin in altcoins {
            let spreadScore = Double.random(in: 0.0001...0.002)
            spreadScores[altcoin] = spreadScore
        }

        return spreadScores
    }
}

public class MockAllocationManager: AllocationManagerProtocol {
    private let mockVolatilityAdjustment: VolatilityAdjustment?
    private let mockAltcoinRotation: AltcoinRotation?

    public init(
        mockVolatilityAdjustment: VolatilityAdjustment? = nil,
        mockAltcoinRotation: AltcoinRotation? = nil
    ) {
        self.mockVolatilityAdjustment = mockVolatilityAdjustment
        self.mockAltcoinRotation = mockAltcoinRotation
    }

    public func createAllocationPlan(amount: Double) async throws -> AllocationPlan {
        let baseAllocation = BaseAllocation(btc: 0.4, eth: 0.3, altcoins: 0.3)
        let adjustedAllocation = AdjustedAllocation(
            btc: 0.4,
            eth: 0.3,
            altcoins: [
                AltcoinAllocation(symbol: "ADA", percentage: 0.15, exchange: "kraken", spreadScore: 0.001),
                AltcoinAllocation(symbol: "DOT", percentage: 0.15, exchange: "coinbase", spreadScore: 0.0008)
            ]
        )

        return AllocationPlan(
            baseAllocation: baseAllocation,
            adjustedAllocation: adjustedAllocation,
            rationale: "Mock allocation plan for testing",
            volatilityAdjustment: mockVolatilityAdjustment,
            altcoinRotation: mockAltcoinRotation
        )
    }

    public func calculateVolatilityAdjustment() async throws -> VolatilityAdjustment? {
        return mockVolatilityAdjustment
    }

    public func selectAltcoins() async throws -> AltcoinRotation? {
        return mockAltcoinRotation
    }
}
