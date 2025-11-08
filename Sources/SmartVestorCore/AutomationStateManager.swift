import Foundation
import Utils

public struct AutomationState: Codable {
    public let isRunning: Bool
    public let mode: AutomationMode
    public let startedAt: Date?
    public let lastExecutionTime: Date?
    public let nextExecutionTime: Date?
    public let pid: Int32?

    public init(
        isRunning: Bool,
        mode: AutomationMode,
        startedAt: Date?,
        lastExecutionTime: Date? = nil,
        nextExecutionTime: Date? = nil,
        pid: Int32? = nil
    ) {
        self.isRunning = isRunning
        self.mode = mode
        self.startedAt = startedAt
        self.lastExecutionTime = lastExecutionTime
        self.nextExecutionTime = nextExecutionTime
        self.pid = pid
    }
}

public class AutomationStateManager {
    private let statePath: String
    private let logger: StructuredLogger
    private weak var tuiServer: TUIServer?

    public init(statePath: String = ".automation-state.json", logger: StructuredLogger = StructuredLogger(), tuiServer: TUIServer? = nil) {
        self.statePath = statePath
        self.logger = logger
        self.tuiServer = tuiServer
    }

    public func save(_ state: AutomationState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(state)

        try data.write(to: URL(fileURLWithPath: statePath))

        logger.debug(component: "AutomationStateManager", event: "State saved", data: [
            "path": statePath,
            "mode": state.mode.rawValue,
            "is_running": String(state.isRunning)
        ])

        publishStateChange(state: state)
    }

    public func load() throws -> AutomationState? {
        guard FileManager.default.fileExists(atPath: statePath) else {
            return nil
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(AutomationState.self, from: data)

        logger.debug(component: "AutomationStateManager", event: "State loaded", data: [
            "path": statePath,
            "mode": state.mode.rawValue,
            "is_running": String(state.isRunning)
        ])

        return state
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: statePath) else {
            return
        }

        try FileManager.default.removeItem(atPath: statePath)

        logger.debug(component: "AutomationStateManager", event: "State cleared", data: [
            "path": statePath
        ])

        let cleared = AutomationState(
            isRunning: false,
            mode: .continuous,
            startedAt: nil,
            lastExecutionTime: Date(),
            nextExecutionTime: nil,
            pid: nil
        )
        publishStateChange(state: cleared)
    }

    private func publishStateChange(state: AutomationState) {
        guard let server = tuiServer else { return }
        let data = TUIData(
            recentTrades: [],
            balances: [],
            circuitBreakerOpen: false,
            lastExecutionTime: state.lastExecutionTime,
            nextExecutionTime: state.nextExecutionTime,
            totalPortfolioValue: 0,
            errorCount: 0
        )
        server.publish(type: .stateChange, state: state, data: data)
    }
}
