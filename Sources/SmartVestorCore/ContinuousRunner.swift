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

    public init(
        config: SmartVestorConfig,
        persistence: PersistenceProtocol,
        depositMonitor: DepositMonitorProtocol,
        allocationManager: AllocationManagerProtocol,
        executionEngine: ExecutionEngineProtocol,
        crossExchangeAnalyzer: CrossExchangeAnalyzerProtocol
    ) {
        self.config = config
        self.persistence = persistence
        self.depositMonitor = depositMonitor
        self.allocationManager = allocationManager
        self.executionEngine = executionEngine
        self.crossExchangeAnalyzer = crossExchangeAnalyzer
        self.logger = StructuredLogger()
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

        monitoringTask = Task { [weak self] in
            guard let self = self else { return }

            while self.isRunning {
                do {
                    try await self.runContinuousCycle()

                    try await Task.sleep(nanoseconds: 60_000_000_000) // Check every minute
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
        logger.debug(component: "ContinuousRunner", event: "Running continuous cycle")

        let deposits = try await depositMonitor.scanForDeposits()

        if deposits.isEmpty {
            logger.debug(component: "ContinuousRunner", event: "No new deposits found")
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

        if failedOrders > 0 {
            logger.warn(component: "ContinuousRunner", event: "Some orders failed", data: [
                "failed_count": String(failedOrders)
            ])
        }
    }
}
