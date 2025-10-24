import Foundation

/// Represents raw price data emitted by an exchange feed.
public struct RawPriceData: Sendable, Codable, Equatable {
    public let exchange: String
    public let symbol: String
    public let bid: Decimal
    public let ask: Decimal
    public let timestamp: Date

    public init(exchange: String, symbol: String, bid: Decimal, ask: Decimal, timestamp: Date) {
        self.exchange = exchange
        self.symbol = symbol
        self.bid = bid
        self.ask = ask
        self.timestamp = timestamp
    }
}

/// Lifecycle indicator for any connector maintaining an exchange session.
public enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(reason: String)
}

/// Envelope describing discrete connection events.
public enum ConnectionEvent: Sendable, Equatable {
    case statusChanged(ConnectionStatus)
    case receivedHeartbeat(Date)
    case disconnected(reason: String?)
}
