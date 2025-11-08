import Foundation

public actor PanelScrollState {
    private var scrollPositions: [PanelType: Int]

    public init() {
        self.scrollPositions = [:]
    }

    public func getScrollPosition(for panelType: PanelType) -> Int {
        return scrollPositions[panelType] ?? 0
    }

    public func setScrollPosition(_ position: Int, for panelType: PanelType) {
        scrollPositions[panelType] = max(0, position)
    }

    public func scrollUp(panelType: PanelType, lineCount: Int = 1) -> Int {
        let current = getScrollPosition(for: panelType)
        let newPosition = max(0, current - lineCount)
        setScrollPosition(newPosition, for: panelType)
        return newPosition
    }

    public func scrollDown(panelType: PanelType, lineCount: Int = 1, maxItems: Int) -> Int {
        let current = getScrollPosition(for: panelType)
        let maxScroll = max(0, maxItems - 1)
        let newPosition = min(maxScroll, current + lineCount)
        setScrollPosition(newPosition, for: panelType)
        return newPosition
    }

    public func scrollPageUp(panelType: PanelType, pageSize: Int) -> Int {
        return scrollUp(panelType: panelType, lineCount: pageSize)
    }

    public func scrollPageDown(panelType: PanelType, pageSize: Int, maxItems: Int) -> Int {
        return scrollDown(panelType: panelType, lineCount: pageSize, maxItems: maxItems)
    }

    public func resetScrollPosition(for panelType: PanelType) {
        scrollPositions[panelType] = 0
    }

    public func getVisibleRange(panelType: PanelType, visibleHeight: Int, totalItems: Int) -> Range<Int> {
        guard totalItems > 0 else {
            return 0..<0
        }

        let scrollPos = getScrollPosition(for: panelType)
        let start = max(0, min(scrollPos, totalItems - 1))
        let end = min(totalItems, start + visibleHeight)

        guard start < totalItems else {
            return 0..<0
        }

        return start..<end
    }
}
