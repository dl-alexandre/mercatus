import Foundation

public final class LRU<Key: Hashable, Value> {
    private var cache: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private let capacity: Int

    private class Node {
        var key: Key
        var value: Value
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    public init(capacity: Int = 1000) {
        self.capacity = capacity
    }

    public func get(_ key: Key) -> Value? {
        guard let node = cache[key] else { return nil }
        moveToHead(node)
        return node.value
    }

    public func put(_ key: Key, _ value: Value) {
        if let node = cache[key] {
            node.value = value
            moveToHead(node)
        } else {
            let newNode = Node(key: key, value: value)
            if cache.count >= capacity {
                if let oldTail = tail {
                    cache.removeValue(forKey: oldTail.key)
                    removeTail()
                }
            }
            cache[key] = newNode
            addToHead(newNode)
        }
    }

    public func clear() {
        cache.removeAll()
        head = nil
        tail = nil
    }

    private func moveToHead(_ node: Node) {
        removeNode(node)
        addToHead(node)
    }

    private func addToHead(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil {
            tail = node
        }
    }

    private func removeTail() {
        guard let oldTail = tail else { return }
        if let prev = oldTail.prev {
            prev.next = nil
            tail = prev
        } else {
            head = nil
            tail = nil
        }
    }

    private func removeNode(_ node: Node) {
        if let prev = node.prev {
            prev.next = node.next
        } else {
            head = node.next
        }
        if let next = node.next {
            next.prev = node.prev
        } else {
            tail = node.prev
        }
    }
}

public actor CharacterWidthCache {
    private var cache: LRU<String, Int> = LRU(capacity: 1000)
    private var currentEnv: TerminalEnv?

    public init() {}

    public func width(of grapheme: Substring, env: TerminalEnv) -> Int {
        if currentEnv != env {
            cache.clear()
            currentEnv = env
        }

        let key = String(grapheme)
        if let cached = cache.get(key) {
            Task {
                await TUIMetrics.shared.recordWidthCacheHit()
            }
            return cached
        }

        Task {
            await TUIMetrics.shared.recordWidthCacheMiss()
        }
        let width = calculateWidth(grapheme, env: env)
        cache.put(key, width)
        return width
    }

    private func calculateWidth(_ grapheme: Substring, env: TerminalEnv) -> Int {
        let string = String(grapheme)

        if string.isEmpty {
            return 0
        }

        if string.utf8.allSatisfy({ $0 < 128 }) {
            return string.count
        }

        var width = 0
        var iter = string.unicodeScalars.makeIterator()

        while let scalar = iter.next() {
            let codePoint = scalar.value

            if codePoint == 0 {
                continue
            }

            if (0x0001...0x001F).contains(codePoint) || (0x007F...0x009F).contains(codePoint) {
                continue
            }

            if (0x0300...0x036F).contains(codePoint) {
                continue
            }

            if (0x200B...0x200D).contains(codePoint) {
                continue
            }

            if (0xFE00...0xFE0F).contains(codePoint) {
                continue
            }

            if env.cjk {
                if ((0x1100...0x115F).contains(codePoint) ||
                    (0x2329...0x232A).contains(codePoint) ||
                    (0x2E80...0x2FFF).contains(codePoint) ||
                    (0x3000...0x303F).contains(codePoint) ||
                    (0x3040...0x4DBF).contains(codePoint) ||
                    (0x4E00...0x9FFF).contains(codePoint) ||
                    (0xA000...0xA4CF).contains(codePoint) ||
                    (0xAC00...0xD7A3).contains(codePoint) ||
                    (0xF900...0xFAFF).contains(codePoint) ||
                    (0xFE30...0xFE4F).contains(codePoint) ||
                    (0xFE50...0xFE6F).contains(codePoint) ||
                    (0xFF00...0xFFEF).contains(codePoint) ||
                    (0x20000...0x2FFFD).contains(codePoint) ||
                    (0x30000...0x3FFFD).contains(codePoint)) {
                    width += 2
                    continue
                }
            }

            width += 1
        }

        return width
    }
}
