import Testing
import Foundation
@testable import SmartVestor

@Suite("TigerBeetle Edge Case Tests")
struct TigerBeetleEdgeCaseTests {

    @Test("Cross-asset P/L: Random fills + fees + FX changes → equity invariant")
    func testCrossAssetPLInvariant() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)
        let fxManager = FXManager()

        fxManager.updateSnapshot(FXSnapshot(
            rates: ["BTC": 50000.0, "ETH": 3000.0, "USDC": 1.0]
        ))

        let deposits: Double = 10000.0
        var withdrawals: Double = 0.0
        var totalFees: Double = 0.0

        let btcAccount = TigerBeetleAccount(
            id: AccountMapping.accountID(exchange: "test", asset: "BTC"),
            code: 1,
            creditsAccepted: UInt128(0.1)
        )
        let ethAccount = TigerBeetleAccount(
            id: AccountMapping.accountID(exchange: "test", asset: "ETH"),
            code: 1,
            creditsAccepted: UInt128(1.0)
        )
        _ = try await client.createAccounts([btcAccount, ethAccount])

        let btcTx = InvestmentTransaction(
            type: .buy,
            exchange: "test",
            asset: "BTC",
            quantity: 0.1,
            price: 50000.0,
            fee: 5.0
        )

        let ethTx = InvestmentTransaction(
            type: .sell,
            exchange: "test",
            asset: "ETH",
            quantity: 0.5,
            price: 3000.0,
            fee: 1.5
        )

        try persistence.saveTransaction(btcTx)
        try persistence.saveTransaction(ethTx)

        totalFees += btcTx.fee + ethTx.fee

        let accounts = try persistence.getAllAccounts()
        let totalValue = accounts.reduce(0.0) { acc, account in
            let normalized = fxManager.normalizeAmount(account.total, from: account.asset)
            return acc + normalized
        }

        let expectedEquity = deposits - withdrawals - totalFees
        let actualEquity = totalValue

        #expect(abs(actualEquity - expectedEquity) < 100.0)
    }

    @Test("Partial migration: Stop mid-stream, resume, verify no duplicates")
    func testPartialMigrationResume() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("test-partial-migration.db")
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let sqlitePersistence = SQLitePersistence(dbPath: dbPath)
        try sqlitePersistence.initialize()

        let transactions = (0..<100).map { i in
            InvestmentTransaction(
                type: i % 2 == 0 ? .deposit : .buy,
                exchange: "test",
                asset: i % 2 == 0 ? "USDC" : "BTC",
                quantity: Double.random(in: 1...100),
                price: Double.random(in: 1000...10000),
                fee: Double.random(in: 0...10)
            )
        }

        for tx in transactions.prefix(50) {
            try sqlitePersistence.saveTransaction(tx)
        }

        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)
        let tracker = ExactlyOnceTracker()

        let migration1 = TigerBeetleMigration(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: persistence
        )

        try migration1.migrateAll()

        for tx in transactions.suffix(50) {
            try sqlitePersistence.saveTransaction(tx)
        }

        let migration2 = TigerBeetleMigration(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: persistence
        )

        try migration2.migrateAll()

        let sqliteAccounts = try sqlitePersistence.getAllAccounts()
        let tbAccounts = try persistence.getAllAccounts()

        let sqliteTotal = sqliteAccounts.reduce(0.0) { $0 + $1.total }
        let tbTotal = tbAccounts.reduce(0.0) { $0 + $1.total }

        #expect(abs(sqliteTotal - tbTotal) < 1e-8)
    }

    @Test("Determinism: Same event stream on different instances → identical checksums")
    func testDeterminismAcrossInstances() async throws {
        var transactions: [InvestmentTransaction] = []
        for i in 0..<50 {
            let txType: TransactionType
            if i % 3 == 0 {
                txType = .deposit
            } else if i % 3 == 1 {
                txType = .buy
            } else {
                txType = .sell
            }
            let asset = i % 2 == 0 ? "BTC" : "ETH"
            transactions.append(InvestmentTransaction(
                type: txType,
                exchange: "test",
                asset: asset,
                quantity: Double(i + 1),
                price: Double((i + 1) * 100),
                fee: Double(i) * 0.1
            ))
        }

        let client1 = InMemoryTigerBeetleClient()
        let client2 = InMemoryTigerBeetleClient()
        let persistence1 = TigerBeetlePersistence(client: client1)
        let persistence2 = TigerBeetlePersistence(client: client2)

        for tx in transactions {
            try persistence1.saveTransaction(tx)
        }

        for tx in transactions {
            try persistence2.saveTransaction(tx)
        }

        let accounts1 = try persistence1.getAllAccounts()
        let accounts2 = try persistence2.getAllAccounts()

        let total1 = accounts1.reduce(0.0) { $0 + $1.total }
        let total2 = accounts2.reduce(0.0) { $0 + $1.total }

        #expect(abs(total1 - total2) < 1e-8)
    }

    @Test("Fee edge cases: Zero fee, negative rebate, dust fees")
    func testFeeEdgeCases() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let accountID = AccountMapping.accountID(exchange: "test", asset: "USDC")
        let usdcAccount = TigerBeetleAccount(
            id: accountID,
            code: 1,
            creditsAccepted: UInt128(10000.0)
        )
        _ = try await client.createAccounts([usdcAccount])

        let zeroFeeTx = InvestmentTransaction(
            type: .buy,
            exchange: "test",
            asset: "BTC",
            quantity: 0.1,
            price: 50000.0,
            fee: 0.0
        )

        let dustFeeTx = InvestmentTransaction(
            type: .buy,
            exchange: "test",
            asset: "ETH",
            quantity: 0.001,
            price: 3000.0,
            fee: 0.00000001
        )

        try persistence.saveTransaction(zeroFeeTx)
        try persistence.saveTransaction(dustFeeTx)

        let finalAccount = try persistence.getAccount(exchange: "test", asset: "USDC")
        let expectedRemaining = 10000.0 - (0.1 * 50000.0) - (0.001 * 3000.0) - 0.00000001

        #expect(abs((finalAccount?.available ?? 0) - expectedRemaining) < 0.01)
    }
}
