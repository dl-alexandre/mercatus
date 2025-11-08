import Foundation

public actor KeyDebouncer {
    private var lastKeyPressTimes: [KeyEvent: Date]
    private let debounceInterval: TimeInterval

    public init(debounceInterval: TimeInterval = 0.1) {
        self.lastKeyPressTimes = [:]
        self.debounceInterval = debounceInterval
    }

    public func shouldProcess(_ keyEvent: KeyEvent) -> Bool {
        let now = Date()

        if let lastTime = lastKeyPressTimes[keyEvent] {
            let timeSinceLastPress = now.timeIntervalSince(lastTime)
            if timeSinceLastPress < debounceInterval {
                return false
            }
        }

        lastKeyPressTimes[keyEvent] = now
        return true
    }

    public func reset() {
        lastKeyPressTimes.removeAll()
    }
}

extension KeyEvent: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .character(let char):
            hasher.combine("char")
            hasher.combine(char)
        case .arrowUp:
            hasher.combine("arrowUp")
        case .arrowDown:
            hasher.combine("arrowDown")
        case .arrowLeft:
            hasher.combine("arrowLeft")
        case .arrowRight:
            hasher.combine("arrowRight")
        case .enter:
            hasher.combine("enter")
        case .backspace:
            hasher.combine("backspace")
        case .escape:
            hasher.combine("escape")
        case .tab:
            hasher.combine("tab")
        case .control(let char):
            hasher.combine("control")
            hasher.combine(char)
        case .unknown(let bytes):
            hasher.combine("unknown")
            hasher.combine(bytes.count)
            if !bytes.isEmpty {
                hasher.combine(bytes[0])
            }
        }
    }
}
