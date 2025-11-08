import Foundation

public actor TigerBeetleOnlineReconciliation {
    private var lastReconciliation: Date = .distantPast
    private let interval: TimeInterval
    private let reconciliation: TigerBeetleReconciliation
    private var isRunning = false

    public init(
        reconciliation: TigerBeetleReconciliation,
        interval: TimeInterval = 300
    ) {
        self.reconciliation = reconciliation
        self.interval = interval
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        Task {
            await runPeriodicReconciliation()
        }
    }

    public func stop() {
        isRunning = false
    }

    private func runPeriodicReconciliation() async {
        while isRunning {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

            guard isRunning else { break }

            do {
                let results = try reconciliation.reconcileAll()
                let unhealthy = results.filter { !$0.isHealthy }

                if !unhealthy.isEmpty {
                    await reportDrift(unhealthy)
                }
            } catch {

            }
        }
    }

    private func reportDrift(_ unhealthy: [ReconciliationResult]) async {
        for result in unhealthy {
            reconciliation.logger.warn(
                component: "TigerBeetleOnlineReconciliation",
                event: "Balance drift alarm",
                data: [
                    "exchange": result.exchange,
                    "asset": result.asset,
                    "drift": String(result.drift),
                    "threshold": "1e-8"
                ]
            )
        }
    }
}
