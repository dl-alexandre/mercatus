import Foundation
import Utils

public enum OrderSide: String, CaseIterable, Sendable {
    case buy = "BUY"
    case sell = "SELL"
}

public enum OrderType: String, CaseIterable, Sendable {
    case market = "MARKET"
    case limit = "LIMIT"
    case stop = "STOP"
    case stopLimit = "STOP_LIMIT"
}

public struct OrderBook: Sendable {
    public let bids: [OrderBookEntry]
    public let asks: [OrderBookEntry]

    public init(bids: [OrderBookEntry], asks: [OrderBookEntry]) {
        self.bids = bids
        self.asks = asks
    }
}

public struct OrderBookEntry: Sendable {
    public let price: Double
    public let quantity: Double

    public init(price: Double, quantity: Double) {
        self.price = price
        self.quantity = quantity
    }
}

public struct Transaction: Sendable {
    public let id: String
    public let type: TransactionType
    public let asset: String
    public let quantity: Double
    public let price: Double
    public let timestamp: Date

    public init(id: String, type: TransactionType, asset: String, quantity: Double, price: Double, timestamp: Date) {
        self.id = id
        self.type = type
        self.asset = asset
        self.quantity = quantity
        self.price = price
        self.timestamp = timestamp
    }
}

public enum TransactionType: String, CaseIterable, Sendable {
    case buy = "BUY"
    case sell = "SELL"
    case deposit = "DEPOSIT"
    case withdrawal = "WITHDRAWAL"
}

public struct Order: Sendable {
    public let id: String
    public let symbol: String
    public let side: OrderSide
    public let type: OrderType
    public let quantity: Double
    public let price: Double
    public let status: OrderStatus
    public let timestamp: Date

    public init(id: String, symbol: String, side: OrderSide, type: OrderType, quantity: Double, price: Double, status: OrderStatus, timestamp: Date) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.type = type
        self.quantity = quantity
        self.price = price
        self.status = status
        self.timestamp = timestamp
    }
}

public enum OrderStatus: String, CaseIterable, Sendable {
    case pending = "PENDING"
    case filled = "FILLED"
    case cancelled = "CANCELLED"
    case rejected = "REJECTED"
}

public protocol ExchangeConnector: Sendable {
    var name: String { get }
    var connectionStatus: ConnectionStatus { get async }
    var priceUpdates: AsyncStream<RawPriceData> { get }
    var connectionEvents: AsyncStream<ConnectionEvent> { get }

    func connect() async throws
    func disconnect() async
    func subscribeToPairs(_ pairs: [String]) async throws
    func getOrderBook(symbol: String) async throws -> OrderBook
    func getRecentTransactions(limit: Int) async throws -> [Transaction]
    func placeOrder(symbol: String, side: OrderSide, type: OrderType, quantity: Double, price: Double) async throws -> Order
}

public typealias ExchangeConnectorProtocol = ExchangeConnector
