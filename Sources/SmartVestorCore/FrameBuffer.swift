import Foundation

public struct FrameCell: Sendable {
    public var content: String
    public var ansiCodes: String

    public init(content: String = " ", ansiCodes: String = "") {
        self.content = content
        self.ansiCodes = ansiCodes
    }

    public var isEmpty: Bool {
        return content.trimmingCharacters(in: .whitespaces).isEmpty && ansiCodes.isEmpty
    }
}

public final class FrameBuffer: @unchecked Sendable {
    private var cells: [[FrameCell]]
    private let width: Int
    private let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.cells = Array(repeating: Array(repeating: FrameCell(), count: width), count: height)
    }

    public func clear() {
        for y in 0..<height {
            for x in 0..<width {
                cells[y][x] = FrameCell()
            }
        }
    }

    public func write(_ content: String, at x: Int, y: Int, ansiCodes: String = "") {
        guard y >= 0 && y < height && x >= 0 && x < width else { return }

        let cell = FrameCell(content: content, ansiCodes: ansiCodes)
        cells[y][x] = cell
    }

    public func writeLine(_ line: String, at y: Int, ansiCodes: String = "") {
        guard y >= 0 && y < height else { return }

        var x = 0
        for char in line {
            if x >= width { break }
            let cell = FrameCell(content: String(char), ansiCodes: x == 0 ? ansiCodes : "")
            cells[y][x] = cell
            x += 1
        }
    }

    public func render() -> [String] {
        var lines: [String] = []

        for row in cells {
            var line = ""
            var currentAnsi = ""

            for cell in row {
                if cell.ansiCodes != currentAnsi {
                    line += cell.ansiCodes
                    currentAnsi = cell.ansiCodes
                }
                line += cell.content
            }

            if !currentAnsi.isEmpty {
                line += "\u{001B}[0m"
            }

            lines.append(line)
        }

        return lines
    }

    public func getCell(at x: Int, y: Int) -> FrameCell? {
        guard y >= 0 && y < height && x >= 0 && x < width else { return nil }
        return cells[y][x]
    }

    public func resize(newWidth: Int, newHeight: Int) {
        let oldWidth = width
        let oldHeight = height

        var newCells = Array(repeating: Array(repeating: FrameCell(), count: newWidth), count: newHeight)

        let copyWidth = min(oldWidth, newWidth)
        let copyHeight = min(oldHeight, newHeight)

        for y in 0..<copyHeight {
            for x in 0..<copyWidth {
                newCells[y][x] = cells[y][x]
            }
        }

        self.cells = newCells
    }
}
