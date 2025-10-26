import Foundation
import Testing
@testable import Core
import Connectors
import Utils

@Suite
struct ArbitrageEngineTests {
    @Test
    func engineLifecycle() async throws {
        let engine = DummyEngine()
        let connector = MockConnector(name: "TestConnector")

        engine.register(connector: connector)
        try await engine.start()

        #expect(engine.isRunning)
        let status = await connector.connectionStatus
        #expect(status == .connected)

        await engine.stop()
        #expect(engine.isRunning == false)
    }
}

// MARK: - Test Fixtures

private final class DummyEngine: ArbitrageEngine {
    private(set) var isRunning: Bool = false
    private var connectors: [ExchangeConnector] = []

    func register(connector: ExchangeConnector) {
        connectors.append(connector)
    }

    func start() async throws {
        for connector in connectors {
            try await connector.connect()
        }
        isRunning = true
    }

    func stop() async {
        for connector in connectors {
            await connector.disconnect()
        }
        isRunning = false
    }
}

private final class MockConnector: ExchangeConnector, @unchecked Sendable {
    let name: String
    private var status: ConnectionStatus = .disconnected
    private var priceContinuation: AsyncStream<RawPriceData>.Continuation
    private var eventContinuation: AsyncStream<ConnectionEvent>.Continuation
    private let priceStreamStorage: AsyncStream<RawPriceData>
    private let eventStreamStorage: AsyncStream<ConnectionEvent>

    var connectionStatus: ConnectionStatus {
        get async { status }
    }

    var priceUpdates: AsyncStream<RawPriceData> {
        priceStreamStorage
    }

    var connectionEvents: AsyncStream<ConnectionEvent> {
        eventStreamStorage
    }

    init(name: String) {
        self.name = name

        let priceStream = AsyncStream.makeStream(of: RawPriceData.self)
        priceStreamStorage = priceStream.stream
        priceContinuation = priceStream.continuation
        priceContinuation.finish()

        let eventStream = AsyncStream.makeStream(of: ConnectionEvent.self)
        eventStreamStorage = eventStream.stream
        eventContinuation = eventStream.continuation
        eventContinuation.finish()
    }

    func connect() async throws {
        status = .connected
    }

    func disconnect() async {
        status = .disconnected
    }

    func subscribeToPairs(_ pairs: [String]) async throws {
        // no-op in tests
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
