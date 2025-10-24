import Utils

public protocol ExchangeConnector: Sendable {
    var name: String { get }
    var connectionStatus: ConnectionStatus { get async }
    var priceUpdates: AsyncStream<RawPriceData> { get }
    var connectionEvents: AsyncStream<ConnectionEvent> { get }

    func connect() async throws
    func disconnect() async
    func subscribeToPairs(_ pairs: [String]) async throws
}
