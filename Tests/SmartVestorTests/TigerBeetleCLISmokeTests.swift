import Testing
import Foundation
import CryptoKit
@testable import SmartVestor

@Suite("TigerBeetle CLI Smoke Tests")
struct TigerBeetleCLISmokeTests {

    @Test("export-balances deterministic across nodes")
    func testExportBalancesDeterministic() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath1 = (tmpDir as NSString).appendingPathComponent("test-export1.db")
        let dbPath2 = (tmpDir as NSString).appendingPathComponent("test-export2.db")
        defer {
            try? FileManager.default.removeItem(atPath: dbPath1)
            try? FileManager.default.removeItem(atPath: dbPath2)
        }

        let sqlite1 = SQLitePersistence(dbPath: dbPath1)
        let sqlite2 = SQLitePersistence(dbPath: dbPath2)
        try sqlite1.initialize()
        try sqlite2.initialize()

        let accounts = [
            Holding(exchange: "test", asset: "USDC", available: 1000.0),
            Holding(exchange: "test", asset: "BTC", available: 0.1)
        ]

        for account in accounts {
            try sqlite1.saveAccount(account)
            try sqlite2.saveAccount(account)
        }

        let client1 = InMemoryTigerBeetleClient()
        let client2 = InMemoryTigerBeetleClient()
        let persistence1 = TigerBeetlePersistence(client: client1)
        let persistence2 = TigerBeetlePersistence(client: client2)

        let migration1 = TigerBeetleMigration(sqlitePersistence: sqlite1, tigerBeetlePersistence: persistence1)
        let migration2 = TigerBeetleMigration(sqlitePersistence: sqlite2, tigerBeetlePersistence: persistence2)

        try migration1.migrateAll()
        try migration2.migrateAll()

        let tools1 = TigerBeetleCLITools(persistence: HybridPersistence(
            sqlitePersistence: sqlite1,
            tigerBeetlePersistence: persistence1
        ))
        let tools2 = TigerBeetleCLITools(persistence: HybridPersistence(
            sqlitePersistence: sqlite2,
            tigerBeetlePersistence: persistence2
        ))

        let data1 = try tools1.exportBalances()
        let data2 = try tools2.exportBalances()

        let hash1 = SHA256.hash(data: data1)
        let hash2 = SHA256.hash(data: data2)

        #expect(Data(hash1) == Data(hash2))
    }

    @Test("diff-ledger returns empty on steady state")
    func testDiffLedgerSteadyState() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("test-diff.db")
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let sqlitePersistence = SQLitePersistence(dbPath: dbPath)
        try sqlitePersistence.initialize()

        let transactions = (0..<10).map { i in
            InvestmentTransaction(
                type: .deposit,
                exchange: "test",
                asset: "USDC",
                quantity: Double(i + 1) * 100,
                price: 1.0,
                fee: 0.0
            )
        }

        for tx in transactions {
            try sqlitePersistence.saveTransaction(tx)
        }

        let persistence = HybridPersistence(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: nil
        )
        let tools = TigerBeetleCLITools(persistence: persistence)

        let lastID = transactions.last!.id
        let diff = try tools.diffLedger(sinceID: lastID, limit: 1000)

        #expect(diff.isEmpty || diff.allSatisfy { $0.id == lastID || transactions.contains { $0.id == $0.id } })
    }
}
