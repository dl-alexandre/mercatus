import Foundation

public struct CutoverSLO {
    public let zeroDriftDays: Int
    public let mirrorPhaseDays: Int
    public let readPhaseDays: Int
    public let maxDriftThreshold: Double

    public init(
        zeroDriftDays: Int = 7,
        mirrorPhaseDays: Int = 7,
        readPhaseDays: Int = 30,
        maxDriftThreshold: Double = 1e-8
    ) {
        self.zeroDriftDays = zeroDriftDays
        self.mirrorPhaseDays = mirrorPhaseDays
        self.readPhaseDays = readPhaseDays
        self.maxDriftThreshold = maxDriftThreshold
    }
}

public actor CutoverGuardrails {
    private var phaseStartDate: Date?
    private var consecutiveZeroDriftDays: Int = 0
    private var lastDriftCheck: Date?
    private let slo: CutoverSLO
    private let reconciliation: TigerBeetleReconciliation

    public init(
        slo: CutoverSLO,
        reconciliation: TigerBeetleReconciliation
    ) {
        self.slo = slo
        self.reconciliation = reconciliation
    }

    public func startPhase(_ phase: CutoverPhase) {
        phaseStartDate = Date()
        consecutiveZeroDriftDays = 0
    }

    public func recordReconciliation(_ results: [ReconciliationResult]) {
        let hasDrift = results.contains { !$0.isHealthy }

        if !hasDrift {
            consecutiveZeroDriftDays += 1
        } else {
            consecutiveZeroDriftDays = 0
        }

        lastDriftCheck = Date()
    }

    public func canAdvanceToReadPhase() -> Bool {
        guard let startDate = phaseStartDate else { return false }
        let daysInPhase = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0

        return daysInPhase >= slo.mirrorPhaseDays && consecutiveZeroDriftDays >= slo.zeroDriftDays
    }

    public func canAdvanceToDisableSQLite() -> Bool {
        guard let startDate = phaseStartDate else { return false }
        let daysInPhase = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0

        return daysInPhase >= slo.readPhaseDays && consecutiveZeroDriftDays >= slo.zeroDriftDays
    }

    public func getStatus() -> (
        phase: CutoverPhase,
        daysInPhase: Int,
        consecutiveZeroDriftDays: Int,
        canAdvance: Bool
    ) {
        let daysInPhase = phaseStartDate.map {
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
        } ?? 0

        let canAdvance = canAdvanceToDisableSQLite() || canAdvanceToReadPhase()

        return (
            phase: .mirror,
            daysInPhase: daysInPhase,
            consecutiveZeroDriftDays: consecutiveZeroDriftDays,
            canAdvance: canAdvance
        )
    }
}
