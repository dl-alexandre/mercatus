import Foundation

public struct StatusView: TUIView {
    @TUIState private var uptime: String

    public init(uptime: String = "0:00") {
        self._uptime = TUIState(wrappedValue: uptime)
    }

    public var body: VStack {
        let statusText = Text("System Status")
        let uptimeText = Text(uptime)
        return VStack(content: {
            statusText
            uptimeText
        })
    }

    public var uptimeValue: String {
        _uptime.wrappedValue
    }

    public func updateUptime(_ newUptime: String) {
        _uptime.wrappedValue = newUptime
    }

    public func bind(to reconciler: TUIReconciler) {
        let builder: @Sendable () -> TUIRenderable = {
            StatusView(uptime: self._uptime.wrappedValue).body
        }
        _uptime.bind(to: reconciler, rootBuilder: builder)
    }
}
