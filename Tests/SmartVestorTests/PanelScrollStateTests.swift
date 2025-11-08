import Testing
import Foundation
@testable import SmartVestor

@Suite("PanelScrollState Tests")
struct PanelScrollStateTests {

    @Test("Initial scroll position is zero")
    func testInitialPosition() async {
        let scrollState = PanelScrollState()
        let position = await scrollState.getScrollPosition(for: .balances)
        #expect(position == 0)
    }

    @Test("Scroll down within bounds")
    func testScrollDown() async {
        let scrollState = PanelScrollState()
        let newPos = await scrollState.scrollDown(panelType: .balances, maxItems: 10)
        #expect(newPos == 1)

        let position = await scrollState.getScrollPosition(for: .balances)
        #expect(position == 1)
    }

    @Test("Scroll down respects max items")
    func testScrollDownMaxItems() async {
        let scrollState = PanelScrollState()
        await scrollState.setScrollPosition(8, for: .balances)
        let newPos = await scrollState.scrollDown(panelType: .balances, maxItems: 10)
        #expect(newPos == 9)

        let finalPos = await scrollState.scrollDown(panelType: .balances, maxItems: 10)
        #expect(finalPos == 9)
    }

    @Test("Scroll up")
    func testScrollUp() async {
        let scrollState = PanelScrollState()
        await scrollState.setScrollPosition(5, for: .balances)
        let newPos = await scrollState.scrollUp(panelType: .balances)
        #expect(newPos == 4)
    }

    @Test("Scroll up doesn't go below zero")
    func testScrollUpMinimum() async {
        let scrollState = PanelScrollState()
        let newPos = await scrollState.scrollUp(panelType: .balances)
        #expect(newPos == 0)
    }

    @Test("Page scroll down")
    func testPageScrollDown() async {
        let scrollState = PanelScrollState()
        let newPos = await scrollState.scrollPageDown(panelType: .balances, pageSize: 5, maxItems: 20)
        #expect(newPos == 5)
    }

    @Test("Page scroll up")
    func testPageScrollUp() async {
        let scrollState = PanelScrollState()
        await scrollState.setScrollPosition(10, for: .balances)
        let newPos = await scrollState.scrollPageUp(panelType: .balances, pageSize: 5)
        #expect(newPos == 5)
    }

    @Test("Get visible range")
    func testGetVisibleRange() async {
        let scrollState = PanelScrollState()
        await scrollState.setScrollPosition(5, for: .balances)
        let range = await scrollState.getVisibleRange(panelType: .balances, visibleHeight: 3, totalItems: 20)
        #expect(range.lowerBound == 5)
        #expect(range.upperBound == 8)
    }

    @Test("Reset scroll position")
    func testResetScroll() async {
        let scrollState = PanelScrollState()
        await scrollState.setScrollPosition(10, for: .balances)
        await scrollState.resetScrollPosition(for: .balances)
        let position = await scrollState.getScrollPosition(for: .balances)
        #expect(position == 0)
    }
}
