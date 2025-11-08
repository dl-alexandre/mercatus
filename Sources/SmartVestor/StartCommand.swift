import Foundation
import ArgumentParser
import SmartVestor
import Utils
import Connectors
import Core

#if os(macOS) || os(Linux)
import Darwin
#endif

struct StartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start portfolio monitoring bot with automated execution"
    )

    @Option(name: .shortAndLong, help: "Automation mode: continuous or weekly")
    var mode: AutomationMode = .continuous

    @Option(name: .shortAndLong, help: "Path to configuration file")
    var configPath: String?

    @Flag(name: .long, help: "Enable production mode (execute real trades)")
    var production: Bool = false

    @Flag(name: .long, help: "Launch TUI client automatically after starting")
    var tui: Bool = false

    @Option(name: .long, help: "Path to log file")
    var logPath: String?

    func run() async throws {
        let resolvedLogPath = logPath ?? "/tmp/smartvestor-automation.log"
        setenv("SMARTVESTOR_LOG_PATH", resolvedLogPath, 1)

        let logger: DualLogger
        let consoleLogger: StructuredLogger

        do {
            let fileLogger = try FileLogger(logPath: resolvedLogPath, logger: StructuredLogger())
            consoleLogger = StructuredLogger(maxLogsPerMinute: 300, enabled: false)
            logger = DualLogger(consoleLogger: consoleLogger, fileLogger: fileLogger)
        } catch {
            consoleLogger = StructuredLogger(maxLogsPerMinute: 300)
            consoleLogger.warn(component: "StartCommand", event: "Failed to initialize file logger, using console only", data: [
                "error": error.localizedDescription
            ])
            logger = DualLogger(consoleLogger: consoleLogger, fileLogger: nil)
        }

        logger.info(component: "StartCommand", event: "Starting automation", data: [
            "mode": mode.rawValue,
            "production": String(production)
        ])

        if production {
            setenv("SMARTVESTOR_PRODUCTION_MODE", "true", 1)
        }

        let lockManager = ProcessLockManager(logger: consoleLogger)
        guard try lockManager.acquireLock() else {
            logger.error(component: "StartCommand", event: "Failed to acquire lock - automation may already be running")
            if let lockPid = lockManager.getLockPid() {
                print("Error: Automation already running (PID: \(lockPid))")
                print("   Use 'sv stop' to stop the running instance first")
            } else {
                print("Error: Lock file exists - another instance may be running")
            }
            return
        }

        if production {
            let prompter = SafetyPrompter(logger: consoleLogger)
            let tempConfig = try SmartVestorConfigurationManager(configPath: configPath).currentConfig
            guard prompter.confirmProductionMode(config: tempConfig) else {
                try lockManager.releaseLock()
                return
            }
        }

        var exchangeConnectors: [String: ExchangeConnectorProtocol] = [:]

        var apiKey = ProcessInfo.processInfo.environment["ROBINHOOD_API_KEY"]
        var privateKeyBase64 = ProcessInfo.processInfo.environment["ROBINHOOD_PRIVATE_KEY"]

        if apiKey == nil || privateKeyBase64 == nil {
            let envPath = ".env"
            if let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) {
                for line in envContent.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count >= 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)

                        if key == "ROBINHOOD_API_KEY" && apiKey == nil {
                            apiKey = value
                        } else if key == "ROBINHOOD_PRIVATE_KEY" && privateKeyBase64 == nil {
                            privateKeyBase64 = value
                        }
                    }
                }
            }
        }

        if let apiKey = apiKey, let privateKeyBase64 = privateKeyBase64 {
            let sanitizedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            let sanitizedPrivateKey = privateKeyBase64
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                .filter { !$0.isWhitespace && $0 != "\n" && $0 != "\r" }

            if !sanitizedApiKey.isEmpty && !sanitizedPrivateKey.isEmpty {
                setenv("ROBINHOOD_API_KEY", sanitizedApiKey, 1)
                setenv("ROBINHOOD_PRIVATE_KEY", sanitizedPrivateKey, 1)

                do {
                    let credentials = try RobinhoodConnector.Configuration.Credentials(
                        apiKey: sanitizedApiKey,
                        privateKeyBase64: sanitizedPrivateKey
                    )
                    let robinhoodConnector = RobinhoodConnector(
                        logger: consoleLogger,
                        configuration: RobinhoodConnector.Configuration(
                            credentials: credentials
                        )
                    )
                    exchangeConnectors["robinhood"] = robinhoodConnector
                    logger.info(component: "StartCommand", event: "Robinhood connector initialized")
                } catch {
                    logger.warn(component: "StartCommand", event: "Failed to initialize Robinhood connector", data: [
                        "error": error.localizedDescription
                    ])
                }
            }
        }

        let components = try await AutomationBootstrapper.createComponents(
            configPath: configPath,
            productionMode: production,
            exchangeConnectors: exchangeConnectors,
            logger: consoleLogger
        )

        let validation = try await ConfigValidator.validate(
            config: components.config,
            persistence: components.persistence,
            connectors: components.exchangeConnectors,
            processLockManager: lockManager
        )

        if !validation.isValid {
            logger.error(component: "StartCommand", event: "Configuration validation failed", data: [
                "errors": validation.errors.joined(separator: "; ")
            ])
            print("Configuration validation failed:")
            for error in validation.errors {
                print("  • \(error)")
            }
            try lockManager.releaseLock()
            return
        }

        if !validation.warnings.isEmpty {
            logger.warn(component: "StartCommand", event: "Configuration warnings", data: [
                "warnings": validation.warnings.joined(separator: "; ")
            ])
            for warning in validation.warnings {
                print("Warning: \(warning)")
            }
            print("")
        }

        logger.info(component: "StartCommand", event: "Performing initial Robinhood sync")
        print("Performing initial portfolio sync...")
        do {
            if let robinhoodConnector = components.robinhoodConnector as? RobinhoodConnector {
                let holdings = try await robinhoodConnector.getHoldings(assetCode: nil)
                for holding in holdings {
                    if holding.quantity > 0 {
                        let existing = try? components.persistence.getAccount(exchange: "robinhood", asset: holding.assetCode)
                        let account = Holding(
                            id: existing?.id ?? UUID(),
                            exchange: "robinhood",
                            asset: holding.assetCode,
                            available: holding.available,
                            pending: holding.pending,
                            staked: holding.staked,
                            updatedAt: Date()
                        )
                        try components.persistence.saveAccount(account)
                    }
                }
                let fetchedSymbols = Set(holdings.map { $0.assetCode })
                let existingAccounts = try components.persistence.getAllAccounts().filter { $0.exchange == "robinhood" }
                for account in existingAccounts {
                    if !fetchedSymbols.contains(account.asset) && account.total > 0 {
                        let cleared = Holding(
                            id: account.id,
                            exchange: account.exchange,
                            asset: account.asset,
                            available: 0,
                            pending: 0,
                            staked: 0,
                            updatedAt: Date()
                        )
                        try components.persistence.saveAccount(cleared)
                    }
                }
                logger.info(component: "StartCommand", event: "Initial sync complete", data: [
                    "holdings_count": String(holdings.count)
                ])
                print("Initial sync complete (\(holdings.count) holdings)")
                print("")
            }
        } catch {
            logger.warn(component: "StartCommand", event: "Initial sync failed, continuing", data: [
                "error": error.localizedDescription
            ])
            print("Warning: Initial sync failed: \(error.localizedDescription)")
            print("   Continuing anyway...")
            print("")
        }

        let tuiServer = TUIServer()
        try await tuiServer.start()

        let stateManager = AutomationStateManager(logger: consoleLogger)
        let initialState = AutomationState(
            isRunning: true,
            mode: mode,
            startedAt: Date(),
            lastExecutionTime: nil,
            nextExecutionTime: nil,
            pid: ProcessInfo.processInfo.processIdentifier
        )
        try stateManager.save(initialState)

        // Heartbeat publisher removed; ContinuousRunner will publish heartbeats

        logger.info(component: "StartCommand", event: "Starting automation runner", data: [
            "mode": mode.rawValue
        ])

        print("Starting portfolio monitoring bot...")
        print("   Mode: \(mode.rawValue)")
        print("   Production: \(production ? "YES" : "NO (dry-run)")")
        print("")
        print("Press Ctrl+C to stop")
        print("")

        #if os(macOS) || os(Linux)
        var signalSource: DispatchSourceSignal?
        let runnerRef = components.continuousRunner
        let tuiServerRef = tuiServer
        let stateManagerRef = stateManager
        let lockManagerRef = lockManager
        let loggerRef = logger
        let initialStateRef = initialState
        let modeValue = mode
        let tuiFlag = tui

        let mainTask = Task { @Sendable in
            do {
                switch modeValue {
                case .continuous:
                    guard let runner = runnerRef else {
                        throw SmartVestorError.executionError("ContinuousRunner not available")
                    }
                    runner.setTUI(server: tuiServerRef)
                    try await runner.startContinuousMonitoring()

                    if tuiFlag {
                        Task.detached {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            let tuiProcess = Process()
                            tuiProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                            let executablePath = ProcessInfo.processInfo.arguments.first ?? "sv"
                            tuiProcess.arguments = [executablePath, "tui"]
                            tuiProcess.standardOutput = nil
                            tuiProcess.standardError = nil
                            try? tuiProcess.run()
                        }
                    }

                    while !Task.isCancelled {
                        try Task.checkCancellation()
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                case .weekly:
                    throw SmartVestorError.executionError("Weekly mode not yet implemented")
                }
            } catch {
                if error is CancellationError {
                    throw error
                }
                throw error
            }
        }

        signal(SIGINT, SIG_IGN)
        let signalQueue = DispatchQueue(label: "com.smartvestor.signal")
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
        signalSource = source

        source.setEventHandler { @Sendable in
            loggerRef.info(component: "StartCommand", event: "SIGINT received, stopping automation")
            mainTask.cancel()
        }

        source.resume()
        #endif

        do {
            #if os(macOS) || os(Linux)
            try await mainTask.value
            #else
            switch mode {
            case .continuous:
                guard let runner = components.continuousRunner else {
                    throw SmartVestorError.executionError("ContinuousRunner not available")
                }
                runner.setTUI(server: tuiServer)
                try await runner.startContinuousMonitoring()

                if tui {
                    Task.detached {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        let tuiProcess = Process()
                        tuiProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                        let executablePath = ProcessInfo.processInfo.arguments.first ?? "sv"
                        tuiProcess.arguments = [executablePath, "tui"]
                        tuiProcess.standardOutput = nil
                        tuiProcess.standardError = nil
                        try? tuiProcess.run()
                    }
                }

                while !Task.isCancelled {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            case .weekly:
                throw SmartVestorError.executionError("Weekly mode not yet implemented")
            }
            #endif
        } catch {
            #if os(macOS) || os(Linux)
            signalSource?.cancel()
            #endif

            if error is CancellationError {
                logger.info(component: "StartCommand", event: "Automation stopped by user")
                print("")
                print("Stopping automation...")
                if let runner = components.continuousRunner {
                    await runner.stopContinuousMonitoring()
                }
                await tuiServer.stop()
                try? stateManager.save(AutomationState(
                    isRunning: false,
                    mode: mode,
                    startedAt: initialState.startedAt,
                    lastExecutionTime: Date(),
                    nextExecutionTime: nil,
                    pid: nil
                ))
                try? lockManager.releaseLock()
                logger.close()
                print("Automation stopped")
                return
            }
            logger.error(component: "StartCommand", event: "Automation failed", data: [
                "error": error.localizedDescription
            ])
            print("Error: \(error.localizedDescription)")
            try? stateManager.save(AutomationState(
                isRunning: false,
                mode: mode,
                startedAt: initialState.startedAt,
                lastExecutionTime: Date(),
                nextExecutionTime: nil,
                pid: nil
            ))
            await tuiServer.stop()
            try? lockManager.releaseLock()
            logger.close()
            throw error
        }
    }
}
