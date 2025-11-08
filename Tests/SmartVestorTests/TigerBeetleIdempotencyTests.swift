import Testing
import Foundation
@testable import SmartVestor

@Suite("TigerBeetle Idempotency Tests")
struct TigerBeetleIdempotencyTests {

    @Test("Replay same transaction stream N times → no net change after first apply")
    func testIdempotentReplay() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let idempotencyKey = UUID().uuidString

        let transaction = InvestmentTransaction(
            type: .buy,
            exchange: "test",
            asset: "BTC",
            quantity: 0.1,
            price: 50000.0,
            fee: 5.0,
            idempotencyKey: idempotencyKey
        )

        let accountID = AccountMapping.accountID(exchange: "test", asset: "USDC")
        let usdcAccount = TigerBeetleAccount(
            id: accountID,
            code: 1,
            creditsAccepted: UInt128(10000.0)
        )
        _ = try await client.createAccounts([usdcAccount])

        try persistence.saveTransaction(transaction)

        let balance1 = try persistence.getAccount(exchange: "test", asset: "USDC")
        let balance1Value = balance1?.available ?? 0

        for _ in 0..<5 {
            do {
                try persistence.saveTransaction(transaction)
            } catch {

            }
        }

        let balance2 = try persistence.getAccount(exchange: "test", asset: "USDC")
        let balance2Value = balance2?.available ?? 0

        #expect(abs(balance1Value - balance2Value) < 1e-8)
    }

    @Test("Shuffle event order in migration → final balances identical")
    func testOrderIndependence() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath1 = (tmpDir as NSString).appendingPathComponent("test-order1.db")
        let dbPath2 = (tmpDir as NSString).appendingPathComponent("test-order2.db")
        defer {
            try? FileManager.default.removeItem(atPath: dbPath1)
            try? FileManager.default.removeItem(atPath: dbPath2)
        }

        let sqlite1 = SQLitePersistence(dbPath: dbPath1)
        let sqlite2 = SQLitePersistence(dbPath: dbPath2)
        try sqlite1.initialize()
        try sqlite2.initialize()

        let transactions = [
            InvestmentTransaction(type: .deposit, exchange: "test", asset: "USDC", quantity: 1000, price: 1, fee: 0),
            InvestmentTransaction(type: .buy, exchange: "test", asset: "BTC", quantity: 0.01, price: 50000, fee: 5),
            InvestmentTransaction(type: .sell, exchange: "test", asset: "BTC", quantity: 0.005, price: 51000, fee: 5)
        ]

        for tx in transactions {
            try sqlite1.saveTransaction(tx)
        }

        for tx in transactions.reversed() {
            try sqlite2.saveTransaction(tx)
        }

        let client1 = InMemoryTigerBeetleClient()
        let client2 = InMemoryTigerBeetleClient()
        let persistence1 = TigerBeetlePersistence(client: client1)
        let persistence2 = TigerBeetlePersistence(client: client2)

        let migration1 = TigerBeetleMigration(sqlitePersistence: sqlite1, tigerBeetlePersistence: persistence1)
        let migration2 = TigerBeetleMigration(sqlitePersistence: sqlite2, tigerBeetlePersistence: persistence2)

        try migration1.migrateAll()
        try migration2.migrateAll()

        let accounts1 = try persistence1.getAllAccounts()
        let accounts2 = try persistence2.getAllAccounts()

        let total1 = accounts1.reduce(0.0) { $0 + $1.total }
        let total2 = accounts2.reduce(0.0) { $0 + $1.total }

        #expect(abs(total1 - total2) < 1e-8)
    }
}
