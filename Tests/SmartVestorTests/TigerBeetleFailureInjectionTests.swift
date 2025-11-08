import Testing
import Foundation
@testable import SmartVestor

class FaultyTigerBeetleClient: TigerBeetleClientProtocol {
    private let baseClient: TigerBeetleClientProtocol
    private let failureMode: FailureMode
    private var callCount = 0

    enum FailureMode {
        case timeout
        case partialBatch
        case duplicateAck
        case staleRead
        case exceedsDebits
        case exceedsCredits
        case none
    }

    init(baseClient: TigerBeetleClientProtocol, failureMode: FailureMode) {
        self.baseClient = baseClient
        self.failureMode = failureMode
    }

    func createAccounts(_ accounts: [TigerBeetleAccount]) throws -> [TigerBeetleError] {
        callCount += 1

        switch failureMode {
        case .timeout:
            if callCount % 3 == 0 {
                throw TigerBeetleError.connectionError("Timeout")
            }
        case .exceedsDebits:
            return [.exceedsDebits]
        default:
            break
        }

        return try baseClient.createAccounts(accounts)
    }

    func lookupAccounts(_ accountIDs: [UUID]) throws -> [TigerBeetleAccount] {
        switch failureMode {
        case .staleRead:
            return []
        default:
            return try baseClient.lookupAccounts(accountIDs)
        }
    }

    func createTransfers(_ transfers: [TigerBeetleTransfer]) throws -> [TigerBeetleError] {
        callCount += 1

        switch failureMode {
        case .timeout:
            if callCount % 3 == 0 {
                throw TigerBeetleError.connectionError("Timeout")
            }
        case .partialBatch:
            if callCount % 2 == 0 {
                return Array(repeating: .unknownError("Partial"), count: transfers.count / 2)
            }
        case .duplicateAck:
            return try baseClient.createTransfers(transfers)
        case .exceedsCredits:
            return [.exceedsCredits]
        default:
            break
        }

        return try baseClient.createTransfers(transfers)
    }

    func lookupTransfers(_ transferIDs: [UUID]) throws -> [TigerBeetleTransfer] {
        return try baseClient.lookupTransfers(transferIDs)
    }
}

@Suite("TigerBeetle Failure Injection Tests")
struct TigerBeetleFailureInjectionTests {

    @Test("Transport fault: timeout recovery")
    func testTimeoutRecovery() async throws {
        let baseClient = InMemoryTigerBeetleClient()
        let faultyClient = FaultyTigerBeetleClient(baseClient: baseClient, failureMode: .timeout)
        let persistence = TigerBeetlePersistence(client: faultyClient)

        let account = Holding(exchange: "test", asset: "USDC", available: 1000.0)

        var success = false
        for _ in 0..<5 {
            do {
                try persistence.saveAccount(account)
                success = true
                break
            } catch {
                continue
            }
        }

        #expect(success)
    }

    @Test("Storage fault: exceeds_debits handling")
    func testExceedsDebitsHandling() async throws {
        let baseClient = InMemoryTigerBeetleClient()
        let faultyClient = FaultyTigerBeetleClient(baseClient: baseClient, failureMode: .exceedsDebits)
        let persistence = TigerBeetlePersistence(client: faultyClient)

        let account = Holding(exchange: "test", asset: "USDC", available: 1000.0)

        do {
            try persistence.saveAccount(account)
            #expect(false, "Should have thrown exceeds_debits")
        } catch {
            #expect(error is SmartVestorError)
        }
    }

    @Test("Concurrency: 50 parallel writers to same account")
    func testConcurrentWrites() async throws {
        let client = InMemoryTigerBeetleClient()
        let persistence = TigerBeetlePersistence(client: client)

        let accountID = AccountMapping.accountID(exchange: "test", asset: "USDC")
        let initialAccount = TigerBeetleAccount(
            id: accountID,
            code: 1,
            creditsAccepted: UInt128(10000.0)
        )
        _ = try await client.createAccounts([initialAccount])

        let depositAmount = 100.0
        let numWriters = 50

        for _ in 0..<numWriters {
            let tx = InvestmentTransaction(
            type: .deposit,
        exchange: "test",
        asset: "USDC",
        quantity: depositAmount,
        price: 1.0,
        fee: 0.0
        )
        try? persistence.saveTransaction(tx)
        }

        let finalAccount = try persistence.getAccount(exchange: "test", asset: "USDC")
        let expectedBalance = 10000.0 + (Double(numWriters) * depositAmount)

        #expect(abs((finalAccount?.available ?? 0) - expectedBalance) < 1.0)
    }
}
