import Foundation
import NIOCore
import NIOPosix

public final class TUIServer: @unchecked Sendable {
    private let socketPath: String
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?
    private var clients: [ObjectIdentifier: Channel] = [:]
    private let clientsQueue = DispatchQueue(label: "com.smartvestor.tui.clients")
    private var sequence: Int64 = 0
    private var lastPayload: Data?

    public init(socketPath: String = "/tmp/smartvestor-tui.sock") {
        self.socketPath = socketPath
    }

    public func start() async throws {
        try? FileManager.default.removeItem(atPath: socketPath)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = group

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [weak self] channel in
                guard let self = self else { return channel.eventLoop.makeSucceededFuture(()) }
                return channel.pipeline.addHandler(TUIClientHandler(server: self))
            }

        let channel = try await bootstrap.bind(unixDomainSocketPath: socketPath).get()
        self.serverChannel = channel
    }

    public func stop() async {
        try? await serverChannel?.close()
        if let group = eventLoopGroup {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
        }
        try? FileManager.default.removeItem(atPath: socketPath)
        clientsQueue.sync { clients.removeAll() }
    }

    public func register(client: Channel) {
        clientsQueue.sync { clients[ObjectIdentifier(client)] = client }
        if let payload = lastPayload {
            var buffer = client.allocator.buffer(capacity: payload.count + 1)
            buffer.writeBytes(payload)
            buffer.writeInteger(UInt8(10))
            client.writeAndFlush(buffer, promise: nil)
        }
    }

    public func unregister(client: Channel) {
        _ = clientsQueue.sync { clients.removeValue(forKey: ObjectIdentifier(client)) }
    }

    func getLastPayload() -> Data? {
        return lastPayload
    }

    public func publish(type: TUIUpdate.UpdateType, state: AutomationState, data: TUIData) {
        sequence &+= 1
        let update = TUIUpdate(type: type, state: state, data: data, sequenceNumber: sequence)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(update) else { return }
        lastPayload = payload
        let snapshot: [Channel] = clientsQueue.sync { Array(clients.values) }
        for channel in snapshot {
            var buffer = channel.allocator.buffer(capacity: payload.count + 1)
            buffer.writeBytes(payload)
            buffer.writeInteger(UInt8(10))
            channel.writeAndFlush(buffer, promise: nil)
        }
    }
}

final class TUIClientHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let server: TUIServer

    init(server: TUIServer) {
        self.server = server
    }

    func channelActive(context: ChannelHandlerContext) {
        server.register(client: context.channel)
    }

    func channelInactive(context: ChannelHandlerContext) {
        server.unregister(client: context.channel)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = self.unwrapInboundIn(data)
        if let bytes = buffer.readBytes(length: buffer.readableBytes), let text = String(bytes: bytes, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased() == "PING" {
                if let payload = server.getLastPayload() {
                    var out = context.channel.allocator.buffer(capacity: payload.count + 1)
                    out.writeBytes(payload)
                    out.writeInteger(UInt8(10))
                    context.channel.writeAndFlush(out, promise: nil)
                }
            }
        }
    }
}
