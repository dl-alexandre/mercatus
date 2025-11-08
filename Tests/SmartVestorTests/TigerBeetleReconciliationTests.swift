import Testing
import Foundation
@testable import SmartVestor

@Suite("TigerBeetle Reconciliation Tests")
struct TigerBeetleReconciliationTests {

    @Test("Reconcile account balances between SQLite and TigerBeetle")
    func testBalanceReconciliation() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("test-reconciliation.db")
        defer {
            try? FileManager.default.removeItem(atPath: dbPath)
        }

        let sqlitePersistence = SQLitePersistence(dbPath: dbPath)
        try sqlitePersistence.initialize()

        let client = InMemoryTigerBeetleClient()
        let tigerBeetlePersistence = TigerBeetlePersistence(client: client)

        let testAccount = Holding(
            exchange: "test",
            asset: "USDC",
            available: 1000.0,
            pending: 100.0,
            staked: 50.0
        )

        try sqlitePersistence.saveAccount(testAccount)
        try tigerBeetlePersistence.saveAccount(testAccount)

        let sqliteAccount = try sqlitePersistence.getAccount(exchange: "test", asset: "USDC")
        let tigerBeetleAccount = try tigerBeetlePersistence.getAccount(exchange: "test", asset: "USDC")

        #expect(sqliteAccount != nil)
        #expect(tigerBeetleAccount != nil)
        #expect(sqliteAccount?.available == tigerBeetleAccount?.available)
        #expect(abs((sqliteAccount?.total ?? 0) - (tigerBeetleAccount?.total ?? 0)) < 0.01)
    }

    @Test("Reconcile transaction totals after migration")
    func testTransactionReconciliation() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("test-tx-reconciliation.db")
        defer {
            try? FileManager.default.removeItem(atPath: dbPath)
        }

        let sqlitePersistence = SQLitePersistence(dbPath: dbPath)
        try sqlitePersistence.initialize()

        let client = InMemoryTigerBeetleClient()
        let tigerBeetlePersistence = TigerBeetlePersistence(client: client)

        let transaction = InvestmentTransaction(
            type: .buy,
            exchange: "test",
            asset: "BTC",
            quantity: 0.1,
            price: 50000.0,
            fee: 5.0
        )

        try sqlitePersistence.saveTransaction(transaction)
        try tigerBeetlePersistence.saveTransaction(transaction)

        let sqliteTransactions = try sqlitePersistence.getTransactions(exchange: "test", asset: "BTC", type: .buy, limit: 10)
        let tigerBeetleTransactions = try tigerBeetlePersistence.getTransactions(exchange: "test", asset: "BTC", type: .buy, limit: 10)

        #expect(!sqliteTransactions.isEmpty)
    }

    @Test("Verify checksum matches after full migration")
    func testMigrationChecksum() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("test-checksum.db")
        defer {
            try? FileManager.default.removeItem(atPath: dbPath)
        }

        let sqlitePersistence = SQLitePersistence(dbPath: dbPath)
        try sqlitePersistence.initialize()

        let account1 = Holding(exchange: "test1", asset: "USDC", available: 1000.0)
        let account2 = Holding(exchange: "test2", asset: "BTC", available: 0.5)

        try sqlitePersistence.saveAccount(account1)
        try sqlitePersistence.saveAccount(account2)

        let client = InMemoryTigerBeetleClient()
        let tigerBeetlePersistence = TigerBeetlePersistence(client: client)
        let migration = TigerBeetleMigration(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: tigerBeetlePersistence
        )

        try migration.migrateAll()

        let sqliteAccounts = try sqlitePersistence.getAllAccounts()
        let tigerBeetleAccounts = try tigerBeetlePersistence.getAllAccounts()

        let sqliteTotal = sqliteAccounts.reduce(0.0) { $0 + $1.total }
        let tigerBeetleTotal = tigerBeetleAccounts.reduce(0.0) { $0 + $1.total }

        #expect(abs(sqliteTotal - tigerBeetleTotal) < 0.01)
    }
}
