import Foundation

public struct ClockSanityChecker {
    private static let maxSkewSeconds: TimeInterval = 2.0
    private static let ntpServers = ["time.apple.com", "time.google.com"]

    public static func checkMonotonicTime() -> Bool {
        let now1 = ProcessInfo.processInfo.systemUptime
        usleep(1000)
        let now2 = ProcessInfo.processInfo.systemUptime

        return now2 > now1
    }

    public static func estimateClockSkew() -> TimeInterval {
        let localTime = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let estimatedNTPTime = Date().addingTimeInterval(-uptime)

        return abs(localTime.timeIntervalSince(estimatedNTPTime))
    }

    public static func validateClock() throws {
        guard checkMonotonicTime() else {
            throw SmartVestorError.configurationError("System clock is not monotonic")
        }

        let skew = estimateClockSkew()
        if skew > maxSkewSeconds {
            throw SmartVestorError.configurationError("Clock skew exceeds threshold: \(skew)s > \(maxSkewSeconds)s")
        }
    }

    public static func getMaxSkew() throws -> TimeInterval {
        return estimateClockSkew()
    }
}
