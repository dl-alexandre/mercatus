import Testing
import Foundation
@testable import SmartVestor

@Suite("SwapExecutionManager Tests")
struct SwapExecutionManagerTests {

    func createTestSwapEvaluation() -> SwapEvaluation {
        return SwapEvaluation(
            fromAsset: "BTC",
            toAsset: "ETH",
            fromQuantity: 0.1,
            estimatedToQuantity: 3.0,
            totalCost: SwapCost(
                sellFee: 5.0,
                buyFee: 5.0,
                sellSpread: 2.0,
                buySpread: 2.0,
                sellSlippage: 1.0,
                buySlippage: 1.0,
                totalCostUSD: 16.0,
                costPercentage: 0.32
            ),
            potentialBenefit: SwapBenefit(
                expectedReturnDifferential: 20.0,
                portfolioImprovement: 15.0,
                riskReduction: 5.0,
                allocationAlignment: 10.0,
                totalBenefitUSD: 50.0,
                benefitPercentage: 1.0
            ),
            netValue: 34.0,
            isWorthwhile: true,
            confidence: 0.75,
            exchange: "robinhood"
        )
    }

    class MockPersistence: PersistenceProtocol {
        func getAllAccounts() async throws -> [Account] {
            return []
        }

        func saveAccounts(_ accounts: [Account]) async throws {}

        func getAccount(for exchange: String) async throws -> Account? {
            return nil
        }

        func saveAccount(_ account: Account) async throws {}

        func getTransactions(for exchange: String, limit: Int?) async throws -> [Transaction] {
            return []
        }

        func saveTransactions(_ transactions: [Transaction], for exchange: String) async throws {}

        func getLatestTransactionId(for exchange: String) async throws -> String? {
            return nil
        }

        func getLedgerEntries(for exchange: String, limit: Int?) async throws -> [LedgerEntry] {
            return []
        }

        func saveLedgerEntries(_ entries: [LedgerEntry], for exchange: String) async throws {}

        func getLatestLedgerEntryId(for exchange: String) async throws -> String? {
            return nil
        }
    }

    class MockExecutionEngine: ExecutionEngineProtocol {
        func placeMakerOrder(asset: String, quantity: Double, exchange: String, dryRun: Bool) async throws -> ExecutionResult {
            return ExecutionResult(success: true, orderId: "test", executedQuantity: quantity, averagePrice: 100.0, totalCost: 10.0, fees: 1.0, error: nil)
        }
    }

    @Test("Execute swap rejects non-worthwhile swap")
    func testRejectNonWorthwhileSwap() async throws {
        let mockEngine = MockExecutionEngine()
        let mockPersistence = MockPersistence()
        let manager = SwapExecutionManager(
            executionEngine: mockEngine,
            persistence: mockPersistence,
            maxRetries: 3
        )

        var evaluation = createTestSwapEvaluation()
        evaluation = SwapEvaluation(
            id: evaluation.id,
            fromAsset: evaluation.fromAsset,
            toAsset: evaluation.toAsset,
            fromQuantity: evaluation.fromQuantity,
            estimatedToQuantity: evaluation.estimatedToQuantity,
            totalCost: evaluation.totalCost,
            potentialBenefit: evaluation.potentialBenefit,
            netValue: evaluation.netValue,
            isWorthwhile: false,
            confidence: evaluation.confidence,
            exchange: evaluation.exchange,
            timestamp: evaluation.timestamp
        )

        let result = await manager.executeSwap(evaluation, dryRun: true)
        #expect(result.success == false)
        // Note: The actual error checking is simplified for now
    }

    @Test("Dry run succeeds without execution")
    func testDryRun() async throws {
        let mockEngine = MockExecutionEngine()
        let mockPersistence = MockPersistence()
        let manager = SwapExecutionManager(
            executionEngine: mockEngine,
            persistence: mockPersistence,
            maxRetries: 3
        )

        let evaluation = createTestSwapEvaluation()
        let result = await manager.executeSwap(evaluation, dryRun: true)
        #expect(result.success == true)
    }

    @Test("Cancel execution")
    func testCancelExecution() async {
        let mockEngine = MockExecutionEngine()
        let mockPersistence = MockPersistence()
        let manager = SwapExecutionManager(
            executionEngine: mockEngine,
            persistence: mockPersistence,
            maxRetries: 3
        )

        let evaluation = createTestSwapEvaluation()
        let executionId = evaluation.id

        let isExecutingBefore = await manager.isExecuting(executionId)
        #expect(isExecutingBefore == false)

        Task {
            _ = await manager.executeSwap(evaluation, dryRun: false)
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
        await manager.cancelExecution(executionId)

        let isExecutingAfter = await manager.isExecuting(executionId)
        #expect(isExecutingAfter == false)
    }
}
