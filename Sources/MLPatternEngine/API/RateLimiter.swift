import Foundation
import Utils

public class RateLimiter {
    private let maxRequests: Int
    private let windowSize: TimeInterval
    private var requestCounts: [String: [Date]] = [:]
    private let lock = NSLock()

    public init(maxRequests: Int, windowSize: TimeInterval) {
        self.maxRequests = maxRequests
        self.windowSize = windowSize
    }

    public func checkLimit(for identifier: String) async throws -> Bool {
        return await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }

            let now = Date()
            let windowStart = now.addingTimeInterval(-windowSize)

            // Clean up old requests
            if var requests = requestCounts[identifier] {
                requests = requests.filter { $0 > windowStart }
                requestCounts[identifier] = requests

                // Check if limit exceeded
                if requests.count >= maxRequests {
                    continuation.resume(returning: false)
                    return
                }

                // Add current request
                requests.append(now)
                requestCounts[identifier] = requests
            } else {
                // First request for this identifier
                requestCounts[identifier] = [now]
            }

            continuation.resume(returning: true)
        }
    }

    public func getRemainingRequests(for identifier: String) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let windowStart = now.addingTimeInterval(-windowSize)

        guard let requests = requestCounts[identifier] else {
            return maxRequests
        }

        let validRequests = requests.filter { $0 > windowStart }
        return max(0, maxRequests - validRequests.count)
    }

    public func getResetTime(for identifier: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }

        guard let requests = requestCounts[identifier], !requests.isEmpty else {
            return nil
        }

        let oldestRequest = requests.min() ?? Date()
        return oldestRequest.addingTimeInterval(windowSize)
    }

    public func resetLimit(for identifier: String) {
        lock.lock()
        defer { lock.unlock() }

        requestCounts.removeValue(forKey: identifier)
    }

    public func getStats() -> RateLimitStats {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let windowStart = now.addingTimeInterval(-windowSize)

        var totalRequests = 0
        var activeIdentifiers = 0

        for (_, requests) in requestCounts {
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
    private var requestCounts: [String: [RateLimitEntry]] = [:]
    private let lock = NSLock()

    public init(rules: [RateLimitRule], logger: StructuredLogger) {
        self.rules = rules
        self.logger = logger
    }

    public func checkLimit(for identifier: String, endpoint: String, userRole: String?) async throws -> RateLimitResult {
        return await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }

            let now = Date()

            // Find applicable rule
            guard let rule = findApplicableRule(endpoint: endpoint, userRole: userRole) else {
                continuation.resume(returning: RateLimitResult(allowed: true, remainingRequests: Int.max, resetTime: nil))
                return
            }

            // Clean up old entries
            cleanupOldEntries(for: identifier, now: now)

            // Check current count
            let currentCount = getCurrentCount(for: identifier, rule: rule, now: now)

            if currentCount >= rule.maxRequests {
                logger.warn(component: "AdvancedRateLimiter", event: "Rate limit exceeded", data: [
                    "identifier": identifier,
                    "endpoint": endpoint,
                    "currentCount": String(currentCount),
                    "maxRequests": String(rule.maxRequests)
                ])

                continuation.resume(returning: RateLimitResult(
                    allowed: false,
                    remainingRequests: 0,
                    resetTime: getResetTime(for: identifier, rule: rule, now: now)
                ))
                return
            }

            // Record new request
            recordRequest(for: identifier, now: now)

            continuation.resume(returning: RateLimitResult(
                allowed: true,
                remainingRequests: rule.maxRequests - currentCount - 1,
                resetTime: getResetTime(for: identifier, rule: rule, now: now)
            ))
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

    private func cleanupOldEntries(for identifier: String, now: Date) {
        guard var entries = requestCounts[identifier] else { return }

        entries = entries.filter { entry in
            now.timeIntervalSince(entry.timestamp) <= 3600 // Keep last hour
        }

        requestCounts[identifier] = entries
    }

    private func getCurrentCount(for identifier: String, rule: RateLimitRule, now: Date) -> Int {
        guard let entries = requestCounts[identifier] else { return 0 }

        let windowStart = now.addingTimeInterval(-rule.windowSize)
        return entries.filter { $0.timestamp > windowStart }.count
    }

    private func recordRequest(for identifier: String, now: Date) {
        if requestCounts[identifier] == nil {
            requestCounts[identifier] = []
        }

        requestCounts[identifier]?.append(RateLimitEntry(timestamp: now))
    }

    private func getResetTime(for identifier: String, rule: RateLimitRule, now: Date) -> Date? {
        guard let entries = requestCounts[identifier], !entries.isEmpty else {
            return nil
        }

        let windowStart = now.addingTimeInterval(-rule.windowSize)
        let oldestEntry = entries.filter { $0.timestamp > windowStart }.min { $0.timestamp < $1.timestamp }

        return oldestEntry?.timestamp.addingTimeInterval(rule.windowSize)
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
