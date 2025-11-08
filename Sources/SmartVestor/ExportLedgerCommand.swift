import Foundation
import ArgumentParser
import SmartVestor

public struct ExportLedgerCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "export-ledger",
        abstract: "Export ledger transactions to JSON"
    )

    public init() {}

    @Option(name: .shortAndLong, help: "Export transactions since this ID")
    var sinceID: String?

    @Option(name: .shortAndLong, help: "Maximum number of transactions to export")
    var limit: Int?

    @Option(name: .shortAndLong, help: "Output file path")
    var output: String = "ledger_export.json"

    public func run() async throws {
        let config = try SmartVestorConfigurationManager().currentConfig
        let persistence = try SmartVestorConfigurationManager().createPersistence()
        try persistence.initialize()

        let tools = TigerBeetleCLITools(persistence: persistence)

        let sinceUUID = sinceID.flatMap { UUID(uuidString: $0) }
        let ledgerData = try tools.exportLedger(sinceID: sinceUUID, limit: limit)

        try ledgerData.write(to: URL(fileURLWithPath: output))
        print("Exported ledger to \(output)")
    }
}

public struct ExportBalancesCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "export-balances",
        abstract: "Export account balances to JSON"
    )

    public init() {}

    @Option(name: .shortAndLong, help: "Output file path")
    var output: String = "balances_export.json"

    public func run() async throws {
        let persistence = try SmartVestorConfigurationManager().createPersistence()
        try persistence.initialize()

        let tools = TigerBeetleCLITools(persistence: persistence)
        let balancesData = try tools.exportBalances()

        try balancesData.write(to: URL(fileURLWithPath: output))
        print("Exported balances to \(output)")
    }
}

public struct DiffLedgerCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "diff-ledger",
        abstract: "Get ledger differences since a transaction ID"
    )

    public init() {}

    @Argument(help: "Transaction ID to diff since")
    var sinceID: String

    @Option(name: .shortAndLong, help: "Maximum number of transactions")
    var limit: Int = 1000

    public func run() async throws {
        guard let sinceUUID = UUID(uuidString: sinceID) else {
            throw SmartVestorError.validationError("Invalid UUID format: \(sinceID)")
        }

        let persistence = try SmartVestorConfigurationManager().createPersistence()
        try persistence.initialize()

        let tools = TigerBeetleCLITools(persistence: persistence)
        let diff = try tools.diffLedger(sinceID: sinceUUID, limit: limit)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(diff)

        print(String(data: data, encoding: .utf8) ?? "")
    }
}

public struct ReplayVerifyCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "replay",
        abstract: "Replay transactions and verify correctness"
    )

    public init() {}

    @Flag(name: .shortAndLong, help: "Verify replay results")
    var verify: Bool = false

    @Argument(help: "Input ledger file")
    var inputFile: String

    public func run() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: inputFile))
        let transactions = try JSONDecoder().decode([InvestmentTransaction].self, from: data)

        let persistence = try SmartVestorConfigurationManager().createPersistence()
        try persistence.initialize()

        let tools = TigerBeetleCLITools(persistence: persistence)

        if verify {
            let isValid = try tools.replayAndVerify(transactions: transactions)
            if isValid {
                print("Replay verification passed")
            } else {
                throw SmartVestorError.validationError("Replay verification failed")
            }
        } else {
            for tx in transactions {
                try persistence.saveTransaction(tx)
            }
            print("Replayed \(transactions.count) transactions")
        }
    }
}
