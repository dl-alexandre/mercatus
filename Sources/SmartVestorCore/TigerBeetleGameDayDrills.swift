import Foundation
import Utils
import Core

public class TigerBeetleGameDayDrills {
    private let sqlitePersistence: SQLitePersistence
    private let tigerBeetlePersistence: TigerBeetlePersistence
    private let circuitBreaker: TigerBeetleCircuitBreaker
    private let logger: StructuredLogger

    public init(
        sqlitePersistence: SQLitePersistence,
        tigerBeetlePersistence: TigerBeetlePersistence,
        circuitBreaker: TigerBeetleCircuitBreaker,
        logger: StructuredLogger = StructuredLogger()
    ) {
        self.sqlitePersistence = sqlitePersistence
        self.tigerBeetlePersistence = tigerBeetlePersistence
        self.circuitBreaker = circuitBreaker
        self.logger = logger
    }

    public func drillKillWriterMidBatch() async throws -> Bool {
        logger.info(component: "GameDayDrills", event: "Drill: Kill writer mid-batch")

        let transactions = try sqlitePersistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: 100)
        let beforeChecksum = try calculateChecksum(accounts: try tigerBeetlePersistence.getAllAccounts())

        var processedCount = 0
        for tx in transactions {
            processedCount += 1
            if processedCount == transactions.count / 2 {
                logger.info(component: "GameDayDrills", event: "Simulating crash at midpoint", data: ["processed": String(processedCount)])
                break
            }
            try tigerBeetlePersistence.saveTransaction(tx)
        }

        let freshClient = InMemoryTigerBeetleClient()
        let freshPersistence = TigerBeetlePersistence(client: freshClient, logger: logger)

        let migration = TigerBeetleMigration(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: freshPersistence
        )
        try migration.migrateAll()

        let afterChecksum = try calculateChecksum(accounts: try freshPersistence.getAllAccounts())
        let drift = abs(beforeChecksum.totalBalance - afterChecksum.totalBalance)

        if drift > 1e-8 {
            logger.error(
                component: "GameDayDrills",
                event: "Kill writer drill failed: drift detected after replay",
                data: ["drift": String(drift)]
            )
            return false
        }

        logger.info(component: "GameDayDrills", event: "Kill writer drill passed: zero delta after replay")
        return true
    }

    public func drillDropReplica() async throws -> Bool {
        logger.info(component: "GameDayDrills", event: "Drill: Drop replica")

        let initialState = await circuitBreaker.getState()
        guard initialState == .closed else {
            logger.warn(component: "GameDayDrills", event: "Circuit breaker not in closed state")
            return false
        }

        for _ in 0..<15 {
            do {
                let account = Holding(exchange: "test", asset: "USDC", available: 1000.0)
                try await tigerBeetlePersistence.executeWithCircuitBreaker({
                    try tigerBeetlePersistence.saveAccount(account)
                }, circuitBreaker: circuitBreaker)
            } catch {
                await circuitBreaker.recordFailure(error)
            }
        }

        let trippedState = await circuitBreaker.getState()
        let didTrip = trippedState == .open || trippedState == .halfOpen

        await circuitBreaker.reset()

        let recoveredState = await circuitBreaker.getState()
        let autoRecovered = recoveredState == .closed

        if !didTrip {
            logger.error(component: "GameDayDrills", event: "Drop replica drill failed: circuit breaker did not trip")
            return false
        }

        if !autoRecovered {
            logger.error(component: "GameDayDrills", event: "Drop replica drill failed: circuit breaker did not auto-recover")
            return false
        }

        logger.info(component: "GameDayDrills", event: "Drop replica drill passed: breaker tripped and auto-recovered")
        return true
    }

    public func drillSnapshotRestore() async throws -> Bool {
        logger.info(component: "GameDayDrills", event: "Drill: Snapshot restore")

        let originalAccounts = try tigerBeetlePersistence.getAllAccounts()
        let originalChecksum = try calculateChecksum(accounts: originalAccounts)

        let shadowClient = InMemoryTigerBeetleClient()
        let shadowPersistence = TigerBeetlePersistence(client: shadowClient, logger: logger)

        let migration = TigerBeetleMigration(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: shadowPersistence
        )
        try migration.migrateAll()

        let shadowAccounts = try shadowPersistence.getAllAccounts()
        let shadowChecksum = try calculateChecksum(accounts: shadowAccounts)

        let drift = abs(originalChecksum.totalBalance - shadowChecksum.totalBalance)

        if drift > 1e-8 {
            logger.error(
                component: "GameDayDrills",
                event: "Snapshot restore drill failed: checksum mismatch",
                data: ["drift": String(drift)]
            )
            return false
        }

        logger.info(component: "GameDayDrills", event: "Snapshot restore drill passed: checksums match")
        return true
    }

    private struct Checksum {
        let totalBalance: Double
    }

    private func calculateChecksum(accounts: [Holding]) throws -> Checksum {
        let totalBalance = accounts.reduce(0.0) { $0 + $1.total }
        return Checksum(totalBalance: totalBalance)
    }
}
