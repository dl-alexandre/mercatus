import Foundation
import Synchronization
import Utils

public class RateLimiter {
    private let maxRequests: Int
    private let windowSize: TimeInterval
    private let requestCounts = Mutex([String: [Date]]())

    public init(maxRequests: Int, windowSize: TimeInterval) {
        self.maxRequests = maxRequests
        self.windowSize = windowSize
    }

    public func checkLimit(for identifier: String) async throws -> Bool {
        return await withCheckedContinuation { continuation in
            let now = Date()
            let windowStart = now.addingTimeInterval(-windowSize)

            requestCounts.withLock { counts in
                if var requests = counts[identifier] {
                    requests = requests.filter { $0 > windowStart }
                    counts[identifier] = requests

                    if requests.count >= maxRequests {
                        continuation.resume(returning: false)
                        return
                    }

                    requests.append(now)
                    counts[identifier] = requests
                } else {
                    counts[identifier] = [now]
                }

                continuation.resume(returning: true)
            }
        }
    }

    public func getRemainingRequests(for identifier: String) -> Int {
        let now = Date()
        let windowStart = now.addingTimeInterval(-windowSize)

        return requestCounts.withLock { counts in
            guard let requests = counts[identifier] else {
                return maxRequests
            }

            let validRequests = requests.filter { $0 > windowStart }
            return max(0, maxRequests - validRequests.count)
        }
    }

    public func getResetTime(for identifier: String) -> Date? {
        return requestCounts.withLock { counts in
            guard let requests = counts[identifier], !requests.isEmpty else {
                return nil
            }

            let oldestRequest = requests.min() ?? Date()
            return oldestRequest.addingTimeInterval(windowSize)
        }
    }

    public func resetLimit(for identifier: String) {
        requestCounts.withLock { _ = $0.removeValue(forKey: identifier) }
    }

    public func getStats() -> RateLimitStats {
        let now = Date()
        let windowStart = now.addingTimeInterval(-windowSize)

        return requestCounts.withLock { counts in
            var totalRequests = 0
            var activeIdentifiers = 0

            for (_, requests) in counts {
                let validRequests = requests.filter { $0 > windowStart }
                totalRequests += validRequests.count
                if !validRequests.isEmpty {
                    activeIdentifiers += 1
                }
            }

            return RateLimitStats(
                totalRequests: totalRequests,
                activeIdentifiers: activeIdentifiers,
                maxRequestsPerWindow: maxRequests,
                windowSize: windowSize,
                timestamp: now
            )
        }
    }
}

public struct RateLimitStats {
    public let totalRequests: Int
    public let activeIdentifiers: Int
    public let maxRequestsPerWindow: Int
    public let windowSize: TimeInterval
    public let timestamp: Date
}

public class AdvancedRateLimiter {
    private let rules: [RateLimitRule]
    private let logger: StructuredLogger
    private let requestCounts = Mutex([String: [RateLimitEntry]]())

    public init(rules: [RateLimitRule], logger: StructuredLogger) {
        self.rules = rules
        self.logger = logger
    }

    public func checkLimit(for identifier: String, endpoint: String, userRole: String?) async throws -> RateLimitResult {
        return await withCheckedContinuation { continuation in
            let now = Date()

            guard let rule = findApplicableRule(endpoint: endpoint, userRole: userRole) else {
                continuation.resume(returning: RateLimitResult(allowed: true, remainingRequests: Int.max, resetTime: nil))
                return
            }

            requestCounts.withLock { counts in
                if var entries = counts[identifier] {
                    entries = entries.filter { entry in
                        now.timeIntervalSince(entry.timestamp) <= 3600
                    }
                    counts[identifier] = entries
                }

                let windowStart = now.addingTimeInterval(-rule.windowSize)
                let currentCount = counts[identifier]?.filter { $0.timestamp > windowStart }.count ?? 0

                if currentCount >= rule.maxRequests {
                    logger.warn(component: "AdvancedRateLimiter", event: "Rate limit exceeded", data: [
                        "identifier": identifier,
                        "endpoint": endpoint,
                        "currentCount": String(currentCount),
                        "maxRequests": String(rule.maxRequests)
                    ])

                    let oldestEntry = counts[identifier]?.filter { $0.timestamp > windowStart }.min { $0.timestamp < $1.timestamp }
                    let resetTime = oldestEntry?.timestamp.addingTimeInterval(rule.windowSize)

                    continuation.resume(returning: RateLimitResult(
                        allowed: false,
                        remainingRequests: 0,
                        resetTime: resetTime
                    ))
                    return
                }

                if counts[identifier] == nil {
                    counts[identifier] = []
                }
                counts[identifier]?.append(RateLimitEntry(timestamp: now))

                let oldestEntry = counts[identifier]?.filter { $0.timestamp > windowStart }.min { $0.timestamp < $1.timestamp }
                let resetTime = oldestEntry?.timestamp.addingTimeInterval(rule.windowSize)

                continuation.resume(returning: RateLimitResult(
                    allowed: true,
                    remainingRequests: rule.maxRequests - currentCount - 1,
                    resetTime: resetTime
                ))
            }
        }
    }

    private func findApplicableRule(endpoint: String, userRole: String?) -> RateLimitRule? {
        // Find most specific rule first
        for rule in rules.sorted(by: { $0.priority > $1.priority }) {
            if rule.matches(endpoint: endpoint, userRole: userRole) {
                return rule
            }
        }
        return nil
    }

}

public struct RateLimitRule {
    public let name: String
    public let maxRequests: Int
    public let windowSize: TimeInterval
    public let endpointPattern: String?
    public let userRoles: [String]?
    public let priority: Int

    public init(name: String, maxRequests: Int, windowSize: TimeInterval, endpointPattern: String? = nil, userRoles: [String]? = nil, priority: Int = 0) {
        self.name = name
        self.maxRequests = maxRequests
        self.windowSize = windowSize
        self.endpointPattern = endpointPattern
        self.userRoles = userRoles
        self.priority = priority
    }

    public func matches(endpoint: String, userRole: String?) -> Bool {
        // Check endpoint pattern
        if let pattern = endpointPattern {
            if !endpoint.contains(pattern) {
                return false
            }
        }

        // Check user role
        if let roles = userRoles {
            guard let role = userRole else { return false }
            if !roles.contains(role) {
                return false
            }
        }

        return true
    }
}

public struct RateLimitEntry {
    public let timestamp: Date

    public init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

public struct RateLimitResult {
    public let allowed: Bool
    public let remainingRequests: Int
    public let resetTime: Date?

    public init(allowed: Bool, remainingRequests: Int, resetTime: Date?) {
        self.allowed = allowed
        self.remainingRequests = remainingRequests
        self.resetTime = resetTime
    }
}
