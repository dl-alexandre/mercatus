import Foundation
#if os(macOS)
import Darwin
#endif

public enum LayoutPriority: Int, Comparable, Sendable {
    case critical = 0
    case high = 1
    case medium = 2
    case low = 3

    public static func < (lhs: LayoutPriority, rhs: LayoutPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public struct LayoutValidationError: Error, Sendable {
    public let message: String
    public init(_ message: String) {
        self.message = message
    }
}

public struct PanelLayout: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = max(0, x)
        self.y = max(0, y)
        self.width = max(1, width)
        self.height = max(1, height)
    }

    public var isValid: Bool {
        return width > 0 && height > 0 && x >= 0 && y >= 0
    }
}

public enum PanelType: String, Sendable, Codable {
    case status
    case balances
    case balance
    case activity
    case price
    case swap
    case logs
    case custom
}

enum PanelLayoutNode: Sendable {
    case panel(PanelType)
    case vStack(spacing: Int, children: [PanelLayoutNode])
    case hStack(spacing: Int, children: [PanelLayoutNode])

    var isPanel: Bool {
        if case .panel = self {
            return true
        }
        return false
    }

    var panelType: PanelType? {
        if case .panel(let type) = self {
            return type
        }
        return nil
    }
}

public protocol LayoutManagerProtocol: Sendable {
    func detectTerminalSize() -> TerminalSize
    func calculateLayout(terminalSize: TerminalSize) -> [PanelType: PanelLayout]
    func calculateLayout(terminalSize: TerminalSize, priorities: [PanelType: LayoutPriority], visiblePanels: Set<PanelType>?) -> [PanelType: PanelLayout]
    func calculateLayout(terminalSize: TerminalSize, visiblePanels: Set<PanelType>) -> [PanelType: PanelLayout]
    func isMinimumSizeMet(terminalSize: TerminalSize) -> Bool
    func validateLayout(_ layout: [PanelType: PanelLayout], terminalSize: TerminalSize) -> Result<Void, LayoutValidationError>
    func startResizeMonitoring(onResize: @escaping @Sendable (TerminalSize) -> Void) -> Task<Void, Never>
    func stopResizeMonitoring()
}

public final class LayoutManager: LayoutManagerProtocol, @unchecked Sendable {
    public static let shared = LayoutManager()

    private let minimumWidth = 80
    private let minimumHeight = 24
    private let terminalOps: TerminalOperations
    private var resizeMonitoringTaskLock = os_unfair_lock()
    private var _resizeMonitoringTask: Task<Void, Never>?
    private var resizeMonitoringTask: Task<Void, Never>? {
        get {
            os_unfair_lock_lock(&resizeMonitoringTaskLock)
            defer { os_unfair_lock_unlock(&resizeMonitoringTaskLock) }
            return _resizeMonitoringTask
        }
        set {
            os_unfair_lock_lock(&resizeMonitoringTaskLock)
            defer { os_unfair_lock_unlock(&resizeMonitoringTaskLock) }
            _resizeMonitoringTask = newValue
        }
    }
    private var currentSizeLock = os_unfair_lock()
    private var _currentSize: TerminalSize?
    private var currentSize: TerminalSize? {
        get {
            os_unfair_lock_lock(&currentSizeLock)
            defer { os_unfair_lock_unlock(&currentSizeLock) }
            return _currentSize
        }
        set {
            os_unfair_lock_lock(&currentSizeLock)
            defer { os_unfair_lock_unlock(&currentSizeLock) }
            _currentSize = newValue
        }
    }

    public init(terminalOps: TerminalOperations? = nil) {
        self.terminalOps = terminalOps ?? RealTerminalOperations()
        self._currentSize = detectTerminalSize()
    }

    public func detectTerminalSize() -> TerminalSize {
        return terminalOps.size
    }

    public func isMinimumSizeMet(terminalSize: TerminalSize) -> Bool {
        return terminalSize.width >= minimumWidth && terminalSize.height >= minimumHeight
    }

    public func calculateLayout(terminalSize: TerminalSize) -> [PanelType: PanelLayout] {
        let defaultPriorities: [PanelType: LayoutPriority] = [
            .status: .critical,
            .balances: .high,
            .balance: .high,
            .activity: .medium,
            .price: .medium,
            .swap: .low,
            .logs: .low
        ]
        return calculateLayout(terminalSize: terminalSize, priorities: defaultPriorities, visiblePanels: nil)
    }

    public func calculateLayout(terminalSize: TerminalSize, visiblePanels: Set<PanelType>) -> [PanelType: PanelLayout] {
        var priorities: [PanelType: LayoutPriority] = [:]

        for panelType in visiblePanels {
            switch panelType {
            case .status:
                priorities[.status] = .critical
            case .balances, .balance:
                priorities[.balances] = .high
                priorities[.balance] = .high
            case .activity:
                priorities[.activity] = .medium
            case .price:
                priorities[.price] = .medium
            case .swap:
                priorities[.swap] = .low
            case .logs:
                priorities[.logs] = .low
            default:
                priorities[panelType] = .low
            }
        }

        return calculateLayout(terminalSize: terminalSize, priorities: priorities, visiblePanels: visiblePanels)
    }

    public func calculateLayout(terminalSize: TerminalSize, priorities: [PanelType: LayoutPriority], visiblePanels: Set<PanelType>? = nil) -> [PanelType: PanelLayout] {
        let size = terminalSize

        if !isMinimumSizeMet(terminalSize: size) {
            return calculatePriorityBasedLayout(size: size, priorities: priorities)
        }

        let isVisible = { (panelType: PanelType) -> Bool in
            guard let visiblePanels = visiblePanels else { return true }
            if panelType == .balance || panelType == .balances {
                return visiblePanels.contains(.balance) || visiblePanels.contains(.balances)
            }
            return visiblePanels.contains(panelType)
        }

        let layoutTree = buildLayoutTree(
            priorities: priorities,
            isVisible: isVisible
        )

        let headerHeight = 3
        let footerHeight = 1
        let availableHeight = size.height - headerHeight - footerHeight

        let panelDimensions = computePanelDimensions(
            priorities: priorities,
            isVisible: isVisible,
            availableHeight: availableHeight,
            terminalHeight: size.height
        )

        var layouts: [PanelType: PanelLayout] = [:]
        computeFrames(
            node: layoutTree,
            originX: 0,
            originY: headerHeight,
            availableWidth: size.width,
            availableHeight: availableHeight,
            panelDimensions: panelDimensions,
            layouts: &layouts
        )

        #if DEBUG
        if TUIFeatureFlags.isDebugOverlayEnabled {
            let msg = "[Layout] Terminal size: \(size.width)x\(size.height), computed layouts: \(layouts.count)\n"
            #if os(macOS) || os(Linux)
            msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
            #else
            print(msg, to: &FileHandle.standardError)
            #endif
            for (type, layout) in layouts.sorted(by: { $0.value.y < $1.value.y }) {
                let layoutMsg = "[Layout] \(type): x=\(layout.x) y=\(layout.y) w=\(layout.width) h=\(layout.height)\n"
                #if os(macOS) || os(Linux)
                layoutMsg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
                #else
                print(layoutMsg, to: &FileHandle.standardError)
                #endif
            }
        }
        #endif

        return layouts
    }

    private func buildLayoutTree(
        priorities: [PanelType: LayoutPriority],
        isVisible: (PanelType) -> Bool
    ) -> PanelLayoutNode {
        let verticalGap = 1
        let horizontalGap = 2

        var verticalChildren: [PanelLayoutNode] = []

        if isVisible(.status) {
            verticalChildren.append(.panel(.status))
        }

        if isVisible(.balances) || isVisible(.balance) {
            verticalChildren.append(.panel(.balances))
        }

        let horizontalPanels: [PanelType] = [
            .activity,
            .price,
            .swap
        ].filter { isVisible($0) }

        if !horizontalPanels.isEmpty {
            let horizontalChildren = horizontalPanels.map { PanelLayoutNode.panel($0) }
            verticalChildren.append(.hStack(spacing: horizontalGap, children: horizontalChildren))
        }

        if isVisible(.logs) {
            verticalChildren.append(.panel(.logs))
        }

        return .vStack(spacing: verticalGap, children: verticalChildren)
    }

    private func computePanelDimensions(
        priorities: [PanelType: LayoutPriority],
        isVisible: (PanelType) -> Bool,
        availableHeight: Int,
        terminalHeight: Int
    ) -> [PanelType: (width: Int, height: Int)] {
        var dimensions: [PanelType: (width: Int, height: Int)] = [:]

        let panelOrder: [PanelType] = [.status, .balances, .balance, .activity, .price, .swap, .logs]
        let sortedPanels = priorities.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            let lhsIndex = panelOrder.firstIndex(of: lhs.key) ?? Int.max
            let rhsIndex = panelOrder.firstIndex(of: rhs.key) ?? Int.max
            return lhsIndex < rhsIndex
        }.filter { isVisible($0.key) }

        for (panelType, priority) in sortedPanels {
            let height = calculatePanelHeight(
                panelType: panelType,
                priority: priority,
                availableHeight: availableHeight,
                terminalHeight: terminalHeight
            )
            dimensions[panelType] = (width: 0, height: height)

            if panelType == .balance || panelType == .balances {
                dimensions[.balance] = dimensions[panelType]
                dimensions[.balances] = dimensions[panelType]
            }
        }

        return dimensions
    }

    private func computeNodeHeight(
        node: PanelLayoutNode,
        panelDimensions: [PanelType: (width: Int, height: Int)],
        spacing: Int = 0
    ) -> Int {
        switch node {
        case .panel(let panelType):
            return panelDimensions[panelType]?.height ?? 8

        case .vStack(let sp, let children):
            let childrenHeights = children.map { computeNodeHeight(node: $0, panelDimensions: panelDimensions) }
            let totalChildrenHeight = childrenHeights.reduce(0, +)
            let totalSpacing = sp * max(0, children.count - 1)
            return totalChildrenHeight + totalSpacing

        case .hStack(_, let children):
            return children.compactMap { child -> Int? in
                switch child {
                case .panel(let pt):
                    return panelDimensions[pt]?.height
                default:
                    return nil
                }
            }.max() ?? 8
        }
    }

    private func computeFrames(
        node: PanelLayoutNode,
        originX: Int,
        originY: Int,
        availableWidth: Int,
        availableHeight: Int,
        panelDimensions: [PanelType: (width: Int, height: Int)],
        layouts: inout [PanelType: PanelLayout]
    ) {
        switch node {
        case .panel(let panelType):
            let height = panelDimensions[panelType]?.height ?? 8
            let finalHeight = min(height, availableHeight)

            if finalHeight > 0 {
                let layout = PanelLayout(
                    x: originX,
                    y: originY,
                    width: availableWidth,
                    height: finalHeight
                )

                #if DEBUG
                if TUIFeatureFlags.isDebugOverlayEnabled {
                    let msg = "[Layout] Panel \(panelType) x=\(originX) y=\(originY) width=\(availableWidth) height=\(finalHeight)\n"
                    #if os(macOS) || os(Linux)
                    msg.withCString { _ = write(STDERR_FILENO, $0, strlen($0)) }
                    #else
                    print(msg, to: &FileHandle.standardError)
                    #endif
                }
                #endif

                if panelType == .balance || panelType == .balances {
                    layouts[.balance] = layout
                    layouts[.balances] = layout
                } else {
                    layouts[panelType] = layout
                }
            }

        case .vStack(let spacing, let children):
            var currentY = originY
            let remainingHeight = availableHeight

            for child in children {
                let childHeight = computeNodeHeight(node: child, panelDimensions: panelDimensions)
                let remainingSpace = remainingHeight - (currentY - originY)
                let finalChildHeight = min(childHeight, remainingSpace)

                if finalChildHeight > 0 && currentY + finalChildHeight <= originY + remainingHeight {
                    computeFrames(
                        node: child,
                        originX: originX,
                        originY: currentY,
                        availableWidth: availableWidth,
                        availableHeight: finalChildHeight,
                        panelDimensions: panelDimensions,
                        layouts: &layouts
                    )
                    currentY += finalChildHeight + spacing
                } else {
                    break
                }
            }

        case .hStack(let spacing, let children):
            let panelCount = children.count
            guard panelCount > 0 else { return }

            let totalGaps = (panelCount - 1) * spacing
            let totalWidth = availableWidth - totalGaps
            let basePanelWidth = totalWidth / panelCount
            let remainder = totalWidth % panelCount

            var widths: [Int] = []
            for i in 0..<panelCount {
                widths.append(basePanelWidth + (i < remainder ? 1 : 0))
            }

            let childHeight = children.compactMap { child -> Int? in
                switch child {
                case .panel(let pt):
                    return panelDimensions[pt]?.height
                default:
                    return nil
                }
            }.max() ?? 8
            let finalChildHeight = min(childHeight, availableHeight)

            var currentX = originX
            for (index, child) in children.enumerated() {
                let actualWidth = widths[index]

                if actualWidth >= 20 && finalChildHeight >= 5 {
                    computeFrames(
                        node: child,
                        originX: currentX,
                        originY: originY,
                        availableWidth: actualWidth,
                        availableHeight: finalChildHeight,
                        panelDimensions: panelDimensions,
                        layouts: &layouts
                    )

                    if index < children.count - 1 {
                        currentX += actualWidth + spacing
                    }
                }
            }
        }
    }

    private func calculatePanelHeight(panelType: PanelType, priority: LayoutPriority, availableHeight: Int, terminalHeight: Int) -> Int {
        let minHeight: Int
        switch panelType {
        case .status:
            minHeight = 6
        case .balances, .balance:
            minHeight = 8
        case .activity:
            minHeight = 5
        case .price:
            minHeight = 6
        case .swap:
            minHeight = 8
        case .logs:
            minHeight = 6
        default:
            minHeight = 3
        }

        switch priority {
        case .critical:
            switch panelType {
            case .status:
                return min(8, max(minHeight, availableHeight / 4))
            default:
                return min(6, max(minHeight, availableHeight / 5))
            }
        case .high:
            switch panelType {
            case .balances, .balance:
                return min(max(minHeight, availableHeight * 2 / 5), availableHeight)
            default:
                return min(max(minHeight, availableHeight / 5), availableHeight)
            }
        case .medium:
            return min(max(minHeight, availableHeight / 6), availableHeight)
        case .low:
            return min(max(minHeight, availableHeight / 8), availableHeight)
        }
    }

    private func calculatePriorityBasedLayout(size: TerminalSize, priorities: [PanelType: LayoutPriority]) -> [PanelType: PanelLayout] {
        let headerHeight = 2
        let footerHeight = 1
        let _ = size.height - headerHeight - footerHeight  // Available height (for future use)

        var layouts: [PanelType: PanelLayout] = [:]
        var currentY = headerHeight
        let verticalGap = 0

        let sortedPanels = priorities.sorted { $0.value < $1.value }

        for (panelType, priority) in sortedPanels.prefix(3) {
            let remainingHeight = size.height - currentY - footerHeight
            if remainingHeight <= 3 {
                break
            }

            let height: Int
            switch priority {
            case .critical:
                height = min(6, max(3, remainingHeight / 2))
            case .high:
                height = min(8, max(3, remainingHeight * 2 / 3))
            case .medium, .low:
                height = min(max(3, remainingHeight), remainingHeight)
            }

            if height > 0 && currentY + height <= size.height {
                let layout = PanelLayout(x: 0, y: currentY, width: size.width, height: height)
                layouts[panelType] = layout
                currentY += height + verticalGap
                if currentY >= size.height - footerHeight {
                    break
                }
            } else {
                break
            }
        }

        if layouts[.status] == nil {
            let remainingHeight = size.height - headerHeight - footerHeight
            let statusHeight = min(6, max(3, remainingHeight / 3))
            if statusHeight > 0 && headerHeight + statusHeight <= size.height {
                layouts[.status] = PanelLayout(x: 0, y: headerHeight, width: size.width, height: statusHeight)
            }
        }

        return layouts
    }

    public func validateLayout(_ layout: [PanelType: PanelLayout], terminalSize: TerminalSize) -> Result<Void, LayoutValidationError> {
        for (panelType, panelLayout) in layout {
            if !panelLayout.isValid {
                return .failure(LayoutValidationError("Invalid panel layout for \(panelType): \(panelLayout)"))
            }

            if panelLayout.x < 0 || panelLayout.y < 0 {
                return .failure(LayoutValidationError("Panel \(panelType) has negative position"))
            }

            if panelLayout.x + panelLayout.width > terminalSize.width {
                return .failure(LayoutValidationError("Panel \(panelType) exceeds terminal width"))
            }

            if panelLayout.y + panelLayout.height > terminalSize.height {
                return .failure(LayoutValidationError("Panel \(panelType) exceeds terminal height"))
            }

            for (otherType, otherLayout) in layout {
                if panelType != otherType {
                    if panelsOverlap(panelLayout, otherLayout) {
                        return .failure(LayoutValidationError("Panels \(panelType) and \(otherType) overlap"))
                    }
                }
            }
        }

        return .success(())
    }

    private func panelsOverlap(_ a: PanelLayout, _ b: PanelLayout) -> Bool {
        let aRight = a.x + a.width
        let aBottom = a.y + a.height
        let bRight = b.x + b.width
        let bBottom = b.y + b.height

        return !(aRight <= b.x || a.x >= bRight || aBottom <= b.y || a.y >= bBottom)
    }

    public func startResizeMonitoring(onResize: @escaping @Sendable (TerminalSize) -> Void) -> Task<Void, Never> {
        stopResizeMonitoring()

        let task = Task { [weak self] in
            guard let self = self else { return }

            var lastResizeTime: Date = Date()
            let resizeDebounceInterval: TimeInterval = 0.5

            #if os(macOS)
            signal(SIGWINCH, SIG_IGN)
            let signalQueue = DispatchQueue(label: "com.smartvestor.layout.signal")
            let source = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: signalQueue)

            var lastSize = self.currentSize ?? TerminalSize.minimum

            source.setEventHandler { [weak self] in
                guard let self = self else { return }
                let now = Date()
                guard now.timeIntervalSince(lastResizeTime) >= resizeDebounceInterval else { return }
                lastResizeTime = now

                let newSize = self.detectTerminalSize()
                if newSize != lastSize {
                    lastSize = newSize
                    self.currentSize = newSize
                    onResize(newSize)
                }
            }

            source.resume()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let newSize = self.detectTerminalSize()
                if newSize != lastSize {
                    let now = Date()
                    guard now.timeIntervalSince(lastResizeTime) >= resizeDebounceInterval else { continue }
                    lastResizeTime = now
                    lastSize = newSize
                    self.currentSize = newSize
                    onResize(newSize)
                }
            }

            source.cancel()
            #else
            while !Task.isCancelled {
                let newSize = self.detectTerminalSize()
                if newSize != self.currentSize {
                    let now = Date()
                    guard now.timeIntervalSince(lastResizeTime) >= resizeDebounceInterval else {
                        continue
                    }
                    lastResizeTime = now
                    self.currentSize = newSize
                    onResize(newSize)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            #endif
        }

        resizeMonitoringTask = task
        return task
    }

    public func stopResizeMonitoring() {
        let task = resizeMonitoringTask
        task?.cancel()
        resizeMonitoringTask = nil
    }
}
