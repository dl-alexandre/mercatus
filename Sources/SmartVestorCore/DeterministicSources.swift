import Foundation

public struct FixedSeedRNG: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64 = 42) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &* 1103515245 &+ 12345
        return state
    }
}

public struct FixedClock {
    private var baseTime: Date
    private var increment: TimeInterval

    public init(baseTime: Date = Date(timeIntervalSince1970: 0), increment: TimeInterval = 1.0) {
        self.baseTime = baseTime
        self.increment = increment
    }

    public mutating func now() -> Date {
        let result = baseTime
        baseTime = baseTime.addingTimeInterval(increment)
        return result
    }
}

public struct DeterministicUUIDGenerator {
    private var counter: UInt64

    public init(startingCounter: UInt64 = 0) {
        self.counter = startingCounter
    }

    public mutating func generate() -> UUID {
        let bytes = withUnsafeBytes(of: counter.bigEndian) { Array($0) }
        var uuidBytes: [UInt8] = Array(repeating: 0, count: 16)
        let prefixCount = min(8, bytes.count)
        for i in 0..<prefixCount {
            uuidBytes[i] = bytes[i]
        }
        uuidBytes[8] = 0x40
        uuidBytes[9] = 0x80
        counter += 1
        let uuidTuple: uuid_t = (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        )
        return UUID(uuid: uuidTuple)
    }
}
