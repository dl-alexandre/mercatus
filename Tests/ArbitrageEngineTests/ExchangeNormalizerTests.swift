import Foundation
import Testing
@testable import Core
import Utils

@Suite
struct ExchangeNormalizerTests {
    @Test
    func normalizeRoundsToEightDecimalPlaces() async throws {
        let now = Date()
        let raw = RawPriceData(
            exchange: "Binance",
            symbol: "BTC-USD",
            bid: Decimal(string: "43210.123456789")!,
            ask: Decimal(string: "43211.987654321")!,
            timestamp: now
        )

        let normalizer = ExchangeNormalizer(
            now: { now },
            monotonicNow: { 1.0 }
        )

        let normalizedOptional = await normalizer.normalize(raw)
        let normalized = try #require(normalizedOptional)
        #expect(normalized.bid == Decimal(string: "43210.12345679"))
        #expect(normalized.ask == Decimal(string: "43211.98765432"))
        #expect(abs(normalized.normalizedTime - 1.0) < 1e-9)
    }

    @Test
    func normalizeFiltersStaleData() async {
        let reference = Date()
        let staleTimestamp = reference.addingTimeInterval(-10)
        let config = ExchangeNormalizer.Configuration(staleInterval: 2.0, minimumGap: 0.001)
        let normalizer = ExchangeNormalizer(
            config: config,
            now: { reference },
            monotonicNow: { 0.0 }
        )

        let staleQuote = RawPriceData(
            exchange: "Coinbase",
            symbol: "ETH-USD",
            bid: 1800,
            ask: 1801,
            timestamp: staleTimestamp
        )

        let normalized = await normalizer.normalize(staleQuote)
        #expect(normalized == nil)
    }

    @Test
    func normalizedTimestampsAreMonotonicPerInstrument() async throws {
        let reference = Date()
        let generator = TimeGenerator(times: [5.0, 5.0, 5.002])
        let config = ExchangeNormalizer.Configuration(staleInterval: 5.0, minimumGap: 0.001)
        let normalizer = ExchangeNormalizer(
            config: config,
            now: { reference },
            monotonicNow: { generator.next() }
        )

        let quoteA = RawPriceData(
            exchange: "Binance",
            symbol: "SOL-USD",
            bid: 20,
            ask: 21,
            timestamp: reference
        )

        let quoteB = RawPriceData(
            exchange: "Binance",
            symbol: "SOL-USD",
            bid: 20.5,
            ask: 21.5,
            timestamp: reference
        )

        let normalizedAValue = await normalizer.normalize(quoteA)
        let normalizedBValue = await normalizer.normalize(quoteB)
        let normalizedA = try #require(normalizedAValue)
        let normalizedB = try #require(normalizedBValue)

        #expect(normalizedB.normalizedTime > normalizedA.normalizedTime)
        let delta = normalizedB.normalizedTime - normalizedA.normalizedTime
        #expect(abs(delta - 0.001) < 1e-9)
    }
}

private final class TimeGenerator: @unchecked Sendable {
    private let times: [TimeInterval]
    private var index = 0
    private let lock = NSLock()

    init(times: [TimeInterval]) {
        self.times = times
    }

    func next() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }

        guard index < times.count else {
            return times.last ?? 0
        }

        let value = times[index]
        index += 1
        return value
    }
}
