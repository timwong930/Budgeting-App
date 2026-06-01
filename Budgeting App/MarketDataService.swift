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
        guard decoded.currentPrice > 0 else {
            throw MarketDataServiceError.invalidPrice
        }
        return decoded.currentPrice
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

        var components = URLComponents(string: "https://finnhub.io/api/v1/stock/candle")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: ticker),
            URLQueryItem(name: "resolution", value: "D"),
            URLQueryItem(name: "from", value: String(from)),
            URLQueryItem(name: "to", value: String(to)),
            URLQueryItem(name: "token", value: apiKey)
        ]
        guard let url = components?.url else { throw MarketDataServiceError.invalidResponse }

        let (data, response) = try await session.data(from: url)
        try validateFinnhubResponse(data: data, response: response)

        let decoded = try JSONDecoder().decode(FinnhubCandleResponse.self, from: data)
        guard decoded.status == "ok", let closes = decoded.closes, !closes.isEmpty else {
            throw MarketDataServiceError.invalidPrice
        }
        guard let close = closes.last, close > 0 else {
            throw MarketDataServiceError.invalidPrice
        }
        return close
    }

    private func fetchFinnhubDividendPerShare(ticker: String, apiKey: String) async throws -> Double? {
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
        if trailing12m > 0 {
            return trailing12m
        }

        // Fallback: use the latest dividend year total if no payments in trailing 12 months.
        let sortedByDate = positivePayouts.sorted {
            ($0.exDateDate ?? .distantPast) > ($1.exDateDate ?? .distantPast)
        }
        guard let latestDate = sortedByDate.first?.exDateDate else { return nil }
        let latestYear = calendar.component(.year, from: latestDate)
        let latestYearTotal = sortedByDate.reduce(0.0) { partial, payout in
            guard let date = payout.exDateDate else { return partial }
            return calendar.component(.year, from: date) == latestYear ? partial + payout.amountValue : partial
        }
        let annualDividendPerShare = latestYearTotal
        return annualDividendPerShare > 0 ? annualDividendPerShare : nil
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
    }
}

struct MarketQuoteDetails: Sendable {
    let price: Double
    let annualDividendPerShare: Double?
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
    let currentPrice: Double

    enum CodingKeys: String, CodingKey {
        case currentPrice = "c"
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
    let closes: [Double]?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case closes = "c"
        case status = "s"
    }
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
