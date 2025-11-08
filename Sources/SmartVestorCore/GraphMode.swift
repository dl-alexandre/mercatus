import Foundation

public enum GraphMode: String, Codable, Sendable {
    case braille
    case block
    case tty
    case ascii
    case `default`

    public var symbolSet: GraphSymbolSet {
        switch self {
        case .braille:
            return GraphSymbolSet.braille
        case .block:
            return GraphSymbolSet.block
        case .tty:
            return GraphSymbolSet.tty
        case .ascii:
            return GraphSymbolSet.ascii
        case .default:
            return GraphSymbolSet.default
        }
    }

    public var fallbackOrder: [GraphMode] {
        switch self {
        case .braille:
            return [.braille, .block, .tty, .ascii]
        case .block:
            return [.block, .tty, .ascii]
        case .tty:
            return [.tty, .ascii]
        case .ascii:
            return [.ascii]
        case .default:
            return [.default, .block, .tty, .ascii]
        }
    }
}

public struct GraphSymbolSet: Sendable {
    public let low: Character
    public let mid: Character
    public let high: Character
    public let lowRes: Character
    public let highRes: Character

    public var characters: [Character] {
        return [low, mid, high]
    }

    public static let braille = GraphSymbolSet(
        low: "\u{28F0}",
        mid: "\u{28F4}",
        high: "\u{28FF}",
        lowRes: "\u{28F0}",
        highRes: "\u{28FF}"
    )

    public static let block = GraphSymbolSet(
        low: "▁",
        mid: "▅",
        high: "█",
        lowRes: "▁",
        highRes: "█"
    )

    public static let tty = GraphSymbolSet(
        low: "_",
        mid: "-",
        high: "#",
        lowRes: "_",
        highRes: "#"
    )

    public static let ascii = GraphSymbolSet(
        low: ".",
        mid: "-",
        high: "=",
        lowRes: ".",
        highRes: "="
    )

    public static let `default` = GraphSymbolSet(
        low: "▂",
        mid: "▅",
        high: "▇",
        lowRes: "▂",
        highRes: "▇"
    )
}
