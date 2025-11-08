import Testing
import Foundation
@testable import SmartVestor
import Utils

@Suite("Command Bar Tests")
struct CommandBarTests {

    @Test("CommandBarRenderer should format commands with hotkeys in brackets")
    func testCommandBarFormatting() {
        let colorManager = ColorManager(monochrome: true)
        let renderer = CommandBarRenderer(colorManager: colorManager, separator: "  ")

        let items = [
            CommandBarItem(label: "ause", hotkey: "P"),
            CommandBarItem(label: "esume", hotkey: "R"),
            CommandBarItem(label: "ogs", hotkey: "L"),
            CommandBarItem(label: "uit", hotkey: "Q")
        ]

        let result = renderer.render(items: items)
        #expect(result.contains("[P]"))
        #expect(result.contains("[R]"))
        #expect(result.contains("[L]"))
        #expect(result.contains("[Q]"))
        #expect(result.contains("ause"))
        #expect(result.contains("esume"))
        #expect(result.contains("ogs"))
        #expect(result.contains("uit"))
    }

    @Test("CommandBarRenderer should render default commands")
    func testDefaultCommands() {
        let colorManager = ColorManager(monochrome: true)
        let renderer = CommandBarRenderer(colorManager: colorManager)

        let result = renderer.renderDefaultCommands()

        #expect(result.contains("[P]"))
        #expect(result.contains("[R]"))
        #expect(result.contains("[L]"))
        #expect(result.contains("[Q]"))
    }

    @Test("CommandBarRenderer should use custom separator")
    func testCustomSeparator() {
        let colorManager = ColorManager(monochrome: true)
        let renderer = CommandBarRenderer(colorManager: colorManager, separator: " | ")

        let items = [
            CommandBarItem(label: "ause", hotkey: "P"),
            CommandBarItem(label: "esume", hotkey: "R")
        ]

        let result = renderer.render(items: items)
        #expect(result.contains(" | "))
    }

    @Test("CommandBarRenderer should handle empty items array")
    func testEmptyItems() {
        let colorManager = ColorManager(monochrome: true)
        let renderer = CommandBarRenderer(colorManager: colorManager)

        let result = renderer.render(items: [])
        #expect(result.isEmpty)
    }

    @Test("TUICommand should map keyboard events to commands")
    func testTUICommandFromKeyEvent() {
        let pauseEvent = KeyEvent.character("p")
        #expect(TUICommand.from(keyEvent: pauseEvent) == .pause)

        let pauseEventUpper = KeyEvent.character("P")
        #expect(TUICommand.from(keyEvent: pauseEventUpper) == .pause)

        let resumeEvent = KeyEvent.character("r")
        #expect(TUICommand.from(keyEvent: resumeEvent) == .resume)

        let logsEvent = KeyEvent.character("l")
        #expect(TUICommand.from(keyEvent: logsEvent) == .logs)

        let quitEvent = KeyEvent.character("q")
        #expect(TUICommand.from(keyEvent: quitEvent) == .quit)

        let invalidEvent = KeyEvent.character("x")
        #expect(TUICommand.from(keyEvent: invalidEvent) == nil)

        let arrowEvent = KeyEvent.arrowUp
        #expect(TUICommand.from(keyEvent: arrowEvent) == nil)
    }

    @Test("CommandProcessor should handle pause command when running")
    func testPauseCommandWhenRunning() async throws {
        let tmpDir = NSTemporaryDirectory()
        let statePath = (tmpDir as NSString).appendingPathComponent("test-state.json")
        try? FileManager.default.removeItem(atPath: statePath)

        let logger = StructuredLogger()
        let stateManager = AutomationStateManager(statePath: statePath, logger: logger)
        let processor = CommandProcessor(stateManager: stateManager, logger: logger)

        let runningState = AutomationState(
            isRunning: true,
            mode: .continuous,
            startedAt: Date(),
            lastExecutionTime: nil,
            nextExecutionTime: nil,
            pid: 1234
        )

        try stateManager.save(runningState)

        let result = try await processor.process(.pause, currentState: runningState)

        #expect(result.success == true)
        #expect(result.shouldExit == false)

        let updatedState = try stateManager.load()
        #expect(updatedState != nil)
        #expect(updatedState?.isRunning == false)

        try? FileManager.default.removeItem(atPath: statePath)
    }

    @Test("CommandProcessor should handle resume command when paused")
    func testResumeCommandWhenPaused() async throws {
        let tmpDir = NSTemporaryDirectory()
        let statePath = (tmpDir as NSString).appendingPathComponent("test-resume-state.json")
        try? FileManager.default.removeItem(atPath: statePath)

        let logger = StructuredLogger()
        let stateManager = AutomationStateManager(statePath: statePath, logger: logger)
        let processor = CommandProcessor(stateManager: stateManager, logger: logger)

        let pausedState = AutomationState(
            isRunning: false,
            mode: .continuous,
            startedAt: Date(),
            lastExecutionTime: Date(),
            nextExecutionTime: nil,
            pid: 1234
        )

        try stateManager.save(pausedState)

        let loadedPausedState = try stateManager.load()
        #expect(loadedPausedState?.isRunning == false)

        let result = try await processor.process(.resume, currentState: pausedState)

        #expect(result.success == true)
        #expect(result.shouldExit == false)

        let updatedState = try stateManager.load()
        #expect(updatedState != nil)
        #expect(updatedState?.isRunning == true)

        try? FileManager.default.removeItem(atPath: statePath)
    }

    @Test("CommandProcessor should reject pause when already paused")
    func testPauseCommandWhenPaused() async throws {
        let tmpDir = NSTemporaryDirectory()
        let statePath = (tmpDir as NSString).appendingPathComponent("test-state.json")
        try? FileManager.default.removeItem(atPath: statePath)

        let logger = StructuredLogger()
        let stateManager = AutomationStateManager(statePath: statePath, logger: logger)
        let processor = CommandProcessor(stateManager: stateManager, logger: logger)

        let pausedState = AutomationState(
            isRunning: false,
            mode: .continuous,
            startedAt: Date(),
            lastExecutionTime: Date(),
            nextExecutionTime: nil,
            pid: 1234
        )

        let result = try await processor.process(.pause, currentState: pausedState)

        #expect(result.success == false)
        #expect(result.message?.contains("already paused") == true)

        try? FileManager.default.removeItem(atPath: statePath)
    }

    @Test("CommandProcessor should reject resume when already running")
    func testResumeCommandWhenRunning() async throws {
        let tmpDir = NSTemporaryDirectory()
        let statePath = (tmpDir as NSString).appendingPathComponent("test-state.json")
        try? FileManager.default.removeItem(atPath: statePath)

        let logger = StructuredLogger()
        let stateManager = AutomationStateManager(statePath: statePath, logger: logger)
        let processor = CommandProcessor(stateManager: stateManager, logger: logger)

        let runningState = AutomationState(
            isRunning: true,
            mode: .continuous,
            startedAt: Date(),
            lastExecutionTime: nil,
            nextExecutionTime: nil,
            pid: 1234
        )

        let result = try await processor.process(.resume, currentState: runningState)

        #expect(result.success == false)
        #expect(result.message?.contains("already running") == true)

        try? FileManager.default.removeItem(atPath: statePath)
    }

    @Test("CommandProcessor should handle quit command")
    func testQuitCommand() async throws {
        let logger = StructuredLogger()
        let stateManager = AutomationStateManager(logger: logger)
        let processor = CommandProcessor(stateManager: stateManager, logger: logger)

        let result = try await processor.process(.quit, currentState: nil)

        #expect(result.success == true)
        #expect(result.shouldExit == true)
        #expect(result.message?.contains("Exiting") == true)
    }

    @Test("CommandProcessor should handle logs command")
    func testLogsCommand() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("test-command-bar.db")
        try? FileManager.default.removeItem(atPath: dbPath)

        let logger = StructuredLogger()
        let stateManager = AutomationStateManager(logger: logger)
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        let processor = CommandProcessor(
            stateManager: stateManager,
            logger: logger,
            persistence: persistence
        )

        let tx = InvestmentTransaction(
            id: UUID(),
            type: .buy,
            exchange: "robinhood",
            asset: "BTC",
            quantity: 0.1,
            price: 45000.0,
            fee: 5.0,
            timestamp: Date(),
            metadata: [:],
            idempotencyKey: UUID().uuidString
        )

        try persistence.saveTransaction(tx)

        let result = try await processor.process(.logs, currentState: nil)

        #expect(result.success == true)
        #expect(result.message != nil)
        #expect(result.message?.contains("Recent Transactions") == true)

        try? FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("CommandProcessor should handle logs command with no transactions")
    func testLogsCommandNoTransactions() async throws {
        let tmpDir = NSTemporaryDirectory()
        let dbPath = (tmpDir as NSString).appendingPathComponent("test-command-bar-empty.db")
        try? FileManager.default.removeItem(atPath: dbPath)

        let logger = StructuredLogger()
        let stateManager = AutomationStateManager(logger: logger)
        let persistence = SQLitePersistence(dbPath: dbPath)
        try persistence.initialize()

        let processor = CommandProcessor(
            stateManager: stateManager,
            logger: logger,
            persistence: persistence
        )

        let result = try await processor.process(.logs, currentState: nil)

        #expect(result.success == true)
        #expect(result.message != nil)
        #expect(result.message?.contains("No recent transactions") == true)

        try? FileManager.default.removeItem(atPath: dbPath)
    }

    @Test("CommandProcessor should handle missing state gracefully")
    func testCommandProcessorWithMissingState() async throws {
        let logger = StructuredLogger()
        let stateManager = AutomationStateManager(logger: logger)
        let processor = CommandProcessor(stateManager: stateManager, logger: logger)

        let pauseResult = try await processor.process(.pause, currentState: nil)
        #expect(pauseResult.success == false)
        #expect(pauseResult.message?.contains("No automation state") == true)

        let resumeResult = try await processor.process(.resume, currentState: nil)
        #expect(resumeResult.success == false)
        #expect(resumeResult.message?.contains("No automation state") == true)
    }

    @Test("TUIRenderer should include command bar in initial state")
    func testCommandBarInInitialState() async {
        let colorManager = ColorManager(monochrome: true)
        let commandBar = CommandBarRenderer(colorManager: colorManager)
        let expectedCommands = commandBar.renderDefaultCommands()

        #expect(expectedCommands.contains("[P]"))
        #expect(expectedCommands.contains("[R]"))
        #expect(expectedCommands.contains("[L]"))
        #expect(expectedCommands.contains("[Q]"))
    }

    @Test("TUIRenderer should include command bar in updates")
    func testCommandBarInUpdates() async {
        let colorManager = ColorManager(monochrome: true)
        let commandBar = CommandBarRenderer(colorManager: colorManager)

        let runningCommands = commandBar.renderDefaultCommands(isRunning: true)
        #expect(runningCommands.contains("[P]"))
        #expect(runningCommands.contains("[R]"))
        #expect(runningCommands.contains("[L]"))
        #expect(runningCommands.contains("[Q]"))
    }

    @Test("TUIRenderer should include command bar in updates with prices")
    func testCommandBarInUpdatesWithPrices() async {
        let colorManager = ColorManager(monochrome: true)
        let commandBar = CommandBarRenderer(colorManager: colorManager)

        let pausedCommands = commandBar.renderDefaultCommands(isRunning: false)
        #expect(pausedCommands.contains("[S]"))
        #expect(pausedCommands.contains("[R]"))
        #expect(pausedCommands.contains("[L]"))
        #expect(pausedCommands.contains("[Q]"))
    }

    @Test("CommandBarRenderer should update based on running state")
    func testCommandBarStateUpdates() {
        let colorManager = ColorManager(monochrome: true)
        let renderer = CommandBarRenderer(colorManager: colorManager)

        let runningCommands = renderer.renderDefaultCommands(isRunning: true)
        let pausedCommands = renderer.renderDefaultCommands(isRunning: false)

        #expect(runningCommands.contains("[P]"))
        #expect(runningCommands.contains("[R]"))
        #expect(pausedCommands.contains("[S]"))
        #expect(pausedCommands.contains("[R]"))
    }
}
