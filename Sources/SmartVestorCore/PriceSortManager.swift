import Foundation

public enum PriceSortMode: String, Sendable, Codable {
    case symbol
    case price
    case change24h
}

public enum SortDirection: Sendable {
    case ascending
    case descending
}

public actor PriceSortManager {
    private var sortMode: PriceSortMode
    private var sortDirection: SortDirection

    public init(initialMode: PriceSortMode = .symbol, initialDirection: SortDirection = .ascending) {
        self.sortMode = initialMode
        self.sortDirection = initialDirection
    }

    public func getSortMode() -> PriceSortMode {
        return sortMode
    }

    public func getSortDirection() -> SortDirection {
        return sortDirection
    }

    public func toggleSortMode() {
        switch sortMode {
        case .symbol:
            sortMode = .price
        case .price:
            sortMode = .change24h
        case .change24h:
            sortMode = .symbol
        }
    }

    public func setSortMode(_ mode: PriceSortMode) {
        sortMode = mode
    }

    public func toggleDirection() {
        sortDirection = sortDirection == .ascending ? .descending : .ascending
    }

    public func sortPrices(_ prices: [String: Double], change24h: [String: Double]? = nil) -> [(String, Double)] {
        var sorted: [(String, Double)] = []

        switch sortMode {
        case .symbol:
            sorted = prices.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
        case .price:
            sorted = prices.map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
        case .change24h:
            if let changes = change24h {
                let withChanges = prices.map { (symbol: $0.key, price: $0.value, change: changes[$0.key] ?? 0.0) }
                sorted = withChanges.sorted { $0.change < $1.change }.map { ($0.symbol, $0.price) }
            } else {
                sorted = prices.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
            }
        }

        if sortDirection == .descending {
            sorted.reverse()
        }

        return sorted
    }
}
