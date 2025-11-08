import Foundation

public struct BorderCharacters: Sendable {
    public let topLeft: String
    public let topRight: String
    public let bottomLeft: String
    public let bottomRight: String
    public let horizontal: String
    public let vertical: String
    public let topTee: String
    public let bottomTee: String
    public let leftTee: String
    public let rightTee: String
    public let cross: String

    public init(
        topLeft: String,
        topRight: String,
        bottomLeft: String,
        bottomRight: String,
        horizontal: String,
        vertical: String,
        topTee: String,
        bottomTee: String,
        leftTee: String,
        rightTee: String,
        cross: String
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
        self.horizontal = horizontal
        self.vertical = vertical
        self.topTee = topTee
        self.bottomTee = bottomTee
        self.leftTee = leftTee
        self.rightTee = rightTee
        self.cross = cross
    }
}

public enum BorderStyle: Sendable {
    case unicode
    case ascii
    case none

    public func characters(unicodeSupported: Bool) -> BorderCharacters {
        switch self {
        case .unicode where unicodeSupported:
            return BorderCharacters(
                topLeft: "┌",
                topRight: "┐",
                bottomLeft: "└",
                bottomRight: "┘",
                horizontal: "─",
                vertical: "│",
                topTee: "┬",
                bottomTee: "┴",
                leftTee: "├",
                rightTee: "┤",
                cross: "┼"
            )
        case .ascii, .unicode:
            return BorderCharacters(
                topLeft: "+",
                topRight: "+",
                bottomLeft: "+",
                bottomRight: "+",
                horizontal: "-",
                vertical: "|",
                topTee: "+",
                bottomTee: "+",
                leftTee: "+",
                rightTee: "+",
                cross: "+"
            )
        case .none:
            return BorderCharacters(
                topLeft: " ",
                topRight: " ",
                bottomLeft: " ",
                bottomRight: " ",
                horizontal: " ",
                vertical: " ",
                topTee: " ",
                bottomTee: " ",
                leftTee: " ",
                rightTee: " ",
                cross: " "
            )
        }
    }
}
