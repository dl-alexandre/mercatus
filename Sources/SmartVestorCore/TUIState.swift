import Foundation
import Core

@propertyWrapper
public final class TUIState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    private var streamContinuation: AsyncStream<RenderIntent>.Continuation?
    private var rootBuilder: (() -> TUIRenderable)?

    public var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            let changed: Bool
            var continuation: AsyncStream<RenderIntent>.Continuation?
            var builder: (() -> TUIRenderable)?

            lock.lock()
            if let oldValue = _value as? AnyHashable,
               let newValue = newValue as? AnyHashable {
                changed = oldValue != newValue
            } else {
                changed = true
            }
            _value = newValue
            continuation = streamContinuation
            builder = rootBuilder
            lock.unlock()

            if changed, let cont = continuation, let buildRoot = builder {
                let root = buildRoot()
                let intent = RenderIntent(root: root, priority: .normal)
                cont.yield(intent)
            }
        }
    }

    public var projectedValue: TUIState<Value> {
        return self
    }

    public init(wrappedValue: Value) {
        self._value = wrappedValue
    }

    public func setRootBuilder(_ builder: @escaping () -> TUIRenderable) {
        lock.lock()
        defer { lock.unlock() }
        rootBuilder = builder
    }

    public func intentStream() -> AsyncStream<RenderIntent> {
        AsyncStream { continuation in
            lock.lock()
            streamContinuation = continuation
            let builder = rootBuilder
            lock.unlock()

            if let buildRoot = builder {
                let root = buildRoot()
                let intent = RenderIntent(root: root, priority: .normal)
                continuation.yield(intent)
            }
        }
    }

    public func bind(to reconciler: TUIReconciler, rootBuilder: @escaping @Sendable () -> TUIRenderable) {
        setRootBuilder(rootBuilder)

        Task {
            for await intent in intentStream() {
                await reconciler.submit(intent: intent)
            }
        }
    }
}
