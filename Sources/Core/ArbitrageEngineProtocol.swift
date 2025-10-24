import Foundation

public protocol ArbitrageEngine {
    var isRunning: Bool { get async }
    func start() async throws
    func stop() async
}
