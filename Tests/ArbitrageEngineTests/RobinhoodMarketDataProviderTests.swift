import Testing
import Foundation
import SmartVestor
import Utils

struct RobinhoodMarketDataProviderTests {

    struct MockHoldingsProvider: RobinhoodHoldingsProvider {
        let holdings: [[String: Any]]

        func getHoldings() async throws -> [[String: Any]] {
            return holdings
        }
    }

    @Test func testFetchLatestPriceSuccess() async throws {
        let holdings = [
            [
                "asset": "BTC",
                "quantity": "1.5",
                "available": "1.5",
                "pending": "0",
                "staked": "0"
            ]
        ]

        let provider = MockHoldingsProvider(holdings: holdings)
        let logger = StructuredLogger()
        let dataProvider = RobinhoodMarketDataProvider(
            holdingsProvider: provider,
            logger: logger
        )

        let price = try await dataProvider.fetchLatestPrice(symbol: "BTC")

        #expect(price == 100.0)
    }

    @Test func testFetchLatestPriceNotFound() async throws {
        let holdings: [[String: Any]] = []

        let provider = MockHoldingsProvider(holdings: holdings)
        let logger = StructuredLogger()
        let dataProvider = RobinhoodMarketDataProvider(
            holdingsProvider: provider,
            logger: logger
        )

        do {
            _ = try await dataProvider.fetchLatestPrice(symbol: "ETH")
            Issue.record("Expected MarketDataError")
        } catch let error as MarketDataError {
            switch error {
            case .unsupportedSymbol(let symbol):
                #expect(symbol == "ETH")
            default:
                Issue.record("Wrong error type")
            }
        }
    }

    @Test func testFetchOHLCVDataReturnsCorrectCount() async throws {
        let holdings: [[String: Any]] = []

        let provider = MockHoldingsProvider(holdings: holdings)
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
        let holdings: [[String: Any]] = []

        let provider = MockHoldingsProvider(holdings: holdings)
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

    @Test func testSubscriptionYieldsMultiplePrices() async throws {
        let holdings = [
            [
                "asset": "SOL",
                "quantity": "10.0",
                "available": "10.0",
                "pending": "0",
                "staked": "0"
            ]
        ]

        let provider = MockHoldingsProvider(holdings: holdings)
        let logger = StructuredLogger()
        let dataProvider = RobinhoodMarketDataProvider(
            holdingsProvider: provider,
            logger: logger
        )

        let stream = dataProvider.subscribeToPriceUpdates(symbol: "SOL")
        var prices: [Double] = []

        for await price in stream {
            prices.append(price)
            if prices.count >= 3 {
                break
            }
        }

        #expect(prices.count >= 3)
        for price in prices {
            #expect(price == 100.0)
        }
    }

    @Test func testRateLimiterBlocksExcessiveRequests() async throws {
        let limiter = RobinhoodRateLimiter(maxRequestsPerMinute: 5)

        for _ in 0..<5 {
            try await limiter.waitIfNeeded()
        }

        let startTime = Date()
        try await limiter.waitIfNeeded()
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(elapsed > 55.0)
    }
}
