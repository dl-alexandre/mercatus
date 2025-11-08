import Foundation
import Utils

public class ColdStartValidator {
    private let sqlitePersistence: SQLitePersistence
    private let tigerBeetlePersistence: TigerBeetlePersistence
    private let logger: StructuredLogger

    public init(
        sqlitePersistence: SQLitePersistence,
        tigerBeetlePersistence: TigerBeetlePersistence,
        logger: StructuredLogger = StructuredLogger()
    ) {
        self.sqlitePersistence = sqlitePersistence
        self.tigerBeetlePersistence = tigerBeetlePersistence
        self.logger = logger
    }

    public func validateColdStart() throws -> Bool {
        logger.info(component: "ColdStartValidator", event: "Starting cold start validation")

        try ClockSanityChecker.validateClock()

        let sqliteAccounts = try sqlitePersistence.getAllAccounts()
        let _ = try sqlitePersistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: 100)

        let sqliteTotal = sqliteAccounts.reduce(0.0) { $0 + $1.total }

        let tbAccounts = try tigerBeetlePersistence.getAllAccounts()
        let tbTotal = tbAccounts.reduce(0.0) { $0 + $1.total }

        let drift = abs(sqliteTotal - tbTotal)
        let threshold = 1e-8

        if drift > threshold {
            logger.error(
                component: "ColdStartValidator",
                event: "Cold start validation failed",
                data: [
                    "drift": String(drift),
                    "threshold": String(threshold),
                    "sqlite_total": String(sqliteTotal),
                    "tigerbeetle_total": String(tbTotal)
                ]
            )
            throw SmartVestorError.persistenceError("Cold start validation failed: drift \(drift) > threshold \(threshold)")
        }

        logger.info(component: "ColdStartValidator", event: "Cold start validation passed")
        return true
    }
}
