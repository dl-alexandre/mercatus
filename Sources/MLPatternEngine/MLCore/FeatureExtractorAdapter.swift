import Foundation

// MARK: - Boundary Adapter Between SmartVestorCore and MLPatternEngine
//
// This file contains adapter functions that convert between SmartVestor.MarketDataPoint
// and MLPatternEngine.MarketDataPoint types. This is necessary because both modules
// define a MarketDataPoint struct, causing type resolution conflicts in SmartVestorCore.
//
// **Boundary Contract:**
// - All cross-module type conversions happen here only
// - This file is in MLPatternEngine module, so MarketDataPoint resolves to MLPatternEngine.MarketDataPoint
// - Future field additions must be mapped here explicitly
// - This adapter will be removed once shared SmartVestorTypes module is created
//
// **Runtime Safety:**
// - We reconstruct MLPatternEngine.MarketDataPoint instances from properties
// - No unsafe memory reinterpretation (no unsafeBitCast, withMemoryRebound, etc.)
// - All conversions are explicit and type-safe

/// Creates a MLPatternEngine.MarketDataPoint instance from individual properties
/// This function is in MLPatternEngine module, so MarketDataPoint resolves correctly
public func createMarketDataPoint(
    timestamp: Date,
    symbol: String,
    open: Double,
    high: Double,
    low: Double,
    close: Double,
    volume: Double,
    exchange: String
) -> MarketDataPoint {
    // MarketDataPoint resolves to MLPatternEngine.MarketDataPoint in this module
    return MarketDataPoint(
        timestamp: timestamp,
        symbol: symbol,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
        exchange: exchange
    )
}

/// Adapter function to call extractFeatures with proper type conversion
///
/// Converts data from SmartVestorCore context (where MarketDataPoint resolves to SmartVestor.MarketDataPoint)
/// to MLPatternEngine context (where MarketDataPoint resolves to MLPatternEngine.MarketDataPoint).
///
/// **Usage:**
/// - Extract properties from SmartVestor.MarketDataPoint using Mirror
/// - Pass properties tuple to this function
/// - Function creates MLPatternEngine.MarketDataPoint instances and calls extractFeatures
///
/// **Field Mapping:**
/// - timestamp, symbol, open, high, low, close, volume, exchange are mapped directly
/// - If either type gains new fields, this adapter must be updated
public func extractFeaturesAdapter(
    extractor: FeatureExtractorProtocol,
    currentProps: (timestamp: Date, symbol: String, open: Double, high: Double, low: Double, close: Double, volume: Double, exchange: String),
    historicalProps: [(timestamp: Date, symbol: String, open: Double, high: Double, low: Double, close: Double, volume: Double, exchange: String)]
) async throws -> FeatureSet {
    // Create MLPatternEngine.MarketDataPoint instances
    let mlCurrent = createMarketDataPoint(
        timestamp: currentProps.timestamp,
        symbol: currentProps.symbol,
        open: currentProps.open,
        high: currentProps.high,
        low: currentProps.low,
        close: currentProps.close,
        volume: currentProps.volume,
        exchange: currentProps.exchange
    )

    let mlHistorical = historicalProps.map { props in
        createMarketDataPoint(
            timestamp: props.timestamp,
            symbol: props.symbol,
            open: props.open,
            high: props.high,
            low: props.low,
            close: props.close,
            volume: props.volume,
            exchange: props.exchange
        )
    }

    // Call extractFeatures with correctly typed instances
    return try await extractor.extractFeatures(
        from: mlCurrent,
        historicalData: mlHistorical
    )
}
