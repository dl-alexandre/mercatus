import Foundation
import Utils

public final class ContinuousRunner: @unchecked Sendable {
    private let config: SmartVestorConfig
    private let persistence: PersistenceProtocol
    private let depositMonitor: DepositMonitorProtocol
    private let allocationManager: AllocationManagerProtocol
    private let executionEngine: ExecutionEngineProtocol
    private let logger: StructuredLogger
    private let crossExchangeAnalyzer: CrossExchangeAnalyzerProtocol

    private let isRunningLock = NSLock()
    private var _isRunning = false
    private var monitoringTask: Task<Void, Never>?

    private var isRunning: Bool {
        get {
            isRunningLock.lock()
            defer { isRunningLock.unlock() }
            return _isRunning
        }
        set {
            isRunningLock.lock()
            defer { isRunningLock.unlock() }
            _isRunning = newValue
        }
    }

    private var tuiServer: TUIServer?
    private let stateManager: AutomationStateManager
    private var lastBalanceRefreshAt: Date?

    public func setTUI(server: TUIServer) {
        self.tuiServer = server
    }

    public init(
        config: SmartVestorConfig,
        persistence: PersistenceProtocol,
        depositMonitor: DepositMonitorProtocol,
        allocationManager: AllocationManagerProtocol,
        executionEngine: ExecutionEngineProtocol,
        crossExchangeAnalyzer: CrossExchangeAnalyzerProtocol,
        stateManager: AutomationStateManager? = nil,
        logger: StructuredLogger? = nil
    ) {
        self.config = config
        self.persistence = persistence
        self.depositMonitor = depositMonitor
        self.allocationManager = allocationManager
        self.executionEngine = executionEngine
        self.crossExchangeAnalyzer = crossExchangeAnalyzer
        self.logger = logger ?? StructuredLogger()
        self.stateManager = stateManager ?? AutomationStateManager(logger: logger ?? StructuredLogger())
    }

    public func startContinuousMonitoring() async throws {
        guard !isRunning else {
            logger.warn(component: "ContinuousRunner", event: "Already running")
            return
        }

        logger.info(component: "ContinuousRunner", event: "Starting continuous USDC monitoring", data: [
            "min_deposit": String(config.depositAmount),
            "tolerance": String(config.depositTolerance)
        ])

        isRunning = true

        await publishTUI(event: TUIUpdate.UpdateType.heartbeat)

        monitoringTask = Task { [weak self] in
            guard let self = self else { return }

            while self.isRunning {
                do {
                    try await self.runContinuousCycle()
                    await self.refreshBalancesIfStale()
                    await self.publishTUI(event: TUIUpdate.UpdateType.heartbeat)

                    try await Task.sleep(nanoseconds: 10_000_000_000) // Check every 10 seconds
                } catch {
                    self.logger.error(component: "ContinuousRunner", event: "Error in continuous cycle", data: [
                        "error": error.localizedDescription
                    ])

                    try? await Task.sleep(nanoseconds: 300_000_000_000) // Wait 5 minutes on error
                }
            }
        }
    }

    public func stopContinuousMonitoring() async {
        guard isRunning else { return }

        logger.info(component: "ContinuousRunner", event: "Stopping continuous monitoring")

        isRunning = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func runContinuousCycle() async throws {
        let deposits = try await depositMonitor.scanForDeposits()

        if deposits.isEmpty {
            return
        }

        logger.info(component: "ContinuousRunner", event: "Found deposits", data: [
            "count": String(deposits.count)
        ])

        var totalNewUSDC = 0.0

        for deposit in deposits {
            let validation = try await depositMonitor.validateDeposit(deposit)

            if validation.isValid {
                try await depositMonitor.confirmDeposit(deposit)
                totalNewUSDC += deposit.amount

                logger.info(component: "ContinuousRunner", event: "Deposit confirmed", data: [
                    "deposit_id": deposit.id.uuidString,
                    "amount": String(deposit.amount),
                    "exchange": deposit.exchange
                ])

                await publishTUI(event: TUIUpdate.UpdateType.depositDetected)
            } else {
                logger.warn(component: "ContinuousRunner", event: "Deposit validation failed", data: [
                    "deposit_id": deposit.id.uuidString,
                    "amount": String(deposit.amount),
                    "reasons": validation.reasons.joined(separator: "; ")
                ])
            }
        }

        if totalNewUSDC > 0 {
            logger.info(component: "ContinuousRunner", event: "New USDC detected", data: [
                "total_amount": String(totalNewUSDC)
            ])

            try await allocateUSDCToHighRankingCoins(amount: totalNewUSDC)
        }
    }

    private func allocateUSDCToHighRankingCoins(amount: Double) async throws {
        logger.info(component: "ContinuousRunner", event: "Allocating USDC to high-ranking coins", data: [
            "amount": String(amount)
        ])

        let plan = try await allocationManager.createAllocationPlan(amount: amount)
        try persistence.saveAllocationPlan(plan)

        logger.info(component: "ContinuousRunner", event: "Allocation plan created", data: [
            "plan_id": plan.id.uuidString,
            "btc_percentage": String(plan.adjustedAllocation.btc * 100),
            "eth_percentage": String(plan.adjustedAllocation.eth * 100),
            "altcoin_count": String(plan.adjustedAllocation.altcoins.count)
        ])

        let results = try await executionEngine.executePlan(plan, dryRun: config.simulation.enabled)

        let successfulOrders = results.filter { $0.success }.count
        let failedOrders = results.filter { !$0.success }.count

        logger.info(component: "ContinuousRunner", event: "Allocation executed", data: [
            "plan_id": plan.id.uuidString,
            "successful_orders": String(successfulOrders),
            "failed_orders": String(failedOrders),
            "total_amount_allocated": String(amount)
        ])

        if successfulOrders > 0 {
            await publishTUI(event: TUIUpdate.UpdateType.tradeExecuted)
        }

        if failedOrders > 0 {
            logger.warn(component: "ContinuousRunner", event: "Some orders failed", data: [
                "failed_count": String(failedOrders)
            ])
        }
    }

    private func refreshBalancesIfStale(maxAgeSeconds: TimeInterval = 300) async {
        let now = Date()
        if let lastRefresh = lastBalanceRefreshAt, now.timeIntervalSince(lastRefresh) < maxAgeSeconds {
            return
        }

        guard let engine = executionEngine as? ExecutionEngine else {
            logger.warn(component: "ContinuousRunner", event: "Balance refresh skipped", data: [
                "error": "ExecutionEngine type not available"
            ])
            return
        }

        do {
            let balances = try await engine.refreshRobinhoodBalances()
            lastBalanceRefreshAt = now
            logger.debug(component: "ContinuousRunner", event: "Balances refreshed", data: [
                "asset_count": String(balances.count)
            ])
        } catch {
            logger.warn(component: "ContinuousRunner", event: "Balance refresh skipped", data: [
                "error": error.localizedDescription
            ])
        }
    }

    private func publishTUI(event: TUIUpdate.UpdateType) async {
        guard let tuiServer = tuiServer else { return }
        do {
            let balances = try persistence.getAllAccounts()
            let recent = try persistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: 10)
            var symbols = Array(Set(balances.map { $0.asset }))

            if !symbols.contains("USDC") && !symbols.contains("USD") {
                symbols.append("USDC")
            }

            var prices: [String: Double] = [:]
            let provider = MultiProviderMarketDataProvider()

            func aliasCandidates(for asset: String) -> [String] {
                switch asset {
                case "WLFI": return ["WIF", "WLF", "WOLF"]
                default: return []
                }
            }

            if !symbols.isEmpty {
                let aliasSymbols = symbols.flatMap { aliasCandidates(for: $0) }
                let allSymbolsToFetch = Array(Set(symbols + aliasSymbols))

                if !allSymbolsToFetch.isEmpty {
                    let fetchedPrices = (try? await provider.getCurrentPrices(symbols: allSymbolsToFetch)) ?? [:]

                    for asset in symbols {
                        if let directPrice = fetchedPrices[asset], directPrice > 0 {
                            prices[asset] = directPrice
                        } else {
                            for alias in aliasCandidates(for: asset) {
                                if let aliasPrice = fetchedPrices[alias], aliasPrice > 0 {
                                    prices[asset] = aliasPrice
                                    break
                                }
                            }
                        }
                    }
                }
            }

            for asset in symbols {
                if prices[asset] == nil {
                    prices[asset] = 0.0
                }
            }

            if prices["USDC"] == nil && prices["USD"] == nil {
                let usdcPrice = (try? await provider.getCurrentPrices(symbols: ["USDC"]))?["USDC"] ?? 1.0
                prices["USDC"] = usdcPrice
                prices["USD"] = usdcPrice
            }

            func price(for asset: String) -> Double {
                if let p = prices[asset], p > 0 { return p }
                return 0
            }
            let totalValue = balances.reduce(0.0) { acc, h in acc + h.total * price(for: h.asset) }
            let actualState = (try? stateManager.load()) ?? AutomationState(
                isRunning: true,
                mode: config.simulation.enabled ? .continuous : .continuous,
                startedAt: Date(),
                lastExecutionTime: Date(),
                nextExecutionTime: nil,
                pid: ProcessInfo.processInfo.processIdentifier
            )
            let state = AutomationState(
                isRunning: actualState.isRunning,
                mode: actualState.mode,
                startedAt: actualState.startedAt,
                lastExecutionTime: Date(),
                nextExecutionTime: actualState.nextExecutionTime,
                pid: actualState.pid
            )

            let swapEvaluations = generateSwapEvaluations(
                balances: balances,
                prices: prices
            )

            let data = TUIData(
                recentTrades: recent,
                balances: balances,
                circuitBreakerOpen: false,
                lastExecutionTime: state.lastExecutionTime,
                nextExecutionTime: state.nextExecutionTime,
                totalPortfolioValue: totalValue,
                errorCount: 0,
                prices: prices,
                swapEvaluations: swapEvaluations
            )
            tuiServer.publish(type: event, state: state, data: data)
        } catch {
            logger.error(component: "ContinuousRunner", event: "Error publishing TUI update", data: [
                "error": error.localizedDescription
            ])
        }
    }
}

private func valueForHolding(_ holding: Holding, using prices: [String: Double]) -> Double {
    let price = prices[holding.asset] ?? 0.0
    return holding.total * price
}

private func deterministicFactor(for key: String) -> Double {
    let scalarSum = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return Double((scalarSum % 100)) / 100.0
}

private func generateSwapEvaluations(
    balances: [Holding],
    prices: [String: Double]
) -> [SwapEvaluation] {
    let excludedAssets: Set<String> = ["USD", "USDC", "CASH"]
    let tradable = balances.filter { !excludedAssets.contains($0.asset.uppercased()) && (prices[$0.asset] ?? 0) > 0 }
    guard tradable.count >= 2 else { return [] }

    let sortedByValue = tradable.sorted {
        valueForHolding($0, using: prices) > valueForHolding($1, using: prices)
    }

    let donors = Array(sortedByValue.prefix(4))
    let receivers = Array(sortedByValue.suffix(4))

    var evaluations: [SwapEvaluation] = []
    var uuidGenerator = DeterministicUUIDGenerator(startingCounter: 1)

    for donor in donors {
        let donorPrice = prices[donor.asset] ?? 0.0
        let donorValue = donor.total * donorPrice
        guard donorValue > 25 else { continue }

        for receiver in receivers {
            guard receiver.asset != donor.asset else { continue }
            let receiverPrice = prices[receiver.asset] ?? 0
            guard receiverPrice > 0 else { continue }

            let baseFraction = 0.05 + 0.02 * deterministicFactor(for: donor.asset + receiver.asset)
            let fromQuantity = max(0.0001, (donorValue * baseFraction) / max(donorPrice, 0.0001))
            let sellValue = fromQuantity * donorPrice
            guard sellValue > 1 else { continue }

            let feeFraction = 0.0006 + 0.0004 * deterministicFactor(for: receiver.asset + donor.asset)
            let spreadSeed = String(donor.asset.reversed()) + receiver.asset
            let slippageSeed = String(receiver.asset.reversed()) + donor.asset
            let spreadFraction = 0.0009 + 0.0003 * deterministicFactor(for: spreadSeed)
            let slippageFraction = 0.0005 + 0.0003 * deterministicFactor(for: slippageSeed)

            let sellFee = sellValue * feeFraction
            let buyFee = sellValue * feeFraction
            let sellSpread = sellValue * spreadFraction
            let buySpread = sellValue * spreadFraction
            let sellSlippage = sellValue * slippageFraction
            let buySlippage = sellValue * slippageFraction
            let totalCostUSD = sellFee + buyFee + sellSpread + buySpread + sellSlippage + buySlippage
            let costPercentage = sellValue > 0 ? (totalCostUSD / sellValue) * 100 : 0

            let benefitMultiplier = 0.012 + 0.008 * deterministicFactor(for: donor.asset + ":" + receiver.asset)
            let totalBenefitUSD = sellValue * benefitMultiplier
            let expectedReturnDifferential = totalBenefitUSD * 0.45
            let portfolioImprovement = totalBenefitUSD * 0.3
            let riskReduction = totalBenefitUSD > 3 ? totalBenefitUSD * 0.1 : nil
            let allocationAlignment = totalBenefitUSD * 0.25
            let benefitPercentage = sellValue > 0 ? totalBenefitUSD / sellValue : 0

            let remainingValue = max(0.0, sellValue - totalCostUSD + totalBenefitUSD)
            let estimatedToQuantity = remainingValue / receiverPrice
            let netValue = totalBenefitUSD - totalCostUSD
            let confidenceBase = 0.45 + 0.4 * deterministicFactor(for: receiver.asset + donor.asset)
            let confidence = min(0.95, max(0.25, confidenceBase))
            let isWorthwhile = netValue >= max(0.75, totalCostUSD * 0.8)

            let evaluation = SwapEvaluation(
                id: uuidGenerator.generate(),
                fromAsset: donor.asset,
                toAsset: receiver.asset,
                fromQuantity: fromQuantity,
                estimatedToQuantity: estimatedToQuantity,
                totalCost: SwapCost(
                    sellFee: sellFee,
                    buyFee: buyFee,
                    sellSpread: sellSpread,
                    buySpread: buySpread,
                    sellSlippage: sellSlippage,
                    buySlippage: buySlippage,
                    totalCostUSD: totalCostUSD,
                    costPercentage: costPercentage
                ),
                potentialBenefit: SwapBenefit(
                    expectedReturnDifferential: expectedReturnDifferential,
                    portfolioImprovement: portfolioImprovement,
                    riskReduction: riskReduction,
                    allocationAlignment: allocationAlignment,
                    totalBenefitUSD: totalBenefitUSD,
                    benefitPercentage: benefitPercentage
                ),
                netValue: netValue,
                isWorthwhile: isWorthwhile,
                confidence: confidence,
                exchange: donor.exchange
            )

            evaluations.append(evaluation)
            if evaluations.count >= 12 {
                break
            }
        }
        if evaluations.count >= 12 {
            break
        }
    }

    return evaluations.sorted { $0.netValue > $1.netValue }
}

private func awaitSync<T>(_ body: (@escaping (T?) -> Void) -> Void) throws -> T? {
    let group = DispatchGroup()
    group.enter()
    var result: T?
    body { value in result = value; group.leave() }
    group.wait()
    return result
}
