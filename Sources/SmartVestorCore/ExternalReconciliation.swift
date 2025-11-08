import Foundation
import Utils
import Core

public struct ExchangeBalanceSnapshot {
    public let exchange: String
    public let asset: String
    public let balance: Double
    public let timestamp: Date
    public let source: String
}

public struct ReconciliationIncident {
    public let id: UUID
    public let exchange: String
    public let asset: String
    public let tigerBeetleBalance: Double
    public let exchangeBalance: Double
    public let drift: Double
    public let threshold: Double
    public let timestamp: Date
    public let severity: IncidentSeverity

    public enum IncidentSeverity {
        case warning
        case critical
    }
}

public class ExternalReconciliation {
    private let tigerBeetlePersistence: TigerBeetlePersistence
    private let exchangeConnectors: [String: ExchangeConnectorProtocol]
    private let logger: StructuredLogger
    private let threshold: Double

    public init(
        tigerBeetlePersistence: TigerBeetlePersistence,
        exchangeConnectors: [String: ExchangeConnectorProtocol],
        logger: StructuredLogger = StructuredLogger(),
        threshold: Double = 0.01
    ) {
        self.tigerBeetlePersistence = tigerBeetlePersistence
        self.exchangeConnectors = exchangeConnectors
        self.logger = logger
        self.threshold = threshold
    }

    public func reconcileWithExchanges() async throws -> [ReconciliationIncident] {
        var incidents: [ReconciliationIncident] = []

        for (exchangeName, connector) in exchangeConnectors {
            do {
                let holdings = try await connector.getHoldings()
                let tbAccounts = try tigerBeetlePersistence.getAllAccounts()

                for holding in holdings {
                    guard let asset = holding["asset"] as? String ?? holding["assetCode"] as? String,
                          let exchangeBalance = parseBalance(holding) else {
                        continue
                    }

                    let tbAccount = tbAccounts.first { $0.exchange == exchangeName && $0.asset == asset }
                    let tbBalance = tbAccount?.total ?? 0.0

                    let drift = abs(exchangeBalance - tbBalance)

                    if drift > threshold {
                        let incident = ReconciliationIncident(
                            id: UUID(),
                            exchange: exchangeName,
                            asset: asset,
                            tigerBeetleBalance: tbBalance,
                            exchangeBalance: exchangeBalance,
                            drift: drift,
                            threshold: threshold,
                            timestamp: Date(),
                            severity: drift > threshold * 10 ? .critical : .warning
                        )
                        incidents.append(incident)

                        logger.error(
                            component: "ExternalReconciliation",
                            event: "Balance drift detected",
                            data: [
                                "exchange": exchangeName,
                                "asset": asset,
                                "drift": String(drift),
                                "tb_balance": String(tbBalance),
                                "exchange_balance": String(exchangeBalance),
                                "severity": incident.severity == ReconciliationIncident.IncidentSeverity.critical ? "critical" : "warning"
                            ]
                        )
                    }
                }
            } catch {
                logger.warn(
                    component: "ExternalReconciliation",
                    event: "Failed to reconcile exchange",
                    data: ["exchange": exchangeName, "error": error.localizedDescription]
                )
            }
        }

        return incidents
    }

    private func parseBalance(_ holding: [String: Any]) -> Double? {
        if let balance = holding["available"] as? Double {
            return balance
        }
        if let balance = holding["quantity"] as? Double {
            return balance
        }
        if let balanceStr = holding["available"] as? String,
           let balance = Double(balanceStr) {
            return balance
        }
        return nil
    }
}
