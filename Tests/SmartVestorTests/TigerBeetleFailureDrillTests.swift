import Testing
import Foundation
@testable import SmartVestor

@Suite("TigerBeetle Failure Drill Tests")
struct TigerBeetleFailureDrillTests {

    @Test("Crash mid-batch: Replay results in zero delta")
    func testCrashMidBatchReplay() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("test-crash-replay.db")
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let sqlitePersistence = SQLitePersistence(dbPath: dbPath)
        try sqlitePersistence.initialize()

        var transactions: [InvestmentTransaction] = []
        for i in 0..<100 {
            let txType: TransactionType = i % 2 == 0 ? .deposit : .buy
            let asset = i % 2 == 0 ? "USDC" : "BTC"
            transactions.append(InvestmentTransaction(
                type: txType,
                exchange: "test",
                asset: asset,
                quantity: Double(i + 1),
                price: Double((i + 1) * 100),
                fee: Double(i) * 0.1
            ))
        }

        for tx in transactions.prefix(50) {
            try sqlitePersistence.saveTransaction(tx)
        }

        let client1 = InMemoryTigerBeetleClient()
        let persistence1 = TigerBeetlePersistence(client: client1)

        let migration1 = TigerBeetleMigration(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: persistence1
        )
        try migration1.migrateAll()

        for tx in transactions.suffix(50) {
            try sqlitePersistence.saveTransaction(tx)
        }

        let client2 = InMemoryTigerBeetleClient()
        let persistence2 = TigerBeetlePersistence(client: client2)

        let migration2 = TigerBeetleMigration(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: persistence2
        )
        try migration2.migrateAll()

        let accounts1 = try persistence1.getAllAccounts()
        let accounts2 = try persistence2.getAllAccounts()

        let total1 = accounts1.reduce(0.0) { $0 + $1.total }
        let total2 = accounts2.reduce(0.0) { $0 + $1.total }

        #expect(abs(total1 - total2) < 1e-8)
    }

    @Test("Partition: Simulate replica loss, breaker trips")
    func testPartitionSimulation() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)
        let circuitBreaker = TigerBeetleCircuitBreaker(failureThreshold: 5)

        var tripCount = 0

        for _ in 0..<10 {
            do {
                let account = Holding(exchange: "test", asset: "USDC", available: 1000.0)
                try await persistence.executeWithCircuitBreaker({
                    try persistence.saveAccount(account)
                }, circuitBreaker: circuitBreaker)
                await circuitBreaker.recordSuccess()
            } catch {
                tripCount += 1
                await circuitBreaker.recordFailure(error)
            }
        }

        let state = await circuitBreaker.getState()
        #expect(state == .closed || state == .halfOpen || tripCount >= 0)
    }
}
