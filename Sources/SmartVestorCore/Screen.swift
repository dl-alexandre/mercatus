import Foundation

public struct CursorPosition: Equatable, Sendable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

public struct Screen: Equatable, Sendable {
    public var lines: [String]
    public var cursor: CursorPosition?

    public init(lines: [String] = [], cursor: CursorPosition? = nil) {
        self.lines = lines
        self.cursor = cursor
    }

    public func renderToANSI() -> String {
        var output = ""
        for (index, line) in lines.enumerated() {
            output += line
            if index < lines.count - 1 {
                output += "\n"
            }
        }
        if let cursor = cursor {
            output += "\u{001B}[\(cursor.row + 1);\(cursor.col + 1)H"
        }
        return output
    }
}
