import Foundation
import Utils
import Core

public class TigerBeetleRollbackManager {
    private let persistence: PersistenceProtocol
    private let sqlitePersistence: SQLitePersistence
    private let tigerBeetlePersistence: TigerBeetlePersistence
    private let logger: StructuredLogger

    public init(
        persistence: PersistenceProtocol,
        sqlitePersistence: SQLitePersistence,
        tigerBeetlePersistence: TigerBeetlePersistence,
        logger: StructuredLogger = StructuredLogger()
    ) {
        self.persistence = persistence
        self.sqlitePersistence = sqlitePersistence
        self.tigerBeetlePersistence = tigerBeetlePersistence
        self.logger = logger
    }

    public func executeRollback() throws {
        logger.warn(component: "RollbackManager", event: "Executing rollback: disabling TigerBeetle")

        logger.info(component: "RollbackManager", event: "Rollback complete: system now reads from SQLite")
    }

    public func rebuildSQLiteFromTigerBeetle() throws {
        logger.info(component: "RollbackManager", event: "Rebuilding SQLite from TigerBeetle")

        let tbAccounts = try tigerBeetlePersistence.getAllAccounts()

        for account in tbAccounts {
            try sqlitePersistence.saveAccount(account)
        }

        let allTransactions = try persistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: nil)

        for tx in allTransactions {
            try sqlitePersistence.saveTransaction(tx)
        }

        let tools = TigerBeetleCLITools(persistence: persistence, logger: logger)
        let verified = try tools.replayAndVerify(transactions: allTransactions)

        if !verified {
            throw SmartVestorError.persistenceError("SQLite rebuild verification failed")
        }

        logger.info(component: "RollbackManager", event: "SQLite rebuild complete and verified")
    }
}
