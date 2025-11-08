import Foundation
import ArgumentParser
import SmartVestor

public struct TUIDataCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "tui-data",
        abstract: "Export TUI data to TSV or CSV format"
    )

    public init() {}

    @Option(name: .shortAndLong, help: "Output format: tsv or csv")
    var format: String = "tsv"

    @Option(name: .shortAndLong, help: "Output file path (default: stdout)")
    var output: String?

    @Flag(name: .long, help: "Include balances")
    var balances: Bool = false

    @Flag(name: .long, help: "Include transactions")
    var transactions: Bool = false

    @Flag(name: .long, help: "Include prices")
    var prices: Bool = false

    @Flag(name: .long, help: "Include swap evaluations")
    var swaps: Bool = false

    @Option(name: .long, help: "Limit number of records")
    var limit: Int?

    public func run() async throws {
        let persistence = try createPersistence()
        try persistence.initialize()
        try persistence.migrate()

        let delimiter: String
        switch format.lowercased() {
        case "csv":
            delimiter = ","
        case "tsv":
            delimiter = "\t"
        default:
            throw ExitCode.failure
        }

        var outputLines: [String] = []

        if balances {
            let accounts = try persistence.getAllAccounts()
            outputLines.append("Type\(delimiter)Exchange\(delimiter)Asset\(delimiter)Available\(delimiter)Pending\(delimiter)Staked\(delimiter)Total\(delimiter)UpdatedAt")
            let limited = limit.map { Array(accounts.prefix($0)) } ?? accounts
            for account in limited {
                let line = "balance\(delimiter)\(account.exchange)\(delimiter)\(account.asset)\(delimiter)\(account.available)\(delimiter)\(account.pending)\(delimiter)\(account.staked)\(delimiter)\(account.total)\(delimiter)\(ISO8601DateFormatter().string(from: account.updatedAt))"
                outputLines.append(line)
            }
        }

        if transactions {
            let txns = try persistence.getTransactions(exchange: nil, asset: nil, type: nil, limit: limit)
            outputLines.append("Type\(delimiter)ID\(delimiter)Exchange\(delimiter)Asset\(delimiter)Quantity\(delimiter)Price\(delimiter)Timestamp")
            for txn in txns {
                let line = "transaction\(delimiter)\(txn.id.uuidString)\(delimiter)\(txn.exchange)\(delimiter)\(txn.asset)\(delimiter)\(txn.quantity)\(delimiter)\(txn.price)\(delimiter)\(ISO8601DateFormatter().string(from: txn.timestamp))"
                outputLines.append(line)
            }
        }

        if prices {
            let provider = MultiProviderMarketDataProvider()
            let accounts = try persistence.getAllAccounts()
            let symbols = Array(Set(accounts.map { $0.asset }))
            if !symbols.isEmpty {
                let prices = try? await provider.getCurrentPrices(symbols: symbols)
                outputLines.append("Type\(delimiter)Symbol\(delimiter)Price\(delimiter)Timestamp")
                if let prices = prices {
                    for (symbol, price) in prices.sorted(by: { $0.key < $1.key }) {
                        let line = "price\(delimiter)\(symbol)\(delimiter)\(price)\(delimiter)\(ISO8601DateFormatter().string(from: Date()))"
                        outputLines.append(line)
                    }
                }
            }
        }

        if swaps {
            let accounts = try persistence.getAllAccounts()
            let provider = MultiProviderMarketDataProvider()
            let symbols = Array(Set(accounts.map { $0.asset }))
            let prices = try? await provider.getCurrentPrices(symbols: symbols) ?? [:]

            outputLines.append("Type\(delimiter)FromAsset\(delimiter)ToAsset\(delimiter)FromQuantity\(delimiter)EstimatedToQuantity\(delimiter)NetValue\(delimiter)IsWorthwhile\(delimiter)Confidence\(delimiter)Exchange\(delimiter)Timestamp")

            let holdings = accounts.map { holding in
                Holding(
                    exchange: holding.exchange,
                    asset: holding.asset,
                    available: holding.available,
                    pending: holding.pending,
                    staked: holding.staked,
                    updatedAt: holding.updatedAt
                )
            }

            let swapEvaluations = generateSwapEvaluations(balances: holdings, prices: prices ?? [:])
            let limited = limit.map { Array(swapEvaluations.prefix($0)) } ?? swapEvaluations

            for eval in limited {
                let line = "swap\(delimiter)\(eval.fromAsset)\(delimiter)\(eval.toAsset)\(delimiter)\(eval.fromQuantity)\(delimiter)\(eval.estimatedToQuantity)\(delimiter)\(eval.netValue)\(delimiter)\(eval.isWorthwhile)\(delimiter)\(eval.confidence)\(delimiter)\(eval.exchange)\(delimiter)\(ISO8601DateFormatter().string(from: eval.timestamp))"
                outputLines.append(line)
            }
        }

        let outputText = outputLines.joined(separator: "\n") + "\n"

        if let outputPath = output {
            try outputText.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            print("Exported \(outputLines.count - 1) records to \(outputPath)")
        } else {
            print(outputText, terminator: "")
        }
    }

    private func generateSwapEvaluations(balances: [Holding], prices: [String: Double]) -> [SwapEvaluation] {
        let excludedAssets: Set<String> = ["USD", "USDC", "CASH"]
        let tradable = balances.filter { !excludedAssets.contains($0.asset.uppercased()) && (prices[$0.asset] ?? 0) > 0 }
        guard tradable.count >= 2 else { return [] }

        let sortedByValue = tradable.sorted {
            ($0.total * (prices[$0.asset] ?? 0)) > ($1.total * (prices[$1.asset] ?? 0))
        }

        let donors = Array(sortedByValue.prefix(4))
        let receivers = Array(sortedByValue.suffix(4))

        var evaluations: [SwapEvaluation] = []

        for donor in donors {
            let donorPrice = prices[donor.asset] ?? 0.0
            let donorValue = donor.total * donorPrice
            guard donorValue > 25 else { continue }

            for receiver in receivers {
                guard receiver.asset != donor.asset else { continue }
                let receiverPrice = prices[receiver.asset] ?? 0
                guard receiverPrice > 0 else { continue }

                let fromQuantity = max(0.0001, (donorValue * 0.05) / max(donorPrice, 0.0001))
                let sellValue = fromQuantity * donorPrice
                guard sellValue > 1 else { continue }

                let totalCostUSD = sellValue * 0.002
                let estimatedToQuantity = (sellValue - totalCostUSD) / receiverPrice
                let netValue = sellValue * 0.01 - totalCostUSD
                let confidence = 0.65
                let isWorthwhile = netValue > 0

                let evaluation = SwapEvaluation(
                    fromAsset: donor.asset,
                    toAsset: receiver.asset,
                    fromQuantity: fromQuantity,
                    estimatedToQuantity: estimatedToQuantity,
                    totalCost: SwapCost(
                        sellFee: totalCostUSD * 0.5,
                        buyFee: totalCostUSD * 0.5,
                        sellSpread: 0,
                        buySpread: 0,
                        sellSlippage: 0,
                        buySlippage: 0,
                        totalCostUSD: totalCostUSD,
                        costPercentage: (totalCostUSD / sellValue) * 100
                    ),
                    potentialBenefit: SwapBenefit(
                        expectedReturnDifferential: netValue * 0.5,
                        portfolioImprovement: netValue * 0.3,
                        riskReduction: netValue > 3 ? netValue * 0.1 : nil,
                        allocationAlignment: netValue * 0.2,
                        totalBenefitUSD: netValue + totalCostUSD,
                        benefitPercentage: ((netValue + totalCostUSD) / sellValue) * 100
                    ),
                    netValue: netValue,
                    isWorthwhile: isWorthwhile,
                    confidence: confidence,
                    exchange: donor.exchange
                )

                evaluations.append(evaluation)
                if evaluations.count >= 12 {
                    break
                }
            }
            if evaluations.count >= 12 {
                break
            }
        }

        return evaluations.sorted { $0.netValue > $1.netValue }
    }
}
