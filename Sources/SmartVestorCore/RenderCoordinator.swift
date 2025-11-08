import Foundation

public actor RenderCoordinator {
    private var isRendering = false
    private var pendingRender: (() async -> Void)?
    private var renderQueue: [() async -> Void] = []

    public init() {}

    public func coordinate(_ render: @escaping @Sendable () async -> Void) async {
        if isRendering {
            renderQueue.append(render)
            return
        }

        isRendering = true
        defer {
            isRendering = false
            processNext()
        }

        await render()
    }

    private func processNext() {
        guard !isRendering, !renderQueue.isEmpty else { return }

        let next = renderQueue.removeFirst()
        isRendering = true

        Task {
            defer {
                Task { @Sendable in
                    await self.markRenderingComplete()
                }
            }
            await next()
        }
    }

    private func markRenderingComplete() async {
        isRendering = false
        if !renderQueue.isEmpty {
            processNext()
        }
    }

    public func reset() async {
        isRendering = false
        renderQueue.removeAll()
        pendingRender = nil
    }
}
