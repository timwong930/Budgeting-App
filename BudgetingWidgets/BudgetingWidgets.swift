import WidgetKit
import SwiftUI

// MARK: - Constants

private let appGroupIdentifier = "group.Timothy-Wong.Budgeting-App"
private let saveFileName = "budget.json"

private enum WidgetAction {
    static let addIncome = URL(string: "momosmoney://addIncome")!
    static let addExpense = URL(string: "momosmoney://addExpense")!
    static let budgetTab = URL(string: "momosmoney://tab/budget")!
    static let marginTab = URL(string: "momosmoney://tab/margin")!
    static let homeTab = URL(string: "momosmoney://tab/home")!
}

// MARK: - Snapshot Models

private struct WidgetSnapshot: Codable {
    let income: Double
    let incomeByMonth: [String: Double]?
    let payFrequency: String
    let needsCategories: [WidgetCategory]
    let wantsCategories: [WidgetCategory]
    let savingsGoals: [WidgetSavingsGoal]
    let portfolioSnapshot: WidgetPortfolioSnapshot?
    let holdings: [WidgetHolding]?
    let cachedQuotes: [String: WidgetCachedQuote]?
    let watchlistTickers: [String]?
}

private struct WidgetCategory: Codable {
    let id: UUID
    let name: String
    let allocatedAmount: Double
    let budgetedAmount: Double?
    let spendByDate: [String: Double]?
    let rollover: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        allocatedAmount = try container.decode(Double.self, forKey: .allocatedAmount)
        budgetedAmount = try container.decodeIfPresent(Double.self, forKey: .budgetedAmount)
        spendByDate = try container.decodeIfPresent([String: Double].self, forKey: .spendByDate)
        rollover = try container.decodeIfPresent(Bool.self, forKey: .rollover)
    }
}

private struct WidgetSavingsGoal: Codable {
    let id: UUID
    let name: String
    let monthlyContribution: Double
    let currentAmount: Double
    let targetAmount: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        monthlyContribution = try container.decode(Double.self, forKey: .monthlyContribution)
        currentAmount = try container.decodeIfPresent(Double.self, forKey: .currentAmount) ?? 0
        targetAmount = try container.decodeIfPresent(Double.self, forKey: .targetAmount) ?? 0
    }
}

private struct WidgetPortfolioSnapshot: Codable {
    let portfolioValue: Double
    let cashBalance: Double
    let marginUsed: Double
}

private struct WidgetHolding: Codable {
    let ticker: String
    let shares: Double
    let currentPrice: Double
}

private struct WidgetCachedQuote: Codable {
    let ticker: String
    let price: Double
}

// MARK: - Data Store

private struct WidgetDataStore {
    static func load() -> WidgetSnapshot? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }

        let saveURL = containerURL.appendingPathComponent(saveFileName)
        guard let data = try? Data(contentsOf: saveURL),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return nil }

        return snapshot
    }
}

// MARK: - Helpers

private let monthKeyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM"
    return f
}()

private let currency: (Double) -> String = {
    $0.formatted(.currency(code: "USD").precision(.fractionLength(0)))
}

// MARK: - Budget Entry

struct BudgetWidgetEntry: TimelineEntry {
    let date: Date
    let monthlyIncome: Double
    let needsBudget: Double
    let wantsBudget: Double
    let savingsBudget: Double
    let needsAllocated: Double
    let wantsAllocated: Double
    let savingsAllocated: Double

    static let placeholder = BudgetWidgetEntry(
        date: Date(),
        monthlyIncome: 6000,
        needsBudget: 3000,
        wantsBudget: 1200,
        savingsBudget: 1800,
        needsAllocated: 2200,
        wantsAllocated: 950,
        savingsAllocated: 1400
    )

    var remainingBudget: Double {
        (needsBudget - needsAllocated) + (wantsBudget - wantsAllocated) + (savingsBudget - savingsAllocated)
    }

    var spendRate: Double {
        let total = needsBudget + wantsBudget + savingsBudget
        guard total > 0 else { return 0 }
        return (needsAllocated + wantsAllocated + savingsAllocated) / total
    }
}

private func makeBudgetEntry(from snapshot: WidgetSnapshot, date: Date) -> BudgetWidgetEntry {
    let monthKey = monthKeyFormatter.string(from: date)
    let currentIncome = snapshot.incomeByMonth?[monthKey] ?? snapshot.income
    let payMultiplier: Double = {
        switch snapshot.payFrequency {
        case "Weekly": return 52.0
        case "Bi-Weekly": return 26.0
        case "Monthly": return 12.0
        case "Annually": return 1.0
        default: return 12.0
        }
    }()
    let monthlyIncome = (currentIncome * payMultiplier) / 12.0
    let needsBudget = monthlyIncome * 0.50
    let wantsBudget = monthlyIncome * 0.20
    let savingsBudget = monthlyIncome * 0.30

    let needsAllocated = snapshot.needsCategories.reduce(0) { $0 + $1.allocatedAmount }
    let wantsAllocated = snapshot.wantsCategories.reduce(0) { $0 + $1.allocatedAmount }
    let savingsAllocated = snapshot.savingsGoals.reduce(0) { $0 + $1.monthlyContribution }

    return BudgetWidgetEntry(
        date: date,
        monthlyIncome: monthlyIncome,
        needsBudget: needsBudget,
        wantsBudget: wantsBudget,
        savingsBudget: savingsBudget,
        needsAllocated: needsAllocated,
        wantsAllocated: wantsAllocated,
        savingsAllocated: savingsAllocated
    )
}

// MARK: - Budget Provider

struct BudgetWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetWidgetEntry) -> Void) {
        let entry = WidgetDataStore.load().map { makeBudgetEntry(from: $0, date: Date()) } ?? .placeholder
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetWidgetEntry>) -> Void) {
        let entry = WidgetDataStore.load().map { makeBudgetEntry(from: $0, date: Date()) } ?? .placeholder
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Portfolio Entry

struct PortfolioWidgetEntry: TimelineEntry {
    let date: Date
    let portfolioValue: Double
    let cashBalance: Double
    let marginUsed: Double
    let holdingsCount: Int
    let topHoldings: [HoldingSummary]

    struct HoldingSummary {
        let ticker: String
        let value: Double
        let pctOfPortfolio: Double
    }

    static let placeholder = PortfolioWidgetEntry(
        date: Date(),
        portfolioValue: 25000,
        cashBalance: 5000,
        marginUsed: 3000,
        holdingsCount: 6,
        topHoldings: [
            HoldingSummary(ticker: "AAPL", value: 8500, pctOfPortfolio: 0.34),
            HoldingSummary(ticker: "NVDA", value: 6200, pctOfPortfolio: 0.25),
        ]
    )
}

private func makePortfolioEntry(from snapshot: WidgetSnapshot, date: Date) -> PortfolioWidgetEntry {
    let holdings = snapshot.holdings ?? []
    let quotes = snapshot.cachedQuotes ?? [:]

    let holdingsValue = holdings.reduce(0) { sum, h in
        let price = quotes[h.ticker.uppercased()]?.price ?? h.currentPrice
        return sum + (h.shares * price)
    }

    let cash = snapshot.portfolioSnapshot?.cashBalance ?? 0
    let margin = snapshot.portfolioSnapshot?.marginUsed ?? 0
    let portfolioValue = holdingsValue + cash

    let summaries: [PortfolioWidgetEntry.HoldingSummary] = holdings
        .map { h in
            let price = quotes[h.ticker.uppercased()]?.price ?? h.currentPrice
            let val = h.shares * price
            return PortfolioWidgetEntry.HoldingSummary(
                ticker: h.ticker,
                value: val,
                pctOfPortfolio: portfolioValue > 0 ? val / portfolioValue : 0
            )
        }
        .sorted { $0.value > $1.value }
        .prefix(3)
        .map { $0 }

    return PortfolioWidgetEntry(
        date: date,
        portfolioValue: portfolioValue,
        cashBalance: cash,
        marginUsed: margin,
        holdingsCount: holdings.count,
        topHoldings: summaries
    )
}

// MARK: - Portfolio Provider

struct PortfolioWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PortfolioWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (PortfolioWidgetEntry) -> Void) {
        let entry = WidgetDataStore.load().map { makePortfolioEntry(from: $0, date: Date()) } ?? .placeholder
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortfolioWidgetEntry>) -> Void) {
        let entry = WidgetDataStore.load().map { makePortfolioEntry(from: $0, date: Date()) } ?? .placeholder
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Watchlist Entry

struct WatchlistWidgetEntry: TimelineEntry {
    let date: Date
    let tickers: [WatchlistRow]

    struct WatchlistRow {
        let symbol: String
        let price: Double
    }

    static let placeholder = WatchlistWidgetEntry(
        date: Date(),
        tickers: [
            WatchlistRow(symbol: "AAPL", price: 198.50),
            WatchlistRow(symbol: "NVDA", price: 875.20),
            WatchlistRow(symbol: "MSFT", price: 425.30),
        ]
    )
}

private func makeWatchlistEntry(from snapshot: WidgetSnapshot, date: Date) -> WatchlistWidgetEntry {
    let tickers = snapshot.watchlistTickers ?? []
    let quotes = snapshot.cachedQuotes ?? [:]

    let rows: [WatchlistWidgetEntry.WatchlistRow] = tickers.prefix(5).compactMap { symbol in
        guard let quote = quotes[symbol.uppercased()] else { return nil }
        return WatchlistWidgetEntry.WatchlistRow(symbol: symbol, price: quote.price)
    }

    return WatchlistWidgetEntry(date: date, tickers: rows)
}

// MARK: - Watchlist Provider

struct WatchlistWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchlistWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchlistWidgetEntry) -> Void) {
        let entry = WidgetDataStore.load().map { makeWatchlistEntry(from: $0, date: Date()) } ?? .placeholder
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchlistWidgetEntry>) -> Void) {
        let entry = WidgetDataStore.load().map { makeWatchlistEntry(from: $0, date: Date()) } ?? .placeholder
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Shared UI Components

private struct BudgetBar: View {
    let label: String
    let used: Double
    let total: Double
    let tint: Color

    private var pct: Double {
        guard total > 0 else { return 0 }
        return min(used / total, 1.4)
    }

    private var remaining: Double {
        max(total - used, 0)
    }

    private var isOverBudget: Bool {
        used > total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(currency(used)) / \(currency(total))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.fill.quaternary)
                    Capsule()
                        .fill(isOverBudget ? .red : tint)
                        .frame(width: geo.size.width * min(pct, 1))
                }
                .clipped()
            }
            .frame(height: 6)
        }
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let url: URL

    var body: some View {
        Link(destination: url) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(color.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.15), lineWidth: 0.5)
                )
        }
    }
}

private struct CardHeader: View {
    let title: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
        }
    }
}

// MARK: - Budget Widget Views

struct BudgetingWidgetsEntryView: View {
    var entry: BudgetWidgetProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text("Budget Left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Text(entry.remainingBudget, format: .currency(code: "USD"))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundColor(entry.remainingBudget >= 0 ? .primary : .red)

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(entry.monthlyIncome, format: .currency(code: "USD"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("mo")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 16) {
                Link(destination: WidgetAction.addIncome) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                }
                Link(destination: WidgetAction.addExpense) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .clipped()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: "This Month", icon: "chart.pie.fill", iconColor: .blue)
                Spacer()
                Link(destination: WidgetAction.budgetTab) {
                    HStack(spacing: 3) {
                        Text("Details")
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
            }

            BudgetBar(label: "Needs", used: entry.needsAllocated, total: entry.needsBudget, tint: .blue)
            BudgetBar(label: "Wants", used: entry.wantsAllocated, total: entry.wantsBudget, tint: .orange)
            BudgetBar(label: "Savings", used: entry.savingsAllocated, total: entry.savingsBudget, tint: .green)

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                ActionButton(title: "Add Income", icon: "plus.circle.fill", color: .green, url: WidgetAction.addIncome)
                ActionButton(title: "Add Expense", icon: "plus.circle.fill", color: .orange, url: WidgetAction.addExpense)
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .clipped()
    }
}

// MARK: - Portfolio Widget Views

struct PortfolioWidgetEntryView: View {
    var entry: PortfolioWidgetProvider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumView
            default:
                smallView
            }
        }
        .widgetURL(WidgetAction.marginTab)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Portfolio", icon: "chart.pie.fill", iconColor: .green)

            Spacer(minLength: 6)

            Text(entry.portfolioValue, format: .currency(code: "USD"))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer(minLength: 6)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Cash", systemImage: "banknote")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(entry.cashBalance, format: .currency(code: "USD"))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Label("Margin", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(entry.marginUsed, format: .currency(code: "USD"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.marginUsed > 0 ? .red : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
        .clipped()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Portfolio", icon: "chart.pie.fill", iconColor: .green)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Value")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(entry.portfolioValue, format: .currency(code: "USD"))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Cash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(entry.cashBalance, format: .currency(code: "USD"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.leading, 8)
            }

            if !entry.topHoldings.isEmpty {
                Divider()

                ForEach(entry.topHoldings.indices, id: \.self) { i in
                    let h = entry.topHoldings[i]
                    HStack(spacing: 8) {
                        Text(h.ticker)
                            .font(.caption.weight(.semibold))
                            .frame(width: 48, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.green.opacity(0.25))
                                .frame(width: geo.size.width * h.pctOfPortfolio)
                        }
                        .frame(height: 4)

                        Text(h.value, format: .currency(code: "USD"))
                            .font(.caption.weight(.medium))
                            .frame(width: 72, alignment: .trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Spacer()
                Image(systemName: "building.columns.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(entry.holdingsCount) holding\(entry.holdingsCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
        .clipped()
    }
}

// MARK: - Watchlist Widget Views

struct WatchlistWidgetEntryView: View {
    var entry: WatchlistWidgetProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumView
            default:
                smallView
            }
        }
        .widgetURL(WidgetAction.homeTab)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Watchlist", icon: "star.fill", iconColor: .yellow)

            if let first = entry.tickers.first {
                Spacer(minLength: 6)

                Text(first.symbol)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .lineLimit(1)

                Text(first.price, format: .currency(code: "USD"))
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if entry.tickers.count > 1 {
                    Spacer(minLength: 4)
                    HStack(spacing: 3) {
                        Image(systemName: "ellipsis")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("+\(entry.tickers.count - 1) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No tickers")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .clipped()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Watchlist", icon: "star.fill", iconColor: .yellow)

            if entry.tickers.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No watchlist tickers added")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.tickers.indices, id: \.self) { i in
                    let row = entry.tickers[i]
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.yellow.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(String(row.symbol.prefix(1)))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tint)
                            )

                        Text(row.symbol)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer()

                        Text(row.price, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    if i < entry.tickers.count - 1 {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .clipped()
    }
}

// MARK: - Widget Configurations

struct BudgetingWidgets: Widget {
    let kind: String = "BudgetingWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BudgetWidgetProvider()) { entry in
            BudgetingWidgetsEntryView(entry: entry)
        }
        .configurationDisplayName("Budget Summary")
        .description("Remaining budget, section progress, and quick-add buttons for income & expenses.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PortfolioWidget: Widget {
    let kind: String = "PortfolioWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortfolioWidgetProvider()) { entry in
            PortfolioWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Portfolio Snapshot")
        .description("Portfolio value, cash balance, margin used, and top holdings.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WatchlistWidget: Widget {
    let kind: String = "WatchlistWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchlistWidgetProvider()) { entry in
            WatchlistWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Watchlist")
        .description("Quick view of watchlist ticker prices.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    BudgetingWidgets()
} timeline: {
    BudgetWidgetEntry.placeholder
}

#Preview(as: .systemMedium) {
    BudgetingWidgets()
} timeline: {
    BudgetWidgetEntry.placeholder
}

#Preview(as: .systemSmall) {
    PortfolioWidget()
} timeline: {
    PortfolioWidgetEntry.placeholder
}

#Preview(as: .systemMedium) {
    PortfolioWidget()
} timeline: {
    PortfolioWidgetEntry.placeholder
}

#Preview(as: .systemSmall) {
    WatchlistWidget()
} timeline: {
    WatchlistWidgetEntry.placeholder
}

#Preview(as: .systemMedium) {
    WatchlistWidget()
} timeline: {
    WatchlistWidgetEntry.placeholder
}
