import Foundation
import Utils

extension TigerBeetlePersistence {
    func callActor<T: Sendable>(_ operation: @escaping () async throws -> T) throws -> T {
        return try Task<T, Error>.runBlocking(operation: {
            try await operation()
        })
    }
}

public class TigerBeetlePersistence {
    let client: TigerBeetleClientProtocol
    private let logger: StructuredLogger
    let metricsCollector: TigerBeetleMetricsCollector?
    let extendedMetrics: TigerBeetleExtendedMetrics?
    let traceIDGenerator: () -> String

    public init(
        client: TigerBeetleClientProtocol,
        logger: StructuredLogger = StructuredLogger(),
        metricsCollector: TigerBeetleMetricsCollector? = nil,
        extendedMetrics: TigerBeetleExtendedMetrics? = nil,
        traceIDGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        self.client = client
        self.logger = logger
        self.metricsCollector = metricsCollector
        self.extendedMetrics = extendedMetrics
        self.traceIDGenerator = traceIDGenerator
    }

    public func saveAccount(_ account: Holding) throws {
        let accountID = AccountMapping.accountID(exchange: account.exchange, asset: account.asset)

        let amount = UInt128(UInt64(account.available * 1_000_000))
        let tbAccount = TigerBeetleAccount(
            id: accountID,
            code: 1,
            debitsReserved: UInt128(UInt64(account.pending * 1_000_000)),
            debitsAccepted: UInt128(0, 0),
            creditsReserved: UInt128(0, 0),
            creditsAccepted: amount,
            flags: []
        )

        let errors: [TigerBeetleError]
        if let actorClient = client as? InMemoryTigerBeetleClient {
            errors = try callActor {
                try await actorClient.createAccounts([tbAccount])
            }
        } else {
            errors = try client.createAccounts([tbAccount])
        }
        if let error = errors.first {
            throw mapTigerBeetleError(error)
        }

        logger.info(
            component: "TigerBeetlePersistence",
            event: "Account saved",
            data: [
                "account_id": accountID.uuidString,
                "exchange": account.exchange,
                "asset": account.asset,
                "balance": String(account.available)
            ]
        )
    }

    public func getAccount(exchange: String, asset: String) throws -> Holding? {
        let accountID = AccountMapping.accountID(exchange: exchange, asset: asset)

        let accounts = try client.lookupAccounts([accountID])
        guard let tbAccount = accounts.first else {
            return nil
        }

        let balance = tbAccount.availableBalance.asDouble

        return Holding(
            id: accountID,
            exchange: exchange,
            asset: asset,
            available: balance,
            pending: tbAccount.debitsReserved.asDouble,
            staked: 0,
            updatedAt: Date()
        )
    }

    public func getAllAccounts() throws -> [Holding] {
        return []
    }

    public func updateAccountBalance(exchange: String, asset: String, available: Double, pending: Double, staked: Double) throws {
        let accountID = AccountMapping.accountID(exchange: exchange, asset: asset)

        let accounts = try client.lookupAccounts([accountID])
        guard var tbAccount = accounts.first else {
            let holding = Holding(
                exchange: exchange,
                asset: asset,
                available: available,
                pending: pending,
                staked: staked
            )
            try saveAccount(holding)
            return
        }

        let newCreditsAccepted = UInt128(available)
        let newDebitsReserved = UInt128(pending)

        tbAccount = TigerBeetleAccount(
            id: tbAccount.id,
            code: tbAccount.code,
            debitsReserved: newDebitsReserved,
            debitsAccepted: tbAccount.debitsAccepted,
            creditsReserved: tbAccount.creditsReserved,
            creditsAccepted: newCreditsAccepted,
            flags: tbAccount.flags
        )

        let errors = try client.createAccounts([tbAccount])
        if let error = errors.first {
            throw mapTigerBeetleError(error)
        }
    }

    public func saveTransaction(_ transaction: InvestmentTransaction) throws {
        try AssetScale.validateScale(transaction.quantity, asset: transaction.asset)
        if transaction.price > 0 {
            try AssetScale.validateScale(transaction.price, asset: transaction.asset)
        }

        let accountID = AccountMapping.accountID(exchange: transaction.exchange, asset: transaction.asset)
        let usdcAccountID = AccountMapping.accountID(exchange: transaction.exchange, asset: "USDC")

        let usdcAmount = transaction.quantity * transaction.price
        let amount = AssetScale.toFixedPoint(usdcAmount, asset: "USDC")
        let feeAmount = AssetScale.toFixedPoint(transaction.fee, asset: "USDC")
        let timestamp = UInt64(transaction.timestamp.timeIntervalSince1970 * 1_000_000)

        var transfers: [TigerBeetleTransfer] = []

        switch transaction.type {
        case .buy:
            let mainTransfer = TigerBeetleTransfer(
                id: UUID(),
                debitAccountID: usdcAccountID,
                creditAccountID: accountID,
                amount: amount,
                timestamp: timestamp,
                userData: UInt128(UInt64(bitPattern: Int64(transaction.id.hashValue)))
            )
            transfers.append(mainTransfer)

            if transaction.fee > 0 {
                let feeAccountID = AccountMapping.feeAccountID(exchange: transaction.exchange)
                let feeTransfer = TigerBeetleTransfer(
                    id: UUID(),
                    debitAccountID: usdcAccountID,
                    creditAccountID: feeAccountID,
                    amount: feeAmount,
                    timestamp: timestamp,
                    userData: UInt128(UInt64(bitPattern: Int64(transaction.id.hashValue)))
                )
                transfers.append(feeTransfer)
            }

        case .sell:
            let mainTransfer = TigerBeetleTransfer(
                id: UUID(),
                debitAccountID: accountID,
                creditAccountID: usdcAccountID,
                amount: amount,
                timestamp: timestamp,
                userData: UInt128(UInt64(bitPattern: Int64(transaction.id.hashValue)))
            )
            transfers.append(mainTransfer)

            if transaction.fee > 0 {
                let feeAccountID = AccountMapping.feeAccountID(exchange: transaction.exchange)
                let feeTransfer = TigerBeetleTransfer(
                    id: UUID(),
                    debitAccountID: usdcAccountID,
                    creditAccountID: feeAccountID,
                    amount: feeAmount,
                    timestamp: timestamp,
                    userData: UInt128(UInt64(bitPattern: Int64(transaction.id.hashValue)))
                )
                transfers.append(feeTransfer)
            }

        case .deposit:
            let depositAccountID = AccountMapping.accountID(exchange: "DEPOSIT", asset: transaction.asset)
            let transfer = TigerBeetleTransfer(
                id: UUID(),
                debitAccountID: depositAccountID,
                creditAccountID: accountID,
                amount: UInt128(transaction.quantity),
                timestamp: timestamp,
                userData: UInt128(UInt64(bitPattern: Int64(transaction.id.hashValue)))
            )
            transfers.append(transfer)

        case .withdrawal:
            let withdrawalAccountID = AccountMapping.accountID(exchange: "WITHDRAWAL", asset: transaction.asset)
            let transfer = TigerBeetleTransfer(
                id: UUID(),
                debitAccountID: accountID,
                creditAccountID: withdrawalAccountID,
                amount: UInt128(transaction.quantity),
                timestamp: timestamp,
                userData: UInt128(UInt64(bitPattern: Int64(transaction.id.hashValue)))
            )
            transfers.append(transfer)

        case .stake:
            let stakingAccountID = AccountMapping.accountID(exchange: transaction.exchange, asset: "\(transaction.asset)_STAKED")
            let transfer = TigerBeetleTransfer(
                id: UUID(),
                debitAccountID: accountID,
                creditAccountID: stakingAccountID,
                amount: UInt128(transaction.quantity),
                timestamp: timestamp,
                userData: UInt128(UInt64(bitPattern: Int64(transaction.id.hashValue)))
            )
            transfers.append(transfer)

        case .unstake:
            let stakingAccountID = AccountMapping.accountID(exchange: transaction.exchange, asset: "\(transaction.asset)_STAKED")
            let transfer = TigerBeetleTransfer(
                id: UUID(),
                debitAccountID: stakingAccountID,
                creditAccountID: accountID,
                amount: UInt128(transaction.quantity),
                timestamp: timestamp,
                userData: UInt128(UInt64(bitPattern: Int64(transaction.id.hashValue)))
            )
            transfers.append(transfer)

        case .reward:
            let rewardAccountID = AccountMapping.accountID(exchange: "REWARD", asset: transaction.asset)
            let transfer = TigerBeetleTransfer(
                id: UUID(),
                debitAccountID: rewardAccountID,
                creditAccountID: accountID,
                amount: UInt128(transaction.quantity),
                timestamp: timestamp,
                userData: UInt128(UInt64(bitPattern: Int64(transaction.id.hashValue)))
            )
            transfers.append(transfer)

        case .fee:
            let feeAccountID = AccountMapping.feeAccountID(exchange: transaction.exchange)
            let transfer = TigerBeetleTransfer(
                id: UUID(),
                debitAccountID: accountID,
                creditAccountID: feeAccountID,
                amount: UInt128(transaction.quantity),
                timestamp: timestamp,
                userData: UInt128(UInt64(bitPattern: Int64(transaction.id.hashValue)))
            )
            transfers.append(transfer)
        }

        let traceID = transaction.traceID ?? traceIDGenerator()
        let idempotencyKey = transaction.idempotencyKey

        let fxSnapshotID = transaction.metadata["fx_snapshot_id"]

        for transfer in transfers {
            logger.info(
                component: "TigerBeetlePersistence",
                event: "transfer_pair",
                data: [
                    "trace_id": traceID,
                    "idempotency_key": idempotencyKey,
                    "fx_snapshot_id": fxSnapshotID ?? "",
                    "transfer_id": transfer.id.uuidString,
                    "transaction_id": transaction.id.uuidString,
                    "debit_account_id": transfer.debitAccountID.uuidString,
                    "credit_account_id": transfer.creditAccountID.uuidString,
                    "amount": String(transfer.amount.asDouble),
                    "timestamp": String(transfer.timestamp),
                    "ledger": String(transfer.ledger),
                    "code": String(transfer.code),
                    "flags": String(transfer.flags.rawValue),
                    "transaction_type": transaction.type.rawValue,
                    "exchange": transaction.exchange,
                    "asset": transaction.asset
                ]
            )

            let metrics = extendedMetrics
            let exchange = transaction.exchange
            let asset = transaction.asset
            Task { @MainActor in
                await metrics?.recordTransfer(labels: TigerBeetleMetricLabels(
                    operation: "create_transfer",
                    exchange: exchange,
                    asset: asset,
                    result: "success"
                ))
            }
        }

        let errors: [TigerBeetleError]
        if let actorClient = client as? InMemoryTigerBeetleClient {
            errors = try callActor {
                try await actorClient.createTransfers(transfers)
            }
        } else {
            errors = try client.createTransfers(transfers)
        }
        if !errors.isEmpty {
            let metrics = extendedMetrics
            let exchange = transaction.exchange
            let asset = transaction.asset
            Task { @MainActor in
                await metrics?.recordTransfer(labels: TigerBeetleMetricLabels(
                    operation: "create_transfer",
                    exchange: exchange,
                    asset: asset,
                    result: "error"
                ))
            }
            throw mapTigerBeetleError(errors.first!)
        }

        logger.info(
            component: "TigerBeetlePersistence",
            event: "Transaction saved",
            data: [
                "transaction_id": transaction.id.uuidString,
                "type": transaction.type.rawValue,
                "exchange": transaction.exchange,
                "asset": transaction.asset,
                "transfer_count": String(transfers.count)
            ]
        )
    }

    public func getTransactions(exchange: String?, asset: String?, type: TransactionType?, limit: Int?) throws -> [InvestmentTransaction] {
        return []
    }

    public func getTransaction(by idempotencyKey: String) throws -> InvestmentTransaction? {
        return nil
    }

    private func mapTigerBeetleError(_ error: TigerBeetleError) -> SmartVestorError {
        switch error {
        case .insufficientFunds, .exceedsDebits, .exceedsCredits:
            return SmartVestorError.persistenceError("Insufficient funds: \(error)")
        case .accountNotFound:
            return SmartVestorError.persistenceError("Account not found: \(error)")
        case .duplicateTransfer:
            return SmartVestorError.persistenceError("Duplicate transfer: \(error)")
        case .connectionError(let msg):
            return SmartVestorError.persistenceError("Connection error: \(msg)")
        default:
            return SmartVestorError.persistenceError("TigerBeetle error: \(error)")
        }
    }
}
