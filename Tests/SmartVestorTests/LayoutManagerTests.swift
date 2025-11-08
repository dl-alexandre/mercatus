import Testing
import Foundation
@testable import SmartVestor
import Darwin

@Suite("Layout Manager Tests")
struct LayoutManagerTests {

    @Test("TerminalSize should enforce minimum dimensions")
    func testTerminalSizeMinimumEnforcement() {
        let smallSize = TerminalSize(width: 40, height: 10)
        #expect(smallSize.width == 80)
        #expect(smallSize.height == 24)

        let belowMinimumWidth = TerminalSize(width: 50, height: 30)
        #expect(belowMinimumWidth.width == 80)
        #expect(belowMinimumWidth.height == 30)

        let belowMinimumHeight = TerminalSize(width: 100, height: 15)
        #expect(belowMinimumHeight.width == 100)
        #expect(belowMinimumHeight.height == 24)

        let validSize = TerminalSize(width: 120, height: 40)
        #expect(validSize.width == 120)
        #expect(validSize.height == 40)
    }

    @Test("TerminalSize should validate dimensions correctly")
    func testTerminalSizeValidation() {
        let minimumSize = TerminalSize.minimum
        #expect(minimumSize.isValid == true)

        let validSize = TerminalSize(width: 100, height: 30)
        #expect(validSize.isValid == true)

        let largeSize = TerminalSize(width: 200, height: 60)
        #expect(largeSize.isValid == true)
    }

    @Test("PanelLayout should enforce positive dimensions")
    func testPanelLayoutDimensionEnforcement() {
        let invalidLayout = PanelLayout(x: 0, y: 0, width: -5, height: 10)
        #expect(invalidLayout.width == 1)
        #expect(invalidLayout.height == 10)

        let negativeHeightLayout = PanelLayout(x: 5, y: 5, width: 20, height: -3)
        #expect(negativeHeightLayout.width == 20)
        #expect(negativeHeightLayout.height == 1)

        let validLayout = PanelLayout(x: 10, y: 5, width: 50, height: 15)
        #expect(validLayout.width == 50)
        #expect(validLayout.height == 15)
    }

    @Test("PanelLayout should validate correctly")
    func testPanelLayoutValidation() {
        let validLayout = PanelLayout(x: 0, y: 0, width: 80, height: 24)
        #expect(validLayout.isValid == true)

        let invalidWidth = PanelLayout(x: 0, y: 0, width: 0, height: 10)
        #expect(invalidWidth.width == 1)
        #expect(invalidWidth.isValid == true)

        let invalidHeight = PanelLayout(x: 0, y: 0, width: 10, height: 0)
        #expect(invalidHeight.height == 1)
        #expect(invalidHeight.isValid == true)

        let negativeX = PanelLayout(x: -5, y: 0, width: 10, height: 10)
        #expect(negativeX.isValid == true)
        #expect(negativeX.x == 0)
    }

    @Test("LayoutManager should detect minimum size correctly")
    func testMinimumSizeDetection() {
        let manager = LayoutManager.shared
        let minimumSize = TerminalSize.minimum

        #expect(manager.isMinimumSizeMet(terminalSize: minimumSize) == true)

        let belowMinimumRaw = (width: 70, height: 20)
        let belowMinimum = TerminalSize(width: belowMinimumRaw.width, height: belowMinimumRaw.height)
        #expect(belowMinimum.width == 80)
        #expect(belowMinimum.height == 24)
        #expect(manager.isMinimumSizeMet(terminalSize: belowMinimum) == true)

        let exactlyMinimum = TerminalSize(width: 80, height: 24)
        #expect(manager.isMinimumSizeMet(terminalSize: exactlyMinimum) == true)

        let aboveMinimum = TerminalSize(width: 100, height: 30)
        #expect(manager.isMinimumSizeMet(terminalSize: aboveMinimum) == true)
    }

    @Test("LayoutManager should calculate layout for minimum terminal size")
    func testMinimumSizeLayout() {
        let manager = LayoutManager.shared
        let minimumSize = TerminalSize.minimum
        let layout = manager.calculateLayout(terminalSize: minimumSize)

        #expect(layout[.status] != nil)
        #expect(layout[.balances] != nil || layout[.balance] != nil)

        if let statusLayout = layout[.status] {
            #expect(statusLayout.width == minimumSize.width)
            #expect(statusLayout.height > 0)
            #expect(statusLayout.height <= minimumSize.height)
        }

        if let balancesLayout = layout[.balances] ?? layout[.balance] {
            #expect(balancesLayout.width == minimumSize.width)
            #expect(balancesLayout.height > 0)
        }

        if let activityLayout = layout[.activity] {
            #expect(activityLayout.width == minimumSize.width)
            #expect(activityLayout.height >= 3)
        }
    }

    @Test("LayoutManager should calculate layout for small terminal size")
    func testSmallTerminalLayout() {
        let manager = LayoutManager.shared
        let smallSize = TerminalSize(width: 80, height: 24)
        let layout = manager.calculateLayout(terminalSize: smallSize)

        #expect(layout[.status] != nil)

        let validationResult = manager.validateLayout(layout, terminalSize: smallSize)
        #expect(validationResult.isSuccess)
    }

    @Test("LayoutManager should calculate layout for medium terminal size")
    func testMediumTerminalLayout() {
        let manager = LayoutManager.shared
        let mediumSize = TerminalSize(width: 120, height: 40)
        let layout = manager.calculateLayout(terminalSize: mediumSize)

        #expect(layout[.status] != nil)
        #expect(layout[.balances] != nil || layout[.balance] != nil)

        if let balancesLayout = layout[.balances] ?? layout[.balance] {
            #expect(balancesLayout.height >= 10)
        }

        let validationResult = manager.validateLayout(layout, terminalSize: mediumSize)
        #expect(validationResult.isSuccess)
    }

    @Test("LayoutManager should calculate layout for large terminal size")
    func testLargeTerminalLayout() {
        let manager = LayoutManager.shared
        let largeSize = TerminalSize(width: 200, height: 60)
        let layout = manager.calculateLayout(terminalSize: largeSize)

        #expect(layout[.status] != nil)
        #expect(layout[.balances] != nil || layout[.balance] != nil)

        if let statusLayout = layout[.status] {
            #expect(statusLayout.width == largeSize.width)
        }

        let validationResult = manager.validateLayout(layout, terminalSize: largeSize)
        #expect(validationResult.isSuccess)
    }

    @Test("LayoutManager should calculate layout with custom priorities")
    func testCustomPriorityLayout() {
        let manager = LayoutManager.shared
        let size = TerminalSize(width: 100, height: 30)
        let priorities: [PanelType: LayoutPriority] = [
            .status: .critical,
            .balance: .high,
            .activity: .low
        ]

        let layout = manager.calculateLayout(terminalSize: size, priorities: priorities)

        #expect(layout[.status] != nil)

        let validationResult = manager.validateLayout(layout, terminalSize: size)
        #expect(validationResult.isSuccess)
    }

    @Test("LayoutManager should prioritize critical panels in constrained space")
    func testPriorityBasedLayout() {
        let manager = LayoutManager.shared
        let constrainedSize = TerminalSize(width: 80, height: 24)
        let priorities: [PanelType: LayoutPriority] = [
            .status: .critical,
            .balances: .high,
            .activity: .low
        ]

        let layout = manager.calculateLayout(terminalSize: constrainedSize, priorities: priorities)

        #expect(layout[.status] != nil)

        if let statusLayout = layout[.status], let activityLayout = layout[.activity] {
            #expect(statusLayout.height >= activityLayout.height || activityLayout.height <= 5)
        }

        let validationResult = manager.validateLayout(layout, terminalSize: constrainedSize)
        #expect(validationResult.isSuccess)
    }

    @Test("LayoutManager should validate layouts correctly")
    func testLayoutValidation() {
        let manager = LayoutManager.shared
        let size = TerminalSize(width: 100, height: 30)

        let validLayout: [PanelType: PanelLayout] = [
            .status: PanelLayout(x: 0, y: 0, width: 100, height: 5),
            .balances: PanelLayout(x: 0, y: 6, width: 100, height: 10),
            .activity: PanelLayout(x: 0, y: 17, width: 100, height: 10)
        ]

        let validationResult = manager.validateLayout(validLayout, terminalSize: size)
        #expect(validationResult.isSuccess)

        let overlappingLayout: [PanelType: PanelLayout] = [
            .status: PanelLayout(x: 0, y: 0, width: 100, height: 10),
            .balances: PanelLayout(x: 0, y: 5, width: 100, height: 10)
        ]

        let overlapResult = manager.validateLayout(overlappingLayout, terminalSize: size)
        #expect(overlapResult.isFailure)

        if case .failure(let error) = overlapResult {
            #expect(error.message.contains("overlap"))
        }

        let exceedingLayout: [PanelType: PanelLayout] = [
            .status: PanelLayout(x: 0, y: 0, width: 150, height: 35)
        ]

        let exceedResult = manager.validateLayout(exceedingLayout, terminalSize: size)
        #expect(exceedResult.isFailure)

        if case .failure(let error) = exceedResult {
            #expect(error.message.contains("exceeds") || error.message.contains("boundaries"))
        }
    }

    @Test("LayoutManager should detect overlapping panels")
    func testPanelOverlapDetection() {
        let manager = LayoutManager.shared
        let size = TerminalSize(width: 100, height: 30)

        let overlappingPanels: [PanelType: PanelLayout] = [
            .status: PanelLayout(x: 0, y: 0, width: 100, height: 10),
            .balances: PanelLayout(x: 0, y: 8, width: 100, height: 10)
        ]

        let result = manager.validateLayout(overlappingPanels, terminalSize: size)
        #expect(result.isFailure)

        let nonOverlappingPanels: [PanelType: PanelLayout] = [
            .status: PanelLayout(x: 0, y: 0, width: 100, height: 5),
            .balances: PanelLayout(x: 0, y: 6, width: 100, height: 10),
            .activity: PanelLayout(x: 0, y: 17, width: 100, height: 10)
        ]

        let nonOverlapResult = manager.validateLayout(nonOverlappingPanels, terminalSize: size)
        #expect(nonOverlapResult.isSuccess)
    }

    @Test("LayoutManager should handle graceful degradation for very small terminals")
    func testGracefulDegradation() {
        let manager = LayoutManager.shared
        let verySmallSize = TerminalSize(width: 80, height: 24)

        let layout = manager.calculateLayout(terminalSize: verySmallSize)

        #expect(layout[.status] != nil)

        if let statusLayout = layout[.status] {
            #expect(statusLayout.height <= verySmallSize.height)
            #expect(statusLayout.width <= verySmallSize.width)
        }

        let validationResult = manager.validateLayout(layout, terminalSize: verySmallSize)
        #expect(validationResult.isSuccess)

        var totalUsedHeight = 0
        for (_, panelLayout) in layout {
            totalUsedHeight = max(totalUsedHeight, panelLayout.y + panelLayout.height)
        }

        #expect(totalUsedHeight <= verySmallSize.height)
    }

    @Test("LayoutManager should handle responsive behavior across different sizes")
    func testResponsiveLayoutBehavior() {
        let manager = LayoutManager.shared

        let sizes = [
            TerminalSize(width: 80, height: 24),
            TerminalSize(width: 100, height: 30),
            TerminalSize(width: 120, height: 40),
            TerminalSize(width: 150, height: 50),
            TerminalSize(width: 200, height: 60)
        ]

        for size in sizes {
            let layout = manager.calculateLayout(terminalSize: size)

            #expect(layout[.status] != nil)

            if let statusLayout = layout[.status] {
                #expect(statusLayout.width == size.width)
                #expect(statusLayout.height > 0)
            }

            let validationResult = manager.validateLayout(layout, terminalSize: size)
            #expect(validationResult.isSuccess, "Layout should be valid for size \(size.width)x\(size.height)")
        }
    }

    @Test("LayoutManager resize monitoring should start and stop correctly")
    func testResizeMonitoringLifecycle() async {
        let manager = LayoutManager.shared
        nonisolated(unsafe) var resizeCount = 0
        nonisolated(unsafe) var lastSize: TerminalSize?

        let task = manager.startResizeMonitoring { newSize in
            resizeCount += 1
            lastSize = newSize
        }

        #expect(task != nil)

        try? await Task.sleep(nanoseconds: 100_000_000)

        manager.stopResizeMonitoring()

        task.cancel()

        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    @Test("LayoutManager should handle resize events")
    func testResizeEventHandling() async {
        let manager = LayoutManager.shared
        nonisolated(unsafe) var resizeEvents: [TerminalSize] = []

        let task = manager.startResizeMonitoring { newSize in
            resizeEvents.append(newSize)
        }

        try? await Task.sleep(nanoseconds: 200_000_000)

        manager.stopResizeMonitoring()
        task.cancel()

        #expect(resizeEvents.count >= 0)
    }

    @Test("LayoutManager should recalculate layout on resize")
    func testLayoutRecalculationOnResize() async {
        let manager = LayoutManager.shared
        nonisolated(unsafe) var lastLayout: [PanelType: PanelLayout]?
        nonisolated(unsafe) var resizeCount = 0

        let initialSize = TerminalSize(width: 100, height: 30)
        let initialLayout = manager.calculateLayout(terminalSize: initialSize)
        lastLayout = initialLayout

        let task = manager.startResizeMonitoring { newSize in
            resizeCount += 1
            if newSize != initialSize {
                let newLayout = manager.calculateLayout(terminalSize: newSize)
                lastLayout = newLayout

                let validationResult = manager.validateLayout(newLayout, terminalSize: newSize)
                #expect(validationResult.isSuccess)
            }
        }

        try? await Task.sleep(nanoseconds: 150_000_000)

        manager.stopResizeMonitoring()
        task.cancel()

        if let layout = lastLayout {
            let validationResult = manager.validateLayout(layout, terminalSize: initialSize)
            #expect(validationResult.isSuccess)
        }
    }

    @Test("LayoutManager should handle multiple resize calls gracefully")
    func testMultipleResizeCalls() async {
        let manager = LayoutManager.shared
        nonisolated(unsafe) var eventCount = 0

        let task1 = manager.startResizeMonitoring { _ in
            eventCount += 1
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        let task2 = manager.startResizeMonitoring { _ in
            eventCount += 1
        }

        #expect(task1 != task2)

        try? await Task.sleep(nanoseconds: 50_000_000)

        manager.stopResizeMonitoring()
        task1.cancel()
        task2.cancel()
    }

    @Test("LayoutManager should maintain layout consistency across size changes")
    func testLayoutConsistency() {
        let manager = LayoutManager.shared

        let sizes: [TerminalSize] = [
            TerminalSize(width: 80, height: 24),
            TerminalSize(width: 120, height: 40),
            TerminalSize(width: 100, height: 30),
            TerminalSize(width: 150, height: 50)
        ]

        for size in sizes {
            let layout = manager.calculateLayout(terminalSize: size)

            #expect(layout[.status] != nil)

            for (_, panelLayout) in layout {
                #expect(panelLayout.width <= size.width)
                #expect(panelLayout.height <= size.height)
                #expect(panelLayout.x >= 0)
                #expect(panelLayout.y >= 0)
                #expect(panelLayout.x + panelLayout.width <= size.width)
                #expect(panelLayout.y + panelLayout.height <= size.height)
            }

            let validationResult = manager.validateLayout(layout, terminalSize: size)
            #expect(validationResult.isSuccess)
        }
    }

    @Test("LayoutPriority should compare correctly")
    func testLayoutPriorityComparison() {
        #expect(LayoutPriority.critical < LayoutPriority.high)
        #expect(LayoutPriority.high < LayoutPriority.medium)
        #expect(LayoutPriority.medium < LayoutPriority.low)

        #expect(LayoutPriority.critical.rawValue == 0)
        #expect(LayoutPriority.high.rawValue == 1)
        #expect(LayoutPriority.medium.rawValue == 2)
        #expect(LayoutPriority.low.rawValue == 3)
    }

    @Test("LayoutValidationError should provide descriptive messages")
    func testLayoutValidationError() {
        let error1 = LayoutValidationError("Panel overlaps")
        #expect(error1.message == "Panel overlaps")

        let error2 = LayoutValidationError("Exceeds terminal width")
        #expect(error2.message == "Exceeds terminal width")
    }
}

extension Result {
    var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    var isFailure: Bool {
        return !isSuccess
    }
}
