import Foundation
import Utils

public class TigerBeetleMigration {
    private let sqlitePersistence: SQLitePersistence
    private let tigerBeetlePersistence: TigerBeetlePersistence
    private let logger: StructuredLogger

    public init(
        sqlitePersistence: SQLitePersistence,
        tigerBeetlePersistence: TigerBeetlePersistence,
        logger: StructuredLogger = StructuredLogger()
    ) {
        self.sqlitePersistence = sqlitePersistence
        self.tigerBeetlePersistence = tigerBeetlePersistence
        self.logger = logger
    }

    public func migrateAll() throws {
        logger.info(component: "TigerBeetleMigration", event: "Starting migration from SQLite to TigerBeetle")

        let sqliteChecksum = try calculateSQLiteChecksum()

        try migrateAccounts()
        try migrateTransactions()

        let tigerBeetleChecksum = try calculateTigerBeetleChecksum()

        if sqliteChecksum.totalBalance != tigerBeetleChecksum.totalBalance {
            throw SmartVestorError.persistenceError(
                "Checksum mismatch: SQLite total=\(sqliteChecksum.totalBalance), TigerBeetle total=\(tigerBeetleChecksum.totalBalance)"
            )
        }

        logger.info(
            component: "TigerBeetleMigration",
            event: "Migration completed successfully",
            data: [
                "sqlite_balance": String(sqliteChecksum.totalBalance),
                "tigerbeetle_balance": String(tigerBeetleChecksum.totalBalance),
                "account_count": String(sqliteChecksum.accountCount),
                "transaction_count": String(sqliteChecksum.transactionCount)
            ]
        )
    }

    private struct MigrationChecksum {
        let totalBalance: Double
        let accountCount: Int
        let transactionCount: Int
    }

    private func calculateSQLiteChecksum() throws -> MigrationChecksum {
        let accounts = try sqlitePersistence.getAllAccounts()
        let transactions = try sqlitePersistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: nil)

        let totalBalance = accounts.reduce(0.0) { $0 + $1.total }

        return MigrationChecksum(
            totalBalance: totalBalance,
            accountCount: accounts.count,
            transactionCount: transactions.count
        )
    }

    private func calculateTigerBeetleChecksum() throws -> MigrationChecksum {
        let allAccounts = try tigerBeetlePersistence.getAllAccounts()
        let totalBalance = allAccounts.reduce(0.0) { $0 + $1.total }

        return MigrationChecksum(
            totalBalance: totalBalance,
            accountCount: allAccounts.count,
            transactionCount: 0
        )
    }

    private func migrateAccounts() throws {
        logger.info(component: "TigerBeetleMigration", event: "Migrating accounts")

        let accounts = try sqlitePersistence.getAllAccounts()

        for account in accounts {
            try tigerBeetlePersistence.saveAccount(account)
        }

        logger.info(
            component: "TigerBeetleMigration",
            event: "Migrated accounts",
            data: ["count": String(accounts.count)]
        )
    }

    private func migrateTransactions() throws {
        logger.info(component: "TigerBeetleMigration", event: "Migrating transactions")

        let transactions = try sqlitePersistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: nil)

        var successCount = 0
        var errorCount = 0

        for transaction in transactions {
            do {
                try tigerBeetlePersistence.saveTransaction(transaction)
                successCount += 1
            } catch {
                errorCount += 1
                logger.warn(
                    component: "TigerBeetleMigration",
                    event: "Failed to migrate transaction",
                    data: [
                        "transaction_id": transaction.id.uuidString,
                        "error": error.localizedDescription
                    ]
                )
            }
        }

        logger.info(
            component: "TigerBeetleMigration",
            event: "Migrated transactions",
            data: [
                "total": String(transactions.count),
                "success": String(successCount),
                "errors": String(errorCount)
            ]
        )
    }
}
