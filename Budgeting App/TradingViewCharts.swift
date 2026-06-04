import SwiftUI
import WebKit

// MARK: - Symbol formatting (OpenStock / Finnhub suffix conventions)

enum TradingViewSymbol {
    private static let exchangeSuffixMap: [String: String] = [
        ".TWO": "TPEX", ".TW": "TWSE", ".T": "TSE", ".HK": "HKEX", ".SS": "SSE", ".SZ": "SZSE",
        ".KS": "KRX", ".KQ": "KRX", ".SI": "SGX", ".AX": "ASX", ".NZ": "NZX", ".BO": "BSE", ".NS": "NSE",
        ".BK": "SET", ".JK": "IDX", ".KL": "MYX",
        ".L": "LSE", ".IL": "LSE", ".DE": "XETR", ".F": "FWB", ".PA": "EURONEXT", ".AS": "EURONEXT",
        ".BR": "EURONEXT", ".LS": "EURONEXT", ".MI": "MIL", ".MC": "BME", ".ST": "OMXSTO", ".HE": "OMXHEX",
        ".CO": "OMXCOP", ".OL": "OSL", ".SW": "SIX", ".VI": "VIE", ".WA": "GPW", ".PR": "PSE", ".AT": "ATHEX",
        ".IS": "BIST",
        ".TO": "TSX", ".V": "TSXV", ".SA": "BMFBOVESPA", ".MX": "BMV", ".BA": "BCBA",
        ".TA": "TASE", ".JO": "JSE"
    ]

    static func format(_ symbol: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return "" }

        let suffixes = exchangeSuffixMap.keys.sorted { $0.count > $1.count }
        for suffix in suffixes {
            if trimmed.hasSuffix(suffix.uppercased()) {
                let ticker = String(trimmed.dropLast(suffix.count))
                if let exchange = exchangeSuffixMap[suffix] {
                    return "\(exchange):\(ticker)"
                }
            }
        }
        return trimmed
    }
}

// MARK: - Widget kinds (TradingView free embed widgets)

enum TradingViewWidgetKind: Equatable {
    case marketQuotes(symbols: [String], groupName: String = "My Watchlist")
    case symbolOverview(symbol: String)
    case symbolInfo(symbol: String)
    case advancedChart(symbol: String, style: Int = 1)
    case baselineChart(symbol: String)
    case technicalAnalysis(symbol: String)
    case miniSymbolChart(symbol: String)

    var scriptURL: String {
        let base = "https://s3.tradingview.com/external-embedding/embed-widget-"
        switch self {
        case .marketQuotes:
            return base + "market-quotes.js"
        case .symbolOverview:
            return base + "symbol-overview.js"
        case .symbolInfo:
            return base + "symbol-info.js"
        case .advancedChart, .baselineChart, .miniSymbolChart:
            return base + "advanced-chart.js"
        case .technicalAnalysis:
            return base + "technical-analysis.js"
        }
    }

    func configuration(colorScheme: ColorScheme) -> [String: Any] {
        let theme = colorScheme == .dark ? "dark" : "light"
        let background = colorScheme == .dark ? "#141414" : "#FFFFFF"
        let gridColor = colorScheme == .dark ? "#1E1E1E" : "#F0F3FA"

        switch self {
        case let .marketQuotes(symbols, groupName):
            let formatted = symbols.map { symbol in
                [
                    "name": TradingViewSymbol.format(symbol),
                    "displayName": symbol.uppercased()
                ] as [String: String]
            }
            return [
                "width": "100%",
                "height": 460,
                "symbolsGroups": [
                    ["name": groupName, "symbols": formatted] as [String: Any]
                ],
                "showSymbolLogo": true,
                "showFloatingTooltip": false,
                "isTransparent": true,
                "colorTheme": theme,
                "locale": "en"
            ]

        case let .symbolOverview(symbol):
            let tvSymbol = TradingViewSymbol.format(symbol)
            return [
                "symbols": [["description": "", "proName": tvSymbol, "symbol": tvSymbol]],
                "chartOnly": true,
                "width": "100%",
                "height": "100%",
                "locale": "en",
                "colorTheme": theme,
                "autosize": true,
                "showVolume": false,
                "showMA": false,
                "hideDateRanges": true,
                "hideMarketStatus": true,
                "hideSymbolLogo": true,
                "isTransparent": true
            ]

        case let .symbolInfo(symbol):
            return [
                "symbol": TradingViewSymbol.format(symbol),
                "colorTheme": theme,
                "isTransparent": true,
                "locale": "en",
                "width": "100%",
                "height": 152
            ]

        case let .advancedChart(symbol, style):
            let tvSymbol = TradingViewSymbol.format(symbol)
            return [
                "allow_symbol_change": false,
                "calendar": false,
                "details": true,
                "hide_side_toolbar": false,
                "hide_top_toolbar": false,
                "hide_legend": false,
                "hide_volume": false,
                "hotlist": false,
                "interval": "D",
                "locale": "en",
                "save_image": false,
                "style": style,
                "symbol": tvSymbol,
                "theme": theme,
                "timezone": "exchange",
                "backgroundColor": background,
                "gridColor": gridColor,
                "watchlist": [] as [String],
                "withdateranges": true,
                "compareSymbols": [] as [String],
                "studies": [] as [String],
                "width": "100%",
                "height": 420
            ]

        case let .baselineChart(symbol):
            let tvSymbol = TradingViewSymbol.format(symbol)
            return [
                "allow_symbol_change": false,
                "calendar": false,
                "details": false,
                "hide_side_toolbar": true,
                "hide_top_toolbar": false,
                "hide_legend": false,
                "hide_volume": false,
                "hotlist": false,
                "interval": "D",
                "locale": "en",
                "save_image": false,
                "style": 10,
                "symbol": tvSymbol,
                "theme": theme,
                "timezone": "exchange",
                "backgroundColor": background,
                "gridColor": gridColor,
                "watchlist": [] as [String],
                "withdateranges": true,
                "compareSymbols": [] as [String],
                "studies": [] as [String],
                "width": "100%",
                "height": 320
            ]

        case let .technicalAnalysis(symbol):
            return [
                "symbol": TradingViewSymbol.format(symbol),
                "colorTheme": theme,
                "isTransparent": true,
                "locale": "en",
                "width": "100%",
                "height": 360,
                "interval": "1D",
                "showIntervalTabs": true
            ]

        case let .miniSymbolChart(symbol):
            let tvSymbol = TradingViewSymbol.format(symbol)
            return [
                "allow_symbol_change": false,
                "calendar": false,
                "details": false,
                "hide_side_toolbar": true,
                "hide_top_toolbar": true,
                "hide_legend": true,
                "hide_volume": true,
                "hotlist": false,
                "interval": "D",
                "locale": "en",
                "save_image": false,
                "style": 3,
                "symbol": tvSymbol,
                "theme": theme,
                "timezone": "exchange",
                "backgroundColor": background,
                "gridColor": gridColor,
                "watchlist": [] as [String],
                "withdateranges": false,
                "compareSymbols": [] as [String],
                "studies": [] as [String],
                "width": "100%",
                "height": 72
            ]
        }
    }
}

// MARK: - WKWebView embed host

private struct TradingViewEmbedWebView: UIViewRepresentable {
    let kind: TradingViewWidgetKind
    let colorScheme: ColorScheme
    var isUserInteractionEnabled = true
    @Binding var didFailToLoad: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(didFailToLoad: $didFailToLoad)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = isUserInteractionEnabled
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let signature = context.coordinator.signature(for: kind, colorScheme: colorScheme)
        guard context.coordinator.lastSignature != signature else { return }
        context.coordinator.lastSignature = signature
        didFailToLoad = false
        webView.isUserInteractionEnabled = isUserInteractionEnabled

        guard let html = Self.html(for: kind, colorScheme: colorScheme) else {
            didFailToLoad = true
            return
        }
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.tradingview.com"))
    }

    private static func html(for kind: TradingViewWidgetKind, colorScheme: ColorScheme) -> String? {
        guard let configData = try? JSONSerialization.data(withJSONObject: kind.configuration(colorScheme: colorScheme)),
              let configJSON = String(data: configData, encoding: .utf8) else {
            return nil
        }

        let escapedConfig = configJSON
            .replacingOccurrences(of: "</", with: "<\\/")
        let extraCSS: String
        switch kind {
        case .symbolInfo:
            extraCSS = """
              body { transform: scale(0.72); transform-origin: top left; width: 138.9%; height: 138.9%; }
            """
        default:
            extraCSS = ""
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
        <style>
          html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; height: 100%; width: 100%; }
          .tradingview-widget-container { height: 100%; width: 100%; }
          .tradingview-widget-container__widget { height: 100%; width: 100%; }
          .tv-widget-market-quotes__symbol-cell,
          .tv-widget-market-quotes__symbol { width: 1%; white-space: nowrap; }
          \(extraCSS)
        </style>
        </head>
        <body>
        <div class="tradingview-widget-container">
          <div class="tradingview-widget-container__widget"></div>
          <script type="text/javascript" src="\(kind.scriptURL)" async>
          \(escapedConfig)
          </script>
        </div>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var didFailToLoad: Bool
        var lastSignature: String?

        init(didFailToLoad: Binding<Bool>) {
            _didFailToLoad = didFailToLoad
        }

        func signature(for kind: TradingViewWidgetKind, colorScheme: ColorScheme) -> String {
            let config = kind.configuration(colorScheme: colorScheme)
            let data = (try? JSONSerialization.data(withJSONObject: config)) ?? Data()
            return "\(kind.scriptURL)-\(colorScheme)-\(data.base64EncodedString())"
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            didFailToLoad = true
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            didFailToLoad = true
        }
    }
}

// MARK: - SwiftUI wrappers

struct TradingViewWidgetContainer: View {
    let kind: TradingViewWidgetKind
    var height: CGFloat
    var isUserInteractionEnabled = true
    var fallback: (() -> AnyView)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var didFailToLoad = false

    var body: some View {
        Group {
            if didFailToLoad, let fallback {
                fallback()
            } else {
                TradingViewEmbedWebView(
                    kind: kind,
                    colorScheme: colorScheme,
                    isUserInteractionEnabled: isUserInteractionEnabled,
                    didFailToLoad: $didFailToLoad
                )
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .accessibilityLabel("TradingView chart")
    }
}

struct TradingViewWatchlistBoard: View {
    let symbols: [String]
    var onSelectSymbol: ((String) -> Void)? = nil

    private var height: CGFloat {
        min(460, CGFloat(max(symbols.count, 3)) * 52 + 120)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TradingViewWidgetContainer(
                kind: .marketQuotes(symbols: symbols),
                height: height
            )

            if let onSelectSymbol {
                VStack(spacing: 0) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            onSelectSymbol(symbol.uppercased())
                        } label: {
                            Color.clear
                                .frame(width: 132, height: 52)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(symbol) snapshot")
                    }
                }
                .padding(.top, 78)
                .padding(.leading, 0)
            }
        }
        .frame(height: height)
    }
}

struct TradingViewTickerChartPanel: View {
    let symbol: String
    var showsTechnicalAnalysis: Bool = true
    var showsSymbolInfo: Bool = true
    let fallbackPoints: [TickerPricePoint]
    let trendIsPositive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var chartStyle: ChartDisplayStyle = .candlestick

    enum ChartDisplayStyle: String, CaseIterable, Identifiable {
        case candlestick = "Candles"
        case baseline = "Baseline"
        case area = "Area"

        var id: String { rawValue }

        var tradingViewStyle: Int {
            switch self {
            case .candlestick: return 1
            case .baseline: return 10
            case .area: return 3
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsSymbolInfo {
                TradingViewWidgetContainer(
                    kind: .symbolInfo(symbol: symbol),
                    height: 118,
                    fallback: { AnyView(compactFallback) }
                )
            }

            Picker("Chart style", selection: $chartStyle) {
                ForEach(ChartDisplayStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)

            TradingViewWidgetContainer(
                kind: .advancedChart(symbol: symbol, style: chartStyle.tradingViewStyle),
                height: 400,
                fallback: { AnyView(detailedFallback) }
            )
            .id("\(symbol)-\(chartStyle.rawValue)-\(colorScheme)")

            if showsTechnicalAnalysis {
                TradingViewWidgetContainer(
                    kind: .technicalAnalysis(symbol: symbol),
                    height: 460,
                    isUserInteractionEnabled: false,
                    fallback: { AnyView(EmptyView()) }
                )
            }
        }
    }

    private var compactFallback: some View {
        TickerPriceHistoryChart(
            points: fallbackPoints,
            trendIsPositive: trendIsPositive,
            style: .compact,
            symbol: nil
        )
    }

    private var detailedFallback: some View {
        TickerPriceHistoryChart(
            points: fallbackPoints,
            trendIsPositive: trendIsPositive,
            style: .detailed,
            symbol: nil
        )
    }
}

struct TradingViewCompactTickerChart: View {
    let symbol: String
    let fallbackPoints: [TickerPricePoint]
    let trendIsPositive: Bool
    var height: CGFloat = 80

    var body: some View {
        TradingViewWidgetContainer(
            kind: .miniSymbolChart(symbol: symbol),
            height: height,
            fallback: {
                AnyView(
                    TickerPriceHistoryChart(
                        points: fallbackPoints,
                        trendIsPositive: trendIsPositive,
                        style: .compact,
                        symbol: nil
                    )
                )
            }
        )
    }
}

struct TradingViewHoldingChartDetailView: View {
    let symbol: String
    let fallbackPoints: [TickerPricePoint]
    let trendIsPositive: Bool
    let marketDataSettings: MarketDataSettings?

    @State private var stockFinancials: StockFinancials?
    @State private var financialsError: String?

    private let marketDataService = MarketDataService()

    init(
        symbol: String,
        fallbackPoints: [TickerPricePoint],
        trendIsPositive: Bool,
        marketDataSettings: MarketDataSettings? = nil
    ) {
        self.symbol = symbol
        self.fallbackPoints = fallbackPoints
        self.trendIsPositive = trendIsPositive
        self.marketDataSettings = marketDataSettings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TradingViewTickerChartPanel(
                    symbol: symbol,
                    showsTechnicalAnalysis: true,
                    fallbackPoints: fallbackPoints,
                    trendIsPositive: trendIsPositive
                )

                if let stockFinancials {
                    StockFinancialsPanel(symbol: symbol, financials: stockFinancials)
                } else if let financialsError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(symbol.uppercased()) Financials")
                            .font(.headline)
                        Text(financialsError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await refreshFinancials()
        }
        .navigationTitle("TradingView")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func refreshFinancials() async {
        guard stockFinancials == nil else { return }
        guard let marketDataSettings, marketDataSettings.canFetchMarketData else {
            financialsError = "Financial metrics need Finnhub market data settings."
            return
        }
        do {
            stockFinancials = try await marketDataService.fetchStockFinancials(
                ticker: symbol.uppercased(),
                settings: marketDataSettings
            )
            financialsError = nil
        } catch {
            financialsError = "Financial metrics are unavailable for this ticker."
        }
    }
}

struct StockFinancialsPanel: View {
    let symbol: String
    let financials: StockFinancials
    var annualDividendPerShare: Double?

    private struct FinancialDisplayRow: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    private struct FinancialDisplaySection: Identifiable {
        let id = UUID()
        let title: String
        let rows: [FinancialDisplayRow]
    }

    var body: some View {
        let sections = financialDisplaySections(for: financials)
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                Text(symbol.uppercased())
                    .foregroundStyle(.blue)
                Text("Financials")
                    .foregroundStyle(.primary)
                Spacer()
                Text("TradingView")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.55)
            .lineLimit(1)

            fiscalSummary

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 22, alignment: .top),
                    GridItem(.flexible(), spacing: 22, alignment: .top)
                ],
                alignment: .leading,
                spacing: 26
            ) {
                ForEach(sections) { section in
                    financialSection(section)
                }
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    private var fiscalSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            financialRow("Fiscal year end", value: financials.fiscalYearEnd ?? "--")
            financialRow("Last fiscal period", value: financials.lastFiscalPeriod ?? "--")
            financialRow("Last fiscal period end date", value: financials.lastFiscalPeriodEndDate ?? "--")
        }
    }

    private func financialSection(_ section: FinancialDisplaySection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.top, 2)
            ForEach(section.rows) { row in
                financialRow(row.label, value: row.value)
            }
        }
    }

    private func financialRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 10)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func financialDisplaySections(for financials: StockFinancials) -> [FinancialDisplaySection] {
        [
            FinancialDisplaySection(
                title: "Valuation",
                rows: [
                    row("Market capitalization", formatFinancialMillions(financials.marketCapitalization)),
                    row("Enterprise value", formatFinancialMillions(financials.enterpriseValue)),
                    row("Enterprise value/EBITDA (TTM)", formatNumber(financials.enterpriseValueToEBITDA)),
                    row("P/E ratio", formatNumber(financials.peRatio)),
                    row("P/S ratio", formatNumber(financials.psRatio)),
                    row("P/B ratio", formatNumber(financials.pbRatio)),
                    row("P/CF ratio", formatNumber(financials.pcfRatio)),
                    row("P/FCF ratio", formatNumber(financials.pfcfRatio))
                ]
            ),
            FinancialDisplaySection(
                title: "Cash Flow",
                rows: [
                    row("Operating cash flow (TTM)", formatFinancialMillions(financials.operatingCashFlow)),
                    row("Investing cash flow (TTM)", formatFinancialMillions(financials.investingCashFlow)),
                    row("Financing cash flow (TTM)", formatFinancialMillions(financials.financingCashFlow)),
                    row("Free cash flow (TTM)", formatFinancialMillions(financials.freeCashFlow)),
                    row("CapEx (TTM)", formatFinancialMillions(financials.capex))
                ]
            ),
            FinancialDisplaySection(
                title: "Income Statement",
                rows: [
                    row("Total revenue (TTM)", formatFinancialMillions(financials.totalRevenue)),
                    row("Revenue per share (TTM)", formatNumber(financials.revenuePerShare)),
                    row("Gross profit (TTM)", formatFinancialMillions(financials.grossProfit)),
                    row("Operating income (TTM)", formatFinancialMillions(financials.operatingIncome)),
                    row("Net income (TTM)", formatFinancialMillions(financials.netIncome)),
                    row("EPS diluted (TTM)", formatNumber(financials.epsDilutedTTM)),
                    row("EPS diluted (FQ)", formatNumber(financials.epsDilutedFQ)),
                    row("Total shares outstanding", formatFinancialMillions(financials.totalSharesOutstanding)),
                    row("Shares float", formatFinancialMillions(financials.sharesFloat))
                ]
            ),
            FinancialDisplaySection(
                title: "Profitability",
                rows: [
                    row("Gross margin (TTM)", formatPercent(financials.grossMargin)),
                    row("Operating margin (TTM)", formatPercent(financials.operatingMargin)),
                    row("Pretax margin (TTM)", formatPercent(financials.pretaxMargin)),
                    row("Net margin (TTM)", formatPercent(financials.netMargin))
                ]
            ),
            FinancialDisplaySection(
                title: "Balance Sheet",
                rows: [
                    row("Total assets (FQ)", formatFinancialMillions(financials.totalAssets)),
                    row("Total liabilities (FQ)", formatFinancialMillions(financials.totalLiabilities)),
                    row("Total equity (FQ)", formatFinancialMillions(financials.totalEquity)),
                    row("Total debt (FQ)", formatFinancialMillions(financials.totalDebt))
                ]
            ),
            FinancialDisplaySection(
                title: "Efficiency",
                rows: [
                    row("Return on assets (TTM)", formatPercent(financials.returnOnAssets)),
                    row("Return on equity (TTM)", formatPercent(financials.returnOnEquity)),
                    row("Return on invested capital (TTM)", formatPercent(financials.returnOnInvestedCapital)),
                    row("Revenue per employee (FY)", formatAbbreviated(financials.revenuePerEmployee)),
                    row("Net income per employee (FY)", formatAbbreviated(financials.netIncomePerEmployee))
                ]
            ),
            FinancialDisplaySection(
                title: "Price History",
                rows: [
                    row("Average volume (10 day)", formatVolumeMillions(financials.averageVolume10Day)),
                    row("1-Year beta", formatNumber(financials.betaOneYear)),
                    row("52 Week high", formatNumber(financials.week52High)),
                    row("52 Week low", formatNumber(financials.week52Low)),
                    row("1 year price target", formatNumber(financials.oneYearPriceTarget))
                ]
            ),
            FinancialDisplaySection(
                title: "Dividends",
                rows: [
                    row("Dividend yield indicated", formatPercent(financials.dividendYieldIndicated)),
                    row("Dividends per share (FY)", formatNumber(financials.dividendsPerShareFY ?? annualDividendPerShare)),
                    row("Last payment amount", formatNumber(financials.lastDividendAmount)),
                    row("Last ex-dividend date", financials.lastDividendExDate ?? "--")
                ]
            )
        ]
    }

    private func row(_ label: String, _ value: String) -> FinancialDisplayRow {
        FinancialDisplayRow(label: label, value: value)
    }

    private func formatFinancialMillions(_ value: Double?) -> String {
        guard let value else { return "--" }
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return "\(formatCompact(value / 1_000_000))T"
        }
        if absValue >= 1_000 {
            return "\(formatCompact(value / 1_000))B"
        }
        return "\(formatCompact(value))M"
    }

    private func formatVolumeMillions(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(formatCompact(value))M"
    }

    private func formatAbbreviated(_ value: Double?) -> String {
        guard let value else { return "--" }
        let absValue = abs(value)
        if absValue >= 1_000_000_000_000 {
            return "\(formatCompact(value / 1_000_000_000_000))T"
        }
        if absValue >= 1_000_000_000 {
            return "\(formatCompact(value / 1_000_000_000))B"
        }
        if absValue >= 1_000_000 {
            return "\(formatCompact(value / 1_000_000))M"
        }
        if absValue >= 1_000 {
            return "\(formatCompact(value / 1_000))K"
        }
        return formatCompact(value)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(formatCompact(value))%"
    }

    private func formatNumber(_ value: Double?) -> String {
        guard let value else { return "--" }
        return formatCompact(value)
    }

    private func formatCompact(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = abs(value) >= 100 ? 1 : 2
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }
}
