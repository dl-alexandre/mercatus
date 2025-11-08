import Foundation
import Utils

public enum PanelFocus: String, Sendable, CaseIterable {
    case status
    case balance
    case activity

    public func navigate(direction: NavigationDirection) -> PanelFocus? {
        switch direction {
        case .up, .down:
            switch self {
            case .status:
                return direction == .down ? .balance : nil
            case .balance:
                return direction == .up ? .status : (direction == .down ? .activity : nil)
            case .activity:
                return direction == .up ? .balance : nil
            }
        case .left, .right:
            return nil
        }
    }

    public var panelType: PanelType {
        switch self {
        case .status:
            return .status
        case .balance:
            return .balance
        case .activity:
            return .activity
        }
    }

    public var identifier: String {
        return self.rawValue
    }
}

public enum NavigationDirection: Sendable {
    case up
    case down
    case left
    case right
}

public final class NavigationManager: @unchecked Sendable {
    @MainActor private var currentFocus: PanelFocus
    private let logger: StructuredLogger

    public init(initialFocus: PanelFocus = .status, logger: StructuredLogger = StructuredLogger()) {
        self.currentFocus = initialFocus
        self.logger = logger
    }

    @MainActor
    public func getCurrentFocus() -> PanelFocus {
        return currentFocus
    }

    @MainActor
    public func setFocus(_ focus: PanelFocus) {
        let previousFocus = currentFocus
        currentFocus = focus

        if previousFocus != focus {
            logger.debug(component: "NavigationManager", event: "Focus changed", data: [
                "from": previousFocus.rawValue,
                "to": focus.rawValue
            ])
        }
    }

    @MainActor
    public func navigate(_ direction: NavigationDirection) -> PanelFocus? {
        guard let newFocus = currentFocus.navigate(direction: direction) else {
            return nil
        }

        setFocus(newFocus)
        return newFocus
    }

    @MainActor
    public func handleNavigation(_ event: KeyEvent) -> Bool {
        let direction: NavigationDirection?

        switch event {
        case .arrowUp:
            direction = .up
        case .arrowDown:
            direction = .down
        case .arrowLeft:
            direction = .left
        case .arrowRight:
            direction = .right
        default:
            return false
        }

        guard let dir = direction else {
            return false
        }

        let navigated = navigate(dir)
        return navigated != nil
    }

    @MainActor
    public func isFocused(_ panel: PanelFocus) -> Bool {
        return currentFocus == panel
    }
}
