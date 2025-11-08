import Foundation
import Utils
import Core

public protocol DepositMonitorProtocol {
    func scanForDeposits() async throws -> [DepositDetection]
    func validateDeposit(_ deposit: DepositDetection) async throws -> DepositValidation
    func confirmDeposit(_ deposit: DepositDetection) async throws
}

public struct DepositDetection: Codable, Identifiable {
    public let id: UUID
    public let exchange: String
    public let asset: String
    public let amount: Double
    public let network: String
    public let transactionHash: String?
    public let timestamp: Date
    public let status: DepositStatus

    public init(
        id: UUID = UUID(),
        exchange: String,
        asset: String,
        amount: Double,
        network: String,
        transactionHash: String? = nil,
        timestamp: Date = Date(),
        status: DepositStatus = .pending
    ) {
        self.id = id
        self.exchange = exchange
        self.asset = asset
        self.amount = amount
        self.network = network
        self.transactionHash = transactionHash
        self.timestamp = timestamp
        self.status = status
    }
}

public enum DepositStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case confirmed = "confirmed"
    case rejected = "rejected"
    case underAmount = "under_amount"
    case overAmount = "over_amount"
    case wrongNetwork = "wrong_network"
    case duplicate = "duplicate"
}

public struct DepositValidation: Codable {
    public let isValid: Bool
    public let reasons: [String]
    public let expectedAmount: Double
    public let tolerance: Double
    public let supportedNetworks: [String]
    public let isDuplicate: Bool

    public init(
        isValid: Bool,
        reasons: [String],
        expectedAmount: Double,
        tolerance: Double,
        supportedNetworks: [String],
        isDuplicate: Bool
    ) {
        self.isValid = isValid
        self.reasons = reasons
        self.expectedAmount = expectedAmount
        self.tolerance = tolerance
        self.supportedNetworks = supportedNetworks
        self.isDuplicate = isDuplicate
    }
}

public class DepositMonitor: DepositMonitorProtocol {
    private let config: SmartVestorConfig
    private let persistence: PersistenceProtocol
    private let exchangeConnectors: [String: ExchangeConnectorProtocol]
    private let logger: StructuredLogger

    public init(
        config: SmartVestorConfig,
        persistence: PersistenceProtocol,
        exchangeConnectors: [String: ExchangeConnectorProtocol],
        logger: StructuredLogger
    ) {
        self.config = config
        self.persistence = persistence
        self.exchangeConnectors = exchangeConnectors
        self.logger = logger
    }

    public func scanForDeposits() async throws -> [DepositDetection] {
        logger.info(component: "DepositMonitor", event: "Starting deposit scan")

        var allDeposits: [DepositDetection] = []

        for exchangeConfig in config.exchanges where exchangeConfig.enabled {
            guard exchangeConnectors[exchangeConfig.name] != nil else {
                logger.warn(component: "DepositMonitor", event: "Skipping exchange - no connector available", data: [
                    "exchange": exchangeConfig.name
                ])
                continue
            }

            do {
                let deposits = try await scanExchangeForDeposits(exchangeConfig)
                allDeposits.append(contentsOf: deposits)

                logger.info(component: "DepositMonitor", event: "Found deposits for exchange", data: [
                    "exchange": exchangeConfig.name,
                    "count": String(deposits.count)
                ])
            } catch {
                logger.warn(component: "DepositMonitor", event: "Failed to scan exchange for deposits", data: [
                    "exchange": exchangeConfig.name,
                    "error": error.localizedDescription
                ])
            }
        }

        logger.info(component: "DepositMonitor", event: "Deposit scan completed", data: [
            "total_deposits": String(allDeposits.count)
        ])

        return allDeposits
    }

    private func scanExchangeForDeposits(_ exchangeConfig: ExchangeConfig) async throws -> [DepositDetection] {
        guard let connector = exchangeConnectors[exchangeConfig.name] else {
            throw SmartVestorError.exchangeError("No connector found for exchange: \(exchangeConfig.name)")
        }

        let transactions = try await connector.getRecentTransactions(limit: 50)

        return transactions.compactMap { transaction -> DepositDetection? in
            guard transaction.type == .deposit,
                  transaction.asset == "USDC" else {
                return nil
            }

            return DepositDetection(
                exchange: exchangeConfig.name,
                asset: transaction.asset,
                amount: transaction.quantity,
                network: "USDC", // Default network for USDC
                transactionHash: transaction.id,
                timestamp: transaction.timestamp
            )
        }
    }

    private func determineNetwork(from transaction: InvestmentTransaction) -> String {
        if let network = transaction.metadata["network"] {
            return network
        }

        if let exchange = transaction.metadata["exchange"] {
            switch exchange.lowercased() {
            case "coinbase":
                return "USDC-ETH"
            case "kraken":
                return "USDC-ETH"
            case "gemini":
                return "USDC-ETH"
            default:
                return "USDC-ETH"
            }
        }

        return "USDC-ETH"
    }

    public func validateDeposit(_ deposit: DepositDetection) async throws -> DepositValidation {
        logger.info(component: "DepositMonitor", event: "Validating deposit", data: [
            "deposit_id": deposit.id.uuidString,
            "exchange": deposit.exchange,
            "amount": String(deposit.amount)
        ])

        var reasons: [String] = []
        var isValid = true

        let expectedAmount = config.depositAmount
        let tolerance = config.depositTolerance
        let minAmount = expectedAmount * (1.0 - tolerance)
        let maxAmount = expectedAmount * (1.0 + tolerance)

        if deposit.amount < minAmount {
            reasons.append("Amount \(deposit.amount) is below minimum \(minAmount)")
            isValid = false
        }

        if deposit.amount > maxAmount {
            reasons.append("Amount \(deposit.amount) is above maximum \(maxAmount)")
            isValid = false
        }

        let exchangeConfig = config.exchanges.first { $0.name == deposit.exchange }
        let supportedNetworks = exchangeConfig?.supportedNetworks ?? ["USDC-ETH", "USDC-SOL"]

        if !supportedNetworks.contains(deposit.network) {
            reasons.append("Network \(deposit.network) not supported. Supported: \(supportedNetworks.joined(separator: ", "))")
            isValid = false
        }

        let isDuplicate = try await checkForDuplicateDeposit(deposit)
        if isDuplicate {
            reasons.append("Duplicate deposit detected")
            isValid = false
        }

        if isValid {
            reasons.append("Deposit validation passed")
        }

        let validation = DepositValidation(
            isValid: isValid,
            reasons: reasons,
            expectedAmount: expectedAmount,
            tolerance: tolerance,
            supportedNetworks: supportedNetworks,
            isDuplicate: isDuplicate
        )

        logger.info(component: "DepositMonitor", event: "Deposit validation completed", data: [
            "deposit_id": deposit.id.uuidString,
            "is_valid": String(isValid),
            "reasons": reasons.joined(separator: "; ")
        ])

        return validation
    }

    private func checkForDuplicateDeposit(_ deposit: DepositDetection) async throws -> Bool {
        let existingTransactions = try persistence.getTransactions(
            exchange: deposit.exchange,
            asset: deposit.asset,
            type: .deposit,
            limit: 100
        )

        let timeWindow: TimeInterval = 24 * 60 * 60
        let cutoffTime = deposit.timestamp.addingTimeInterval(-timeWindow)

        return existingTransactions.contains { transaction in
            transaction.timestamp > cutoffTime &&
            abs(transaction.quantity - deposit.amount) < 0.01 &&
            transaction.metadata["transaction_hash"] == deposit.transactionHash
        }
    }

    public func confirmDeposit(_ deposit: DepositDetection) async throws {
        logger.info(component: "DepositMonitor", event: "Confirming deposit", data: [
            "deposit_id": deposit.id.uuidString,
            "exchange": deposit.exchange,
            "amount": String(deposit.amount)
        ])

        let transaction = InvestmentTransaction(
            type: .deposit,
            exchange: deposit.exchange,
            asset: deposit.asset,
            quantity: deposit.amount,
            price: 1.0,
            fee: 0.0,
            timestamp: deposit.timestamp,
            metadata: [
                "network": deposit.network,
                "transaction_hash": deposit.transactionHash ?? "",
                "deposit_id": deposit.id.uuidString
            ]
        )

        try persistence.saveTransaction(transaction)

        try await updateAccountBalance(
            exchange: deposit.exchange,
            asset: deposit.asset,
            additionalAmount: deposit.amount
        )

        let auditEntry = AuditEntry(
            component: "DepositMonitor",
            action: "deposit_confirmed",
            details: [
                "deposit_id": deposit.id.uuidString,
                "exchange": deposit.exchange,
                "asset": deposit.asset,
                "amount": String(deposit.amount),
                "network": deposit.network
            ],
            hash: generateHash(for: deposit)
        )

        try persistence.saveAuditEntry(auditEntry)

        logger.info(component: "DepositMonitor", event: "Deposit confirmed successfully", data: [
            "deposit_id": deposit.id.uuidString,
            "transaction_id": transaction.id.uuidString
        ])
    }

    private func updateAccountBalance(
        exchange: String,
        asset: String,
        additionalAmount: Double
    ) async throws {
        if let existingAccount = try persistence.getAccount(exchange: exchange, asset: asset) {
            let newAvailable = existingAccount.available + additionalAmount
            try persistence.updateAccountBalance(
                exchange: exchange,
                asset: asset,
                available: newAvailable,
                pending: existingAccount.pending,
                staked: existingAccount.staked
            )
        } else {
            let newAccount = Holding(
                exchange: exchange,
                asset: asset,
                available: additionalAmount,
                pending: 0.0,
                staked: 0.0
            )
            try persistence.saveAccount(newAccount)
        }
    }

    private func generateHash(for deposit: DepositDetection) -> String {
        let data = "\(deposit.id.uuidString)\(deposit.exchange)\(deposit.asset)\(deposit.amount)\(deposit.timestamp.timeIntervalSince1970)"
        return data.data(using: .utf8)?.base64EncodedString() ?? ""
    }
}

public class MockDepositMonitor: DepositMonitorProtocol {
    private let mockDeposits: [DepositDetection]

    public init(mockDeposits: [DepositDetection] = []) {
        self.mockDeposits = mockDeposits
    }

    public func scanForDeposits() async throws -> [DepositDetection] {
        return mockDeposits
    }

    public func validateDeposit(_ deposit: DepositDetection) async throws -> DepositValidation {
        let isValid = deposit.amount >= 95.0 && deposit.amount <= 105.0
        let reasons = isValid ? ["Deposit validation passed"] : ["Amount outside tolerance range"]

        return DepositValidation(
            isValid: isValid,
            reasons: reasons,
            expectedAmount: 100.0,
            tolerance: 0.05,
            supportedNetworks: ["USDC-ETH", "USDC-SOL"],
            isDuplicate: false
        )
    }

    public func confirmDeposit(_ deposit: DepositDetection) async throws {
    }
}
