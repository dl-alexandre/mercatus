import Foundation

public protocol TUIScene: Sendable {
    func makeScreen(size: TerminalSize, now: Date, rng: inout any RandomNumberGenerator) -> Screen
}
