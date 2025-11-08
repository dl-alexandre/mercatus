import Foundation
import Utils

public enum SwapExecutionError: Error, Sendable {
    case swapNotWorthwhile
    case insufficientBalance
    case executionFailed(String)
    case rollbackFailed(String)
    case retryLimitExceeded

    public var localizedDescription: String {
        switch self {
        case .swapNotWorthwhile:
            return "Swap is not worthwhile"
        case .insufficientBalance:
            return "Insufficient balance for swap"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .rollbackFailed(let message):
            return "Rollback failed: \(message)"
        case .retryLimitExceeded:
            return "Retry limit exceeded"
        }
    }
}

public struct SwapExecutionResult: @unchecked Sendable {
    public let success: Bool
    public let swapEvaluation: SwapEvaluation
    public let executionTime: Date
    public let error: SwapExecutionError?
    public let retryCount: Int

    public init(
        success: Bool,
        swapEvaluation: SwapEvaluation,
        executionTime: Date = Date(),
        error: SwapExecutionError? = nil,
        retryCount: Int = 0
    ) {
        self.success = success
        self.swapEvaluation = swapEvaluation
        self.executionTime = executionTime
        self.error = error
        self.retryCount = retryCount
    }
}

public actor SwapExecutionManager {
    nonisolated(unsafe) private let executionEngine: ExecutionEngineProtocol
    private let persistence: PersistenceProtocol
    private let logger: StructuredLogger
    private let maxRetries: Int
    private var pendingExecutions: [UUID: Task<SwapExecutionResult, Never>] = [:]

    public init(
        executionEngine: ExecutionEngineProtocol,
        persistence: PersistenceProtocol,
        logger: StructuredLogger = StructuredLogger(),
        maxRetries: Int = 3
    ) {
        self.executionEngine = executionEngine
        self.persistence = persistence
        self.logger = logger
        self.maxRetries = maxRetries
    }

    public func executeSwap(
        _ evaluation: SwapEvaluation,
        dryRun: Bool = false,
        requireConfirmation: Bool = true
    ) async -> SwapExecutionResult {
        guard evaluation.isWorthwhile else {
            logger.warn(component: "SwapExecutionManager", event: "Swap not worthwhile", data: [
                "fromAsset": evaluation.fromAsset,
                "toAsset": evaluation.toAsset,
                "netValue": String(evaluation.netValue),
                "confidence": String(evaluation.confidence)
            ])
            return SwapExecutionResult(
                success: false,
                swapEvaluation: evaluation,
                error: .swapNotWorthwhile
            )
        }

        let executionId = evaluation.id
        if let existingTask = pendingExecutions[executionId] {
            return await existingTask.value
        }

        let task = Task<SwapExecutionResult, Never> {
            await executeWithRetry(evaluation: evaluation, dryRun: dryRun, retryCount: 0)
        }

        pendingExecutions[executionId] = task
        let result = await task.value
        pendingExecutions.removeValue(forKey: executionId)

        return result
    }

    private func executeWithRetry(
        evaluation: SwapEvaluation,
        dryRun: Bool,
        retryCount: Int
    ) async -> SwapExecutionResult {
        guard retryCount <= maxRetries else {
            logger.error(component: "SwapExecutionManager", event: "Retry limit exceeded", data: [
                "fromAsset": evaluation.fromAsset,
                "toAsset": evaluation.toAsset,
                "retryCount": String(retryCount)
            ])
            return SwapExecutionResult(
                success: false,
                swapEvaluation: evaluation,
                error: .retryLimitExceeded,
                retryCount: retryCount
            )
        }

        logger.info(component: "SwapExecutionManager", event: "Executing swap", data: [
            "fromAsset": evaluation.fromAsset,
            "toAsset": evaluation.toAsset,
            "fromQuantity": String(evaluation.fromQuantity),
            "netValue": String(evaluation.netValue),
            "dryRun": String(dryRun),
            "retryCount": String(retryCount)
        ])

        do {
            try await validateSwap(evaluation)

            if dryRun {
                logger.info(component: "SwapExecutionManager", event: "Dry run - skipping execution", data: [
                    "fromAsset": evaluation.fromAsset,
                    "toAsset": evaluation.toAsset
                ])
                return SwapExecutionResult(
                    success: true,
                    swapEvaluation: evaluation,
                    retryCount: retryCount
                )
            }

            let success = try await performSwap(evaluation)

            if success {
                logger.info(component: "SwapExecutionManager", event: "Swap executed successfully", data: [
                    "fromAsset": evaluation.fromAsset,
                    "toAsset": evaluation.toAsset,
                    "retryCount": String(retryCount)
                ])
                return SwapExecutionResult(
                    success: true,
                    swapEvaluation: evaluation,
                    retryCount: retryCount
                )
            } else {
                throw SwapExecutionError.executionFailed("Swap execution returned false")
            }

        } catch {
            logger.error(component: "SwapExecutionManager", event: "Swap execution failed", data: [
                "fromAsset": evaluation.fromAsset,
                "toAsset": evaluation.toAsset,
                "error": error.localizedDescription,
                "retryCount": String(retryCount)
            ])

            if retryCount < maxRetries {
                let delay = min(1000 * Int(pow(2.0, Double(retryCount))), 10000)
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)

                return await executeWithRetry(
                    evaluation: evaluation,
                    dryRun: dryRun,
                    retryCount: retryCount + 1
                )
            }

            if let swapError = error as? SwapExecutionError {
                return SwapExecutionResult(
                    success: false,
                    swapEvaluation: evaluation,
                    error: swapError,
                    retryCount: retryCount
                )
            }

            return SwapExecutionResult(
                success: false,
                swapEvaluation: evaluation,
                error: .executionFailed(error.localizedDescription),
                retryCount: retryCount
            )
        }
    }

    private func validateSwap(_ evaluation: SwapEvaluation) async throws {
        let balances = try persistence.getAllAccounts()
        let fromBalance = balances.first { $0.asset == evaluation.fromAsset && $0.exchange == evaluation.exchange }

        guard let balance = fromBalance else {
            throw SwapExecutionError.insufficientBalance
        }

        guard balance.available >= evaluation.fromQuantity else {
            throw SwapExecutionError.insufficientBalance
        }
    }

    private func performSwap(_ evaluation: SwapEvaluation) async throws -> Bool {
        let sellResult = try await executionEngine.placeMakerOrder(
            asset: evaluation.fromAsset,
            quantity: evaluation.fromQuantity,
            exchange: evaluation.exchange,
            dryRun: false
        )

        guard sellResult.success else {
            throw SwapExecutionError.executionFailed("Sell order failed: \(sellResult.error ?? "Unknown error")")
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        let buyResult = try await executionEngine.placeMakerOrder(
            asset: evaluation.toAsset,
            quantity: evaluation.estimatedToQuantity,
            exchange: evaluation.exchange,
            dryRun: false
        )

        guard buyResult.success else {
            try? await rollbackSell(evaluation: evaluation, sellResult: sellResult)
            throw SwapExecutionError.executionFailed("Buy order failed: \(buyResult.error ?? "Unknown error")")
        }

        return true
    }

    private func rollbackSell(evaluation: SwapEvaluation, sellResult: ExecutionResult) async throws {
        logger.warn(component: "SwapExecutionManager", event: "Attempting rollback", data: [
            "fromAsset": evaluation.fromAsset,
            "toAsset": evaluation.toAsset
        ])

        let buyBackResult = try await executionEngine.placeMakerOrder(
            asset: evaluation.fromAsset,
            quantity: evaluation.fromQuantity,
            exchange: evaluation.exchange,
            dryRun: false
        )

        if !buyBackResult.success {
            throw SwapExecutionError.rollbackFailed("Failed to buy back \(evaluation.fromAsset): \(buyBackResult.error ?? "Unknown error")")
        }

        logger.info(component: "SwapExecutionManager", event: "Rollback successful", data: [
            "fromAsset": evaluation.fromAsset
        ])
    }

    public func cancelExecution(_ evaluationId: UUID) async {
        if let task = pendingExecutions[evaluationId] {
            task.cancel()
            pendingExecutions.removeValue(forKey: evaluationId)
            logger.info(component: "SwapExecutionManager", event: "Execution cancelled", data: [
                "evaluationId": evaluationId.uuidString
            ])
        }
    }

    public func isExecuting(_ evaluationId: UUID) async -> Bool {
        return pendingExecutions[evaluationId] != nil
    }
}
