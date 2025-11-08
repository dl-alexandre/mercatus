import Foundation

public enum TUICommand: Sendable {
    case pause
    case resume
    case logs
    case start
    case quit
    case help
    case refresh

    public static func from(keyEvent: KeyEvent) -> TUICommand? {
        switch keyEvent {
        case .character(let char):
            switch char.lowercased() {
            case "p":
                return .pause
            case "r":
                return .resume
            case "f":
                return .refresh
            case "l":
                return .logs
            case "s":
                return .start
            case "q":
                return .quit
            case "h", "?":
                return .help
            default:
                return nil
            }
        default:
            return nil
        }
    }
}
