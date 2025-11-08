import Testing
import Foundation
@testable import SmartVestor

@Suite("PanelToggleManager Tests")
struct PanelToggleManagerTests {

    @Test("Default visibility state")
    func testDefaultVisibility() async throws {
        let manager = PanelToggleManager()
        let visible = await manager.getVisiblePanels()
        #expect(visible.contains(.status))
        #expect(visible.contains(.balances))
        #expect(visible.contains(.activity))
    }

    @Test("Toggle panel visibility")
    func testTogglePanel() async throws {
        let manager = PanelToggleManager()

        try await manager.toggle(.price)
        let visible = await manager.getVisiblePanels()
        #expect(visible.contains(.price))

        try await manager.toggle(.price)
        let visibleAfter = await manager.getVisiblePanels()
        #expect(!visibleAfter.contains(.price))
    }

    @Test("Set visibility explicitly")
    func testSetVisibility() async throws {
        let manager = PanelToggleManager()

        try await manager.setVisibility(.swap, visible: true)
        let visible = await manager.getVisiblePanels()
        #expect(visible.contains(.swap))

        try await manager.setVisibility(.swap, visible: false)
        let visibleAfter = await manager.getVisiblePanels()
        #expect(!visibleAfter.contains(.swap))
    }

    @Test("Cycle to next visible panel")
    func testCycleToNext() async throws {
        let manager = PanelToggleManager()

        try await manager.setVisibility(.status, visible: true)
        try await manager.setVisibility(.balances, visible: true)
        try await manager.setVisibility(.activity, visible: true)

        let initial = await manager.getSelectedPanel()
        await manager.cycleToNextVisiblePanel()
        let next = await manager.getSelectedPanel()
        #expect(next != initial)
    }
}
