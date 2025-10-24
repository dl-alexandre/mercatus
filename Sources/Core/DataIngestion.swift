import Foundation
import Utils

private final class ThreadSafeBox<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) {
        self.value = value
    }

    func compareAndSet(old: T, new: T) -> Bool where T: Equatable {
        lock.lock()
        defer { lock.unlock() }
        if value == old {
            value = new
            return true
        }
        return false
    }
}

public enum IngestionError: Error, LocalizedError {
    case connectionFailed(exchange: String, reason: String)
    case connectionLost(exchange: String, reason: String)
    case subscriptionFailed(exchange: String, symbol: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let exchange, let reason):
            return "Connection to \(exchange) failed: \(reason)"
        case .connectionLost(let exchange, let reason):
            return "Connection to \(exchange) lost: \(reason)"
        case .subscriptionFailed(let exchange, let symbol, let reason):
            return "Subscription to \(symbol) on \(exchange) failed: \(reason)"
        }
    }
}

/// Bridges exchange connector price streams through the `ExchangeNormalizer`.
public actor ExchangeDataIngestion {
    private let normalizer: ExchangeNormalizer
    private let logger: StructuredLogger?

    public init(normalizer: ExchangeNormalizer, logger: StructuredLogger? = nil) {
        self.normalizer = normalizer
        self.logger = logger
    }

    /// Returns an async stream of normalized prices for the given connector and symbol.
    public func normalizedPriceStream(
        connector: ExchangeConnector,
        symbol: String
    ) -> AsyncThrowingStream<NormalizedPriceData, Error> {
        AsyncThrowingStream { continuation in
            let hasFinished = ThreadSafeBox(false)

            let priceTask = Task {
                for await quote in connector.priceUpdates {
                    guard quote.symbol == symbol else { continue }

                    guard let normalized = await normalizer.normalize(quote) else {
                        logger?.debug(
                            component: "ExchangeDataIngestion",
                            event: "quote_filtered",
                            data: [
                                "exchange": quote.exchange,
                                "symbol": quote.symbol
                            ]
                        )
                        continue
                    }

                    continuation.yield(normalized)
                }
                if hasFinished.compareAndSet(old: false, new: true) {
                    continuation.finish()
                }
            }

            let eventTask = Task {
                for await event in connector.connectionEvents {
                    handleConnectionEvent(
                        event,
                        connector: connector,
                        symbol: symbol,
                        continuation: continuation
                    )
                }
            }

            let subscribeTask = Task {
                do {
                    try await connector.subscribeToPairs([symbol])
                } catch {
                    if hasFinished.compareAndSet(old: false, new: true) {
                        let ingestionError = IngestionError.subscriptionFailed(
                            exchange: connector.name,
                            symbol: symbol,
                            reason: error.localizedDescription
                        )

                        logger?.error(
                            component: "ExchangeDataIngestion",
                            event: "subscription_error",
                            data: [
                                "exchange": connector.name,
                                "symbol": symbol,
                                "reason": error.localizedDescription
                            ]
                        )

                        continuation.finish(throwing: ingestionError)
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                priceTask.cancel()
                eventTask.cancel()
                subscribeTask.cancel()
            }
        }
    }

    private func handleConnectionEvent(
        _ event: ConnectionEvent,
        connector: ExchangeConnector,
        symbol: String,
        continuation: AsyncThrowingStream<NormalizedPriceData, Error>.Continuation
    ) {
        switch event {
        case .disconnected(let reason):
            let errorReason = reason ?? "unknown"

            logger?.warn(
                component: "ExchangeDataIngestion",
                event: "connection_lost",
                data: [
                    "exchange": connector.name,
                    "symbol": symbol,
                    "reason": errorReason
                ]
            )

            let ingestionError = IngestionError.connectionLost(
                exchange: connector.name,
                reason: errorReason
            )
            continuation.finish(throwing: ingestionError)

        case .statusChanged(let status):
            logger?.debug(
                component: "ExchangeDataIngestion",
                event: "status_changed",
                data: [
                    "exchange": connector.name,
                    "symbol": symbol,
                    "status": "\(status)"
                ]
            )

            switch status {
            case .connected:
                logger?.info(
                    component: "ExchangeDataIngestion",
                    event: "connection_established",
                    data: [
                        "exchange": connector.name,
                        "symbol": symbol
                    ]
                )

            case .failed(let reason):
                logger?.error(
                    component: "ExchangeDataIngestion",
                    event: "connection_failed",
                    data: [
                        "exchange": connector.name,
                        "symbol": symbol,
                        "reason": reason
                    ]
                )

                let ingestionError = IngestionError.connectionFailed(
                    exchange: connector.name,
                    reason: reason
                )
                continuation.finish(throwing: ingestionError)

            default:
                break
            }

        case .receivedHeartbeat:
            logger?.debug(
                component: "ExchangeDataIngestion",
                event: "heartbeat_received",
                data: [
                    "exchange": connector.name,
                    "symbol": symbol
                ]
            )
        }
    }
}
