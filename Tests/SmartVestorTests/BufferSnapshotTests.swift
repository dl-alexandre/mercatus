import Testing
@testable import SmartVestor

@Suite("Buffer Snapshot Tests")
struct BufferSnapshotTests {
    @Test
    func statusPanel_basic_80x24() async throws {
        let size = Size(width: 80, height: 24)
        let root = await makeStatusOnlyTree()

        var buf = TerminalBuffer.empty(size: size)
        _ = root.measure(in: size)
        root.render(into: &buf, at: .zero)

        assertSnapshot(buffer: buf, named: "status_only_80x24", testIdentifier: "statusPanel_basic_80x24")
    }

    @Test
    func allPanels_120x40() async throws {
        let size = Size(width: 120, height: 40)
        let root = await makeAllPanelsTree()

        var buf = TerminalBuffer.empty(size: size)
        _ = root.measure(in: size)
        root.render(into: &buf, at: .zero)

        assertSnapshot(buffer: buf, named: "all_panels_120x40", testIdentifier: "allPanels_120x40")
    }

    @Test
    func allPanels_withPrices_120x40() async throws {
        let size = Size(width: 120, height: 40)
        let prices = samplePrices()
        let root = await makeAllPanelsTree(prices: prices)

        var buf = TerminalBuffer.empty(size: size)
        _ = root.measure(in: size)
        root.render(into: &buf, at: .zero)

        assertSnapshot(buffer: buf, named: "all_panels_with_prices_120x40", testIdentifier: "allPanels_withPrices_120x40")
    }
}
