import Testing
import Foundation
@testable import MLPatternEngine
@testable import Core
@testable import Utils

@Suite("TimeSeries Store SQLite Tests")
struct TimeSeriesStoreSQLiteTests {

    @Test("TimeSeriesStore persists and retrieves market data via SQLite")
    func testTimeSeriesStorePersistsData() async throws {
        let logger = createTestLogger()
        let database = try SQLiteTimeSeriesDatabase(location: .inMemory, logger: logger)
        let store = TimeSeriesStore(database: database, logger: logger)

        let now = Date()
        let symbol = "BTC-USD"

        var dataPoints: [MarketDataPoint] = []
        for index in 0..<120 {
            let timestamp = now.addingTimeInterval(TimeInterval(index - 120) * 60) // 1 minute spacing
            dataPoints.append(
                MarketDataPoint(
                    timestamp: timestamp,
                    symbol: symbol,
                    open: 100.0 + Double(index),
                    high: 110.0 + Double(index),
                    low: 90.0 + Double(index),
                    close: 105.0 + Double(index),
                    volume: 1000.0 + Double(index) * 5.0,
                    exchange: "unittest"
                )
            )
        }

        try await store.storeData(dataPoints)

        let firstTimestamp = dataPoints.first!.timestamp
        let lastTimestamp = dataPoints.last!.timestamp

        let fetched = try await store.getData(symbol: symbol, from: firstTimestamp, to: lastTimestamp)
        #expect(fetched.count == dataPoints.count)

        let latest = try await store.getLatestData(symbol: symbol, limit: 10)
        #expect(latest.count == 10)

        // Verify that the data is ordered correctly
        if let firstFetched = fetched.first, let lastFetched = fetched.last {
            #expect(firstFetched.timestamp <= lastFetched.timestamp)
        }
        if let firstLatest = latest.first, let lastLatest = latest.last {
            #expect(firstLatest.timestamp >= lastLatest.timestamp)
        }
    }

    @Test("TimeSeriesStore enforces retention policy with archival")
    func testTimeSeriesStoreRetentionAndArchival() async throws {
        let logger = createTestLogger()
        let database = try SQLiteTimeSeriesDatabase(location: .inMemory, logger: logger)
        let store = TimeSeriesStore(database: database, logger: logger)

        let symbol = "ETH-USD"
        let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60) // 90 days ago

        let archivalBase = cutoff.addingTimeInterval(-5 * 24 * 60 * 60) // 5 days older than retention
        let freshBase = Date().addingTimeInterval(-1 * 60 * 60) // within last hour

        var archivalData: [MarketDataPoint] = []
        var freshData: [MarketDataPoint] = []

        for index in 0..<5 {
            archivalData.append(
                MarketDataPoint(
                    timestamp: archivalBase.addingTimeInterval(TimeInterval(index * 60)),
                    symbol: symbol,
                    open: 2000.0 + Double(index),
                    high: 2010.0 + Double(index),
                    low: 1990.0 + Double(index),
                    close: 2005.0 + Double(index),
                    volume: 800.0 + Double(index) * 2.0,
                    exchange: "unittest"
                )
            )

            freshData.append(
                MarketDataPoint(
                    timestamp: freshBase.addingTimeInterval(TimeInterval(index * 60)),
                    symbol: symbol,
                    open: 2100.0 + Double(index),
                    high: 2110.0 + Double(index),
                    low: 2090.0 + Double(index),
                    close: 2105.0 + Double(index),
                    volume: 1000.0 + Double(index) * 3.0,
                    exchange: "unittest"
                )
            )
        }

        try await store.storeData(archivalData + freshData)
        try await store.deleteOldData(olderThan: cutoff)

        let archivedFetch = try await store.getData(
            symbol: symbol,
            from: archivalBase,
            to: archivalBase.addingTimeInterval(24 * 60 * 60)
        )
        #expect(archivedFetch.isEmpty)

        let freshFetch = try await store.getData(
            symbol: symbol,
            from: freshBase.addingTimeInterval(-60),
            to: Date()
        )
        #expect(freshFetch.count == freshData.count)

        let archiveCount = try await database.archivedEntryCount()
        #expect(archiveCount > 0)
    }
}
