import Foundation
import Connectors
import Utils
import Core

public final class LiveArbitrageEngine: ArbitrageEngine, Sendable {
    private let config: ArbitrageConfig
    private let logger: StructuredLogger
    private let configManager: ConfigurationManager
    private let krakenConnector: KrakenConnector
    private let coinbaseConnector: CoinbaseConnector
    private let normalizer: ExchangeNormalizer
    private let spreadDetector: SpreadDetector
    private let tradeSimulator: TradeSimulator
    private let performanceMonitor: PerformanceMonitor
    private let dataIngestion: ExchangeDataIngestion

    private let componentName = "ArbitrageEngine"
    private let state: State

    private actor State {
        var isRunning = false
        var connectorTasks: [Task<Void, Never>] = []
        var simulatorTask: Task<Void, Never>?
        var signalSource: DispatchSourceSignal?

        func setRunning(_ value: Bool) {
            isRunning = value
        }

        func addConnectorTask(_ task: Task<Void, Never>) {
            connectorTasks.append(task)
        }

        func setSimulatorTask(_ task: Task<Void, Never>) {
            simulatorTask = task
        }

        func setSignalSource(_ source: DispatchSourceSignal) {
            signalSource = source
        }

        func cancelAll() {
            connectorTasks.forEach { $0.cancel() }
            connectorTasks.removeAll()
            simulatorTask?.cancel()
            simulatorTask = nil
            signalSource?.cancel()
            signalSource = nil
        }
    }

    public init(
        config: ArbitrageConfig,
        logger: StructuredLogger? = nil,
        configManager: ConfigurationManager? = nil
    ) {
        self.config = config
        self.logger = logger ?? StructuredLogger()
        self.configManager = configManager ?? ConfigurationManager()

        self.krakenConnector = KrakenConnector(logger: self.logger)
        self.coinbaseConnector = CoinbaseConnector(
            logger: self.logger,
            configuration: .init(
                credentials: .init(
                    apiKey: config.coinbaseCredentials.apiKey,
                    apiSecret: config.coinbaseCredentials.apiSecret
                )
            )
        )

        self.normalizer = ExchangeNormalizer()
        self.spreadDetector = SpreadDetector(config: config, logger: self.logger)

        let simulatorConfig = TradeSimulator.Configuration(
            initialBalance: Decimal(config.defaults.virtualUSDStartingBalance)
        )
        self.tradeSimulator = TradeSimulator(config: simulatorConfig, logger: self.logger)

        self.performanceMonitor = PerformanceMonitor(logger: self.logger)
        self.dataIngestion = ExchangeDataIngestion(normalizer: normalizer, logger: self.logger)
        self.state = State()
    }

    public var isRunning: Bool {
        get async {
            await state.isRunning
        }
    }

    public func start() async throws {
        let correlationId = UUID().uuidString

        guard await !state.isRunning else {
            let error = ArbitrageError.logic(.invalidState(
                component: componentName,
                expected: "stopped",
                actual: "running"
            ))
            logger.logError(error, component: componentName, correlationId: correlationId)
            return
        }

        await state.setRunning(true)

        logger.info(
            component: componentName,
            event: "engine_starting",
            data: [
                "trading_pairs": config.tradingPairs.map(\.symbol).joined(separator: ","),
                "min_spread": String(config.thresholds.minimumSpreadPercentage),
                "max_latency_ms": String(config.thresholds.maximumLatencyMilliseconds)
            ],
            correlationId: correlationId
        )

        configManager.logConfiguration(config, logger: logger)

        await setupSignalHandlers()

        await performanceMonitor.startPeriodicReporting()

        let simulatorTask = tradeSimulator.consumeProfitableStreams(from: spreadDetector)
        await state.setSimulatorTask(simulatorTask)

        do {
            try await startConnectors(correlationId: correlationId)

            logger.info(
                component: componentName,
                event: "engine_started",
                correlationId: correlationId
            )
        } catch let error as ArbitrageError {
            logger.logError(error, component: componentName, correlationId: correlationId)
            await stop()
            throw error
        } catch {
            let arbError = ArbitrageError.logic(.internalError(
                component: componentName,
                reason: error.localizedDescription
            ))
            logger.logError(arbError, component: componentName, correlationId: correlationId)
            await stop()
            throw arbError
        }
    }

    public func stop() async {
        guard await state.isRunning else {
            return
        }

        logger.info(
            component: componentName,
            event: "engine_stopping"
        )

        await state.setRunning(false)
        await state.cancelAll()

        await krakenConnector.disconnect()
        await coinbaseConnector.disconnect()

        await performanceMonitor.stopPeriodicReporting()

        let stats = await tradeSimulator.statistics()
        logger.info(
            component: componentName,
            event: "final_statistics",
            data: [
                "total_trades": String(stats.totalTrades),
                "successful_trades": String(stats.successfulTrades),
                "total_profit": NSDecimalNumber(decimal: stats.totalProfit).stringValue,
                "current_balance": NSDecimalNumber(decimal: stats.currentBalance).stringValue,
                "success_rate": String(format: "%.2f", stats.successRate * 100)
            ]
        )

        logger.info(
            component: componentName,
            event: "engine_stopped"
        )
    }

    private func startConnectors(correlationId: String) async throws {
        let pairs = config.tradingPairs.map(\.symbol)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self else { return }
                do {
                    try await self.krakenConnector.connect()
                    try await self.krakenConnector.subscribeToPairs(pairs)
                    await self.state.addConnectorTask(self.consumeConnectorStream(self.krakenConnector))
                } catch let error as ArbitrageError {
                    self.logger.logError(error, component: self.componentName, correlationId: correlationId)
                    throw error
                } catch {
                    let arbError = ArbitrageError.connection(.failedToConnect(
                        exchange: "Kraken",
                        reason: error.localizedDescription
                    ))
                    self.logger.logError(arbError, component: self.componentName, correlationId: correlationId)
                    throw arbError
                }
            }

            group.addTask { [weak self] in
                guard let self else { return }
                do {
                    try await self.coinbaseConnector.connect()
                    try await self.coinbaseConnector.subscribeToPairs(pairs)
                    await self.state.addConnectorTask(self.consumeConnectorStream(self.coinbaseConnector))
                } catch let error as ArbitrageError {
                    self.logger.logError(error, component: self.componentName, correlationId: correlationId)
                    throw error
                } catch {
                    let arbError = ArbitrageError.connection(.failedToConnect(
                        exchange: "Coinbase",
                        reason: error.localizedDescription
                    ))
                    self.logger.logError(arbError, component: self.componentName, correlationId: correlationId)
                    throw arbError
                }
            }

            try await group.waitForAll()
        }
    }

    private func consumeConnectorStream(_ connector: ExchangeConnector) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }

            for await rawPrice in connector.priceUpdates {
                guard let normalized = await self.normalizer.normalize(rawPrice) else {
                    continue
                }

                await self.spreadDetector.ingest(normalized)
            }
        }
    }

    private func setupSignalHandlers() async {
        signal(SIGINT, SIG_IGN)

        let signalQueue = DispatchQueue(label: "com.mercatus.signal")
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)

        source.setEventHandler { [weak self] in
            guard let self else { return }

            self.logger.info(
                component: self.componentName,
                event: "shutdown_signal_received",
                data: ["signal": "SIGINT"]
            )

            Task {
                await self.stop()
                exit(0)
            }
        }

        source.resume()
        await state.setSignalSource(source)

        logger.info(
            component: componentName,
            event: "signal_handlers_configured",
            data: ["signals": "SIGINT"]
        )
    }

    private func monitorConnectionEvents(_ connector: ExchangeConnector) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }

            for await event in connector.connectionEvents {
                switch event {
                case .statusChanged(let status):
                    self.handleStatusChange(connector: connector, status: status)
                case .receivedHeartbeat:
                    break
                case .disconnected(let reason):
                    self.handleDisconnect(connector: connector, reason: reason)
                }
            }
        }
    }

    private func handleStatusChange(connector: ExchangeConnector, status: ConnectionStatus) {
        var data: [String: String] = [
            "connector": connector.name
        ]

        switch status {
        case .disconnected:
            data["status"] = "disconnected"
        case .connecting:
            data["status"] = "connecting"
        case .connected:
            data["status"] = "connected"
        case .reconnecting:
            data["status"] = "reconnecting"
            Task {
                await performanceMonitor.recordReconnection()
            }
        case .failed(let reason):
            data["status"] = "failed"
            data["reason"] = reason
        }

        logger.info(
            component: componentName,
            event: "connector_status_changed",
            data: data
        )
    }

    private func handleDisconnect(connector: ExchangeConnector, reason: String?) {
        var data: [String: String] = [
            "connector": connector.name
        ]

        if let reason {
            data["reason"] = reason
        }

        logger.warn(
            component: componentName,
            event: "connector_disconnected",
            data: data
        )

        Task {
            await attemptReconnect(connector: connector)
        }
    }

    private func attemptReconnect(connector: ExchangeConnector) async {
        guard await state.isRunning else { return }

        let correlationId = UUID().uuidString

        logger.info(
            component: componentName,
            event: "attempting_reconnect",
            data: ["connector": connector.name],
            correlationId: correlationId
        )

        do {
            try await connector.connect()
            try await connector.subscribeToPairs(config.tradingPairs.map(\.symbol))

            logger.info(
                component: componentName,
                event: "reconnect_successful",
                data: ["connector": connector.name],
                correlationId: correlationId
            )

            await performanceMonitor.recordReconnection()
        } catch let error as ArbitrageError {
            logger.logError(error, component: componentName, correlationId: correlationId)
        } catch {
            let arbError = ArbitrageError.connection(.failedToConnect(
                exchange: connector.name,
                reason: error.localizedDescription
            ))
            logger.logError(arbError, component: componentName, correlationId: correlationId)
        }
    }
}
