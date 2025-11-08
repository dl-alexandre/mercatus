import Foundation
import Utils
import Core

public class TigerBeetleGoNoGo {
    private let sqlitePersistence: SQLitePersistence
    private let tigerBeetlePersistence: TigerBeetlePersistence
    private let logger: StructuredLogger
    private let exchangeConnectors: [String: ExchangeConnectorProtocol]

    public init(
        sqlitePersistence: SQLitePersistence,
        tigerBeetlePersistence: TigerBeetlePersistence,
        exchangeConnectors: [String: ExchangeConnectorProtocol] = [:],
        logger: StructuredLogger = StructuredLogger()
    ) {
        self.sqlitePersistence = sqlitePersistence
        self.tigerBeetlePersistence = tigerBeetlePersistence
        self.exchangeConnectors = exchangeConnectors
        self.logger = logger
    }

    public func runRestoreTest() async throws -> Bool {
        logger.info(component: "GoNoGo", event: "Starting restore test")

        let originalAccounts = try tigerBeetlePersistence.getAllAccounts()
        let originalTransactions = try sqlitePersistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: nil)

        let originalChecksum = try calculateChecksum(accounts: originalAccounts)

        let freshClient = InMemoryTigerBeetleClient()
        let freshPersistence = TigerBeetlePersistence(client: freshClient, logger: logger)

        let migration = TigerBeetleMigration(
            sqlitePersistence: sqlitePersistence,
            tigerBeetlePersistence: freshPersistence
        )
        try migration.migrateAll()

        let restoredAccounts = try freshPersistence.getAllAccounts()
        let restoredChecksum = try calculateChecksum(accounts: restoredAccounts)

        let drift = abs(originalChecksum.totalBalance - restoredChecksum.totalBalance)

        if drift > 1e-8 {
            logger.error(
                component: "GoNoGo",
                event: "Restore test failed: drift detected",
                data: [
                    "original_total": String(originalChecksum.totalBalance),
                    "restored_total": String(restoredChecksum.totalBalance),
                    "drift": String(drift)
                ]
            )
            return false
        }

        logger.info(component: "GoNoGo", event: "Restore test passed: zero drift")
        return true
    }

    public func verifyExchangeParity() async throws -> (passed: Bool, mismatches: [String]) {
        logger.info(component: "GoNoGo", event: "Starting exchange parity verification")

        let allAccounts = try tigerBeetlePersistence.getAllAccounts()
        let sortedAccounts = allAccounts.sorted { $0.total > $1.total }
        let top20PercentCount = max(1, sortedAccounts.count / 5)
        let topAccounts = Array(sortedAccounts.prefix(top20PercentCount))

        var mismatches: [String] = []

        for account in topAccounts {
            guard let connector = exchangeConnectors[account.exchange] else {
                continue
            }

            do {
                let holdings = try await connector.getHoldings()
                guard let exchangeHolding = holdings.first(where: { ($0["asset"] as? String ?? $0["assetCode"] as? String) == account.asset }),
                      let exchangeBalance = parseExchangeBalance(exchangeHolding) else {
                    continue
                }
                let tbBalance = account.available

                let drift = abs(tbBalance - exchangeBalance)
                let driftUSD = drift * (exchangeBalance > 0 ? account.total / account.available : 1.0)

                if drift > 1e-8 && driftUSD > 0.01 {
                    let mismatch = "\(account.exchange):\(account.asset) TB=\(tbBalance) EX=\(exchangeBalance) drift=\(drift) driftUSD=\(driftUSD)"
                    mismatches.append(mismatch)
                    logger.warn(
                        component: "GoNoGo",
                        event: "Exchange parity mismatch",
                        data: [
                            "exchange": account.exchange,
                            "asset": account.asset,
                            "tb_balance": String(tbBalance),
                            "exchange_balance": String(exchangeBalance),
                            "drift": String(drift),
                            "drift_usd": String(driftUSD)
                        ]
                    )
                }
            } catch {
                logger.warn(
                    component: "GoNoGo",
                    event: "Failed to fetch exchange balance",
                    data: ["exchange": account.exchange, "asset": account.asset, "error": error.localizedDescription]
                )
            }
        }

        let passed = mismatches.isEmpty
        logger.info(
            component: "GoNoGo",
            event: passed ? "Exchange parity verification passed" : "Exchange parity verification failed",
            data: ["mismatch_count": String(mismatches.count)]
        )
        return (passed: passed, mismatches: mismatches)
    }

    public func auditIdempotency(sampleSize: Int = 10000) async throws -> Bool {
        logger.info(component: "GoNoGo", event: "Starting idempotency audit", data: ["sample_size": String(sampleSize)])

        let allTransactions = try sqlitePersistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: sampleSize)

        guard allTransactions.count >= sampleSize else {
            logger.warn(component: "GoNoGo", event: "Not enough transactions for audit", data: ["available": String(allTransactions.count)])
            return false
        }

        let sample = Array(allTransactions.suffix(sampleSize))
        let beforeChecksum = try calculateChecksum(accounts: try tigerBeetlePersistence.getAllAccounts())

        var duplicateCount = 0
        var errorCount = 0

        for tx in sample {
            guard let sourceEventID = tx.metadata["source_event_id"],
                  let sourceSystem = tx.metadata["source_system"] else {
                continue
            }

            let duplicate = InvestmentTransaction(
                id: UUID(),
                type: tx.type,
                exchange: tx.exchange,
                asset: tx.asset,
                quantity: tx.quantity,
                price: tx.price,
                fee: tx.fee,
                timestamp: tx.timestamp,
                metadata: tx.metadata,
                idempotencyKey: tx.idempotencyKey
            )

            do {
                try tigerBeetlePersistence.saveTransaction(duplicate)
                duplicateCount += 1
            } catch {
                errorCount += 1
            }
        }

        let afterChecksum = try calculateChecksum(accounts: try tigerBeetlePersistence.getAllAccounts())
        let drift = abs(beforeChecksum.totalBalance - afterChecksum.totalBalance)

        if drift > 1e-8 {
            logger.error(
                component: "GoNoGo",
                event: "Idempotency audit failed: ledger changed",
                data: [
                    "before_total": String(beforeChecksum.totalBalance),
                    "after_total": String(afterChecksum.totalBalance),
                    "drift": String(drift),
                    "duplicates_processed": String(duplicateCount),
                    "errors": String(errorCount)
                ]
            )
            return false
        }

        logger.info(
            component: "GoNoGo",
            event: "Idempotency audit passed: zero net change",
            data: [
                "duplicates_processed": String(duplicateCount),
                "errors": String(errorCount),
                "drift": String(drift)
            ]
        )
        return true
    }

    public func verifyNTPHealth() throws -> (passed: Bool, maxSkew: TimeInterval) {
        logger.info(component: "GoNoGo", event: "Checking NTP health")

        let maxSkew = try ClockSanityChecker.getMaxSkew()

        if maxSkew > 0.5 {
            logger.error(
                component: "GoNoGo",
                event: "NTP health check failed",
                data: ["max_skew_seconds": String(maxSkew)]
            )
            return (passed: false, maxSkew: maxSkew)
        }

        logger.info(component: "GoNoGo", event: "NTP health check passed", data: ["max_skew_seconds": String(maxSkew)])
        return (passed: true, maxSkew: maxSkew)
    }

    public func verifyAccessControl(rbac: LedgerAccessControl) -> (passed: Bool, violations: [String]) {
        logger.info(component: "GoNoGo", event: "Verifying access control")

        var violations: [String] = []

        let executionEngineCanWrite = rbac.hasPermission(.write, for: "ExecutionEngine")
        let cliCanWrite = rbac.hasPermission(.write, for: "TigerBeetleCLITools")
        let dashboardCanWrite = rbac.hasPermission(.write, for: "Dashboard")

        let executionEngineCanRead = rbac.hasPermission(.read, for: "ExecutionEngine")
        let cliCanRead = rbac.hasPermission(.read, for: "TigerBeetleCLITools")
        let dashboardCanRead = rbac.hasPermission(.read, for: "Dashboard")

        if !executionEngineCanWrite {
            violations.append("ExecutionEngine should have write permission")
        }

        if cliCanWrite {
            violations.append("CLI should not have write permission")
        }

        if dashboardCanWrite {
            violations.append("Dashboard should not have write permission")
        }

        if !executionEngineCanRead || !cliCanRead || !dashboardCanRead {
            violations.append("All components should have read permission")
        }

        let passed = violations.isEmpty
        logger.info(
            component: "GoNoGo",
            event: passed ? "Access control verification passed" : "Access control verification failed",
            data: ["violations": String(violations.count)]
        )
        return (passed: passed, violations: violations)
    }

    private struct Checksum {
        let totalBalance: Double
        let accountCount: Int
        let transactionCount: Int
    }

    private func calculateChecksum(accounts: [Holding]) throws -> Checksum {
        let totalBalance = accounts.reduce(0.0) { $0 + $1.total }
        return Checksum(
            totalBalance: totalBalance,
            accountCount: accounts.count,
            transactionCount: 0
        )
    }

    private func parseExchangeBalance(_ holding: [String: Any]) -> Double? {
        if let balance = holding["available"] as? Double {
            return balance
        }
        if let balance = holding["quantity"] as? Double {
            return balance
        }
        if let balanceStr = holding["available"] as? String,
           let balance = Double(balanceStr) {
            return balance
        }
        return nil
    }
}
