import Foundation

public enum ScalingMode: String, Codable, Sendable {
    case auto
    case fixed
    case sync
}

public struct SparklineConfig: Sendable, Codable {
    public let enabled: Bool
    public let showPortfolioHistory: Bool
    public let showAssetTrends: Bool
    public let historyLength: Int
    public let sparklineWidth: Int
    public let minHeight: Int
    public let maxHeight: Int
    public let graphMode: GraphMode
    public let scalingMode: ScalingMode
    public let fixedMin: Double?
    public let fixedMax: Double?

    public init(
        enabled: Bool = true,
        showPortfolioHistory: Bool = true,
        showAssetTrends: Bool = true,
        historyLength: Int = 60,
        sparklineWidth: Int = 20,
        minHeight: Int = 1,
        maxHeight: Int = 4,
        graphMode: GraphMode = .default,
        scalingMode: ScalingMode = .auto,
        fixedMin: Double? = nil,
        fixedMax: Double? = nil
    ) {
        self.enabled = enabled
        self.showPortfolioHistory = showPortfolioHistory
        self.showAssetTrends = showAssetTrends
        self.historyLength = max(10, min(1000, historyLength))
        self.sparklineWidth = max(5, min(100, sparklineWidth))
        self.minHeight = max(1, min(8, minHeight))
        self.maxHeight = max(minHeight, min(8, maxHeight))
        self.graphMode = graphMode
        self.scalingMode = scalingMode
        self.fixedMin = fixedMin
        self.fixedMax = fixedMax
    }

    public static let `default` = SparklineConfig()

    public static let disabled = SparklineConfig(
        enabled: false,
        showPortfolioHistory: false,
        showAssetTrends: false
    )
}
