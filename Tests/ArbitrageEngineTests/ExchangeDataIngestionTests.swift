import Foundation
import Testing
@testable import Core
import Connectors
import Utils

@Suite
struct ExchangeDataIngestionTests {
    @Test
    func normalizedStreamDropsInvalidQuotesAndEmitsNormalizedData() async throws {
        let now = Date()
        let quotes: [RawPriceData] = [
            RawPriceData(
                exchange: "Binance",
                symbol: "BTC-USD",
                bid: Decimal(string: "42000.123456789")!,
                ask: Decimal(string: "42000.987654321")!,
                timestamp: now
            ),
            // Invalid because ask < bid, should be filtered.
            RawPriceData(
                exchange: "Binance",
                symbol: "BTC-USD",
                bid: Decimal(string: "42001.11")!,
                ask: Decimal(string: "42001.00")!,
                timestamp: now
            ),
            RawPriceData(
                exchange: "Binance",
                symbol: "BTC-USD",
                bid: Decimal(string: "42002.000000005")!,
                ask: Decimal(string: "42002.500000009")!,
                timestamp: now
            )
        ]

        let connector = StubConnector(name: "Binance", quotes: quotes)
        let generator = MonotonicSequence(values: [0.0, 0.0009, 0.0012])
        let normalizer = ExchangeNormalizer(
            config: .init(staleInterval: 5, minimumGap: 0.001),
            now: { now },
            monotonicNow: { generator.next() }
        )

        let ingestion = ExchangeDataIngestion(normalizer: normalizer, logger: nil)
        let stream = await ingestion.normalizedPriceStream(connector: connector, symbol: "BTC-USD")

        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        let second = try await iterator.next()
        let third = try await iterator.next()

        #expect(first != nil)
        #expect(second != nil)
        #expect(third == nil)

        let firstQuote = try #require(first)
        let secondQuote = try #require(second)

        #expect(firstQuote.bid == Decimal(string: "42000.12345679"))
        #expect(firstQuote.ask == Decimal(string: "42000.98765432"))
        #expect(abs(firstQuote.normalizedTime - 0.0) < 1e-9)

        #expect(secondQuote.bid == Decimal(string: "42002.00000001"))
        #expect(secondQuote.ask == Decimal(string: "42002.50000001"))
        #expect(secondQuote.normalizedTime > firstQuote.normalizedTime)
        let delta = secondQuote.normalizedTime - firstQuote.normalizedTime
        #expect(abs(delta - 0.001) < 1e-9)
    }

    @Test
    func streamPropagatesErrors() async {
        struct TestError: Error {}

        let now = Date()
        let connector = FailingConnector(error: TestError())
        let normalizer = ExchangeNormalizer(now: { now }, monotonicNow: { 0 })
        let ingestion = ExchangeDataIngestion(normalizer: normalizer, logger: nil)

        let stream = await ingestion.normalizedPriceStream(connector: connector, symbol: "BTC-USD")
        var iterator = stream.makeAsyncIterator()

        do {
            let result = try await iterator.next()
            if result != nil {
                Issue.record("Expected stream to end with error or nil")
            }
        } catch is IngestionError {
            // expected - subscription failed
        } catch is TestError {
            // also acceptable
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func ingestionErrorTypes() {
        let error1 = IngestionError.connectionLost(exchange: "Binance", reason: "timeout")
        #expect(error1.localizedDescription.contains("Binance"))
        #expect(error1.localizedDescription.contains("timeout"))

        let error2 = IngestionError.connectionFailed(exchange: "Kraken", reason: "network error")
        #expect(error2.localizedDescription.contains("Kraken"))
        #expect(error2.localizedDescription.contains("network error"))

        let error3 = IngestionError.subscriptionFailed(exchange: "Coinbase", symbol: "BTC-USD", reason: "invalid symbol")
        #expect(error3.localizedDescription.contains("Coinbase"))
        #expect(error3.localizedDescription.contains("BTC-USD"))
        #expect(error3.localizedDescription.contains("invalid symbol"))
    }
}

private final class StubConnector: ExchangeConnector, @unchecked Sendable {
    let name: String
    private let quotes: [RawPriceData]
    private var status: ConnectionStatus = .connected
    private let priceStreamStorage: AsyncStream<RawPriceData>
    private var priceContinuation: AsyncStream<RawPriceData>.Continuation
    private let eventStreamStorage: AsyncStream<ConnectionEvent>
    private var eventContinuation: AsyncStream<ConnectionEvent>.Continuation

    init(name: String, quotes: [RawPriceData]) {
        self.name = name
        self.quotes = quotes

        let priceStream = AsyncStream.makeStream(of: RawPriceData.self, bufferingPolicy: .bufferingNewest(100))
        self.priceStreamStorage = priceStream.stream
        self.priceContinuation = priceStream.continuation

        let eventStream = AsyncStream.makeStream(of: ConnectionEvent.self, bufferingPolicy: .bufferingNewest(10))
        self.eventStreamStorage = eventStream.stream
        self.eventContinuation = eventStream.continuation
    }

    var connectionStatus: ConnectionStatus {
        get async { status }
    }

    var priceUpdates: AsyncStream<RawPriceData> { priceStreamStorage }
    var connectionEvents: AsyncStream<ConnectionEvent> { eventStreamStorage }

    func connect() async throws {
        status = .connected
        eventContinuation.yield(.statusChanged(.connected))
    }

    func disconnect() async {
        status = .disconnected
        priceContinuation.finish()
        eventContinuation.yield(.disconnected(reason: nil))
        eventContinuation.finish()
    }

    func subscribeToPairs(_ pairs: [String]) async throws {
        for quote in quotes where pairs.contains(quote.symbol) {
            priceContinuation.yield(quote)
        }
        priceContinuation.finish()
        eventContinuation.finish()
    }

    func getOrderBook(symbol: String) async throws -> OrderBook {
        let bids = [
            OrderBookEntry(price: 49900.0, quantity: 0.5),
            OrderBookEntry(price: 49800.0, quantity: 1.0)
        ]
        let asks = [
            OrderBookEntry(price: 50100.0, quantity: 0.3),
            OrderBookEntry(price: 50200.0, quantity: 0.8)
        ]
        return OrderBook(bids: bids, asks: asks)
    }

    func getRecentTransactions(limit: Int) async throws -> [Transaction] {
        return [
            Transaction(
                id: "tx1",
                type: .buy,
                asset: "BTC-USD",
                quantity: 0.1,
                price: 50000.0,
                timestamp: Date()
            )
        ]
    }

    func placeOrder(symbol: String, side: OrderSide, type: OrderType, quantity: Double, price: Double) async throws -> Order {
        return Order(
            id: UUID().uuidString,
            symbol: symbol,
            side: side,
            type: type,
            quantity: quantity,
            price: price,
            status: .filled,
            timestamp: Date()
        )
    }
}

private final class FailingConnector: ExchangeConnector, @unchecked Sendable {
    let name: String = "Failing"
    private let error: Error
    private let priceStreamStorage: AsyncStream<RawPriceData>
    private let eventStreamStorage: AsyncStream<ConnectionEvent>

    init(error: Error) {
        self.error = error
        let priceStream = AsyncStream.makeStream(of: RawPriceData.self)
        self.priceStreamStorage = priceStream.stream
        priceStream.continuation.finish()

        let eventStream = AsyncStream.makeStream(of: ConnectionEvent.self)
        self.eventStreamStorage = eventStream.stream
        eventStream.continuation.finish()
    }

    var connectionStatus: ConnectionStatus {
        get async { .failed(reason: "test") }
    }

    var priceUpdates: AsyncStream<RawPriceData> { priceStreamStorage }
    var connectionEvents: AsyncStream<ConnectionEvent> { eventStreamStorage }

    func connect() async throws {}

    func disconnect() async {}

    func subscribeToPairs(_ pairs: [String]) async throws {
        throw error
    }

    // MARK: - Trading Methods (Mock implementations)

    func getOrderBook(symbol: String) async throws -> OrderBook {
        return OrderBook(
            bids: [OrderBookEntry(price: 50000.0, quantity: 1.0)],
            asks: [OrderBookEntry(price: 50001.0, quantity: 1.0)]
        )
    }

    func getRecentTransactions(limit: Int) async throws -> [Transaction] {
        return [
            Transaction(
                id: "tx1",
                type: .buy,
                asset: "BTC-USD",
                quantity: 0.1,
                price: 50000.0,
                timestamp: Date()
            )
        ]
    }

    func placeOrder(symbol: String, side: OrderSide, type: OrderType, quantity: Double, price: Double) async throws -> Order {
        return Order(
            id: UUID().uuidString,
            symbol: symbol,
            side: side,
            type: type,
            quantity: quantity,
            price: price,
            status: .filled,
            timestamp: Date()
        )
    }
}

private final class MonotonicSequence: @unchecked Sendable {
    private var values: [TimeInterval]
    private let lock = NSLock()

    init(values: [TimeInterval]) {
        self.values = values
    }

    func next() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return 0 }
        return values.removeFirst()
    }
}
