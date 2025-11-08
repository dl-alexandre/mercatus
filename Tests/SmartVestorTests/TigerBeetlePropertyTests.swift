import Testing
import Foundation
@testable import SmartVestor

struct TransactionGenerator {
    static func generateValidSequence(count: Int, exchange: String = "test") -> [InvestmentTransaction] {
        var transactions: [InvestmentTransaction] = []
        var usdcBalance = 10000.0

        for i in 0..<count {
            let type: TransactionType
            let asset: String
            let quantity: Double
            let price: Double

            if i % 3 == 0 && usdcBalance > 1000 {
                type = .buy
                asset = "BTC"
                quantity = Double.random(in: 0.001...0.1)
                price = Double.random(in: 40000...60000)
            } else if i % 5 == 0 && transactions.contains(where: { $0.asset == "BTC" && $0.type == .buy }) {
                type = .sell
                asset = "BTC"
                quantity = Double.random(in: 0.001...0.05)
                price = Double.random(in: 40000...60000)
            } else {
                type = .deposit
                asset = "USDC"
                quantity = Double.random(in: 100...1000)
                price = 1.0
            }

            let fee = (quantity * price) * 0.001
            let tx = InvestmentTransaction(
                type: type,
                exchange: exchange,
                asset: asset,
                quantity: quantity,
                price: price,
                fee: fee
            )

            transactions.append(tx)

            if type == .buy {
                usdcBalance -= (quantity * price + fee)
            } else if type == .deposit {
                usdcBalance += quantity
            }
        }

        return transactions
    }
}

@Suite("TigerBeetle Property Tests")
struct TigerBeetlePropertyTests {

    @Test("Property: Random valid sequences maintain invariants")
    func testRandomSequenceInvariants() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let accountID = AccountMapping.accountID(exchange: "test", asset: "USDC")
        let initialAccount = TigerBeetleAccount(
            id: accountID,
            code: 1,
            creditsAccepted: UInt128(10000.0)
        )
        _ = try await client.createAccounts([initialAccount])

        for iteration in 0..<10 {
            let transactions = TransactionGenerator.generateValidSequence(count: 100)

            var totalDebits: Double = 0
            var totalCredits: Double = 0

            for tx in transactions {
                try? persistence.saveTransaction(tx)

                if tx.type == .buy {
                    totalDebits += (tx.quantity * tx.price + tx.fee)
                } else if tx.type == .deposit {
                    totalCredits += tx.quantity
                }
            }

            let finalAccount = try persistence.getAccount(exchange: "test", asset: "USDC")
            let expectedBalance = 10000.0 + totalCredits - totalDebits
            let actualBalance = finalAccount?.available ?? 0

            #expect(abs(actualBalance - expectedBalance) < 1.0, "Iteration \(iteration) failed")
        }
    }

    @Test("Fuzz: Duplicate delivery handling")
    func testFuzzDuplicateDelivery() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let accountID = AccountMapping.accountID(exchange: "test", asset: "USDC")
        let initialAccount = TigerBeetleAccount(
            id: accountID,
            code: 1,
            creditsAccepted: UInt128(10000.0)
        )
        _ = try await client.createAccounts([initialAccount])

        let idempotencyKey = UUID().uuidString
        let transaction = InvestmentTransaction(
            type: .deposit,
            exchange: "test",
            asset: "USDC",
            quantity: 1000.0,
            price: 1.0,
            fee: 0.0,
            idempotencyKey: idempotencyKey
        )

        var initialBalance = try persistence.getAccount(exchange: "test", asset: "USDC")
        let initialValue = initialBalance?.available ?? 0

        for _ in 0..<10 {
            try? persistence.saveTransaction(transaction)
        }

        let finalBalance = try persistence.getAccount(exchange: "test", asset: "USDC")
        let finalValue = finalBalance?.available ?? 0

        let expectedValue = initialValue + 1000.0
        #expect(abs(finalValue - expectedValue) < 1e-8)
    }

    @Test("Fuzz: Out-of-order delivery")
    func testFuzzOutOfOrder() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let accountID = AccountMapping.accountID(exchange: "test", asset: "USDC")
        let initialAccount = TigerBeetleAccount(
            id: accountID,
            code: 1,
            creditsAccepted: UInt128(10000.0)
        )
        _ = try await client.createAccounts([initialAccount])

        let transactions = TransactionGenerator.generateValidSequence(count: 50)
        let shuffled = transactions.shuffled()

        for tx in shuffled {
            try? persistence.saveTransaction(tx)
        }

        let orderedClient = InMemoryTigerBeetleClient()
        let orderedPersistence = TigerBeetlePersistence(client: orderedClient)
        let orderedAccount = TigerBeetleAccount(
            id: accountID,
            code: 1,
            creditsAccepted: UInt128(10000.0)
        )
        _ = try await orderedClient.createAccounts([orderedAccount])

        for tx in transactions {
            try? orderedPersistence.saveTransaction(tx)
        }

        let shuffledBalance = try persistence.getAccount(exchange: "test", asset: "USDC")
        let orderedBalance = try orderedPersistence.getAccount(exchange: "test", asset: "USDC")

        #expect(abs((shuffledBalance?.available ?? 0) - (orderedBalance?.available ?? 0)) < 1e-8)
    }
}
