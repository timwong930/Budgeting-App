import Foundation

enum MarketDataServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case invalidPrice
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing API key."
        case .invalidResponse:
            return "Invalid market data response."
        case .invalidPrice:
            return "Market data did not include a valid price."
        case .rateLimited:
            return "Rate limited by market data provider."
        }
    }
}

struct MarketDataService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPrice(ticker: String, provider: MarketDataProvider, apiKey: String) async throws -> Double {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw MarketDataServiceError.missingAPIKey
        }

        switch provider {
        case .alphaVantage:
            return try await fetchAlphaVantagePrice(ticker: ticker, apiKey: cleanKey)
        case .finnhub:
            return try await fetchFinnhubPrice(ticker: ticker, apiKey: cleanKey)
        }
    }

    func fetchPrice(ticker: String, settings: MarketDataSettings) async throws -> Double {
        try await fetchWithAlpacaFallback(settings: settings) {
            try await fetchPrice(ticker: ticker, provider: settings.provider, apiKey: settings.apiKey)
        } fallback: {
            try await fetchAlpacaPrice(
                ticker: ticker,
                keyId: settings.alpacaAPIKeyId,
                secretKey: settings.alpacaSecretKey,
                feed: settings.alpacaFeed
            )
        }
    }

    func fetchQuoteSnapshot(ticker: String, provider: MarketDataProvider, apiKey: String) async throws -> MarketQuoteSnapshot {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw MarketDataServiceError.missingAPIKey
        }

        switch provider {
        case .alphaVantage:
            let price = try await fetchAlphaVantagePrice(ticker: ticker, apiKey: cleanKey)
            return MarketQuoteSnapshot(
                price: price,
                change: 0,
                percentChange: 0,
                open: nil,
                high: nil,
                low: nil,
                previousClose: nil
            )
        case .finnhub:
            return try await fetchFinnhubQuoteSnapshot(ticker: ticker, apiKey: cleanKey)
        }
    }

    func fetchQuoteSnapshot(ticker: String, settings: MarketDataSettings) async throws -> MarketQuoteSnapshot {
        try await fetchWithAlpacaFallback(settings: settings) {
            try await fetchQuoteSnapshot(ticker: ticker, provider: settings.provider, apiKey: settings.apiKey)
        } fallback: {
            try await fetchAlpacaQuoteSnapshot(
                ticker: ticker,
                keyId: settings.alpacaAPIKeyId,
                secretKey: settings.alpacaSecretKey,
                feed: settings.alpacaFeed
            )
        }
    }

    func fetchRecentPriceHistory(ticker: String, provider: MarketDataProvider, apiKey: String, days: Int = 14) async throws -> [TickerPricePoint] {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw MarketDataServiceError.missingAPIKey
        }
        let dayCount = max(5, min(days, 120))

        switch provider {
        case .alphaVantage:
            return try await fetchAlphaVantageRecentPriceHistory(ticker: ticker, apiKey: cleanKey, days: dayCount)
        case .finnhub:
            return try await fetchFinnhubRecentPriceHistory(ticker: ticker, apiKey: cleanKey, days: dayCount)
        }
    }

    func fetchRecentCloses(ticker: String, provider: MarketDataProvider, apiKey: String, days: Int = 14) async throws -> [Double] {
        try await fetchRecentPriceHistory(ticker: ticker, provider: provider, apiKey: apiKey, days: days).map(\.close)
    }

    func fetchRecentPriceHistory(ticker: String, settings: MarketDataSettings, days: Int = 14) async throws -> [TickerPricePoint] {
        try await fetchWithAlpacaFallback(settings: settings) {
            try await fetchRecentPriceHistory(ticker: ticker, provider: settings.provider, apiKey: settings.apiKey, days: days)
        } fallback: {
            try await fetchAlpacaRecentPriceHistory(
                ticker: ticker,
                keyId: settings.alpacaAPIKeyId,
                secretKey: settings.alpacaSecretKey,
                feed: settings.alpacaFeed,
                days: days
            )
        }
    }

    func fetchRecentCloses(ticker: String, settings: MarketDataSettings, days: Int = 14) async throws -> [Double] {
        try await fetchRecentPriceHistory(ticker: ticker, settings: settings, days: days).map(\.close)
    }

    func fetchCompositeRecentPriceHistory(ticker: String, settings: MarketDataSettings, days: Int = 90) async throws -> [TickerPricePoint] {
        var candidates: [[TickerPricePoint]] = []

        if settings.hasPrimaryAPIKey,
           let primary = try? await fetchRecentPriceHistory(
            ticker: ticker,
            provider: settings.provider,
            apiKey: settings.apiKey,
            days: days
           ),
           primary.count >= 2 {
            candidates.append(primary)
        }

        if settings.useAlpacaFallback,
           settings.hasAlpacaCredentials,
           let alpaca = try? await fetchAlpacaRecentPriceHistory(
            ticker: ticker,
            keyId: settings.alpacaAPIKeyId,
            secretKey: settings.alpacaSecretKey,
            feed: settings.alpacaFeed,
            days: days
           ),
           alpaca.count >= 2 {
            candidates.append(alpaca)
        }

        guard let best = candidates.max(by: { $0.count < $1.count }) else {
            throw MarketDataServiceError.invalidPrice
        }
        return Array(best.suffix(max(5, min(days, 120))))
    }

    func fetchCompositeRecentCloses(ticker: String, settings: MarketDataSettings, days: Int = 90) async throws -> [Double] {
        try await fetchCompositeRecentPriceHistory(ticker: ticker, settings: settings, days: days).map(\.close)
    }

    func fetchQuoteDetails(ticker: String, provider: MarketDataProvider, apiKey: String) async throws -> MarketQuoteDetails {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw MarketDataServiceError.missingAPIKey
        }

        switch provider {
        case .alphaVantage:
            let price = try await fetchAlphaVantagePrice(ticker: ticker, apiKey: cleanKey)
            let dividendPerShare = try await fetchAlphaVantageDividendPerShare(ticker: ticker, apiKey: cleanKey)
            return MarketQuoteDetails(price: price, annualDividendPerShare: dividendPerShare)
        case .finnhub:
            let price = try await fetchFinnhubPrice(ticker: ticker, apiKey: cleanKey)
            let dividendPerShare = try? await fetchFinnhubDividendPerShare(ticker: ticker, apiKey: cleanKey)
            return MarketQuoteDetails(price: price, annualDividendPerShare: dividendPerShare)
        }
    }

    func fetchQuoteDetails(ticker: String, settings: MarketDataSettings) async throws -> MarketQuoteDetails {
        try await fetchWithAlpacaFallback(settings: settings) {
            let details = try await fetchQuoteDetails(ticker: ticker, provider: settings.provider, apiKey: settings.apiKey)
            guard details.annualDividendPerShare == nil,
                  settings.useAlpacaFallback,
                  settings.hasAlpacaCredentials,
                  let alpacaDividend = try? await fetchAlpacaDividendPerShare(
                    ticker: ticker,
                    keyId: settings.alpacaAPIKeyId,
                    secretKey: settings.alpacaSecretKey
                  ) else {
                return details
            }
            return MarketQuoteDetails(price: details.price, annualDividendPerShare: alpacaDividend)
        } fallback: {
            try await fetchAlpacaQuoteDetails(
                ticker: ticker,
                keyId: settings.alpacaAPIKeyId,
                secretKey: settings.alpacaSecretKey,
                feed: settings.alpacaFeed
            )
        }
    }

    func fetchAlpacaPrice(ticker: String, keyId: String, secretKey: String, feed: AlpacaMarketDataFeed) async throws -> Double {
        try await fetchAlpacaQuoteSnapshot(ticker: ticker, keyId: keyId, secretKey: secretKey, feed: feed).price
    }

    func fetchAlpacaQuoteDetails(ticker: String, keyId: String, secretKey: String, feed: AlpacaMarketDataFeed) async throws -> MarketQuoteDetails {
        let snapshot = try await fetchAlpacaQuoteSnapshot(ticker: ticker, keyId: keyId, secretKey: secretKey, feed: feed)
        let dividendPerShare = try? await fetchAlpacaDividendPerShare(ticker: ticker, keyId: keyId, secretKey: secretKey)
        return MarketQuoteDetails(price: snapshot.price, annualDividendPerShare: dividendPerShare)
    }

    func fetchAlpacaQuoteSnapshot(ticker: String, keyId: String, secretKey: String, feed: AlpacaMarketDataFeed) async throws -> MarketQuoteSnapshot {
        let request = try alpacaRequest(
            path: "stocks/\(ticker.uppercased())/snapshot",
            queryItems: [URLQueryItem(name: "feed", value: feed.apiValue)],
            keyId: keyId,
            secretKey: secretKey
        )

        let (data, response) = try await session.data(for: request)
        try validateAlpacaResponse(data: data, response: response)

        let decoded = try JSONDecoder().decode(AlpacaSnapshotResponse.self, from: data)
        let price = decoded.latestTrade?.price ?? decoded.dailyBar?.close ?? decoded.minuteBar?.close
        guard let price, price > 0 else {
            throw MarketDataServiceError.invalidPrice
        }

        let previousClose = decoded.prevDailyBar?.close
        let change = previousClose.map { price - $0 } ?? 0
        let percentChange = previousClose.flatMap { $0 > 0 ? (change / $0) * 100 : nil } ?? 0

        return MarketQuoteSnapshot(
            price: price,
            change: change,
            percentChange: percentChange,
            open: decoded.dailyBar?.open,
            high: decoded.dailyBar?.high,
            low: decoded.dailyBar?.low,
            previousClose: previousClose
        )
    }

    func fetchAlpacaRecentPriceHistory(ticker: String, keyId: String, secretKey: String, feed: AlpacaMarketDataFeed, days: Int = 14) async throws -> [TickerPricePoint] {
        let dayCount = max(5, min(days, 120))
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -(dayCount * 2), to: now) ?? now
        let bars = try await fetchAlpacaBars(ticker: ticker, start: start, end: now, keyId: keyId, secretKey: secretKey, feed: feed)
        let recent = bars.compactMap { bar -> TickerPricePoint? in
            guard bar.close > 0, let date = bar.tradingDate else { return nil }
            return TickerPricePoint(date: date, close: bar.close)
        }.suffix(dayCount)
        guard recent.count >= 2 else { throw MarketDataServiceError.invalidPrice }
        return Array(recent)
    }

    func fetchAlpacaRecentCloses(ticker: String, keyId: String, secretKey: String, feed: AlpacaMarketDataFeed, days: Int = 14) async throws -> [Double] {
        try await fetchAlpacaRecentPriceHistory(ticker: ticker, keyId: keyId, secretKey: secretKey, feed: feed, days: days).map(\.close)
    }

    func fetchAlpacaDividendPerShare(ticker: String, keyId: String, secretKey: String) async throws -> Double? {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        guard let start = calendar.date(byAdding: .year, value: -1, to: now) else { return nil }
        let actions = try await fetchAlpacaCorporateActions(
            ticker: ticker,
            start: start,
            end: now,
            types: "cash_dividend",
            keyId: keyId,
            secretKey: secretKey
        )
        let total = actions.compactMap(\.cashAmount).filter { $0 > 0 }.reduce(0, +)
        return total > 0 ? total : nil
    }

    func fetchHistoricalClose(ticker: String, onOrBefore date: Date, provider: MarketDataProvider, apiKey: String) async throws -> Double {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw MarketDataServiceError.missingAPIKey
        }

        switch provider {
        case .alphaVantage:
            return try await fetchAlphaVantageHistoricalClose(ticker: ticker, onOrBefore: date, apiKey: cleanKey)
        case .finnhub:
            return try await fetchFinnhubHistoricalClose(ticker: ticker, onOrBefore: date, apiKey: cleanKey)
        }
    }

    func fetchHistoricalClose(ticker: String, onOrBefore date: Date, settings: MarketDataSettings) async throws -> Double {
        try await fetchWithAlpacaFallback(settings: settings) {
            try await fetchHistoricalClose(ticker: ticker, onOrBefore: date, provider: settings.provider, apiKey: settings.apiKey)
        } fallback: {
            try await fetchAlpacaHistoricalClose(
                ticker: ticker,
                onOrBefore: date,
                keyId: settings.alpacaAPIKeyId,
                secretKey: settings.alpacaSecretKey,
                feed: settings.alpacaFeed
            )
        }
    }

    func fetchAlpacaHistoricalClose(ticker: String, onOrBefore date: Date, keyId: String, secretKey: String, feed: AlpacaMarketDataFeed) async throws -> Double {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(byAdding: .day, value: -10, to: date) ?? date
        let bars = try await fetchAlpacaBars(ticker: ticker, start: start, end: date, keyId: keyId, secretKey: secretKey, feed: feed)
        guard let close = bars.last(where: { $0.close > 0 })?.close else {
            throw MarketDataServiceError.invalidPrice
        }
        return close
    }

    func fetchSymbolLookup(query: String, settings: MarketDataSettings) async throws -> [SymbolLookupResult] {
        try await fetchWithAlpacaFallback(settings: settings) {
            let cleanKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanKey.isEmpty else { throw MarketDataServiceError.missingAPIKey }
            switch settings.provider {
            case .finnhub:
                return try await fetchFinnhubSymbolLookup(query: query, apiKey: cleanKey)
            case .alphaVantage:
                return try await fetchAlphaVantageSymbolLookup(query: query, apiKey: cleanKey)
            }
        } fallback: {
            try await fetchAlpacaSymbolLookup(
                query: query,
                keyId: settings.alpacaAPIKeyId,
                secretKey: settings.alpacaSecretKey
            )
        }
    }

    func fetchCompanyProfile(ticker: String, provider: MarketDataProvider, apiKey: String) async throws -> MarketCompanyProfile? {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw MarketDataServiceError.missingAPIKey
        }

        switch provider {
        case .alphaVantage:
            return nil
        case .finnhub:
            return try await fetchFinnhubCompanyProfile(ticker: ticker, apiKey: cleanKey)
        }
    }

    func fetchStockFinancials(ticker: String, settings: MarketDataSettings) async throws -> StockFinancials {
        let cleanKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw MarketDataServiceError.missingAPIKey
        }

        switch settings.provider {
        case .alphaVantage:
            throw MarketDataServiceError.invalidResponse
        case .finnhub:
            return try await fetchFinnhubStockFinancials(ticker: ticker, apiKey: cleanKey)
        }
    }

    func fetchRecentNews(ticker: String, settings: MarketDataSettings, daysBack: Int = 14) async throws -> [TickerNewsArticle] {
        let cleanKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw MarketDataServiceError.missingAPIKey
        }

        switch settings.provider {
        case .alphaVantage:
            throw MarketDataServiceError.invalidResponse
        case .finnhub:
            return try await fetchFinnhubRecentNews(ticker: ticker, apiKey: cleanKey, daysBack: daysBack)
        }
    }

    private func fetchWithAlpacaFallback<T>(
        settings: MarketDataSettings,
        primary: () async throws -> T,
        fallback: () async throws -> T
    ) async throws -> T {
        do {
            return try await primary()
        } catch {
            guard settings.useAlpacaFallback,
                  !settings.alpacaAPIKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !settings.alpacaSecretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw error
            }
            return try await fallback()
        }
    }

    private func fetchAlphaVantagePrice(ticker: String, apiKey: String) async throws -> Double {
        var components = URLComponents(string: "https://www.alphavantage.co/query")
        components?.queryItems = [
            URLQueryItem(name: "function", value: "GLOBAL_QUOTE"),
            URLQueryItem(name: "symbol", value: ticker),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MarketDataServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(AlphaVantageResponse.self, from: data)
        if let note = decoded.note, note.localizedCaseInsensitiveContains("frequency") {
            throw MarketDataServiceError.rateLimited
        }
        if let message = decoded.information, message.localizedCaseInsensitiveContains("rate") {
            throw MarketDataServiceError.rateLimited
        }
        guard let raw = decoded.globalQuote?.price, let price = Double(raw), price > 0 else {
            throw MarketDataServiceError.invalidPrice
        }
        return price
    }

    private func fetchFinnhubPrice(ticker: String, apiKey: String) async throws -> Double {
        var components = URLComponents(string: "https://finnhub.io/api/v1/quote")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: ticker),
            URLQueryItem(name: "token", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        try validateFinnhubResponse(data: data, response: response)

        let decoded = try JSONDecoder().decode(FinnhubQuoteResponse.self, from: data)
        guard let currentPrice = decoded.currentPrice, currentPrice > 0 else {
            throw MarketDataServiceError.invalidPrice
        }
        return currentPrice
    }

    private func fetchFinnhubQuoteSnapshot(ticker: String, apiKey: String) async throws -> MarketQuoteSnapshot {
        var components = URLComponents(string: "https://finnhub.io/api/v1/quote")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: ticker),
            URLQueryItem(name: "token", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        try validateFinnhubResponse(data: data, response: response)

        let decoded = try JSONDecoder().decode(FinnhubQuoteResponse.self, from: data)
        guard let currentPrice = decoded.currentPrice, currentPrice > 0 else {
            throw MarketDataServiceError.invalidPrice
        }
        return MarketQuoteSnapshot(
            price: currentPrice,
            change: decoded.change ?? 0,
            percentChange: decoded.percentChange ?? 0,
            open: decoded.open,
            high: decoded.high,
            low: decoded.low,
            previousClose: decoded.previousClose
        )
    }

    private func fetchAlphaVantageDividendPerShare(ticker: String, apiKey: String) async throws -> Double? {
        var components = URLComponents(string: "https://www.alphavantage.co/query")
        components?.queryItems = [
            URLQueryItem(name: "function", value: "OVERVIEW"),
            URLQueryItem(name: "symbol", value: ticker),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MarketDataServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(AlphaVantageOverviewResponse.self, from: data)
        if let note = decoded.note, note.localizedCaseInsensitiveContains("frequency") {
            throw MarketDataServiceError.rateLimited
        }
        if let info = decoded.information, info.localizedCaseInsensitiveContains("rate") {
            throw MarketDataServiceError.rateLimited
        }
        guard let raw = decoded.dividendPerShare else { return nil }
        return Double(raw)
    }

    private func fetchAlphaVantageHistoricalClose(ticker: String, onOrBefore date: Date, apiKey: String) async throws -> Double {
        var components = URLComponents(string: "https://www.alphavantage.co/query")
        components?.queryItems = [
            URLQueryItem(name: "function", value: "TIME_SERIES_DAILY"),
            URLQueryItem(name: "symbol", value: ticker),
            URLQueryItem(name: "outputsize", value: "full"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MarketDataServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(AlphaVantageTimeSeriesResponse.self, from: data)
        if let note = decoded.note, note.localizedCaseInsensitiveContains("frequency") {
            throw MarketDataServiceError.rateLimited
        }
        if let message = decoded.information, message.localizedCaseInsensitiveContains("rate") {
            throw MarketDataServiceError.rateLimited
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let target = Calendar.current.startOfDay(for: date)

        let series = decoded.timeSeries ?? [:]
        let sorted = series.compactMap { key, point -> (Date, Double)? in
            guard let parsedDate = formatter.date(from: key), let close = Double(point.close), close > 0 else { return nil }
            return (parsedDate, close)
        }.sorted { $0.0 > $1.0 }

        guard let match = sorted.first(where: { Calendar.current.startOfDay(for: $0.0) <= target }) else {
            throw MarketDataServiceError.invalidPrice
        }

        return match.1
    }

    private func fetchFinnhubHistoricalClose(ticker: String, onOrBefore date: Date, apiKey: String) async throws -> Double {
        let calendar = Calendar.current
        let fromDate = calendar.date(byAdding: .day, value: -10, to: date) ?? date
        let from = Int(fromDate.timeIntervalSince1970)
        let to = Int(date.timeIntervalSince1970)

        do {
            let closes = try await fetchFinnhubCandles(
                endpoint: "stock/candle",
                symbol: ticker,
                from: from,
                to: to,
                apiKey: apiKey
            )
            guard let close = closes.last?.close, close > 0 else {
                throw MarketDataServiceError.invalidPrice
            }
            return close
        } catch {
            // Some symbols (e.g. VIX) require index candles on Finnhub.
            let indexSymbol = ticker.hasPrefix("^") ? ticker : "^\(ticker)"
            let closes = try await fetchFinnhubCandles(
                endpoint: "index/candle",
                symbol: indexSymbol,
                from: from,
                to: to,
                apiKey: apiKey
            )
            guard let close = closes.last?.close, close > 0 else {
                throw MarketDataServiceError.invalidPrice
            }
            return close
        }
    }

    private func fetchFinnhubRecentPriceHistory(ticker: String, apiKey: String, days: Int) async throws -> [TickerPricePoint] {
        let calendar = Calendar.current
        let now = Date()
        let fromDate = calendar.date(byAdding: .day, value: -(days + 7), to: now) ?? now
        let from = Int(fromDate.timeIntervalSince1970)
        let to = Int(now.timeIntervalSince1970)

        do {
            let points = try await fetchFinnhubCandles(
                endpoint: "stock/candle",
                symbol: ticker,
                from: from,
                to: to,
                apiKey: apiKey
            )
            let recent = points.filter { $0.close > 0 }.suffix(days)
            guard recent.count >= 2 else { throw MarketDataServiceError.invalidPrice }
            return Array(recent)
        } catch {
            let indexSymbol = ticker.hasPrefix("^") ? ticker : "^\(ticker)"
            let points = try await fetchFinnhubCandles(
                endpoint: "index/candle",
                symbol: indexSymbol,
                from: from,
                to: to,
                apiKey: apiKey
            )
            let recent = points.filter { $0.close > 0 }.suffix(days)
            guard recent.count >= 2 else { throw MarketDataServiceError.invalidPrice }
            return Array(recent)
        }
    }

    private func fetchFinnhubRecentCloses(ticker: String, apiKey: String, days: Int) async throws -> [Double] {
        try await fetchFinnhubRecentPriceHistory(ticker: ticker, apiKey: apiKey, days: days).map(\.close)
    }

    private func fetchFinnhubCandles(
        endpoint: String,
        symbol: String,
        from: Int,
        to: Int,
        apiKey: String
    ) async throws -> [TickerPricePoint] {
        var components = URLComponents(string: "https://finnhub.io/api/v1/\(endpoint)")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "resolution", value: "D"),
            URLQueryItem(name: "from", value: String(from)),
            URLQueryItem(name: "to", value: String(to)),
            URLQueryItem(name: "token", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        try validateFinnhubResponse(data: data, response: response)

        let decoded = try JSONDecoder().decode(FinnhubCandleResponse.self, from: data)
        guard decoded.status == "ok",
              let closes = decoded.closes,
              let timestamps = decoded.timestamps,
              !closes.isEmpty else {
            throw MarketDataServiceError.invalidPrice
        }

        var points: [TickerPricePoint] = []
        for (timestamp, closeValue) in zip(timestamps, closes) {
            guard let close = closeValue, close > 0 else { continue }
            points.append(TickerPricePoint(date: Date(timeIntervalSince1970: TimeInterval(timestamp)), close: close))
        }
        guard points.count >= 2 else {
            throw MarketDataServiceError.invalidPrice
        }
        return points.sorted { $0.date < $1.date }
    }

    private func fetchAlphaVantageRecentPriceHistory(ticker: String, apiKey: String, days: Int) async throws -> [TickerPricePoint] {
        var components = URLComponents(string: "https://www.alphavantage.co/query")
        components?.queryItems = [
            URLQueryItem(name: "function", value: "TIME_SERIES_DAILY"),
            URLQueryItem(name: "symbol", value: ticker),
            URLQueryItem(name: "outputsize", value: "compact"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MarketDataServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(AlphaVantageTimeSeriesResponse.self, from: data)
        if let note = decoded.note, note.localizedCaseInsensitiveContains("frequency") {
            throw MarketDataServiceError.rateLimited
        }
        if let message = decoded.information, message.localizedCaseInsensitiveContains("rate") {
            throw MarketDataServiceError.rateLimited
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        let points = (decoded.timeSeries ?? [:]).compactMap { dateString, point -> TickerPricePoint? in
            guard let date = formatter.date(from: dateString),
                  let close = Double(point.close),
                  close > 0 else { return nil }
            return TickerPricePoint(date: date, close: close)
        }.sorted { $0.date < $1.date }

        let recent = points.suffix(days)
        guard recent.count >= 2 else { throw MarketDataServiceError.invalidPrice }
        return Array(recent)
    }

    private func fetchAlphaVantageRecentCloses(ticker: String, apiKey: String, days: Int) async throws -> [Double] {
        try await fetchAlphaVantageRecentPriceHistory(ticker: ticker, apiKey: apiKey, days: days).map(\.close)
    }

    private func fetchAlphaVantageSymbolLookup(query: String, apiKey: String) async throws -> [SymbolLookupResult] {
        var components = URLComponents(string: "https://www.alphavantage.co/query")
        components?.queryItems = [
            URLQueryItem(name: "function", value: "SYMBOL_SEARCH"),
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MarketDataServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(AlphaVantageSymbolSearchResponse.self, from: data)
        if let note = decoded.note, note.localizedCaseInsensitiveContains("frequency") {
            throw MarketDataServiceError.rateLimited
        }
        guard let matches = decoded.bestMatches, !matches.isEmpty else {
            throw MarketDataServiceError.invalidResponse
        }
        return matches.map { match in
            SymbolLookupResult(
                description: match.name.trimmingCharacters(in: .whitespacesAndNewlines),
                displaySymbol: match.symbol.trimmingCharacters(in: .whitespacesAndNewlines),
                symbol: match.symbol.trimmingCharacters(in: .whitespacesAndNewlines),
                type: match.type?.trimmingCharacters(in: .whitespacesAndNewlines),
                primaryExchange: match.region.map { "\($0)" }
            )
        }
    }

    private func fetchAlpacaSymbolLookup(query: String, keyId: String, secretKey: String) async throws -> [SymbolLookupResult] {
        let cleanKeyId = keyId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKeyId.isEmpty, !cleanSecretKey.isEmpty else {
            throw MarketDataServiceError.missingAPIKey
        }

        var components = URLComponents(string: "https://paper-api.alpaca.markets/v2/assets")
        components?.queryItems = [
            URLQueryItem(name: "status", value: "active")
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        var request = URLRequest(url: url)
        request.addValue(cleanKeyId, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.addValue(cleanSecretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MarketDataServiceError.invalidResponse
        }

        let decoded = try JSONDecoder().decode([AlpacaAssetResponse].self, from: data)
        let upperQuery = query.uppercased()
        let filtered = decoded.filter { asset in
            guard asset.status == "active" else { return false }
            let symbolMatch = asset.symbol.uppercased().contains(upperQuery)
            let nameMatch = asset.name.uppercased().contains(upperQuery)
            return symbolMatch || nameMatch
        }
        guard !filtered.isEmpty else {
            throw MarketDataServiceError.invalidResponse
        }
        return filtered.prefix(20).map { asset in
            SymbolLookupResult(
                description: asset.name.trimmingCharacters(in: .whitespacesAndNewlines),
                displaySymbol: asset.symbol.trimmingCharacters(in: .whitespacesAndNewlines),
                symbol: asset.symbol.trimmingCharacters(in: .whitespacesAndNewlines),
                type: nil,
                primaryExchange: asset.exchange?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func fetchFinnhubSymbolLookup(query: String, apiKey: String) async throws -> [SymbolLookupResult] {
        var components = URLComponents(string: "https://finnhub.io/api/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "token", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        try validateFinnhubResponse(data: data, response: response)

        let decoded = try JSONDecoder().decode(FinnhubSymbolLookupResponse.self, from: data)
        return decoded.result
    }

    private func fetchFinnhubCompanyProfile(ticker: String, apiKey: String) async throws -> MarketCompanyProfile? {
        var components = URLComponents(string: "https://finnhub.io/api/v1/stock/profile2")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: ticker),
            URLQueryItem(name: "token", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        try validateFinnhubResponse(data: data, response: response)

        let decoded = try JSONDecoder().decode(FinnhubCompanyProfileResponse.self, from: data)
        let cleanName = decoded.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExchange = decoded.exchange?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (cleanName?.isEmpty ?? true) && (cleanExchange?.isEmpty ?? true) {
            return nil
        }
        return MarketCompanyProfile(
            name: cleanName?.isEmpty == false ? cleanName : nil,
            exchange: cleanExchange?.isEmpty == false ? cleanExchange : nil
        )
    }

    private func fetchFinnhubStockFinancials(ticker: String, apiKey: String) async throws -> StockFinancials {
        var components = URLComponents(string: "https://finnhub.io/api/v1/stock/metric")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: ticker.uppercased()),
            URLQueryItem(name: "metric", value: "all"),
            URLQueryItem(name: "token", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        try validateFinnhubResponse(data: data, response: response)

        let decoded = try JSONDecoder().decode(FinnhubStockMetricResponse.self, from: data)
        let metrics = decoded.metric

        let dividendSummary = try? await fetchFinnhubDividendSummary(ticker: ticker, apiKey: apiKey)

        return StockFinancials(
            fiscalYearEnd: metrics.string("fiscalYearEnd") ?? metrics.string("fiscalYearEndDate"),
            lastFiscalPeriod: metrics.string("lastFiscalPeriod"),
            lastFiscalPeriodEndDate: metrics.string("lastFiscalPeriodEndDate"),
            marketCapitalization: metrics.double("marketCapitalization"),
            enterpriseValue: metrics.double("enterpriseValue"),
            enterpriseValueToEBITDA: metrics.double("enterpriseValueOverEBITDATTM") ?? metrics.double("evToEbitdaTTM"),
            peRatio: metrics.double("peBasicExclExtraTTM") ?? metrics.double("peTTM"),
            psRatio: metrics.double("psTTM"),
            pbRatio: metrics.double("pbAnnual") ?? metrics.double("pbQuarterly"),
            pcfRatio: metrics.double("pcfShareTTM") ?? metrics.double("priceToCashFlowPerShareTTM"),
            pfcfRatio: metrics.double("pfcfShareTTM"),
            totalRevenue: metrics.double("revenueTTM"),
            revenuePerShare: metrics.double("revenuePerShareTTM"),
            grossProfit: metrics.double("grossProfitTTM"),
            operatingIncome: metrics.double("operatingIncomeTTM"),
            netIncome: metrics.double("netIncomeCommonTTM") ?? metrics.double("netIncomeTTM"),
            epsDilutedTTM: metrics.double("epsInclExtraItemsTTM") ?? metrics.double("epsDilutedTTM"),
            epsDilutedFQ: metrics.double("epsBasicExclExtraItemsQuarterly") ?? metrics.double("epsDilutedQuarterly"),
            totalSharesOutstanding: metrics.double("totalSharesOutstanding"),
            sharesFloat: metrics.double("floatSharesOutstanding"),
            totalAssets: metrics.double("totalAssets"),
            totalLiabilities: metrics.double("totalLiabilities"),
            totalEquity: metrics.double("totalEquity"),
            totalDebt: metrics.double("totalDebt"),
            operatingCashFlow: metrics.double("operatingCashFlowTTM"),
            investingCashFlow: metrics.double("investingCashFlowTTM"),
            financingCashFlow: metrics.double("financingCashFlowTTM"),
            freeCashFlow: metrics.double("freeCashFlowTTM"),
            capex: metrics.double("capitalExpenditureTTM") ?? metrics.double("capexCagr5Y"),
            grossMargin: metrics.double("grossMarginTTM"),
            operatingMargin: metrics.double("operatingMarginTTM"),
            pretaxMargin: metrics.double("pretaxMarginTTM"),
            netMargin: metrics.double("netProfitMarginTTM") ?? metrics.double("netMarginTTM"),
            returnOnAssets: metrics.double("roaTTM"),
            returnOnEquity: metrics.double("roeTTM"),
            returnOnInvestedCapital: metrics.double("roiTTM") ?? metrics.double("roicTTM"),
            revenuePerEmployee: metrics.double("revenuePerEmployeeAnnual"),
            netIncomePerEmployee: metrics.double("netIncomePerEmployeeAnnual"),
            averageVolume10Day: metrics.double("10DayAverageTradingVolume"),
            betaOneYear: metrics.double("beta"),
            week52High: metrics.double("52WeekHigh"),
            week52Low: metrics.double("52WeekLow"),
            oneYearPriceTarget: metrics.double("targetMeanPrice") ?? metrics.double("priceTargetMean"),
            dividendYieldIndicated: metrics.double("dividendYieldIndicatedAnnual") ?? metrics.double("currentDividendYieldTTM"),
            dividendsPerShareFY: metrics.double("dividendPerShareAnnual") ?? dividendSummary?.annualDividendPerShare,
            lastDividendAmount: dividendSummary?.lastAmount,
            lastDividendExDate: dividendSummary?.lastExDate
        )
    }

    private func fetchFinnhubRecentNews(ticker: String, apiKey: String, daysBack: Int) async throws -> [TickerNewsArticle] {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let fromDate = calendar.date(byAdding: .day, value: -max(1, min(daysBack, 60)), to: now) ?? now
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents(string: "https://finnhub.io/api/v1/company-news")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: ticker.uppercased()),
            URLQueryItem(name: "from", value: formatter.string(from: fromDate)),
            URLQueryItem(name: "to", value: formatter.string(from: now)),
            URLQueryItem(name: "token", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        try validateFinnhubResponse(data: data, response: response)

        let decoded = try JSONDecoder().decode([FinnhubNewsResponse].self, from: data)
        let articles = decoded.compactMap { item -> TickerNewsArticle? in
            let headline = item.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headline.isEmpty, !url.isEmpty else { return nil }
            return TickerNewsArticle(
                headline: headline,
                source: item.source.trimmingCharacters(in: .whitespacesAndNewlines),
                summary: item.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                url: url,
                imageURL: item.image?.trimmingCharacters(in: .whitespacesAndNewlines),
                publishedAt: Date(timeIntervalSince1970: TimeInterval(item.datetime))
            )
        }

        return Array(articles.sorted { $0.publishedAt > $1.publishedAt }.prefix(12))
    }

    private func fetchFinnhubDividendPerShare(ticker: String, apiKey: String) async throws -> Double? {
        try await fetchFinnhubDividendSummary(ticker: ticker, apiKey: apiKey)?.annualDividendPerShare
    }

    private func fetchFinnhubDividendSummary(ticker: String, apiKey: String) async throws -> FinnhubDividendSummary? {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        guard let fromDate = calendar.date(byAdding: .year, value: -5, to: now) else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents(string: "https://finnhub.io/api/v1/stock/dividend2")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: ticker),
            URLQueryItem(name: "from", value: formatter.string(from: fromDate)),
            URLQueryItem(name: "to", value: formatter.string(from: now)),
            URLQueryItem(name: "token", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        try validateFinnhubResponse(data: data, response: response)

        let payouts: [FinnhubDividendResponse]
        if let wrapped = try? JSONDecoder().decode(FinnhubDividendWrappedResponse.self, from: data) {
            payouts = wrapped.data
        } else if let flat = try? JSONDecoder().decode([FinnhubDividendResponse].self, from: data) {
            payouts = flat
        } else {
            return nil
        }

        let positivePayouts = payouts.filter { $0.amountValue > 0 }
        if positivePayouts.isEmpty { return nil }

        // Primary estimate: trailing 12 months total from full dividend history.
        let trailing12m = positivePayouts.reduce(0.0) { partial, payout in
            guard let exDate = payout.exDateDate else { return partial }
            guard exDate >= calendar.date(byAdding: .year, value: -1, to: now) ?? now else { return partial }
            return partial + payout.amountValue
        }
        let sortedByDate = positivePayouts.sorted {
            ($0.exDateDate ?? .distantPast) > ($1.exDateDate ?? .distantPast)
        }
        if trailing12m > 0 {
            return FinnhubDividendSummary(
                annualDividendPerShare: trailing12m,
                lastAmount: sortedByDate.first?.amountValue,
                lastExDate: sortedByDate.first?.exDate
            )
        }

        // Fallback: use the latest dividend year total if no payments in trailing 12 months.
        guard let latestDate = sortedByDate.first?.exDateDate else { return nil }
        let latestYear = calendar.component(.year, from: latestDate)
        let latestYearTotal = sortedByDate.reduce(0.0) { partial, payout in
            guard let date = payout.exDateDate else { return partial }
            return calendar.component(.year, from: date) == latestYear ? partial + payout.amountValue : partial
        }
        let annualDividendPerShare = latestYearTotal
        return annualDividendPerShare > 0
            ? FinnhubDividendSummary(
                annualDividendPerShare: annualDividendPerShare,
                lastAmount: sortedByDate.first?.amountValue,
                lastExDate: sortedByDate.first?.exDate
            )
            : nil
    }

    private func validateFinnhubResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MarketDataServiceError.invalidResponse
        }
        if http.statusCode == 429 {
            throw MarketDataServiceError.rateLimited
        }
        guard (200..<300).contains(http.statusCode) else {
            if let body = String(data: data, encoding: .utf8)?.lowercased(),
               body.contains("limit") || body.contains("rate") || body.contains("too many requests") {
                throw MarketDataServiceError.rateLimited
            }
            throw MarketDataServiceError.invalidResponse
        }
        if let parsedError = try? JSONDecoder().decode(FinnhubErrorResponse.self, from: data),
           let message = parsedError.error?.lowercased(),
           !message.isEmpty {
            if message.contains("limit") || message.contains("rate") || message.contains("too many") {
                throw MarketDataServiceError.rateLimited
            }
            throw MarketDataServiceError.invalidResponse
        }
    }

    private func fetchAlpacaBars(ticker: String, start: Date, end: Date, keyId: String, secretKey: String, feed: AlpacaMarketDataFeed) async throws -> [AlpacaBar] {
        let request = try alpacaRequest(
            path: "stocks/\(ticker.uppercased())/bars",
            queryItems: [
                URLQueryItem(name: "timeframe", value: "1Day"),
                URLQueryItem(name: "start", value: Self.alpacaDateFormatter.string(from: start)),
                URLQueryItem(name: "end", value: Self.alpacaDateFormatter.string(from: end)),
                URLQueryItem(name: "adjustment", value: "raw"),
                URLQueryItem(name: "feed", value: feed.apiValue),
                URLQueryItem(name: "limit", value: "100")
            ],
            keyId: keyId,
            secretKey: secretKey
        )

        let (data, response) = try await session.data(for: request)
        try validateAlpacaResponse(data: data, response: response)

        let decoded = try JSONDecoder().decode(AlpacaBarsResponse.self, from: data)
        guard let bars = decoded.bars, !bars.isEmpty else {
            throw MarketDataServiceError.invalidPrice
        }
        return bars
    }

    private func fetchAlpacaCorporateActions(
        ticker: String,
        start: Date,
        end: Date,
        types: String,
        keyId: String,
        secretKey: String
    ) async throws -> [AlpacaCorporateAction] {
        let request = try alpacaRequest(
            baseURL: "https://data.alpaca.markets/v1",
            path: "corporate-actions",
            queryItems: [
                URLQueryItem(name: "symbols", value: ticker.uppercased()),
                URLQueryItem(name: "types", value: types),
                URLQueryItem(name: "start", value: Self.alpacaDayFormatter.string(from: start)),
                URLQueryItem(name: "end", value: Self.alpacaDayFormatter.string(from: end)),
                URLQueryItem(name: "limit", value: "1000"),
                URLQueryItem(name: "sort", value: "asc")
            ],
            keyId: keyId,
            secretKey: secretKey
        )

        let (data, response) = try await session.data(for: request)
        try validateAlpacaResponse(data: data, response: response)

        let decoded = try JSONDecoder().decode(AlpacaCorporateActionsResponse.self, from: data)
        return decoded.allActions
    }

    private func alpacaRequest(path: String, queryItems: [URLQueryItem], keyId: String, secretKey: String) throws -> URLRequest {
        try alpacaRequest(
            baseURL: "https://data.alpaca.markets/v2",
            path: path,
            queryItems: queryItems,
            keyId: keyId,
            secretKey: secretKey
        )
    }

    private func alpacaRequest(baseURL: String, path: String, queryItems: [URLQueryItem], keyId: String, secretKey: String) throws -> URLRequest {
        let cleanKeyId = keyId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKeyId.isEmpty, !cleanSecretKey.isEmpty else {
            throw MarketDataServiceError.missingAPIKey
        }

        var components = URLComponents(string: "\(baseURL)/\(path)")
        components?.queryItems = queryItems
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        var request = URLRequest(url: url)
        request.addValue(cleanKeyId, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.addValue(cleanSecretKey, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validateAlpacaResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MarketDataServiceError.invalidResponse
        }
        if http.statusCode == 429 {
            throw MarketDataServiceError.rateLimited
        }
        guard (200..<300).contains(http.statusCode) else {
            if let body = String(data: data, encoding: .utf8)?.lowercased(),
               body.contains("limit") || body.contains("rate") || body.contains("too many requests") {
                throw MarketDataServiceError.rateLimited
            }
            throw MarketDataServiceError.invalidResponse
        }
    }

    private static let alpacaDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let alpacaDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    fileprivate static func alpacaTradingDate(from timestamp: String) -> Date? {
        alpacaDateFormatter.date(from: timestamp) ?? alpacaDayFormatter.date(from: timestamp)
    }
}

struct MarketQuoteDetails: Sendable {
    let price: Double
    let annualDividendPerShare: Double?
}

struct MarketCompanyProfile: Sendable {
    let name: String?
    let exchange: String?
}

struct MarketQuoteSnapshot: Sendable {
    let price: Double
    let change: Double
    let percentChange: Double
    let open: Double?
    let high: Double?
    let low: Double?
    let previousClose: Double?
}

struct StockFinancials: Sendable {
    let fiscalYearEnd: String?
    let lastFiscalPeriod: String?
    let lastFiscalPeriodEndDate: String?
    let marketCapitalization: Double?
    let enterpriseValue: Double?
    let enterpriseValueToEBITDA: Double?
    let peRatio: Double?
    let psRatio: Double?
    let pbRatio: Double?
    let pcfRatio: Double?
    let pfcfRatio: Double?
    let totalRevenue: Double?
    let revenuePerShare: Double?
    let grossProfit: Double?
    let operatingIncome: Double?
    let netIncome: Double?
    let epsDilutedTTM: Double?
    let epsDilutedFQ: Double?
    let totalSharesOutstanding: Double?
    let sharesFloat: Double?
    let totalAssets: Double?
    let totalLiabilities: Double?
    let totalEquity: Double?
    let totalDebt: Double?
    let operatingCashFlow: Double?
    let investingCashFlow: Double?
    let financingCashFlow: Double?
    let freeCashFlow: Double?
    let capex: Double?
    let grossMargin: Double?
    let operatingMargin: Double?
    let pretaxMargin: Double?
    let netMargin: Double?
    let returnOnAssets: Double?
    let returnOnEquity: Double?
    let returnOnInvestedCapital: Double?
    let revenuePerEmployee: Double?
    let netIncomePerEmployee: Double?
    let averageVolume10Day: Double?
    let betaOneYear: Double?
    let week52High: Double?
    let week52Low: Double?
    let oneYearPriceTarget: Double?
    let dividendYieldIndicated: Double?
    let dividendsPerShareFY: Double?
    let lastDividendAmount: Double?
    let lastDividendExDate: String?
}

private struct AlphaVantageResponse: Decodable {
    struct GlobalQuote: Decodable {
        let price: String?

        enum CodingKeys: String, CodingKey {
            case price = "05. price"
        }
    }

    let globalQuote: GlobalQuote?
    let note: String?
    let information: String?

    enum CodingKeys: String, CodingKey {
        case globalQuote = "Global Quote"
        case note = "Note"
        case information = "Information"
    }
}

private struct FinnhubQuoteResponse: Decodable {
    let currentPrice: Double?
    let change: Double?
    let percentChange: Double?
    let high: Double?
    let low: Double?
    let open: Double?
    let previousClose: Double?

    enum CodingKeys: String, CodingKey {
        case currentPrice = "c"
        case change = "d"
        case percentChange = "dp"
        case high = "h"
        case low = "l"
        case open = "o"
        case previousClose = "pc"
    }
}

private struct AlphaVantageOverviewResponse: Decodable {
    let dividendPerShare: String?
    let note: String?
    let information: String?

    enum CodingKeys: String, CodingKey {
        case dividendPerShare = "DividendPerShare"
        case note = "Note"
        case information = "Information"
    }
}

private struct AlphaVantageTimeSeriesResponse: Decodable {
    struct DailyPoint: Decodable {
        let close: String

        enum CodingKeys: String, CodingKey {
            case close = "4. close"
        }
    }

    let timeSeries: [String: DailyPoint]?
    let note: String?
    let information: String?

    enum CodingKeys: String, CodingKey {
        case timeSeries = "Time Series (Daily)"
        case note = "Note"
        case information = "Information"
    }
}

private struct FinnhubCandleResponse: Decodable {
    let closes: [Double?]?
    let timestamps: [Int]?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case closes = "c"
        case timestamps = "t"
        case status = "s"
    }
}

private struct FinnhubErrorResponse: Decodable {
    let error: String?
}

private struct FinnhubDividendResponse: Decodable {
    let amount: Double?
    let cashAmount: Double?
    let exDate: String?

    var amountValue: Double {
        amount ?? cashAmount ?? 0
    }

    var exDateDate: Date? {
        guard let exDate else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: exDate)
    }

    enum CodingKeys: String, CodingKey {
        case amount = "amount"
        case cashAmount = "cashAmount"
        case exDate = "exDate"
    }
}

private struct FinnhubDividendWrappedResponse: Decodable {
    let data: [FinnhubDividendResponse]
}

private struct FinnhubDividendSummary {
    let annualDividendPerShare: Double
    let lastAmount: Double?
    let lastExDate: String?
}

struct SymbolLookupResult: Decodable, Identifiable, Sendable {
    let description: String
    let displaySymbol: String
    let symbol: String
    let type: String?
    let primaryExchange: String?

    var id: String { symbol }
}

private struct FinnhubSymbolLookupResponse: Decodable {
    let count: Int
    let result: [SymbolLookupResult]
}

private struct AlphaVantageSymbolSearchResponse: Decodable {
    struct Match: Decodable {
        let symbol: String
        let name: String
        let type: String?
        let region: String?

        enum CodingKeys: String, CodingKey {
            case symbol = "1. symbol"
            case name = "2. name"
            case type = "3. type"
            case region = "4. region"
        }
    }

    let bestMatches: [Match]?
    let note: String?
    let information: String?

    enum CodingKeys: String, CodingKey {
        case bestMatches = "bestMatches"
        case note = "Note"
        case information = "Information"
    }
}

private struct AlpacaAssetResponse: Decodable {
    let symbol: String
    let name: String
    let exchange: String?
    let status: String?
}

private struct FinnhubCompanyProfileResponse: Decodable {
    let name: String?
    let exchange: String?
}

private struct FinnhubStockMetricResponse: Decodable {
    let metric: [String: FinnhubMetricValue]
}

private enum FinnhubMetricValue: Decodable {
    case number(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            self = .string("")
        }
    }
}

private extension Dictionary where Key == String, Value == FinnhubMetricValue {
    func double(_ key: String) -> Double? {
        guard let value = self[key] else { return nil }
        switch value {
        case let .number(number):
            return number.isFinite ? number : nil
        case let .string(string):
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func string(_ key: String) -> String? {
        guard let value = self[key] else { return nil }
        switch value {
        case let .number(number):
            return number.formatted(.number.precision(.fractionLength(0...2)))
        case let .string(string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

private struct FinnhubNewsResponse: Decodable {
    let datetime: Int
    let headline: String
    let image: String?
    let source: String
    let summary: String
    let url: String
}

private struct AlpacaSnapshotResponse: Decodable {
    let latestTrade: AlpacaTrade?
    let minuteBar: AlpacaBar?
    let dailyBar: AlpacaBar?
    let prevDailyBar: AlpacaBar?
}

private struct AlpacaTrade: Decodable {
    let price: Double?

    enum CodingKeys: String, CodingKey {
        case price = "p"
    }
}

private struct AlpacaBarsResponse: Decodable {
    let bars: [AlpacaBar]?
}

private struct AlpacaBar: Decodable {
    let timestamp: String?
    let open: Double?
    let high: Double?
    let low: Double?
    let close: Double

    var tradingDate: Date? {
        guard let timestamp else { return nil }
        return MarketDataService.alpacaTradingDate(from: timestamp)
    }

    enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case open = "o"
        case high = "h"
        case low = "l"
        case close = "c"
    }
}

private struct AlpacaCorporateActionsResponse: Decodable {
    let corporateActions: [AlpacaCorporateAction]?
    let data: [String: [AlpacaCorporateAction]]?

    var allActions: [AlpacaCorporateAction] {
        if let corporateActions {
            return corporateActions
        }
        return data?.values.flatMap { $0 } ?? []
    }

    enum CodingKeys: String, CodingKey {
        case corporateActions = "corporate_actions"
        case data
    }
}

private struct AlpacaCorporateAction: Decodable {
    let cashAmount: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        cashAmount = Self.firstDouble(
            in: container,
            keys: [
                "cash",
                "cash_amount",
                "amount",
                "rate",
                "gross_amount",
                "net_amount",
                "cash_rate"
            ]
        )
    }

    private static func firstDouble(in container: KeyedDecodingContainer<DynamicCodingKey>, keys: [String]) -> Double? {
        for key in keys {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            if let value = try? container.decode(Double.self, forKey: codingKey) {
                return value
            }
            if let raw = try? container.decode(String.self, forKey: codingKey),
               let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return value
            }
        }
        return nil
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
