import Foundation

actor HelpState {
    private var isShowing: Bool = false
    private var scrollOffset: Int = 0

    func isVisible() -> Bool {
        return isShowing
    }

    func show() {
        isShowing = true
        scrollOffset = 0
    }

    func hide() {
        isShowing = false
        scrollOffset = 0
    }

    func toggle() {
        isShowing.toggle()
        if !isShowing {
            scrollOffset = 0
        }
    }

    func getScrollOffset() -> Int {
        return scrollOffset
    }

    func scrollDown(maxLines: Int, visibleLines: Int) {
        guard maxLines > 0 && visibleLines > 0 else {
            scrollOffset = 0
            return
        }
        let maxOffset = max(0, maxLines - visibleLines)
        scrollOffset = min(scrollOffset + 1, maxOffset)
    }

    func setScrollOffset(_ offset: Int, maxLines: Int, visibleLines: Int) {
        guard maxLines > 0 && visibleLines > 0 else {
            scrollOffset = 0
            return
        }
        let maxOffset = max(0, maxLines - visibleLines)
        scrollOffset = max(0, min(offset, maxOffset))
    }

    func scrollUp() {
        scrollOffset = max(0, scrollOffset - 1)
    }

    func resetScroll() {
        scrollOffset = 0
    }
}
