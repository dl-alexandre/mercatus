import Foundation
import Core
import Utils

public class DataIngestionService: DataIngestionProtocol, @unchecked Sendable {
    private let exchangeConnectors: [String: any ExchangeConnector]
    private let qualityValidator: DataQualityValidatorProtocol
    private let timeSeriesStore: TimeSeriesStoreProtocol
    private let logger: StructuredLogger
    private var isIngesting = false
    private var realTimeCallbacks: [String: (MarketDataPoint) -> Void] = [:]

    public init(
        exchangeConnectors: [String: any ExchangeConnector],
        qualityValidator: DataQualityValidatorProtocol,
        timeSeriesStore: TimeSeriesStoreProtocol,
        logger: StructuredLogger
    ) {
        self.exchangeConnectors = exchangeConnectors
        self.qualityValidator = qualityValidator
        self.timeSeriesStore = timeSeriesStore
        self.logger = logger
    }

    public init(exchangeConnectors: [String: any ExchangeConnector], dbPath: String, logger: StructuredLogger) async throws {
        self.exchangeConnectors = exchangeConnectors
        self.qualityValidator = DataQualityValidator(logger: logger)
        self.timeSeriesStore = try TimeSeriesStore(dbPath: dbPath, logger: logger)
        self.logger = logger
    }

    public func startIngestion() async throws {
        guard !isIngesting else {
            logger.warn(component: "DataIngestionService", event: "Data ingestion already running")
            return
        }

        isIngesting = true
        logger.info(component: "DataIngestionService", event: "Starting data ingestion service")

        for (exchange, connector) in exchangeConnectors {
            do {
                try await connector.connect()
                logger.info(component: "DataIngestionService", event: "Connected to \(exchange) exchange")
            } catch {
                logger.error(component: "DataIngestionService", event: "Failed to connect to \(exchange): \(error)")
                throw error
            }
        }
    }

    public func stopIngestion() async throws {
        guard isIngesting else {
            logger.warn(component: "DataIngestionService", event: "Data ingestion not running")
            return
        }

        isIngesting = false
        logger.info(component: "DataIngestionService", event: "Stopping data ingestion service")

        for (exchange, connector) in exchangeConnectors {
            await connector.disconnect()
            logger.info(component: "DataIngestionService", event: "Disconnected from \(exchange) exchange")
        }
    }

    public func getLatestData(for symbol: String, limit: Int) async throws -> [MarketDataPoint] {
        // For now, return empty array since ExchangeConnector doesn't have historical data methods
        // In a real implementation, this would query the time series store
        return try await timeSeriesStore.getLatestData(symbol: symbol, limit: limit)
    }

    public func getHistoricalData(for symbol: String, from: Date, to: Date) async throws -> [MarketDataPoint] {
        return try await timeSeriesStore.getData(symbol: symbol, from: from, to: to)
    }

    public func subscribeToRealTimeData(for symbols: [String], callback: @escaping (MarketDataPoint) -> Void) async throws {
        for symbol in symbols {
            realTimeCallbacks[symbol] = callback
        }

        for (_, connector) in exchangeConnectors {
            try await connector.subscribeToPairs(symbols)
            // In a real implementation, we would listen to the priceUpdates stream
            // and convert RawPriceData to MarketDataPoint
        }
    }

    private func processRealTimeData(_ dataPoint: MarketDataPoint) {
        let qualityResult = qualityValidator.validateDataPoint(dataPoint)

        if qualityResult.isValid {
            Task { [weak self] in
                guard let self = self else { return }
                try await self.timeSeriesStore.storeData([dataPoint])
            }

            if let callback = realTimeCallbacks[dataPoint.symbol] {
                callback(dataPoint)
            }
        } else {
            logger.warn(component: "DataIngestionService", event: "Invalid data point received: \(dataPoint.symbol) at \(dataPoint.timestamp)")
        }
    }
}

public protocol TimeSeriesStoreProtocol {
    func storeData(_ dataPoints: [MarketDataPoint]) async throws
    func getData(symbol: String, from: Date, to: Date) async throws -> [MarketDataPoint]
    func getLatestData(symbol: String, limit: Int) async throws -> [MarketDataPoint]
    func deleteOldData(olderThan: Date) async throws
    func enforceRetentionPolicy() async throws
}
