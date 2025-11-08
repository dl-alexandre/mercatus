import Testing
import Foundation
@testable import SmartVestor

@Suite("TigerBeetle Go/No-Go Tests")
struct TigerBeetleGoNoGoTests {

    @Test("Restore test: snapshot restore yields zero drift")
    func testRestoreTest() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("test-restore.db")
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let sqlitePersistence = SQLitePersistence(dbPath: dbPath)
        try sqlitePersistence.initialize()

        let accounts = [
            Holding(exchange: "test", asset: "USDC", available: 1000.0),
            Holding(exchange: "test", asset: "BTC", available: 0.1)
        ]

        for account in accounts {
            try sqlitePersistence.saveAccount(account)
        }

        let client1 = InMemoryTigerBeetleClient()
        let persistence1 = TigerBeetlePersistence(client: client1)

        let migration1 = TigerBeetleMigration(sqlitePersistence: sqlitePersistence, tigerBeetlePersistence: persistence1)
        try migration1.migrateAll()

        let goNoGo = TigerBeetleGoNoGo(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: persistence1
        )

        let passed = try await goNoGo.runRestoreTest()
        #expect(passed)
    }

    @Test("Idempotency audit: duplicate events yield zero net change")
    func testIdempotencyAudit() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("test-idempotency.db")
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let sqlitePersistence = SQLitePersistence(dbPath: dbPath)
        try sqlitePersistence.initialize()

        let transactions = (0..<100).map { i in
            InvestmentTransaction(
                type: .deposit,
                exchange: "test",
                asset: "USDC",
                quantity: Double(i + 1) * 10,
                price: 1.0,
                fee: 0.0,
                timestamp: Date(),
                metadata: [
                    "source_event_id": "event-\(i)",
                    "source_system": "test-system"
                ]
            )
        }

        for tx in transactions {
            try sqlitePersistence.saveTransaction(tx)
        }

        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let migration = TigerBeetleMigration(sqlitePersistence: sqlitePersistence, tigerBeetlePersistence: persistence)
        try migration.migrateAll()

        let goNoGo = TigerBeetleGoNoGo(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: persistence
        )

        let passed = try await goNoGo.auditIdempotency(sampleSize: 100)
        #expect(passed)
    }

    @Test("Access control: ExecutionEngine write, CLI read-only")
    func testAccessControl() async throws {
        let rbac = ProductionRBAC()
        let goNoGo = TigerBeetleGoNoGo(
            sqlitePersistence: SQLitePersistence(dbPath: ":memory:"),
            tigerBeetlePersistence: TigerBeetlePersistence(client: InMemoryTigerBeetleClient())
        )

        let result = goNoGo.verifyAccessControl(rbac: rbac)
        #expect(result.passed)
        #expect(result.violations.isEmpty)
    }
}
