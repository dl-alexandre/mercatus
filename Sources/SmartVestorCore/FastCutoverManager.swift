import Foundation
import Utils

public class FastCutoverManager {
    private let sqlitePersistence: SQLitePersistence
    private let tigerBeetlePersistence: TigerBeetlePersistence
    private let hybridPersistence: HybridPersistence
    private let featureFlags: FeatureFlagManager
    private let logger: StructuredLogger
    private let smokeTests: TigerBeetleSmokeTests
    private let sloMonitor: SLOMonitor
    private let extendedMetrics: TigerBeetleExtendedMetrics
    private var executionEnginePaused: Bool = false

    public init(
        sqlitePersistence: SQLitePersistence,
        tigerBeetlePersistence: TigerBeetlePersistence,
        hybridPersistence: HybridPersistence,
        featureFlags: FeatureFlagManager,
        smokeTests: TigerBeetleSmokeTests,
        sloMonitor: SLOMonitor,
        extendedMetrics: TigerBeetleExtendedMetrics,
        logger: StructuredLogger = StructuredLogger()
    ) {
        self.sqlitePersistence = sqlitePersistence
        self.tigerBeetlePersistence = tigerBeetlePersistence
        self.hybridPersistence = hybridPersistence
        self.featureFlags = featureFlags
        self.smokeTests = smokeTests
        self.sloMonitor = sloMonitor
        self.extendedMetrics = extendedMetrics
        self.logger = logger
    }

    public func executeFastCutover() async throws -> CutoverResult {
        logger.info(component: "FastCutover", event: "Starting fast cutover sequence")

        do {
            try await step1_FreezeWrites()
            try await step2_SnapshotAndExport()
            try await step3_ParityCheck()
            try await step4_FlipToTigerBeetle()
            try await step5_UnfreezeWrites()
            let smokeResults = try await step6_ImmediateSmoke()

            if smokeResults.passed {
                logger.info(component: "FastCutover", event: "Fast cutover completed successfully")
                return .success(smokeResults)
            } else {
                logger.error(component: "FastCutover", event: "Fast cutover completed but smoke tests failed", data: ["violations": String(smokeResults.violations.count)])
                return .partialSuccess(smokeResults)
            }
        } catch {
            logger.error(component: "FastCutover", event: "Fast cutover failed", data: ["error": error.localizedDescription])
            throw error
        }
    }

    private func step1_FreezeWrites() async throws {
        logger.info(component: "FastCutover", event: "Step 1: Freezing writes for 2-3 minutes")

        setenv("EXECUTIONENGINE_WRITES", "false", 1)
        executionEnginePaused = true

        logger.info(component: "FastCutover", event: "Writes frozen. Waiting 2 minutes for in-flight operations to complete")

        try await Task.sleep(nanoseconds: 2 * 60 * 1_000_000_000)
    }

    private func step2_SnapshotAndExport() async throws {
        logger.info(component: "FastCutover", event: "Step 2: Creating SQLite snapshot and exporting ledger")

        let dbPath = getSQLiteDBPath()
        let backupPath = "\(dbPath).pre_cutover.backup"

        let sqliteBackup = SQLiteBackupManager(dbPath: dbPath)
        try sqliteBackup.createBackup(to: backupPath)

        let tools = TigerBeetleCLITools(persistence: hybridPersistence, logger: logger)
        let ledgerData = try tools.exportLedger()
        let ledgerPath = "pre_cutover_ledger.json"
        try ledgerData.write(to: URL(fileURLWithPath: ledgerPath))

        logger.info(
            component: "FastCutover",
            event: "Snapshot and export completed",
            data: [
                "backup_path": backupPath,
                "ledger_path": ledgerPath
            ]
        )
    }

    private func step3_ParityCheck() async throws {
        logger.info(component: "FastCutover", event: "Step 3: Running one-time parity check")

        let tools = TigerBeetleCLITools(persistence: hybridPersistence, logger: logger)
        let allTransactions = try hybridPersistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: nil)

        let verified = try tools.replayAndVerify(transactions: allTransactions)

        if !verified {
            let error = SmartVestorError.persistenceError("Parity check failed: replay verification returned false")
            logger.error(component: "FastCutover", event: "Parity check failed. Aborting cutover.")
            throw error
        }

        logger.info(component: "FastCutover", event: "Parity check passed: zero drift")
    }

    private func step4_FlipToTigerBeetle() async throws {
        logger.info(component: "FastCutover", event: "Step 4: Flipping to TigerBeetle as source of truth")

        await featureFlags.enable(.readFromTigerBeetle)
        await featureFlags.enable(.disableSQLiteWrites)

        logger.info(
            component: "FastCutover",
            event: "Feature flags updated",
            data: [
                "read_from_tigerbeetle": "true",
                "disable_sqlite_writes": "true"
            ]
        )
    }

    private func step5_UnfreezeWrites() async throws {
        logger.info(component: "FastCutover", event: "Step 5: Unfreezing writes")

        setenv("EXECUTIONENGINE_WRITES", "true", 1)
        executionEnginePaused = false

        logger.info(component: "FastCutover", event: "Writes unfrozen. ExecutionEngine now routing to TigerBeetle only")
    }

    private func step6_ImmediateSmoke() async throws -> (passed: Bool, violations: [String]) {
        logger.info(component: "FastCutover", event: "Step 6: Running immediate smoke tests (10 minutes)")

        let _ = hybridPersistence

        let exportDeterministic = try smokeTests.testExportBalancesDeterministic()

        let lastMarkerID = try getLastCutoverMarkerID()
        let diffEmpty = try smokeTests.testDiffLedgerEmpty(sinceMarker: lastMarkerID)

        let sloResults = try await smokeTests.verifySLOs(
            sloMonitor: sloMonitor,
            extendedMetrics: extendedMetrics
        )

        let allPassed = exportDeterministic && diffEmpty && sloResults.passed

        logger.info(
            component: "FastCutover",
            event: allPassed ? "All smoke tests passed" : "Some smoke tests failed",
            data: [
                "export_deterministic": String(exportDeterministic),
                "diff_empty": String(diffEmpty),
                "slos_passed": String(sloResults.passed),
                "total_violations": String(sloResults.violations.count)
            ]
        )

        return (passed: allPassed, violations: sloResults.violations)
    }

    private func getLastTransactionID() throws -> UUID {
        let transactions = try hybridPersistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: 1)
        return transactions.first?.id ?? UUID()
    }

    private func getSQLiteDBPath() -> String {
        return "smartvestor.db"
    }

    private func getLastCutoverMarkerID() throws -> UUID {
        let allTransactions = try hybridPersistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: 1)
        if let lastTx = allTransactions.first {
            return lastTx.id
        }
        return UUID()
    }

    public func executeRollback() async throws {
        logger.warn(component: "FastCutover", event: "Executing rollback")

        setenv("EXECUTIONENGINE_WRITES", "false", 1)
        executionEnginePaused = true

        await featureFlags.disable(.readFromTigerBeetle)
        await featureFlags.disable(.disableSQLiteWrites)

        let rollbackManager = TigerBeetleRollbackManager(
            persistence: hybridPersistence,
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: tigerBeetlePersistence,
            logger: logger
        )

        try rollbackManager.rebuildSQLiteFromTigerBeetle()

        setenv("EXECUTIONENGINE_WRITES", "true", 1)
        executionEnginePaused = false

        logger.info(component: "FastCutover", event: "Rollback completed. System now reading from SQLite")
    }
}

public enum CutoverResult {
    case success((passed: Bool, violations: [String]))
    case partialSuccess((passed: Bool, violations: [String]))
    case failure(Error)
}
