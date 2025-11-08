import Foundation
import Utils

public struct SHAPVisualization {
    public let featureNames: [String]
    public let shapValues: [Double]
    public let baseValue: Double
    public let prediction: Double

    public init(featureNames: [String], shapValues: [Double], baseValue: Double, prediction: Double) {
        self.featureNames = featureNames
        self.shapValues = shapValues
        self.baseValue = baseValue
        self.prediction = prediction
    }
}

public struct BacktestVisualization {
    public let timestamps: [Date]
    public let equity: [Double]
    public let drawdown: [Double]
    public let trades: [Trade]
    public let metrics: BacktestResult

    public init(timestamps: [Date], equity: [Double], drawdown: [Double], trades: [Trade], metrics: BacktestResult) {
        self.timestamps = timestamps
        self.equity = equity
        self.drawdown = drawdown
        self.trades = trades
        self.metrics = metrics
    }
}

public struct DashboardData {
    public let shapVisualization: SHAPVisualization?
    public let backtestVisualization: BacktestVisualization?
    public let featureImportance: [String: Double]
    public let predictionHistory: [(timestamp: Date, prediction: Double, actual: Double?)]
    public let modelMetrics: [String: Double]

    public init(shapVisualization: SHAPVisualization? = nil, backtestVisualization: BacktestVisualization? = nil, featureImportance: [String: Double] = [:], predictionHistory: [(timestamp: Date, prediction: Double, actual: Double?)] = [], modelMetrics: [String: Double] = [:]) {
        self.shapVisualization = shapVisualization
        self.backtestVisualization = backtestVisualization
        self.featureImportance = featureImportance
        self.predictionHistory = predictionHistory
        self.modelMetrics = modelMetrics
    }
}

public class ExplainableAIDashboard {
    private let logger: StructuredLogger

    public init(logger: StructuredLogger) {
        self.logger = logger
    }

    public func generateDashboard(
        model: MLXPricePredictionModel,
        shapValues: [Double],
        featureNames: [String],
        backtestResult: BacktestResult?,
        backtestTrades: [Trade]?,
        backtestEquity: [Double]?,
        backtestTimestamps: [Date]?
    ) -> DashboardData {
        let shapViz = SHAPVisualization(
            featureNames: featureNames,
            shapValues: shapValues,
            baseValue: 0.0,
            prediction: shapValues.reduce(0, +)
        )

        var backtestViz: BacktestVisualization? = nil
        if let result = backtestResult,
           let trades = backtestTrades,
           let equity = backtestEquity,
           let timestamps = backtestTimestamps {
            let drawdown = calculateDrawdown(equity: equity)
            backtestViz = BacktestVisualization(
                timestamps: timestamps,
                equity: equity,
                drawdown: drawdown,
                trades: trades,
                metrics: result
            )
        }

        let featureImportance = Dictionary(uniqueKeysWithValues: zip(featureNames, shapValues.map { abs($0) }))

        logger.info(component: "ExplainableAIDashboard", event: "Dashboard generated", data: [
            "hasSHAP": "true",
            "hasBacktest": String(backtestViz != nil)
        ])

        return DashboardData(
            shapVisualization: shapViz,
            backtestVisualization: backtestViz,
            featureImportance: featureImportance
        )
    }

    public func exportToJSON(dashboard: DashboardData) throws -> Data {
        struct ExportableDashboard: Codable {
            let shapValues: [Double]?
            let featureNames: [String]?
            let equity: [Double]?
            let drawdown: [Double]?
            let metrics: [String: Double]?
        }

        let exportable = ExportableDashboard(
            shapValues: dashboard.shapVisualization?.shapValues,
            featureNames: dashboard.shapVisualization?.featureNames,
            equity: dashboard.backtestVisualization?.equity,
            drawdown: dashboard.backtestVisualization?.drawdown,
            metrics: [
                "totalReturn": dashboard.backtestVisualization?.metrics.totalReturn ?? 0.0,
                "sharpeRatio": dashboard.backtestVisualization?.metrics.sharpeRatio ?? 0.0,
                "maxDrawdown": dashboard.backtestVisualization?.metrics.maxDrawdown ?? 0.0,
                "winRate": dashboard.backtestVisualization?.metrics.winRate ?? 0.0
            ]
        )

        return try JSONEncoder().encode(exportable)
    }

    private func calculateDrawdown(equity: [Double]) -> [Double] {
        var drawdown: [Double] = []
        var peak = equity[0]

        for value in equity {
            if value > peak {
                peak = value
            }
            drawdown.append((peak - value) / peak)
        }

        return drawdown
    }
}
