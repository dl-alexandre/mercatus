import Testing
import Foundation
@testable import SmartVestor

@Suite("PriceSortManager Tests")
struct PriceSortManagerTests {

    @Test("Default sort mode is symbol")
    func testDefaultSortMode() async {
        let manager = PriceSortManager()
        let mode = await manager.getSortMode()
        #expect(mode == .symbol)
    }

    @Test("Toggle sort mode cycles through modes")
    func testToggleSortMode() async {
        let manager = PriceSortManager()

        await manager.toggleSortMode()
        let mode1 = await manager.getSortMode()
        #expect(mode1 == .price)

        await manager.toggleSortMode()
        let mode2 = await manager.getSortMode()
        #expect(mode2 == .change24h)

        await manager.toggleSortMode()
        let mode3 = await manager.getSortMode()
        #expect(mode3 == .symbol)
    }

    @Test("Set sort mode explicitly")
    func testSetSortMode() async {
        let manager = PriceSortManager()

        await manager.setSortMode(.price)
        let mode = await manager.getSortMode()
        #expect(mode == .price)
    }

    @Test("Toggle sort direction")
    func testToggleDirection() async {
        let manager = PriceSortManager()
        let initial = await manager.getSortDirection()

        await manager.toggleDirection()
        let toggled = await manager.getSortDirection()
        #expect(toggled != initial)

        await manager.toggleDirection()
        let back = await manager.getSortDirection()
        #expect(back == initial)
    }

    @Test("Sort prices by symbol")
    func testSortBySymbol() async {
        let manager = PriceSortManager()
        await manager.setSortMode(.symbol)

        let prices: [String: Double] = ["BTC": 50000, "ETH": 3000, "ADA": 1.5]
        let sorted = await manager.sortPrices(prices)

        #expect(sorted[0].0 == "ADA")
        #expect(sorted[1].0 == "BTC")
        #expect(sorted[2].0 == "ETH")
    }

    @Test("Sort prices by price ascending")
    func testSortByPriceAscending() async {
        let manager = PriceSortManager()
        await manager.setSortMode(.price)

        let prices: [String: Double] = ["BTC": 50000, "ETH": 3000, "ADA": 1.5]
        let sorted = await manager.sortPrices(prices)

        #expect(sorted[0].0 == "ADA")
        #expect(sorted[1].0 == "ETH")
        #expect(sorted[2].0 == "BTC")
    }

    @Test("Sort prices by price descending")
    func testSortByPriceDescending() async {
        let manager = PriceSortManager()
        await manager.setSortMode(.price)
        await manager.toggleDirection()

        let prices: [String: Double] = ["BTC": 50000, "ETH": 3000, "ADA": 1.5]
        let sorted = await manager.sortPrices(prices)

        #expect(sorted[0].0 == "BTC")
        #expect(sorted[1].0 == "ETH")
        #expect(sorted[2].0 == "ADA")
    }
}
