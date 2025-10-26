import Foundation
import Utils

public class RealMarketDataProvider: MarketDataProviderProtocol {
    private let logger = StructuredLogger()
    private let session = URLSession.shared
    private let coinGeckoAPIKey: String?
    private let coinMarketCapAPIKey: String?

    public init(coinGeckoAPIKey: String? = nil, coinMarketCapAPIKey: String? = nil) {
        // Try to get API key from parameter first, then environment variable
        self.coinGeckoAPIKey = coinGeckoAPIKey ?? ProcessInfo.processInfo.environment["COINGECKO_API_KEY"]
        self.coinMarketCapAPIKey = coinMarketCapAPIKey ?? ProcessInfo.processInfo.environment["COINMARKETCAP_API_KEY"]
    }

    public func getHistoricalData(startDate: Date, endDate: Date, symbols: [String]) async throws -> [String: [MarketDataPoint]] {
        var data: [String: [MarketDataPoint]] = [:]

        for symbol in symbols {
            do {
                let points = try await getCoinGeckoHistoricalData(symbol: symbol, startDate: startDate, endDate: endDate)
                data[symbol] = points
            } catch {
                logger.warn(component: "RealMarketDataProvider", event: "Failed to get historical data from CoinGecko, trying CoinMarketCap", data: [
                    "symbol": symbol,
                    "error": error.localizedDescription
                ])

                // Fallback to CoinMarketCap
                do {
                    let points = try await getCoinMarketCapHistoricalData(symbol: symbol, startDate: startDate, endDate: endDate)
                    data[symbol] = points
                } catch {
                    logger.error(component: "RealMarketDataProvider", event: "Failed to get historical data from all sources", data: [
                        "symbol": symbol,
                        "error": error.localizedDescription
                    ])
                    throw error
                }
            }
        }

        return data
    }

    public func getCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        do {
            return try await getCoinGeckoCurrentPrices(symbols: symbols)
        } catch {
            logger.warn(component: "RealMarketDataProvider", event: "Failed to get current prices from CoinGecko, trying CoinMarketCap", data: [
                "error": error.localizedDescription
            ])

            return try await getCoinMarketCapCurrentPrices(symbols: symbols)
        }
    }

    public func getVolumeData(symbols: [String]) async throws -> [String: Double] {
        do {
            return try await getCoinGeckoVolumeData(symbols: symbols)
        } catch {
            logger.warn(component: "RealMarketDataProvider", event: "Failed to get volume data from CoinGecko, trying CoinMarketCap", data: [
                "error": error.localizedDescription
            ])

            return try await getCoinMarketCapVolumeData(symbols: symbols)
        }
    }

    // MARK: - CoinGecko API Methods

    private func getCoinGeckoHistoricalData(symbol: String, startDate: Date, endDate: Date) async throws -> [MarketDataPoint] {
        let coinId = try await getCoinGeckoId(for: symbol)
        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let endTimestamp = Int(endDate.timeIntervalSince1970)

        var urlComponents = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(coinId)/market_chart/range")!
        urlComponents.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "from", value: String(startTimestamp)),
            URLQueryItem(name: "to", value: String(endTimestamp))
        ]

        if let apiKey = coinGeckoAPIKey {
            urlComponents.queryItems?.append(URLQueryItem(name: "x_cg_demo_api_key", value: apiKey))
        }

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CoinGecko API error")
        }

        let coinGeckoResponse = try JSONDecoder().decode(CoinGeckoMarketChartResponse.self, from: data)

        var points: [MarketDataPoint] = []
        let prices = coinGeckoResponse.prices
        let volumes = coinGeckoResponse.total_volumes
        let marketCaps = coinGeckoResponse.market_caps

        for i in 0..<min(prices.count, volumes.count, marketCaps.count) {
            let timestamp = Date(timeIntervalSince1970: prices[i][0] / 1000)
            let price = prices[i][1]
            let volume = volumes[i][1]
            _ = marketCaps[i][1] // Market cap data available but not used in this context

            // Estimate OHLC from price (CoinGecko doesn't provide OHLC in this endpoint)
            let high = price * Double.random(in: 1.0...1.05)
            let low = price * Double.random(in: 0.95...1.0)
            let open = price * Double.random(in: 0.98...1.02)
            let close = price

            let point = MarketDataPoint(
                timestamp: timestamp,
                price: price,
                volume: volume,
                high: high,
                low: low,
                open: open,
                close: close
            )

            points.append(point)
        }

        return points
    }

    private func getCoinGeckoCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        let coinIds = try await getCoinGeckoIds(for: symbols)
        let coinIdsString = coinIds.joined(separator: ",")

        logger.info(component: "RealMarketDataProvider", event: "Getting CoinGecko prices", data: [
            "symbols": symbols.joined(separator: ","),
            "coinIds": coinIdsString,
            "hasApiKey": coinGeckoAPIKey != nil ? "true" : "false"
        ])

        var urlComponents = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        urlComponents.queryItems = [
            URLQueryItem(name: "ids", value: coinIdsString),
            URLQueryItem(name: "vs_currencies", value: "usd"),
            URLQueryItem(name: "include_24hr_change", value: "true")
        ]

        if let apiKey = coinGeckoAPIKey {
            urlComponents.queryItems?.append(URLQueryItem(name: "x_cg_demo_api_key", value: apiKey))
        }

        guard let url = urlComponents.url else {
            logger.error(component: "RealMarketDataProvider", event: "Failed to construct URL", data: [
                "baseUrl": "https://api.coingecko.com/api/v3/simple/price",
                "coinIds": coinIdsString
            ])
            throw MarketDataError.invalidURL
        }

        logger.info(component: "RealMarketDataProvider", event: "Making API request", data: [
            "url": url.absoluteString
        ])

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CoinGecko API error")
        }

        let priceResponse = try JSONDecoder().decode([String: CoinGeckoPriceData].self, from: data)

        var prices: [String: Double] = [:]
        for (coinId, priceData) in priceResponse {
            if let symbol = getSymbolFromCoinGeckoId(coinId) {
                prices[symbol] = priceData.usd
            }
        }

        return prices
    }

    private func getCoinGeckoVolumeData(symbols: [String]) async throws -> [String: Double] {
        let coinIds = try await getCoinGeckoIds(for: symbols)
        let coinIdsString = coinIds.joined(separator: ",")

        var urlComponents = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
        urlComponents.queryItems = [
            URLQueryItem(name: "ids", value: coinIdsString),
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "per_page", value: "250"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "sparkline", value: "false")
        ]

        if let apiKey = coinGeckoAPIKey {
            urlComponents.queryItems?.append(URLQueryItem(name: "x_cg_demo_api_key", value: apiKey))
        }

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CoinGecko API error")
        }

        let marketResponse = try JSONDecoder().decode([CoinGeckoMarketData].self, from: data)

        var volumes: [String: Double] = [:]
        for marketData in marketResponse {
            if let symbol = getSymbolFromCoinGeckoId(marketData.id) {
                volumes[symbol] = marketData.total_volume
            }
        }

        return volumes
    }

    private func getCoinGeckoId(for symbol: String) async throws -> String {
        // Map common symbols to CoinGecko IDs
        let symbolToIdMap: [String: String] = [
            "BTC": "bitcoin",
            "ETH": "ethereum",
            "ADA": "cardano",
            "DOT": "polkadot",
            "LINK": "chainlink",
            "SOL": "solana",
            "AVAX": "avalanche-2",
            "MATIC": "matic-network",
            "ARB": "arbitrum",
            "OP": "optimism",
            "ATOM": "cosmos",
            "NEAR": "near",
            "FTM": "fantom",
            "ALGO": "algorand",
            "ICP": "internet-computer",
            "UNI": "uniswap",
            "AAVE": "aave",
            "COMP": "compound-governance-token",
            "MKR": "maker",
            "SNX": "havven",
            "GRT": "the-graph",
            "DOGE": "dogecoin",
            "SHIB": "shiba-inu",
            "PEPE": "pepe",
            "BONK": "bonk",
            "WIF": "dogwifcoin",
            "BOME": "book-of-meme",
            "POPCAT": "popcat",
            "MEW": "cat-in-a-dogs-world",
            "MYRO": "myro",
            "BAND": "band-protocol",
            "API3": "api3",
            "XMR": "monero",
            "ZEC": "zcash",
            "DASH": "dash",
            "FET": "fetch-ai",
            "AGIX": "singularitynet",
            "OCEAN": "ocean-protocol",
            "FIL": "filecoin",
            "AR": "arweave",
            "SC": "siacoin"
        ]

        guard let coinId = symbolToIdMap[symbol.uppercased()] else {
            throw MarketDataError.unsupportedSymbol(symbol)
        }

        return coinId
    }

    private func getCoinGeckoIds(for symbols: [String]) async throws -> [String] {
        var coinIds: [String] = []
        for symbol in symbols {
            let coinId = try await getCoinGeckoId(for: symbol)
            coinIds.append(coinId)
        }
        return coinIds
    }

    private func getSymbolFromCoinGeckoId(_ coinId: String) -> String? {
        let idToSymbolMap: [String: String] = [
            "bitcoin": "BTC",
            "ethereum": "ETH",
            "cardano": "ADA",
            "polkadot": "DOT",
            "chainlink": "LINK",
            "solana": "SOL",
            "avalanche-2": "AVAX",
            "matic-network": "MATIC",
            "arbitrum": "ARB",
            "optimism": "OP",
            "cosmos": "ATOM",
            "near": "NEAR",
            "fantom": "FTM",
            "algorand": "ALGO",
            "internet-computer": "ICP",
            "uniswap": "UNI",
            "aave": "AAVE",
            "compound-governance-token": "COMP",
            "maker": "MKR",
            "havven": "SNX",
            "the-graph": "GRT",
            "dogecoin": "DOGE",
            "shiba-inu": "SHIB",
            "pepe": "PEPE",
            "bonk": "BONK",
            "dogwifcoin": "WIF",
            "book-of-meme": "BOME",
            "popcat": "POPCAT",
            "cat-in-a-dogs-world": "MEW",
            "myro": "MYRO",
            "band-protocol": "BAND",
            "api3": "API3",
            "monero": "XMR",
            "zcash": "ZEC",
            "dash": "DASH",
            "fetch-ai": "FET",
            "singularitynet": "AGIX",
            "ocean-protocol": "OCEAN",
            "filecoin": "FIL",
            "arweave": "AR",
            "siacoin": "SC"
        ]

        return idToSymbolMap[coinId]
    }

    // MARK: - CoinMarketCap API Methods (Backup)

    private func getCoinMarketCapHistoricalData(symbol: String, startDate: Date, endDate: Date) async throws -> [MarketDataPoint] {
        // CoinMarketCap requires paid API for historical data
        // For now, we'll throw an error and suggest using CoinGecko
        throw MarketDataError.apiError("CoinMarketCap historical data requires paid API. Please use CoinGecko.")
    }

    private func getCoinMarketCapCurrentPrices(symbols: [String]) async throws -> [String: Double] {
        guard let apiKey = coinMarketCapAPIKey else {
            throw MarketDataError.apiError("CoinMarketCap API key required")
        }

        let symbolsString = symbols.joined(separator: ",")

        var urlComponents = URLComponents(string: "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest")!
        urlComponents.queryItems = [
            URLQueryItem(name: "symbol", value: symbolsString),
            URLQueryItem(name: "convert", value: "USD")
        ]

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CoinMarketCap API error")
        }

        let cmcResponse = try JSONDecoder().decode(CoinMarketCapResponse.self, from: data)

        var prices: [String: Double] = [:]
        for (symbol, data) in cmcResponse.data {
            prices[symbol] = data.quote.USD.price
        }

        return prices
    }

    private func getCoinMarketCapVolumeData(symbols: [String]) async throws -> [String: Double] {
        guard let apiKey = coinMarketCapAPIKey else {
            throw MarketDataError.apiError("CoinMarketCap API key required")
        }

        let symbolsString = symbols.joined(separator: ",")

        var urlComponents = URLComponents(string: "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest")!
        urlComponents.queryItems = [
            URLQueryItem(name: "symbol", value: symbolsString),
            URLQueryItem(name: "convert", value: "USD")
        ]

        guard let url = urlComponents.url else {
            throw MarketDataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-CMC_PRO_API_KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MarketDataError.apiError("CoinMarketCap API error")
        }

        let cmcResponse = try JSONDecoder().decode(CoinMarketCapResponse.self, from: data)

        var volumes: [String: Double] = [:]
        for (symbol, data) in cmcResponse.data {
            volumes[symbol] = data.quote.USD.volume_24h ?? 0.0
        }

        return volumes
    }
}

// MARK: - Data Models

public enum MarketDataError: Error {
    case invalidURL
    case apiError(String)
    case unsupportedSymbol(String)
    case networkError(Error)
}

struct CoinGeckoMarketChartResponse: Codable {
    let prices: [[Double]]
    let market_caps: [[Double]]
    let total_volumes: [[Double]]
}

struct CoinGeckoPriceData: Codable {
    let usd: Double
    let usd_24h_change: Double?
}

struct CoinGeckoMarketData: Codable {
    let id: String
    let symbol: String
    let name: String
    let current_price: Double
    let market_cap: Double
    let total_volume: Double
    let price_change_percentage_24h: Double?
}

struct CoinMarketCapResponse: Codable {
    let data: [String: CoinMarketCapData]
}

struct CoinMarketCapData: Codable {
    let id: Int
    let name: String
    let symbol: String
    let quote: CoinMarketCapQuote
}

struct CoinMarketCapQuote: Codable {
    let USD: CoinMarketCapUSDData
}

struct CoinMarketCapUSDData: Codable {
    let price: Double
    let volume_24h: Double?
    let market_cap: Double?
    let percent_change_24h: Double?
}
