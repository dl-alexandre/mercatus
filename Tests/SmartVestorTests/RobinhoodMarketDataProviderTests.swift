import Testing
import Foundation
import SmartVestor
import Utils

struct RobinhoodMarketDataProviderTests {

    struct EmptyHoldingsProvider: RobinhoodHoldingsProvider {
        func getHoldings() async throws -> [[String: Any]] {
            return []
        }
    }

@Test func testFetchOHLCVDataReturnsCorrectCount() async throws {
        let provider = EmptyHoldingsProvider()
        let logger = StructuredLogger()
        let dataProvider = RobinhoodMarketDataProvider(
            holdingsProvider: provider,
            logger: logger
        )

        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-24 * 60 * 60)

        let data = try await dataProvider.fetchOHLCVData(
            symbol: "BTC",
            startDate: startDate,
            endDate: endDate
        )

        #expect(data.count > 0)
    }

    @Test func testFetchOHLCVDataValidatesHighLowOpenClose() async throws {
        let provider = EmptyHoldingsProvider()
        let logger = StructuredLogger()
        let dataProvider = RobinhoodMarketDataProvider(
            holdingsProvider: provider,
            logger: logger
        )

        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-24 * 60 * 60)

        let data = try await dataProvider.fetchOHLCVData(
            symbol: "BTC",
            startDate: startDate,
            endDate: endDate
        )

        guard let firstPoint = data.first else {
            Issue.record("No data points returned")
            return
        }

        #expect(firstPoint.high >= firstPoint.low)
        #expect(firstPoint.high >= firstPoint.open)
        #expect(firstPoint.high >= firstPoint.close)
        #expect(firstPoint.low <= firstPoint.open)
        #expect(firstPoint.low <= firstPoint.close)
    }

}
