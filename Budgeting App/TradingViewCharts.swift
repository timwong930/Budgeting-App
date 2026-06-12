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
    case miniSymbolChart(symbol: String, height: Int = 72)
    case timeline
    case fundamentalData(symbol: String)

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
        case .timeline:
            return base + "timeline.js"
        case .fundamentalData:
            return base + "financials.js"
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

        case let .miniSymbolChart(symbol, widgetHeight):
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
                "height": widgetHeight
            ]

        case .timeline:
            return [
                "feedMode": "market",
                "market": "stock",
                "isTransparent": true,
                "displayMode": "regular",
                "width": "100%",
                "height": 1200,
                "colorTheme": theme,
                "locale": "en"
            ]

        case let .fundamentalData(symbol):
            return [
                "symbol": TradingViewSymbol.format(symbol),
                "colorTheme": theme,
                "isTransparent": true,
                "largeChartUrl": "",
                "displayMode": "regular",
                "width": "100%",
                "height": 825,
                "locale": "en"
            ]
        }
    }
}

// MARK: - WKWebView embed host

private struct TradingViewEmbedWebView: UIViewRepresentable {
    let kind: TradingViewWidgetKind
    let colorScheme: ColorScheme
    var isUserInteractionEnabled = true
    var isScrollEnabled = false
    @Binding var didFailToLoad: Bool
    var onNavigate: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(didFailToLoad: $didFailToLoad, onNavigate: onNavigate)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.bounces = isScrollEnabled
        webView.isUserInteractionEnabled = isUserInteractionEnabled
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isUserInteractionEnabled = isUserInteractionEnabled
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.bounces = isScrollEnabled
        context.coordinator.onNavigate = onNavigate

        let contentSignature = context.coordinator.contentSignature(for: kind, colorScheme: colorScheme)
        guard context.coordinator.lastContentSignature != contentSignature else { return }
        context.coordinator.lastContentSignature = contentSignature
        didFailToLoad = false

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

        let baseCSS: String
        let containerCSS: String
        switch kind {
        case .timeline:
            baseCSS = """
              html, body { margin: 0; padding: 0; background: transparent; }
            """
            containerCSS = ""
        case .symbolInfo:
            baseCSS = """
              html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; height: 100%; width: 100%; }
              body { transform: scale(0.72); transform-origin: top left; width: 138.9%; height: 138.9%; }
            """
            containerCSS = "height: 100%; width: 100%;"
        default:
            baseCSS = """
              html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; height: 100%; width: 100%; }
            """
            containerCSS = "height: 100%; width: 100%;"
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
        <style>
          \(baseCSS)
          .tradingview-widget-container { \(containerCSS) }
          .tradingview-widget-container__widget { \(containerCSS) }
          .tv-widget-market-quotes__symbol-cell,
          .tv-widget-market-quotes__symbol { width: 1%; white-space: nowrap; }
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
        var lastContentSignature: String?
        var onNavigate: ((URL) -> Void)?

        init(didFailToLoad: Binding<Bool>, onNavigate: ((URL) -> Void)?) {
            _didFailToLoad = didFailToLoad
            self.onNavigate = onNavigate
        }

        func contentSignature(for kind: TradingViewWidgetKind, colorScheme: ColorScheme) -> String {
            let config = kind.configuration(colorScheme: colorScheme)
            let data = (try? JSONSerialization.data(withJSONObject: config)) ?? Data()
            return "\(kind.scriptURL)-\(data.base64EncodedString())"
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               let onNavigate,
               navigationAction.navigationType == .linkActivated {
                onNavigate(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
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
    var isScrollEnabled = false
    var fallback: (() -> AnyView)?
    var onNavigate: ((URL) -> Void)?

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
                    isScrollEnabled: isScrollEnabled,
                    didFailToLoad: $didFailToLoad,
                    onNavigate: onNavigate
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
            kind: .miniSymbolChart(symbol: symbol, height: Int(height)),
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

    init(
        symbol: String,
        fallbackPoints: [TickerPricePoint],
        trendIsPositive: Bool,
        marketDataSettings: MarketDataSettings? = nil
    ) {
        self.symbol = symbol
        self.fallbackPoints = fallbackPoints
        self.trendIsPositive = trendIsPositive
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

                TradingViewWidgetContainer(
                    kind: .fundamentalData(symbol: symbol),
                    height: 825,
                    isUserInteractionEnabled: true,
                    isScrollEnabled: true
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("TradingView")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TradingViewTimelineNews: View {
    var onNavigate: ((URL) -> Void)?

    var body: some View {
        TradingViewWidgetContainer(
            kind: .timeline,
            height: 600,
            isUserInteractionEnabled: true,
            isScrollEnabled: true,
            onNavigate: onNavigate
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}




