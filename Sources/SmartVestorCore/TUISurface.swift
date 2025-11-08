import Foundation

public struct Surface: Sendable {
    public let lines: [Line]
    public let bounds: Rect
    public let lastVisibleRect: Rect?
    public let env: TerminalEnv

    public init(lines: [Line], bounds: Rect, lastVisibleRect: Rect? = nil, env: TerminalEnv) {
        self.lines = lines
        self.bounds = bounds
        self.lastVisibleRect = lastVisibleRect
        self.env = env
    }
}
