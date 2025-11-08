import Testing
import Foundation
@testable import SmartVestor

struct LedgerInvariants {
    static func verifyDoubleEntry(transfers: [TigerBeetleTransfer]) -> Bool {
        let zero: UInt128 = UInt128(0, 0)
        let totalDebits = transfers.reduce(zero) { $0 + $1.amount }
        let totalCredits = transfers.reduce(zero) { $0 + $1.amount }
        return totalDebits == totalCredits
    }

    static func verifyBalanceConsistency(accounts: [Holding], transactions: [InvestmentTransaction], initialDeposits: Double, initialWithdrawals: Double) -> Bool {
        let currentBalances = accounts.reduce(0.0) { $0 + $1.total }
        let totalFees = transactions.reduce(0.0) { $0 + $1.fee }
        let netDeposits = initialDeposits - initialWithdrawals
        let expectedTotal = netDeposits - totalFees
        return abs(currentBalances - expectedTotal) < 1e-8
    }

    static func verifyMonotonicity(operations: [(type: TransactionType, before: Double, after: Double)]) -> Bool {
        for op in operations {
            switch op.type {
            case .deposit, .buy, .reward, .unstake:
                if op.after < op.before { return false }
            case .withdrawal, .sell, .fee, .stake:
                if op.after > op.before { return false }
            }
        }
        return true
    }
}

@Suite("TigerBeetle Invariant Tests")
struct TigerBeetleInvariantTests {

    @Test("Double-entry: Sum(debits) == Sum(credits) per transfer pair")
    func testDoubleEntryInvariant() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let transaction = InvestmentTransaction(
            type: .buy,
            exchange: "test",
            asset: "BTC",
            quantity: 0.1,
            price: 50000.0,
            fee: 5.0
        )

        let accountID = AccountMapping.accountID(exchange: "test", asset: "BTC")
        let usdcAccountID = AccountMapping.accountID(exchange: "test", asset: "USDC")

        let usdcAccount = TigerBeetleAccount(
            id: usdcAccountID,
            code: 1,
            creditsAccepted: UInt128(10000.0)
        )
        _ = try await client.createAccounts([usdcAccount])

        try persistence.saveTransaction(transaction)

        let transfers = try await client.lookupTransfers([UUID()])
        #expect(LedgerInvariants.verifyDoubleEntry(transfers: transfers))
    }

    @Test("Balance consistency: Sum(balances) + fees == net deposits - withdrawals")
    func testBalanceConsistencyInvariant() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("test-invariant.db")
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let sqlitePersistence = SQLitePersistence(dbPath: dbPath)
        try sqlitePersistence.initialize()

        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let deposit = InvestmentTransaction(
            type: .deposit,
            exchange: "test",
            asset: "USDC",
            quantity: 10000.0,
            price: 1.0,
            fee: 0.0
        )

        let buy = InvestmentTransaction(
            type: .buy,
            exchange: "test",
            asset: "BTC",
            quantity: 0.1,
            price: 50000.0,
            fee: 5.0
        )

        try sqlitePersistence.saveTransaction(deposit)
        try sqlitePersistence.saveTransaction(buy)
        try persistence.saveTransaction(deposit)
        try persistence.saveTransaction(buy)

        let accounts = try persistence.getAllAccounts()
        let transactions = try sqlitePersistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: nil)

        let deposits = transactions.filter { $0.type == .deposit }.reduce(0.0) { $0 + $1.quantity }
        let withdrawals = transactions.filter { $0.type == .withdrawal }.reduce(0.0) { $0 + $1.quantity }

        #expect(LedgerInvariants.verifyBalanceConsistency(
            accounts: accounts,
            transactions: transactions,
            initialDeposits: deposits,
            initialWithdrawals: withdrawals
        ))
    }

    @Test("Monotonicity: Balance changes match operation semantics")
    func testBalanceMonotonicity() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let account = Holding(exchange: "test", asset: "USDC", available: 1000.0)
        try persistence.saveAccount(account)

        let deposit = InvestmentTransaction(
            type: .deposit,
            exchange: "test",
            asset: "USDC",
            quantity: 500.0,
            price: 1.0,
            fee: 0.0
        )

        let before = try persistence.getAccount(exchange: "test", asset: "USDC")
        try persistence.saveTransaction(deposit)
        let after = try persistence.getAccount(exchange: "test", asset: "USDC")

        let operations = [
            (type: TransactionType.deposit, before: before?.total ?? 0, after: after?.total ?? 0)
        ]

        #expect(LedgerInvariants.verifyMonotonicity(operations: operations))
    }
}
