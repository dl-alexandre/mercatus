import Foundation

public protocol TUIRendererProtocol: Sendable {
    func renderInitialState() async
    func renderUpdate(_ update: TUIUpdate) async
    nonisolated func renderUpdateWithPrices(_ update: TUIUpdate, prices: [String: Double]) async
    func clearScreen() async
}

public protocol ColorManagerProtocol: Sendable {
    var supportsColor: Bool { get }
    var supportsUnicode: Bool { get }

    func bold(_ text: String) -> String
    func dim(_ text: String) -> String
    func reset() -> String
    func green(_ text: String) -> String
    func red(_ text: String) -> String
    func yellow(_ text: String) -> String
    func blue(_ text: String) -> String
}
