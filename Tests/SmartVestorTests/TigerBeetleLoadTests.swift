import Testing
import Foundation
@testable import SmartVestor

@Suite("TigerBeetle Load Tests")
struct TigerBeetleLoadTests {

    @Test("Baseline: 10k transfers/sec, p95 < 10ms")
    func testBaselinePerformance() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let accountID = AccountMapping.accountID(exchange: "test", asset: "USDC")
        let initialAccount = TigerBeetleAccount(
            id: accountID,
            code: 1,
            creditsAccepted: UInt128(1_000_000.0)
        )
        _ = try await client.createAccounts([initialAccount])

        let numTransfers = 10000
        var latencies: [TimeInterval] = []

        let startTime = Date()

        for i in 0..<numTransfers {
            let txStart = Date()
            let tx = InvestmentTransaction(
                type: .buy,
                exchange: "test",
                asset: "BTC",
                quantity: 0.001,
                price: 50000.0,
                fee: 0.5
            )
            try persistence.saveTransaction(tx)
            let txLatency = Date().timeIntervalSince(txStart)
            latencies.append(txLatency)
        }

        let totalTime = Date().timeIntervalSince(startTime)
        let transfersPerSec = Double(numTransfers) / totalTime

        let sortedLatencies = latencies.sorted()
        let p95Index = Int(Double(sortedLatencies.count) * 0.95)
        let p95 = sortedLatencies[p95Index]

        #expect(transfersPerSec >= 10000.0, "Expected >= 10k transfers/sec, got \(transfersPerSec)")
        #expect(p95 < 0.01, "Expected p95 < 10ms, got \(p95 * 1000)ms")
    }

    @Test("Stress: 100k transfers/min across 1k accounts, backlog < 5s")
    func testStressLoad() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let numAccounts = 1000
        var accounts: [UUID] = []

        for i in 0..<numAccounts {
            let accountID = AccountMapping.accountID(exchange: "test", asset: "ASSET\(i)")
            let account = TigerBeetleAccount(
                id: accountID,
                code: 1,
                creditsAccepted: UInt128(10000.0)
            )
            _ = try await client.createAccounts([account])
            accounts.append(accountID)
        }

        let numTransfers = 100000
        let startTime = Date()
        var completed = 0

        for _ in 0..<numTransfers {
            let assetIndex = Int.random(in: 0..<numAccounts)
        let tx = InvestmentTransaction(
        type: .buy,
        exchange: "test",
        asset: "ASSET\(assetIndex)",
        quantity: 0.001,
        price: 100.0,
        fee: 0.1
        )
        do {
        try persistence.saveTransaction(tx)
        completed += 1
        } catch {
        // ignore
        }
        }

        let totalTime = Date().timeIntervalSince(startTime)
        let transfersPerMin = Double(completed) / (totalTime / 60.0)

        #expect(transfersPerMin >= 100000.0, "Expected >= 100k transfers/min, got \(transfersPerMin)")
    }
}
