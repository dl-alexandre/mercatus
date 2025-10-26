import Foundation
import Utils

/// Lightweight in-memory database that mirrors the behaviour required by `DatabaseProtocol`.
/// Useful for unit tests that do not need persistence guarantees or SQLite semantics.
public final class MockDatabase: DatabaseProtocol {
    private var marketData: [MarketDataPoint] = []
    private var archivedData: [MarketDataPoint] = []
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func insertMarketData(_ dataPoints: [MarketDataPoint]) async throws {
        guard !dataPoints.isEmpty else { return }
        marketData.append(contentsOf: dataPoints)
        marketData.sort { $0.timestamp < $1.timestamp }
        logger.info(component: "MockDatabase", event: "Inserted \(dataPoints.count) market data points")
    }

    public func getMarketData(symbol: String, from: Date, to: Date) async throws -> [MarketDataPoint] {
        marketData.filter {
            $0.symbol == symbol &&
            $0.timestamp >= from &&
            $0.timestamp <= to
        }
    }

    public func getLatestMarketData(symbol: String, limit: Int) async throws -> [MarketDataPoint] {
        let filtered = marketData
            .filter { $0.symbol == symbol }
            .sorted { $0.timestamp > $1.timestamp }
        return Array(filtered.prefix(limit))
    }

    public func archiveOldMarketData(olderThan cutoff: Date) async throws {
        let dataToArchive = marketData.filter { $0.timestamp < cutoff }
        guard !dataToArchive.isEmpty else {
            logger.debug(component: "MockDatabase", event: "No market data to archive for cutoff \(cutoff)")
            return
        }

        archivedData.append(contentsOf: dataToArchive)
        logger.info(component: "MockDatabase", event: "Archived \(dataToArchive.count) market data points")
    }

    public func deleteOldMarketData(olderThan cutoff: Date) async throws {
        let previousCount = marketData.count
        marketData.removeAll { $0.timestamp < cutoff }
        let deleted = previousCount - marketData.count
        logger.info(component: "MockDatabase", event: "Deleted \(deleted) market data points")
    }

    public func createTables() async throws {
        logger.info(component: "MockDatabase", event: "Mock database tables initialized")
    }

    public func archivedMarketDataCount() -> Int {
        archivedData.count
    }

    public func executeQuery(_ query: String, parameters: [any Sendable]) async throws -> [[String: any Sendable]] {
        // Mock implementation - return empty results
        return []
    }

    public func executeUpdate(_ query: String, parameters: [any Sendable]) async throws -> Int {
        // Mock implementation - return 0 affected rows
        return 0
    }
}
