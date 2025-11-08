import Foundation
import CryptoKit
import Utils
import Core

public class TigerBeetleSmokeTests {
    private let persistence1: PersistenceProtocol
    private let persistence2: PersistenceProtocol
    private let logger: StructuredLogger

    public init(
        persistence1: PersistenceProtocol,
        persistence2: PersistenceProtocol,
        logger: StructuredLogger = StructuredLogger()
    ) {
        self.persistence1 = persistence1
        self.persistence2 = persistence2
        self.logger = logger
    }

    public func testExportBalancesDeterministic() throws -> Bool {
        logger.info(component: "SmokeTests", event: "Testing export-balances determinism")

        let tools1 = TigerBeetleCLITools(persistence: persistence1, logger: logger)
        let tools2 = TigerBeetleCLITools(persistence: persistence2, logger: logger)

        let data1 = try tools1.exportBalances()
        let data2 = try tools2.exportBalances()

        let hash1 = SHA256.hash(data: data1)
        let hash2 = SHA256.hash(data: data2)

        let isDeterministic = Data(hash1) == Data(hash2)

        if !isDeterministic {
            logger.error(component: "SmokeTests", event: "Export-balances not deterministic across nodes")
            return false
        }

        logger.info(component: "SmokeTests", event: "Export-balances deterministic test passed")
        return true
    }

    public func testDiffLedgerEmpty(sinceMarker: UUID) throws -> Bool {
        logger.info(component: "SmokeTests", event: "Testing diff-ledger empty check")

        let tools = TigerBeetleCLITools(persistence: persistence1, logger: logger)
        let diff = try tools.diffLedger(sinceID: sinceMarker, limit: 1000)

        if !diff.isEmpty {
            logger.error(
                component: "SmokeTests",
                event: "Diff-ledger not empty after marker",
                data: ["diff_count": String(diff.count)]
            )
            return false
        }

        logger.info(component: "SmokeTests", event: "Diff-ledger empty test passed")
        return true
    }

    public func verifySLOs(
        sloMonitor: SLOMonitor,
        extendedMetrics: TigerBeetleExtendedMetrics
    ) async throws -> (passed: Bool, violations: [String]) {
        logger.info(component: "SmokeTests", event: "Verifying SLOs")

        let metrics = await extendedMetrics.getMetrics()
        var violations: [String] = []

        let p95Latency = metrics.p95Latency
        let totalErrors = metrics.errorsTotal.values.reduce(0, +)
        let totalTransfers = metrics.transfersTotal
        let errorRate = totalTransfers > 0 ? Double(totalErrors) / Double(totalTransfers) : 0.0
        let backlog = metrics.backlogDepth

        if p95Latency > 0.010 {
            violations.append("p95 latency \(p95Latency * 1000)ms exceeds 10ms")
        }

        if p95Latency * 1000 > 100 {
            violations.append("p99 latency exceeds 100ms threshold")
        }

        if backlog > 1000 {
            violations.append("Backlog \(backlog) exceeds 1000")
        }

        if errorRate > 0.005 {
            violations.append("Error rate \(errorRate * 100)% exceeds 0.5%")
        }

        let passed = violations.isEmpty
        logger.info(
            component: "SmokeTests",
            event: passed ? "SLO verification passed" : "SLO verification failed",
            data: [
                "violations": String(violations.count),
                "p95_latency_ms": String(p95Latency * 1000),
                "backlog": String(backlog),
                "error_rate": String(errorRate)
            ]
        )
        return (passed: passed, violations: violations)
    }
}

extension TigerBeetleExtendedMetrics {
    func getBacklogDepth() async -> Int {
        let metrics = await getMetrics()
        return metrics.backlogDepth
    }
}
