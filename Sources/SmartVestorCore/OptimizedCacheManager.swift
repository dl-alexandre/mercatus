import Foundation
import Compression
import Utils

#if canImport(Compression)
import Compression
#endif

actor OptimizedCacheManager {
    struct CacheEntry {
        let data: Any
        let compressedData: Data?
        let timestamp: Date
        let accessCount: Int

        var age: TimeInterval {
            Date().timeIntervalSince(timestamp)
        }

        var isExpired: Bool {
            age > 7 * 24 * 60 * 60
        }
    }

    private var cache: [String: CacheEntry] = [:]
    private let maxEntries = 50
    private let ttl: TimeInterval = 7 * 24 * 60 * 60
    private let logger: StructuredLogger

    init(logger: StructuredLogger) {
        self.logger = logger
    }

    func get<T>(_ key: String) -> T? {
        guard var entry = cache[key] else {
            return nil
        }

        if entry.isExpired {
            cache.removeValue(forKey: key)
            logger.debug(component: "OptimizedCacheManager", event: "Cache entry expired", data: ["key": key])
            return nil
        }

        entry = CacheEntry(
            data: entry.data,
            compressedData: entry.compressedData,
            timestamp: entry.timestamp,
            accessCount: entry.accessCount + 1
        )
        cache[key] = entry

        if let compressed = entry.compressedData {
            return decompress(compressed) as? T
        }

        return entry.data as? T
    }

    nonisolated func getSendable<T: Sendable>(_ key: String) async -> T? {
        return await get(key)
    }

    func set(_ key: String, value: Any, compress: Bool = true) {
        let compressedData: Data?
        if compress, let array = value as? [Any] {
            compressedData = compressData(array)
        } else {
            compressedData = nil
        }

        let entry = CacheEntry(
            data: value,
            compressedData: compressedData,
            timestamp: Date(),
            accessCount: 0
        )

        cache[key] = entry

        evictIfNeeded()
    }

    private func evictIfNeeded() {
        guard cache.count > maxEntries else { return }

        let sorted = cache.sorted { $0.value.accessCount < $1.value.accessCount }
        let toEvict = sorted.prefix(cache.count - maxEntries)

        for (key, _) in toEvict {
            cache.removeValue(forKey: key)
        }

        logger.debug(component: "OptimizedCacheManager", event: "Evicted cache entries", data: ["count": String(toEvict.count)])
    }

    func clearExpired() {
        let expired = cache.filter { $0.value.isExpired }
        for key in expired.keys {
            cache.removeValue(forKey: key)
        }
        if !expired.isEmpty {
            logger.debug(component: "OptimizedCacheManager", event: "Cleared expired entries", data: ["count": String(expired.count)])
        }
    }

    func prewarm(keys: [String], loader: @Sendable (String) async throws -> Any?) async {
        for key in keys {
            if cache[key] == nil {
                if let value = try? await loader(key) {
                    set(key, value: value)
                }
            }
        }
    }

    private func compressData(_ data: [Any]) -> Data? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else {
            return nil
        }

        return jsonData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }

            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: jsonData.count)
            defer { buffer.deallocate() }

            let compressedSize = compression_encode_buffer(
                buffer,
                jsonData.count,
                baseAddress,
                jsonData.count,
                nil,
                COMPRESSION_LZFSE
            )

            guard compressedSize > 0 else { return nil }

            return Data(bytes: buffer, count: compressedSize)
        }
    }

    private func decompress(_ data: Data) -> Any? {
        return data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }

            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count * 4)
            defer { buffer.deallocate() }

            let decompressedSize = compression_decode_buffer(
                buffer,
                data.count * 4,
                baseAddress,
                data.count,
                nil,
                COMPRESSION_LZFSE
            )

            guard decompressedSize > 0 else { return nil }

            let decompressedData = Data(bytes: buffer, count: decompressedSize)
            return try? JSONSerialization.jsonObject(with: decompressedData)
        }
    }
}
