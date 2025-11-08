import Foundation
import Utils

public struct ReconciliationResult {
    public let accountID: UUID
    public let exchange: String
    public let asset: String
    public let sqliteBalance: Double
    public let tigerBeetleBalance: Double
    public let drift: Double
    public let isHealthy: Bool

    public init(
        accountID: UUID,
        exchange: String,
        asset: String,
        sqliteBalance: Double,
        tigerBeetleBalance: Double,
        threshold: Double = 1e-8
    ) {
        self.accountID = accountID
        self.exchange = exchange
        self.asset = asset
        self.sqliteBalance = sqliteBalance
        self.tigerBeetleBalance = tigerBeetleBalance
        self.drift = abs(sqliteBalance - tigerBeetleBalance)
        self.isHealthy = drift < threshold
    }
}

public class TigerBeetleReconciliation {
    private let sqlitePersistence: SQLitePersistence
    private let tigerBeetlePersistence: TigerBeetlePersistence
    let logger: StructuredLogger
    private let threshold: Double

    public init(
        sqlitePersistence: SQLitePersistence,
        tigerBeetlePersistence: TigerBeetlePersistence,
        logger: StructuredLogger = StructuredLogger(),
        threshold: Double = 1e-8
    ) {
        self.sqlitePersistence = sqlitePersistence
        self.tigerBeetlePersistence = tigerBeetlePersistence
        self.logger = logger
        self.threshold = threshold
    }

    public func reconcileAccount(exchange: String, asset: String) throws -> ReconciliationResult {
        let accountID = AccountMapping.accountID(exchange: exchange, asset: asset)
        let sqliteAccount = try sqlitePersistence.getAccount(exchange: exchange, asset: asset)
        let tbAccount = try tigerBeetlePersistence.getAccount(exchange: exchange, asset: asset)

        let sqliteBalance = sqliteAccount?.total ?? 0
        let tbBalance = tbAccount?.total ?? 0

        return ReconciliationResult(
            accountID: accountID,
            exchange: exchange,
            asset: asset,
            sqliteBalance: sqliteBalance,
            tigerBeetleBalance: tbBalance,
            threshold: threshold
        )
    }

    public func reconcileAll() throws -> [ReconciliationResult] {
        let sqliteAccounts = try sqlitePersistence.getAllAccounts()
        var results: [ReconciliationResult] = []

        for account in sqliteAccounts {
            let result = try reconcileAccount(exchange: account.exchange, asset: account.asset)
            results.append(result)

            if !result.isHealthy {
                logger.warn(
                    component: "TigerBeetleReconciliation",
                    event: "Balance drift detected",
                    data: [
                        "exchange": result.exchange,
                        "asset": result.asset,
                        "drift": String(result.drift),
                        "sqlite_balance": String(result.sqliteBalance),
                        "tigerbeetle_balance": String(result.tigerBeetleBalance)
                    ]
                )
            }
        }

        return results
    }

    public func verifyFullLedger() throws -> Bool {
        let results = try reconcileAll()
        return results.allSatisfy { $0.isHealthy }
    }
}
