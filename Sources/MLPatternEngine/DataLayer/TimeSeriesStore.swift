import Foundation
import Core
import Utils

public final class TimeSeriesStore: TimeSeriesStoreProtocol {
    private let database: DatabaseProtocol
    private let logger: StructuredLogger

    private let retentionPeriod: TimeInterval = 90 * 24 * 60 * 60 // 90 days
    private let retentionCheckInterval: TimeInterval = 12 * 60 * 60 // every 12 hours
    private var lastRetentionEnforcement: Date = .distantPast

    public init(database: DatabaseProtocol, logger: StructuredLogger) {
        self.database = database
        self.logger = logger
    }

    public convenience init(dbPath: String, logger: StructuredLogger) throws {
        let database = try SQLiteTimeSeriesDatabase(
            location: .file(URL(fileURLWithPath: dbPath)),
            logger: logger
        )
        self.init(database: database, logger: logger)
    }

    public func storeData(_ dataPoints: [MarketDataPoint]) async throws {
        guard !dataPoints.isEmpty else { return }

        let batchSize = 1_000
        for batch in dataPoints.chunked(into: batchSize) {
            try await database.insertMarketData(batch)
        }

        logger.info(
            component: "TimeSeriesStore",
            event: "Stored \(dataPoints.count) market data points"
        )

        scheduleRetentionEnforcementIfNeeded()
    }

    public func getData(symbol: String, from: Date, to: Date) async throws -> [MarketDataPoint] {
        try await database.getMarketData(symbol: symbol, from: from, to: to)
    }

    public func getLatestData(symbol: String, limit: Int) async throws -> [MarketDataPoint] {
        try await database.getLatestMarketData(symbol: symbol, limit: limit)
    }

    public func deleteOldData(olderThan: Date) async throws {
        try await database.archiveOldMarketData(olderThan: olderThan)
        try await database.deleteOldMarketData(olderThan: olderThan)
        logger.info(
            component: "TimeSeriesStore",
            event: "Archived and deleted market data older than \(olderThan)"
        )
    }

    public func enforceRetentionPolicy() async throws {
        let cutoff = Date().addingTimeInterval(-retentionPeriod)
        try await deleteOldData(olderThan: cutoff)
    }

    private func scheduleRetentionEnforcementIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastRetentionEnforcement) >= retentionCheckInterval else { return }

        lastRetentionEnforcement = now
        // Note: Retention enforcement is handled elsewhere in production
    }
}

public protocol DatabaseProtocol: Sendable {
    func insertMarketData(_ dataPoints: [MarketDataPoint]) async throws
    func getMarketData(symbol: String, from: Date, to: Date) async throws -> [MarketDataPoint]
    func getLatestMarketData(symbol: String, limit: Int) async throws -> [MarketDataPoint]
    func archiveOldMarketData(olderThan: Date) async throws
    func deleteOldMarketData(olderThan: Date) async throws
    func createTables() async throws
    func executeQuery(_ query: String, parameters: [any Sendable]) async throws -> [[String: any Sendable]]
    func executeUpdate(_ query: String, parameters: [any Sendable]) async throws -> Int
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
