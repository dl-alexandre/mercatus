import Foundation
import Utils

public class TigerBeetleCLITools {
    private let persistence: PersistenceProtocol
    private let logger: StructuredLogger

    public init(persistence: PersistenceProtocol, logger: StructuredLogger = StructuredLogger()) {
        self.persistence = persistence
        self.logger = logger
    }

    public func exportLedger(sinceID: UUID? = nil, limit: Int? = nil) throws -> Data {
        let transactions = try persistence.getTransactions(
            exchange: nil,
            asset: nil,
            type: nil,
            limit: limit
        )

        let filtered = if let sinceID = sinceID {
            transactions.filter { $0.id != sinceID }
        } else {
            transactions
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(filtered)
    }

    public func exportBalances() throws -> Data {
        let accounts = try persistence.getAllAccounts()

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(accounts)
    }

    public func diffLedger(sinceID: UUID, limit: Int = 1000) throws -> [InvestmentTransaction] {
        let allTransactions = try persistence.getTransactions(
            exchange: nil,
            asset: nil,
            type: nil,
            limit: nil
        )

        guard let sinceIndex = allTransactions.firstIndex(where: { $0.id == sinceID }) else {
            return Array(allTransactions.prefix(limit))
        }

        let remaining = allTransactions.prefix(sinceIndex)
        return Array(remaining.prefix(limit))
    }

    public func replayAndVerify(transactions: [InvestmentTransaction]) throws -> Bool {
        let client = InMemoryTigerBeetleClient()
        let replayPersistence = TigerBeetlePersistence(client: client)

        var checksums: [String: Double] = [:]

        for tx in transactions {
            let key = "\(tx.exchange):\(tx.asset)"
            checksums[key, default: 0] += tx.quantity

            try replayPersistence.saveTransaction(tx)
        }

        let accounts = try replayPersistence.getAllAccounts()
        var finalBalances: [String: Double] = [:]

        for account in accounts {
            let key = "\(account.exchange):\(account.asset)"
            finalBalances[key] = account.total
        }

        for (key, expected) in checksums {
            let actual = finalBalances[key] ?? 0
            if abs(actual - expected) > 1e-8 {
                logger.error(
                    component: "TigerBeetleCLITools",
                    event: "Replay verification failed",
                    data: [
                        "account": key,
                        "expected": String(expected),
                        "actual": String(actual),
                        "drift": String(abs(actual - expected))
                    ]
                )
                return false
            }
        }

        return true
    }
}
