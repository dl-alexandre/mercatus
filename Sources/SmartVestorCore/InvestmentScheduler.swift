import Foundation
import Utils

public protocol InvestmentSchedulerProtocol {
    func start() async throws
    func stop() async
    func runInvestmentCycle() async throws
    func scheduleWeekly() async throws
}

public final class InvestmentScheduler: InvestmentSchedulerProtocol, @unchecked Sendable {
    private let config: SmartVestorConfig
    private let persistence: PersistenceProtocol
    private let depositMonitor: DepositMonitorProtocol
    private let allocationManager: AllocationManagerProtocol
    private let executionEngine: ExecutionEngineProtocol
    private let logger: StructuredLogger
    private let crossExchangeAnalyzer: CrossExchangeAnalyzerProtocol

    private var isRunning = false
    private var scheduledTask: Task<Void, Never>?

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

    public func start() async throws {
        guard !isRunning else {
            logger.warn(component: "InvestmentScheduler", event: "Scheduler already running")
            return
        }

        logger.info(component: "InvestmentScheduler", event: "Starting investment scheduler")

        isRunning = true

        if config.simulation.enabled {
            try await runSimulation()
        } else {
            try await scheduleWeekly()
        }
    }

    public func stop() async {
        guard isRunning else {
            logger.warn(component: "InvestmentScheduler", event: "Scheduler not running")
            return
        }

        logger.info(component: "InvestmentScheduler", event: "Stopping investment scheduler")

        isRunning = false
        scheduledTask?.cancel()
        scheduledTask = nil
    }

    public func scheduleWeekly() async throws {
        logger.info(component: "InvestmentScheduler", event: "Scheduling weekly investment cycle")

        scheduledTask = Task { [weak self] in
            guard let self = self else { return }
            while self.isRunning {
                do {
                    try await runInvestmentCycle()

                    let nextRun = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()
                    let timeInterval = nextRun.timeIntervalSince(Date())

                    logger.info(component: "InvestmentScheduler", event: "Next investment cycle scheduled", data: [
                        "next_run": ISO8601DateFormatter().string(from: nextRun)
                    ])

                    try await Task.sleep(nanoseconds: UInt64(timeInterval * 1_000_000_000))
                } catch {
                    logger.error(component: "InvestmentScheduler", event: "Error in scheduled investment cycle", data: [
                        "error": error.localizedDescription
                    ])

                    try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                }
            }
        }
    }

    public func runInvestmentCycle() async throws {
        logger.info(component: "InvestmentScheduler", event: "Starting investment cycle")

        let cycleId = UUID()
        let startTime = Date()

        do {
            try persistence.beginTransaction()

            let auditEntry = AuditEntry(
                component: "InvestmentScheduler",
                action: "cycle_started",
                details: [
                    "cycle_id": cycleId.uuidString,
                    "start_time": ISO8601DateFormatter().string(from: startTime)
                ],
                hash: generateHash(for: cycleId.uuidString)
            )
            try persistence.saveAuditEntry(auditEntry)

            let deposits = try await depositMonitor.scanForDeposits()
            logger.info(component: "InvestmentScheduler", event: "Scanned for deposits", data: [
                "deposit_count": String(deposits.count)
            ])

            for deposit in deposits {
                let validation = try await depositMonitor.validateDeposit(deposit)
                if validation.isValid {
                    try await depositMonitor.confirmDeposit(deposit)
                    logger.info(component: "InvestmentScheduler", event: "Deposit confirmed", data: [
                        "deposit_id": deposit.id.uuidString,
                        "amount": String(deposit.amount)
                    ])
                } else {
                    logger.warn(component: "InvestmentScheduler", event: "Deposit validation failed", data: [
                        "deposit_id": deposit.id.uuidString,
                        "reasons": validation.reasons.joined(separator: "; ")
                    ])
                }
            }

            let accounts = try persistence.getAllAccounts()
            let totalUSDC = accounts.filter { $0.asset == "USDC" }.reduce(0) { $0 + $1.available }

            if totalUSDC >= config.depositAmount {
                logger.info(component: "InvestmentScheduler", event: "Sufficient USDC balance for allocation", data: [
                    "total_usdc": String(totalUSDC)
                ])

                let plan = try await allocationManager.createAllocationPlan(amount: totalUSDC)
                try persistence.saveAllocationPlan(plan)

                logger.info(component: "InvestmentScheduler", event: "Allocation plan created", data: [
                    "plan_id": plan.id.uuidString
                ])

                let results = try await executionEngine.executePlan(plan, dryRun: config.simulation.enabled)

                logger.info(component: "InvestmentScheduler", event: "Plan execution completed", data: [
                    "plan_id": plan.id.uuidString,
                    "successful_orders": String(results.filter { $0.success }.count),
                    "failed_orders": String(results.filter { !$0.success }.count)
                ])
            } else {
                logger.info(component: "InvestmentScheduler", event: "Insufficient USDC balance for allocation", data: [
                    "total_usdc": String(totalUSDC),
                    "required": String(config.depositAmount)
                ])
            }

            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)

            let completionAuditEntry = AuditEntry(
                component: "InvestmentScheduler",
                action: "cycle_completed",
                details: [
                    "cycle_id": cycleId.uuidString,
                    "start_time": ISO8601DateFormatter().string(from: startTime),
                    "end_time": ISO8601DateFormatter().string(from: endTime),
                    "duration_seconds": String(duration)
                ],
                hash: generateHash(for: cycleId.uuidString + String(duration))
            )
            try persistence.saveAuditEntry(completionAuditEntry)

            try persistence.commitTransaction()

            logger.info(component: "InvestmentScheduler", event: "Investment cycle completed successfully", data: [
                "cycle_id": cycleId.uuidString,
                "duration_seconds": String(duration)
            ])

        } catch {
            try? persistence.rollbackTransaction()

            let errorAuditEntry = AuditEntry(
                component: "InvestmentScheduler",
                action: "cycle_failed",
                details: [
                    "cycle_id": cycleId.uuidString,
                    "error": error.localizedDescription
                ],
                hash: generateHash(for: cycleId.uuidString + error.localizedDescription)
            )
            try? persistence.saveAuditEntry(errorAuditEntry)

            logger.error(component: "InvestmentScheduler", event: "Investment cycle failed", data: [
                "cycle_id": cycleId.uuidString,
                "error": error.localizedDescription
            ])

            throw error
        }
    }

    private func runSimulation() async throws {
        logger.info(component: "InvestmentScheduler", event: "Running simulation mode", data: [
            "start_date": config.simulation.startDate?.description ?? "N/A",
            "end_date": config.simulation.endDate?.description ?? "N/A"
        ])

        let startDate = config.simulation.startDate ?? Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let endDate = config.simulation.endDate ?? Date()

        var currentDate = startDate
        let calendar = Calendar.current

        while currentDate <= endDate && isRunning {
            logger.info(component: "InvestmentScheduler", event: "Running simulation for date", data: [
                "date": ISO8601DateFormatter().string(from: currentDate)
            ])

            try await runInvestmentCycle()

            currentDate = calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate) ?? endDate
        }

        logger.info(component: "InvestmentScheduler", event: "Simulation completed")
    }

    private func generateHash(for data: String) -> String {
        return data.data(using: .utf8)?.base64EncodedString() ?? ""
    }
}

public class MockInvestmentScheduler: InvestmentSchedulerProtocol {
    private let mockResults: [String: Any]

    public init(mockResults: [String: Any] = [:]) {
        self.mockResults = mockResults
    }

    public func start() async throws {
    }

    public func stop() async {
    }

    public func runInvestmentCycle() async throws {
    }

    public func scheduleWeekly() async throws {
    }
}
