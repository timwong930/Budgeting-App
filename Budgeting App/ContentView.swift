//
//  ContentView.swift
//  Budgeting App
//
//  Created by Timothy Wong on 1/16/26.
//

import SwiftUI
import UIKit
import Charts
import Combine
import SafariServices

struct TickerMarkdownText: View {
    let markdown: String
    var baseFont: Font = .subheadline
    var baseColor: Color = .primary
    var spacing: CGFloat = 6
    var forceHeader1 = false

    private var lines: [String] {
        markdown
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                lineView(line, forceHeader: forceHeader1 && index == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineView(_ line: String, forceHeader: Bool) -> some View {
        if forceHeader {
            Text(inlineMarkdown(strippedHeading(line)))
                .font(.title3.weight(.bold))
                .foregroundStyle(baseColor)
                .fixedSize(horizontal: false, vertical: true)
        } else if let content = markdownHeading(line, marker: "###") {
            Text(inlineMarkdown(content))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(baseColor)
                .fixedSize(horizontal: false, vertical: true)
        } else if let content = markdownHeading(line, marker: "##") {
            Text(inlineMarkdown(content))
                .font(.headline.weight(.semibold))
                .foregroundStyle(baseColor)
                .fixedSize(horizontal: false, vertical: true)
        } else if let content = markdownHeading(line, marker: "#") {
            Text(inlineMarkdown(content))
                .font(.title3.weight(.bold))
                .foregroundStyle(baseColor)
                .fixedSize(horizontal: false, vertical: true)
        } else if let content = unorderedListContent(line) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(baseFont.weight(.semibold))
                    .foregroundStyle(baseColor)
                Text(inlineMarkdown(content))
                    .font(baseFont)
                    .foregroundStyle(baseColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let item = orderedListContent(line) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.marker)
                    .font(baseFont.weight(.semibold))
                    .foregroundStyle(baseColor)
                    .monospacedDigit()
                Text(inlineMarkdown(item.content))
                    .font(baseFont)
                    .foregroundStyle(baseColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let content = quoteContent(line) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3)
                Text(inlineMarkdown(content))
                    .font(baseFont.italic())
                    .foregroundStyle(baseColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(inlineMarkdown(line))
                .font(baseFont)
                .foregroundStyle(baseColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func markdownHeading(_ line: String, marker: String) -> String? {
        let prefix = "\(marker) "
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func strippedHeading(_ line: String) -> String {
        for marker in ["### ", "## ", "# "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return line
    }

    private func unorderedListContent(_ line: String) -> String? {
        for marker in ["- ", "* "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func orderedListContent(_ line: String) -> (marker: String, content: String)? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let number = String(line[..<dotIndex])
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let contentStart = line.index(after: dotIndex)
        guard contentStart < line.endIndex, line[contentStart] == " " else { return nil }
        let content = String(line[line.index(after: contentStart)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return ("\(number).", content)
    }

    private func quoteContent(_ line: String) -> String? {
        guard line.hasPrefix("> ") else { return nil }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var budget = BudgetModel()
    @State private var showingAddNeedsCategory = false
    @State private var showingAddWantsCategory = false
    @State private var showingAddSavingsGoal = false
    @State private var expenseDraft: ExpenseDraft?
    @State private var savingsEntryDraft: SavingsEntryDraft?
    @State private var showingAddIncome = false
    @State private var editingCategory: Category?
    @State private var editingSavingsGoal: SavingsGoal?
    @State private var editingExpense: Expense?
    @State private var editingIncome: IncomeEntry?
    @State private var editingCashTransfer: CashTransfer?
    @State private var editingSavingsEntry: SavingsEntry?
    @State private var showingIncomeHistory = false
    @State private var showingExpenseHistory = false
    @State private var showingSavingsHistory = false
    @State private var categoryHistorySelection: CategoryHistorySelection?
    @State private var savingsHistorySelection: SavingsHistorySelection?
    @State private var isTabBarMinimized = false
    @State private var selectedTab: BudgetMode = .home
    @State private var expenseDraftSection: BudgetSection = .needs
    @State private var expenseDraftCategoryId: UUID?
    @State private var needsExpanded = true
    @State private var wantsExpanded = true
    @State private var savingsExpanded = true
    @State private var summaryExpanded = true
    @State private var logTrendsExpanded = true
    @State private var categorySummaryExpanded = false
    @State private var planHighlightsExpanded = true
    @State private var overviewExpanded = true
    @State private var incomeExpanded = false
    @State private var budgetBreakdownExpanded = false
    @State private var recurringChargesExpanded = false
    @State private var accountBalancesExpanded = false
    @State private var logTransactionsExpanded = false
    @State private var lastExpenseCategoryId: UUID?
    @State private var lastExpenseSection: BudgetSection = .needs
    @State private var selectedMonth: Date = Date()
    @State private var selectedSpendingPoint: DailySpend?
    @State private var selectedIncomePoint: DailySpend?
    @State private var selectedLogTrend: LogTrend = .spending
    @State private var selectedTrendRange: TrendRange = .monthToDate
    @State private var selectedCalendarDay: CalendarDaySelection?
    @State private var selectedCalendarEventList: CalendarDaySelection?
    @State private var visibleCalendarWeekStart: Date?
    @State private var calendarMonthAnchor: Date = Date()
    @State private var calendarFocusDate: Date = Date()
    @State private var isCalendarSyncing = false
    @State private var calendarSyncStatus: String?
    @AppStorage("calendar.viewMode") private var calendarViewMode: CalendarViewMode = .month
    @AppStorage("calendar.showExpenses") private var calendarShowExpenses = true
    @AppStorage("calendar.showIncome") private var calendarShowIncome = true
    @AppStorage("calendar.showTransfers") private var calendarShowTransfers = true
    @AppStorage("calendar.showCreditDue") private var calendarShowCreditDue = true
    @AppStorage("calendar.showPortfolio") private var calendarShowPortfolio = false
    @State private var calendarEventCache: [Date: [CalendarEventItem]] = [:]
    @State private var calendarCacheRefreshTask: Task<Void, Never>?
    @State private var selectedPortfolioTransaction: PortfolioTransaction?
    @State private var editingRecurringPayment: RecurringPayment?
    @State private var showingCreditAccounts = false
    @State private var showingBankAccounts = false
    @State private var showingAddCashTransfer = false
    @State private var selectedCreditAccount: CreditAccount?
    @State private var showingMarginAddTransaction = false
    @State private var showingMarginAddInvestment = false
    @State private var showingMarginElectricBill = false
    @State private var showingMarginSettings = false
    @State private var showingAppSettings = false
    @State private var showingMarginHistory = false
    @State private var showingMarginManualHolding = false
    @State private var monthlyExpenses: [Expense] = []
    @State private var monthlyIncomes: [IncomeEntry] = []
    @State private var monthlySavingsEntries: [SavingsEntry] = []
    @State private var totalMonthlySpent: Double = 0
    @State private var totalMonthlyIncomeLogged: Double = 0
    @State private var needsSpentByCategoryId: [UUID: Double] = [:]
    @State private var wantsSpentByCategoryId: [UUID: Double] = [:]
    @State private var monthlyNeedsSpent: Double = 0
    @State private var monthlyWantsSpent: Double = 0
    @State private var savingsLoggedByGoalId: [UUID: Double] = [:]
    @State private var monthlySavingsLogged: Double = 0
    @State private var dailySpending: [DailySpend] = []
    @State private var dailyIncome: [DailySpend] = []
    @State private var scrollToIncome = false
    @State private var highlightMonthlyIncome = false
    @State private var selectedPlanHighlight: PlanHighlightSection?
    @State private var homeMarketCards: [HomeMarketCard] = []
    @State private var isLoadingHomeMarkets = false
    @State private var homeMarketError: String?
    @State private var homeWatchlistRows: [HomeWatchlistRow] = []
    @State private var isLoadingHomeWatchlist = false
    @State private var homeWatchlistError: String?
    @State private var selectedHomeWatchlistTicker: TickerSelection?
    @State private var showingWatchlistSearch = false
    @State private var watchlistSortOption: WatchlistSortOption = .ticker
    @State private var watchlistSortAscending = true
    @State private var watchlistFilter: WatchlistFilter = .all
    @State private var selectedWatchlistAlertTicker: TickerSelection?
    @State private var selectedHomeNetWorthRange: HomeNetWorthRange = .threeMonths
    @State private var selectedHomeNetWorthPoint: PortfolioValuePoint?
    @State private var holdingsAutoRefreshTask: Task<Void, Never>?
    @State private var watchlistAlertTask: Task<Void, Never>?
    @State private var isRefreshingHoldingsQuotes = false
    @FocusState private var focusedField: FocusedField?
    private let marketDataService = MarketDataService()

    private struct HomeMarketCard: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let price: Double
        let change: Double
        let percentChange: Double
        let sparkline: [Double]
        let isUnavailable: Bool
    }

    private struct HomeWatchlistRow: Identifiable {
        let id = UUID()
        let symbol: String
        let companyName: String?
        let exchange: String?
        let price: Double
        let change: Double
        let percentChange: Double
        let open: Double?
        let dayHigh: Double?
        let dayLow: Double?
        let previousClose: Double?
        let sma20: Double?
        let sma50: Double?
        let ema20: Double?
        let rsi14: Double?
        let macd: MACDResult?
        let priceHistory: [TickerPricePoint]
    }

    private struct TickerSelection: Identifiable {
        let ticker: String
        var id: String { ticker }
    }

    private enum WatchlistSortOption: String, CaseIterable, Identifiable {
        case ticker = "Ticker"
        case price = "Price"
        case changePercent = "Chg %"
        case changeDollar = "Chg $"
        var id: String { rawValue }
    }

    private enum WatchlistFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case gainers = "Gainers"
        case losers = "Losers"
        var id: String { rawValue }
    }

    private enum FocusedField: Hashable {
        case income
    }

    private enum LogTrend: String, CaseIterable, Identifiable {
        case spending = "Spending"
        case income = "Income"

        var id: String { rawValue }
    }

    private enum TrendRange: String, CaseIterable, Identifiable {
        case last7Days = "Last 7 days"
        case monthToDate = "Month to date"
        case last30Days = "Last 30 days"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .monthToDate:
                return "MTD"
            case .last7Days:
                return "7D"
            case .last30Days:
                return "30D"
            }
        }
    }

    private var appAccent: Color {
        .accentColor
    }

    private enum HomeNetWorthRange: String, CaseIterable, Identifiable {
        case oneDay = "1D"
        case oneWeek = "1W"
        case oneMonth = "1M"
        case threeMonths = "3M"
        case oneYear = "1Y"
        case all = "All"

        var id: String { rawValue }
    }

    private struct ExpenseDraft: Identifiable {
        let id = UUID()
        let section: BudgetSection
        let categoryId: UUID?
    }

    private struct SavingsEntryDraft: Identifiable {
        let id = UUID()
        let goalId: UUID?
    }

    private struct CategoryHistorySelection: Identifiable {
        let id: UUID
        let name: String
        let categoryId: UUID

        init(category: Category) {
            id = category.id
            name = category.name
            categoryId = category.id
        }
    }

    private struct SavingsHistorySelection: Identifiable {
        let id: UUID
        let name: String
        let goalId: UUID

        init(goal: SavingsGoal) {
            id = goal.id
            name = goal.displayName
            goalId = goal.id
        }
    }

    private struct CalendarOccurrence: Identifiable {
        let id = UUID()
        let payment: RecurringPayment
        let date: Date
    }

    private struct CalendarWeek: Identifiable, Hashable {
        let startDate: Date
        let days: [Date]

        var id: Date { startDate }
    }

    private struct CalendarDaySelection: Identifiable {
        let id = UUID()
        let date: Date
    }

    private enum CalendarViewMode: String, CaseIterable, Identifiable, Equatable {
        case month = "Month"
        case week = "Week"
        case day = "Day"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .month: return "calendar"
            case .week: return "rectangle.split.3x1"
            case .day: return "list.bullet.rectangle"
            }
        }
    }

    private struct CalendarDayTransactionsView: View {
        let date: Date
        let events: [CalendarEventItem]
        let onOpen: (CalendarEventItem) -> Void
        let onMarkPaid: (RecurringPayment, Date) -> Void
        let onAddTransaction: () -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                                .font(.headline)
                            Text("\(events.count) transaction\(events.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        if events.isEmpty {
                            ContentUnavailableView("No Transactions", systemImage: "calendar", description: Text("Nothing is scheduled for this day."))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(events) { event in
                                    calendarTransactionRow(event)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .navigationTitle("Transactions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss(); onAddTransaction() } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }

        private func calendarTransactionRow(_ event: CalendarEventItem) -> some View {
            HStack(spacing: 12) {
                Image(systemName: event.iconName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(eventColor(event), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(eventSubtitle(event))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(chipAmountText(for: event))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(event.isIncome ? .green : .primary)

                    if let recurring = event.recurringPayment, !event.isPaid {
                        Button {
                            onMarkPaid(recurring, event.date)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mark \(event.name) paid")
                    }
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(eventColor(event).opacity(0.22), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture {
                dismiss()
                onOpen(event)
            }
        }

        private func eventSubtitle(_ event: CalendarEventItem) -> String {
            if event.isCreditDue { return "Credit card due" }
            if event.isTransfer { return event.paymentAccount }
            if event.recurringPayment != nil { return "Recurring" }
            if !event.paymentAccount.isEmpty { return event.paymentAccount }
            return event.isIncome ? "Income" : "Expense"
        }

        private func chipAmountText(for event: CalendarEventItem) -> String {
            if event.isTransfer {
                return event.amount.formatted(.currency(code: "USD"))
            }
            return "\(event.isIncome ? "+" : "-")\(event.amount.formatted(.currency(code: "USD")))"
        }

        private func eventColor(_ event: CalendarEventItem) -> Color {
            if event.isIncome { return .green }
            if event.isCreditDue { return .orange }
            return event.tint
        }
    }

    private struct LogTransactionItem: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
        let amount: Double
        let date: Date
        let isInflow: Bool
        let iconName: String
        let tint: Color
        let kind: Kind

        enum Kind {
            case expense(Expense)
            case income(IncomeEntry)
            case savings(SavingsEntry)
        }
    }

    private struct TopRecurringCharge: Identifiable {
        let id: UUID
        let name: String
        let amount: Double
        let occurrences: Int
        let paid: Int
        let tint: Color
    }

    private struct ContinuousChargeSummary {
        let totalDue: Double
        let totalPaid: Double
        let totalUnpaid: Double
        let occurrenceCount: Int
        let paidCount: Int
        let unpaidCount: Int
        let nextDueDate: Date?
        let nextDueName: String?
        let topCharges: [TopRecurringCharge]

        var paidProgress: Double {
            guard totalDue > 0 else { return 0 }
            return min(max(totalPaid / totalDue, 0), 1)
        }
    }

    private struct RecurringChargesCard: View {
        let summary: ContinuousChargeSummary

        var body: some View {
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    progress
                    metricRow
                    nextCharge
                    topCharges
                }
            }
        }

        private var header: some View {
            HStack(alignment: .top) {
                Label("Recurring Charges", systemImage: "repeat.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(summary.totalDue, format: .currency(code: "USD"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.pink)
                    Text("since start dates")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }

        private var progress: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(summary.paidCount) paid")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text("\(summary.unpaidCount) unpaid")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                ProgressView(value: summary.paidProgress)
                    .tint(.pink)
            }
        }

        private var metricRow: some View {
            HStack(spacing: 10) {
                RecurringChargeMetricTile(
                    title: "Paid",
                    value: summary.totalPaid,
                    subtitle: "\(summary.paidCount) charges",
                    tint: .green,
                    systemImage: "checkmark.circle.fill"
                )
                RecurringChargeMetricTile(
                    title: "Open",
                    value: summary.totalUnpaid,
                    subtitle: "\(summary.unpaidCount) charges",
                    tint: .orange,
                    systemImage: "clock.fill"
                )
            }
        }

        @ViewBuilder
        private var nextCharge: some View {
            if let nextDate = summary.nextDueDate, let nextName = summary.nextDueName {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.pink)
                        .frame(width: 30, height: 30)
                        .background(Color.pink.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nextName)
                            .font(.subheadline.weight(.semibold))
                        Text("Next charge \(nextDate, format: .dateTime.month().day().year())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }

        @ViewBuilder
        private var topCharges: some View {
            if !summary.topCharges.isEmpty {
                Divider()
                VStack(spacing: 10) {
                    ForEach(Array(summary.topCharges.prefix(3))) { charge in
                        RecurringChargeRow(charge: charge)
                    }
                }
            }
        }
    }

    private struct RecurringChargeMetricTile: View {
        let title: String
        let value: Double
        let subtitle: String
        let tint: Color
        let systemImage: String

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                        .background(tint.opacity(0.12), in: Circle())
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(value, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.title2.weight(.bold))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private struct RecurringChargeRow: View {
        let charge: TopRecurringCharge

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "creditcard.fill")
                    .font(.subheadline)
                    .foregroundStyle(charge.tint)
                    .frame(width: 34, height: 34)
                    .background(charge.tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(charge.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(charge.paid)/\(charge.occurrences) paid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(charge.amount, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.pink)
            }
        }
    }

    private var activeTabContent: AnyView {
        switch selectedTab {
        case .home:
            AnyView(homeTab)
        case .calendar:
            AnyView(calendarTab)
        case .budget:
            AnyView(budgetTab)
        case .margin:
            AnyView(marginTab)
        }
    }
    
    var body: some View {
        NavigationStack {
            activeTabContent
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard selectedTab != .home else { return }
                        let verticalSwipe = abs(value.translation.height) > abs(value.translation.width)
                        guard verticalSwipe else { return }
                        if value.translation.height < -8 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                                isTabBarMinimized = true
                            }
                        } else if value.translation.height > 8 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                                isTabBarMinimized = false
                            }
                        }
                    }
            )
            .scrollDismissesKeyboard(.interactively)
            .background(backgroundView)
            .toolbar(.hidden, for: .navigationBar)
            .simultaneousGesture(TapGesture().onEnded {
                hideKeyboard()
            })
            .overlay(alignment: .bottom) {
                CustomTabBar(
                    selectedTab: $selectedTab,
                    minimized: isTabBarMinimized,
                    onExpand: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                            isTabBarMinimized = false
                        }
                    },
                    onAddExpense: {
                        Haptics.light()
                        expenseDraftSection = lastExpenseSection
                        expenseDraftCategoryId = lastExpenseCategoryId ?? budget.needsCategories.first?.id ?? budget.wantsCategories.first?.id
                        expenseDraft = ExpenseDraft(section: expenseDraftSection, categoryId: expenseDraftCategoryId)
                    },
                    onAddIncome: {
                        Haptics.light()
                        showingAddIncome = true
                    },
                    onCalendarQuickAction: { action in
                        Haptics.light()
                        switch action {
                        case .addCalendarEntry:
                            selectedCalendarDay = CalendarDaySelection(date: calendarActionDate)
                        case .transferCash:
                            showingAddCashTransfer = true
                        case .creditCards:
                            showingCreditAccounts = true
                        }
                    },
                    onMarginQuickAction: { action in
                        Haptics.light()
                        switch action {
                        case .addTransaction:
                            showingMarginAddTransaction = true
                        case .addInvestment:
                            showingMarginAddInvestment = true
                        case .addManualHolding:
                            showingMarginManualHolding = true
                        case .marginSettings:
                            showingMarginSettings = true
                        case .ledgerHistory:
                            showingMarginHistory = true
                        }
                    }
                )
                .frame(maxWidth: .infinity, alignment: isTabBarMinimized ? .trailing : .center)
                .padding(.trailing, isTabBarMinimized ? 12 : 0)
                .padding(.bottom, -16)
            }
            .onAppear {
                budget.income = budget.income(for: selectedMonth)
                budget.applyMonthlyAllocations(for: selectedMonth)
                updateMonthlyData()
                rebuildCalendarEventCache()
                scheduleBudgetNotifications()
                if scenePhase == .active {
                    startHoldingsAutoRefreshLoop()
                    startWatchlistAlertLoop()
                    Task { try? await PlaidSyncCoordinator.shared.sync(budget: budget) }
                }
                consumePendingDeepLink()
            }
            .onDisappear {
                stopHoldingsAutoRefreshLoop()
                stopWatchlistAlertLoop()
                calendarCacheRefreshTask?.cancel()
            }
            .onChange(of: selectedMonth) { _, newValue in
                budget.income = budget.income(for: newValue)
                budget.applyMonthlyAllocations(for: newValue)
                updateMonthlyData()
            }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active {
                    startHoldingsAutoRefreshLoop()
                    startWatchlistAlertLoop()
                    Task { try? await PlaidSyncCoordinator.shared.sync(budget: budget) }
                    consumePendingDeepLink()
                } else {
                    stopHoldingsAutoRefreshLoop()
                    stopWatchlistAlertLoop()
                }
            }
            .onChange(of: budget.income) { _, newValue in
                budget.setIncome(newValue, for: selectedMonth)
            }
            .onChange(of: budget.expenses) { _, _ in
                updateMonthlyData()
                scheduleCalendarEventCacheRebuild()
            }
            .onChange(of: budget.incomes) { _, _ in
                updateMonthlyData()
                scheduleCalendarEventCacheRebuild()
            }
            .onChange(of: budget.savingsEntries) { _, _ in
                updateMonthlyData()
            }
            .onChange(of: budget.creditAccounts) { _, _ in
                scheduleCalendarEventCacheRebuild()
            }
            .onChange(of: budget.portfolioTransactions) { _, _ in
                scheduleCalendarEventCacheRebuild()
            }
            .onChange(of: budget.cashTransfers) { _, _ in
                scheduleCalendarEventCacheRebuild()
            }
            .onChange(of: budget.recurringPayments) { _, _ in
                scheduleCalendarEventCacheRebuild()
            }
            .onChange(of: calendarMonthAnchor) { _, _ in
                scheduleCalendarEventCacheRebuild()
            }
            .onChange(of: calendarFocusDate) { _, _ in
                scheduleCalendarEventCacheRebuild()
            }
            .onChange(of: calendarViewMode) { _, _ in
                scheduleCalendarEventCacheRebuild()
            }
            .onChange(of: calendarShowPortfolio) { _, _ in
                scheduleCalendarEventCacheRebuild()
            }
            .onChange(of: budget.watchlistTickers) { _, _ in
                guard selectedTab == .home else { return }
                Task { await refreshHomeWatchlist() }
            }
            .task(id: selectedTab) {
                await refreshSelectedTabIfNeeded()
            }
            .onReceive(budget.objectWillChange.debounce(for: .milliseconds(800), scheduler: RunLoop.main)) { _ in
                scheduleBudgetNotifications()
            }
            .overlay(alignment: .top) {
                InAppNotificationOverlay()
            }
        }
        .sheet(isPresented: $showingAddNeedsCategory) {
            AddCategoryView(budget: budget, categoryType: .needs, selectedMonth: selectedMonth)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedHomeWatchlistTicker) { selection in
            let ticker = selection.ticker
            let row = homeWatchlistRows.first(where: { $0.symbol == ticker })
            TickerSnapshotDetailView(
                budget: budget,
                ticker: ticker,
                companyName: row?.companyName,
                quoteSnapshot: row.map {
                    MarketQuoteSnapshot(
                        price: $0.price,
                        change: $0.change,
                        percentChange: $0.percentChange,
                        open: $0.open,
                        high: $0.dayHigh,
                        low: $0.dayLow,
                        previousClose: $0.previousClose
                    )
                },
                historicalCloses: row?.priceHistory.map(\.close) ?? [],
                priceHistory: row?.priceHistory
            )
        }
        .sheet(item: $selectedWatchlistAlertTicker) { selection in
            WatchlistAlertSettingsView(budget: budget, ticker: selection.ticker)
        }
        .sheet(isPresented: $showingWatchlistSearch) {
            TickerSearchView(
                budget: budget,
                onAdd: { tickers in
                    for ticker in tickers {
                        let clean = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        if !budget.watchlistTickers.contains(clean) {
                            budget.watchlistTickers.append(clean)
                        }
                    }
                    if !tickers.isEmpty {
                        showingWatchlistSearch = false
                        Task { await refreshHomeWatchlist() }
                    }
                },
                onSnapshot: { ticker in
                    showingWatchlistSearch = false
                    selectedHomeWatchlistTicker = TickerSelection(ticker: ticker.uppercased())
                }
            )
        }
        .sheet(isPresented: $showingAddWantsCategory) {
            AddCategoryView(budget: budget, categoryType: .wants, selectedMonth: selectedMonth)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingCategory) { category in
            EditCategoryView(budget: budget, category: category, selectedMonth: selectedMonth)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddSavingsGoal) {
            AddSavingsGoalView(budget: budget)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingSavingsGoal) { goal in
            EditSavingsGoalView(budget: budget, savingsGoal: goal)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $expenseDraft) { draft in
            AddExpenseView(
                budget: budget,
                preselectedSection: draft.section,
                preselectedCategoryId: draft.categoryId
            ) { expense in
                lastExpenseCategoryId = expense.categoryId
                lastExpenseSection = expense.section
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $savingsEntryDraft) { draft in
            AddSavingsEntryView(
                budget: budget,
                selectedMonth: selectedMonth,
                preselectedGoalId: draft.goalId
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddIncome) {
            AddIncomeView(budget: budget, selectedMonth: selectedMonth)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingIncomeHistory) {
            IncomeHistoryView(
                budget: budget,
                monthlyIncomes: monthlyIncomes,
                onEdit: { editingIncome = $0 },
                onDelete: { income in
                    withAnimation(.easeInOut) {
                        budget.deleteIncomeEntry(id: income.id)
                    }
                    Haptics.warning()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingExpenseHistory) {
            ExpenseHistoryView(
                budget: budget,
                monthlyExpenses: monthlyExpenses,
                onEdit: { editingExpense = $0 },
                onDelete: { expense in
                    withAnimation(.easeInOut) {
                        budget.deleteExpense(id: expense.id)
                    }
                    Haptics.warning()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSavingsHistory) {
            SavingsHistoryView(
                budget: budget,
                monthlySavings: monthlySavingsEntries,
                onEdit: { editingSavingsEntry = $0 },
                onDelete: { entry in
                    withAnimation(.easeInOut) {
                        budget.deleteSavingsEntry(id: entry.id)
                    }
                    Haptics.warning()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $categoryHistorySelection) { selection in
            ExpenseHistoryView(
                budget: budget,
                monthlyExpenses: monthlyExpenses.filter { $0.categoryId == selection.categoryId },
                onEdit: { editingExpense = $0 },
                onDelete: { expense in
                    withAnimation(.easeInOut) {
                        budget.deleteExpense(id: expense.id)
                    }
                    Haptics.warning()
                },
                title: "\(selection.name) History"
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $savingsHistorySelection) { selection in
            SavingsHistoryView(
                budget: budget,
                monthlySavings: monthlySavingsEntries.filter { $0.goalId == selection.goalId },
                onEdit: { editingSavingsEntry = $0 },
                onDelete: { entry in
                    withAnimation(.easeInOut) {
                        budget.deleteSavingsEntry(id: entry.id)
                    }
                    Haptics.warning()
                },
                title: "\(selection.name) History"
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingIncome) { income in
            EditIncomeView(budget: budget, income: income)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddCashTransfer) {
            CashTransferEditorView(budget: budget, selectedDate: selectedTab == .calendar ? calendarActionDate : selectedMonth)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingCashTransfer) { transfer in
            CashTransferEditorView(budget: budget, selectedDate: transfer.date, existingTransfer: transfer)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingExpense) { expense in
            EditExpenseView(budget: budget, expense: expense)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingSavingsEntry) { entry in
            EditSavingsEntryView(budget: budget, savingsEntry: entry)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedCalendarDay) { selection in
            CalendarEntryEditorView(
                budget: budget,
                selectedDate: selection.date
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedCalendarEventList) { selection in
            CalendarDayTransactionsView(
                date: selection.date,
                events: filteredCalendarEvents(for: selection.date),
                onOpen: openCalendarEvent,
                onMarkPaid: { payment, date in
                    markRecurringOccurrencePaid(payment, on: date)
                },
                onAddTransaction: {
                    selectedCalendarDay = CalendarDaySelection(date: selection.date)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $editingRecurringPayment) { payment in
            CalendarEntryEditorView(
                budget: budget,
                selectedDate: Calendar.current.date(from: DateComponents(
                    year: Calendar.current.component(.year, from: selectedMonth),
                    month: Calendar.current.component(.month, from: selectedMonth),
                    day: payment.dayOfMonth
                )) ?? selectedMonth,
                existingRecurringPayment: payment
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingCreditAccounts) {
            CreditAccountsView(budget: budget)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedCreditAccount) { account in
            CreditAccountDetailView(account: account, budget: budget)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedPortfolioTransaction) { transaction in
            PortfolioTransactionDetailView(transaction: transaction)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingBankAccounts) {
            BankAccountsView(budget: budget)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAppSettings) {
            AppSettingsView(budget: budget)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var planTab: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    pageHeader(
                        title: "Plan Mode",
                        subtitle: "Set targets and allocations.",
                        systemImage: "list.bullet.rectangle"
                    )
                    overviewSection
                    planHighlightsSection

                    if budget.income == 0 && budget.needsCategories.isEmpty && budget.wantsCategories.isEmpty && budget.savingsGoals.isEmpty && budget.expenses.isEmpty {
                        firstTimeTipsSection
                    }

                    incomeSection
                    if budget.income > 0 && budget.needsCategories.isEmpty && budget.wantsCategories.isEmpty && budget.savingsGoals.isEmpty {
                        nextStepSection
                    }
                    budgetBreakdownSection
                    summarySection
                }
                .padding(.horizontal)
                .padding(.top, 28)
                .padding(.bottom, contentBottomPadding)
            }
            .onChange(of: scrollToIncome) { _, shouldScroll in
                guard shouldScroll else { return }
                withAnimation(.easeInOut) {
                    proxy.scrollTo("incomeSection", anchor: .top)
                }
                focusedField = .income
                scrollToIncome = false
            }
        }
    }

    private var homeTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                pageHeader(
                    title: "Home Dashboard",
                    subtitle: "Full snapshot across budget, logs, and portfolio.",
                    systemImage: "house.fill"
                ) {
                    Button {
                        showingAppSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
                homeInsightSummarySection
                homeCashFlowSection
                homeNetWorthChartSection
                homeWatchlistSection
            }
            .padding(.horizontal)
            .padding(.top, 28)
            .padding(.bottom, contentBottomPadding)
        }
        .refreshable {
            await refreshHomeDashboard()
        }
    }

    private var logTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                pageHeader(
                    title: "Log Mode",
                    subtitle: "Track spending and income.",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                logMonthSwitcher
                logTrendsSection
                needsSection
                wantsSection
                savingsSection
                categorySummarySection
                summarySection
            }
            .padding(.horizontal)
            .padding(.top, 28)
            .padding(.bottom, contentBottomPadding)
        }
    }

    private var budgetTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                pageHeader(
                    title: "Budget Hub",
                    subtitle: "Snapshot first, details when you need them.",
                    systemImage: "square.grid.2x2"
                ) {
                    logMonthHeaderSelector
                }

                budgetHubSnapshotSection

                if budget.income == 0 && budget.needsCategories.isEmpty && budget.wantsCategories.isEmpty && budget.savingsGoals.isEmpty && budget.expenses.isEmpty {
                    firstTimeTipsSection
                }

                budgetSubmenusSection
            }
            .padding(.horizontal, 12)
            .padding(.top, 22)
            .padding(.bottom, contentBottomPadding)
        }
    }

    private var budgetSubmenusSection: some View {
        VStack(spacing: 10) {
            budgetSubmenuLink(
                title: "Plan",
                subtitle: "Income, targets, categories, and savings goals",
                systemImage: "slider.horizontal.3",
                tint: .blue,
                valueLabel: budget.monthlyIncome.formatted(.currency(code: "USD"))
            ) {
                budgetPlanSubmenu
            }

            budgetSubmenuLink(
                title: "Activity",
                subtitle: "Recurring charges, trends, and recent transactions",
                systemImage: "list.bullet.rectangle.portrait",
                tint: .pink,
                valueLabel: totalMonthlySpent.formatted(.currency(code: "USD"))
            ) {
                budgetActivitySubmenu
            }

            budgetSubmenuLink(
                title: "Accounts",
                subtitle: "Bank balances, credit cards, and portfolio holdings",
                systemImage: "creditcard.and.123",
                tint: .cyan,
                valueLabel: runwayText
            ) {
                budgetAccountsSubmenu
            }

            budgetSubmenuLink(
                title: "Reports",
                subtitle: "Breakdowns, category summaries, and month-end totals",
                systemImage: "chart.pie",
                tint: .purple,
                valueLabel: remainingBudgetForMonth.formatted(.currency(code: "USD"))
            ) {
                budgetReportsSubmenu
            }
        }
    }

    private func budgetSubmenuLink<Destination: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        valueLabel: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            GlassCard(padding: 12) {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(valueLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 116, alignment: .trailing)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var budgetPlanSubmenu: some View {
        budgetSubmenuPage(title: "Plan", subtitle: "Budget setup and monthly targets.", systemImage: "slider.horizontal.3") {
            planHighlightsSection
            overviewSection
            incomeSection
            if budget.income > 0 && budget.needsCategories.isEmpty && budget.wantsCategories.isEmpty && budget.savingsGoals.isEmpty {
                nextStepSection
            }
            budgetBreakdownSection
            needsSection
            wantsSection
            savingsSection
        }
        .onAppear {
            planHighlightsExpanded = true
            overviewExpanded = true
            incomeExpanded = true
            budgetBreakdownExpanded = true
        }
    }

    private var budgetActivitySubmenu: some View {
        budgetSubmenuPage(title: "Activity", subtitle: "Monthly movement and logged cash flow.", systemImage: "list.bullet.rectangle.portrait") {
            logMonthHeaderSelector
            recurringChargesSection
            logTrendsSection
            logTransactionsSection
        }
        .onAppear {
            recurringChargesExpanded = true
            logTrendsExpanded = true
            logTransactionsExpanded = true
        }
    }

    private var budgetAccountsSubmenu: some View {
        budgetSubmenuPage(title: "Accounts", subtitle: "Balances that feed your budget snapshot.", systemImage: "creditcard.and.123") {
            accountBalancesSection
        }
        .onAppear {
            accountBalancesExpanded = true
        }
    }

    private var budgetReportsSubmenu: some View {
        budgetSubmenuPage(title: "Reports", subtitle: "Summaries and allocation readouts.", systemImage: "chart.pie") {
            summarySection
            categorySummarySection
            budgetBreakdownSection
        }
        .onAppear {
            summaryExpanded = true
            categorySummaryExpanded = true
            budgetBreakdownExpanded = true
        }
    }

    private func budgetSubmenuPage<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                pageHeader(title: title, subtitle: subtitle, systemImage: systemImage)
                content()
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, contentBottomPadding)
        }
        .background(backgroundView)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var calendarTab: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                pageHeader(
                    title: "Calendar",
                    subtitle: "Plan cash flow without the transaction noise.",
                    systemImage: "calendar"
                ) {
                    HStack(spacing: 8) {
                        Button {
                            Haptics.light()
                            selectedCalendarDay = CalendarDaySelection(date: calendarActionDate)
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(appAccent, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add Calendar Entry")

                        Button {
                            showingAddCashTransfer = true
                        } label: {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Transfer Cash")

                        Button {
                            showingCreditAccounts = true
                        } label: {
                            Image(systemName: "creditcard")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Credit Cards")
                    }
                }

                calendarViewControls

                if calendarViewMode == .month {
                    calendarSummarySection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Group {
                switch calendarViewMode {
                case .month:
                    recurringCalendarSection
                case .week:
                    calendarWeekAgendaSection
                case .day:
                    calendarDayAgendaSection
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 22)
        .padding(.bottom, 0)
        .background(backgroundView)
        .onChange(of: calendarViewMode) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if newValue == .month {
                calendarMonthAnchor = calendarFocusDate
                return
            }
            if Calendar.current.isDate(visibleCalendarMonth, equalTo: Date(), toGranularity: .month) {
                calendarFocusDate = Date()
            } else {
                calendarFocusDate = visibleCalendarMonth
            }
        }
    }

    private var calendarNetWorth: Double {
        let totalBank = budget.bankAccounts.reduce(0) { $0 + $1.balance }
        let totalCredit = budget.creditAccounts
            .filter(\.isActive)
            .reduce(0) { $0 + creditAccountActualBalance($1) }
        return totalBank + homePortfolioNetValue - totalCredit
    }

    private var calendarNetFlow: Double {
        calendarVisibleIncome - calendarVisibleOutflow
    }

    private var calendarSummarySection: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    calendarSummaryHeader

                    Spacer(minLength: 8)

                    calendarMetricPill(
                        title: "Net Flow",
                        value: calendarNetFlow,
                        tint: calendarNetFlow >= 0 ? .green : .red,
                        systemImage: "arrow.left.arrow.right.circle.fill"
                    )
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    alignment: .leading,
                    spacing: 8
                ) {
                    calendarMetricPill(
                        title: "Income",
                        value: calendarVisibleIncome,
                        tint: .green,
                        systemImage: "arrow.down.circle.fill"
                    )
                    calendarMetricPill(
                        title: "Outflow",
                        value: calendarVisibleOutflow,
                        tint: .red,
                        systemImage: "arrow.up.circle.fill"
                    )
                    calendarMetricPill(
                        title: "Credit Due",
                        value: calendarVisibleCreditDue,
                        tint: .orange,
                        systemImage: "creditcard.fill"
                    )
                }
            }
        }
    }

    private var calendarSummaryHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appAccent)
                .frame(width: 30, height: 30)
                .background(appAccent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Monthly Snapshot")
                    .font(.subheadline.weight(.bold))
                Text(visibleCalendarMonth, format: .dateTime.month(.wide).year())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func calendarMetricPill(title: String, value: Double, tint: Color, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value, format: .currency(code: "USD"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(value < 0 ? Color.red : Color.primary)
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
    }

    private var marginTab: some View {
        MarginDashboardView(
            budget: budget,
            bottomPadding: contentBottomPadding,
            showAddTransaction: $showingMarginAddTransaction,
            showAddInvestment: $showingMarginAddInvestment,
            showElectricBill: $showingMarginElectricBill,
            showMarginSettings: $showingMarginSettings,
            showHistory: $showingMarginHistory,
            showManualHolding: $showingMarginManualHolding
        )
    }

    private var isLogFocus: Bool {
        true
    }

    private var recurringCalendarSection: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    calendarMonthNavigation
                    calendarWeekdayHeader

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                        spacing: 0
                    ) {
                        ForEach(Array(calendarGridDates(for: visibleCalendarMonth).enumerated()), id: \.offset) { _, date in
                            calendarMonthDayCell(for: date)
                        }
                    }
                    .padding(.horizontal, 6)

                    HStack(spacing: 12) {
                        Label("Outflow", systemImage: "arrow.up.right")
                            .foregroundStyle(.red)
                        Label("Income", systemImage: "arrow.down.left")
                            .foregroundStyle(.green)
                        Label("Card due", systemImage: "creditcard.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, contentBottomPadding)
                }
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var calendarMonthNavigation: some View {
        HStack(spacing: 12) {
            Button { shiftVisibleCalendarMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 1) {
                Text(visibleCalendarMonth, format: .dateTime.month(.wide).year())
                    .font(.subheadline.weight(.bold))
                Text("Daily cash flow")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button { shiftVisibleCalendarMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func shiftVisibleCalendarMonth(by offset: Int) {
        guard let shifted = Calendar.current.date(byAdding: .month, value: offset, to: visibleCalendarMonth) else { return }
        withAnimation(.snappy) {
            calendarMonthAnchor = shifted
        }
    }

    private struct CalendarMonthDaySummary {
        let outflow: Double
        let income: Double
        let itemCount: Int
        let dueCount: Int
        let transferCount: Int
    }

    private func calendarMonthDaySummary(for date: Date) -> CalendarMonthDaySummary {
        let events = (calendarEventCache[calendarDayKey(for: date)] ?? []).filter(calendarEventPassesFilters)
        let outflow = events
            .filter { !$0.isIncome && !$0.isTransfer && !$0.isCreditDue }
            .reduce(0) { $0 + $1.amount }
        let income = events
            .filter { $0.isIncome && !$0.isTransfer && !$0.isCreditDue }
            .reduce(0) { $0 + $1.amount }
        return CalendarMonthDaySummary(
            outflow: outflow,
            income: income,
            itemCount: events.count,
            dueCount: events.filter(\.isCreditDue).count,
            transferCount: events.filter(\.isTransfer).count
        )
    }

    private func calendarMonthDayCell(for date: Date?) -> some View {
        Group {
            if let date {
                let summary = calendarMonthDaySummary(for: date)
                let calendar = Calendar.current
                let isToday = calendar.isDateInToday(date)
                let isVisibleMonth = calendar.isDate(date, equalTo: visibleCalendarMonth, toGranularity: .month)

                Button {
                    selectedCalendarEventList = CalendarDaySelection(date: date)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 2) {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.subheadline.weight(isToday ? .bold : .semibold))
                                .foregroundStyle(isToday ? appAccent : (isVisibleMonth ? Color.primary : Color.secondary.opacity(0.45)))
                            Spacer(minLength: 0)
                            if isToday {
                                Circle()
                                    .fill(appAccent)
                                    .frame(width: 5, height: 5)
                            }
                        }

                        if isVisibleMonth {
                            if summary.outflow > 0 {
                                Text("-\(calendarMonthCompactAmount(summary.outflow))")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.58)
                            }
                            if summary.income > 0 {
                                Text("+\(calendarMonthCompactAmount(summary.income))")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.green)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.58)
                            }

                            Spacer(minLength: 1)

                            HStack(spacing: 3) {
                                if summary.dueCount > 0 {
                                    Image(systemName: "creditcard.fill")
                                        .foregroundStyle(.orange)
                                }
                                if summary.transferCount > 0 {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .foregroundStyle(.cyan)
                                }
                                Spacer(minLength: 0)
                                if summary.itemCount > 0 {
                                    Text("\(summary.itemCount) tx")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.system(size: 8, weight: .semibold))
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                    .background(
                        Rectangle()
                            .fill(isToday ? appAccent.opacity(0.10) : Color(.secondarySystemGroupedBackground).opacity(isVisibleMonth ? 0.72 : 0.28))
                            .overlay(
                                Rectangle()
                                    .stroke(isToday ? appAccent.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: isToday ? 1.1 : 0.5)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendarMonthAccessibilityLabel(date: date, summary: summary))
            } else {
                Color.clear
                    .frame(minHeight: 82)
            }
        }
    }

    private func calendarMonthCompactAmount(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return String(format: "$%.1fM", amount / 1_000_000)
        }
        if amount >= 1_000 {
            return String(format: "$%.1fK", amount / 1_000)
        }
        return String(format: "$%.0f", amount)
    }

    private func calendarMonthAccessibilityLabel(date: Date, summary: CalendarMonthDaySummary) -> String {
        var parts = [date.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if summary.outflow > 0 { parts.append("Outflow \(summary.outflow.formatted(.currency(code: "USD")))") }
        if summary.income > 0 { parts.append("Income \(summary.income.formatted(.currency(code: "USD")))") }
        if summary.dueCount > 0 { parts.append("\(summary.dueCount) card due") }
        if summary.itemCount > 0 { parts.append("\(summary.itemCount) transactions") }
        return parts.joined(separator: ", ")
    }

    private var calendarActionDate: Date {
        if calendarViewMode != .month { return calendarFocusDate }
        if Calendar.current.isDate(visibleCalendarMonth, equalTo: Date(), toGranularity: .month) {
            return Date()
        }
        return visibleCalendarMonth
    }

    private var calendarViewControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker("Calendar View", selection: $calendarViewMode) {
                    ForEach(CalendarViewMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Menu {
                    Toggle("Spending & bills", isOn: $calendarShowExpenses)
                    Toggle("Income", isOn: $calendarShowIncome)
                    Toggle("Transfers", isOn: $calendarShowTransfers)
                    Toggle("Credit due", isOn: $calendarShowCreditDue)
                    Toggle("Portfolio", isOn: $calendarShowPortfolio)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 32)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Calendar Filters")
            }

            HStack(spacing: 6) {
                Image(systemName: calendarShowPortfolio ? "eye.fill" : "eye.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(calendarShowPortfolio ? appAccent : Color.secondary)
                Text(calendarFilterSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    resetCalendarToCurrentPeriod()
                } label: {
                    Label(calendarCurrentPeriodButtonTitle, systemImage: calendarViewMode == .week ? "calendar" : "location.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(appAccent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(appAccent)
                .accessibilityLabel(calendarCurrentPeriodButtonTitle)

                Button {
                    Task { await refreshCalendarFromPlaid(force: true) }
                } label: {
                    if isCalendarSyncing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.thinMaterial, in: Circle())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isCalendarSyncing)
                .accessibilityLabel("Sync calendar transactions")
            }

            if let calendarSyncStatus {
                HStack(spacing: 5) {
                    Image(systemName: calendarSyncStatus.hasPrefix("Sync failed") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(calendarSyncStatus.hasPrefix("Sync failed") ? Color.orange : Color.green)
                    Text(calendarSyncStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if calendarViewMode != .month {
                calendarFocusNavigation
            }
        }
    }

    private var calendarCurrentPeriodButtonTitle: String {
        calendarViewMode == .week ? "This Week" : "Today"
    }

    private func resetCalendarToCurrentPeriod() {
        let now = Date()
        withAnimation(.snappy) {
            calendarFocusDate = now
            if calendarViewMode == .month {
                calendarMonthAnchor = now
            }
        }
        scheduleCalendarEventCacheRebuild()
    }

    private var calendarFilterSummary: String {
        let allCoreVisible = calendarShowExpenses && calendarShowIncome && calendarShowTransfers && calendarShowCreditDue
        if allCoreVisible && !calendarShowPortfolio {
            return "Portfolio activity hidden · recommended"
        }
        if allCoreVisible && calendarShowPortfolio {
            return "Showing all activity"
        }
        return "Custom filters active"
    }

    private var calendarFocusNavigation: some View {
        HStack(spacing: 10) {
            Button { shiftCalendarFocus(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 1) {
                Text(calendarFocusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(calendarViewMode == .week ? "Sunday – Saturday" : "Selected day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            Button { shiftCalendarFocus(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var calendarFocusTitle: String {
        switch calendarViewMode {
        case .month:
            return visibleCalendarMonth.formatted(.dateTime.month(.wide).year())
        case .week:
            guard let first = focusedCalendarWeekDays.first, let last = focusedCalendarWeekDays.last else {
                return calendarFocusDate.formatted(.dateTime.month(.abbreviated).day())
            }
            if Calendar.current.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.day()))"
            }
            return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
        case .day:
            return calendarFocusDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }

    private var focusedCalendarWeekDays: [Date] {
        let calendar = Calendar.current
        let focusedDay = calendar.startOfDay(for: calendarFocusDate)
        let weekday = calendar.component(.weekday, from: focusedDay)
        let daysSinceSunday = max(weekday - 1, 0)
        let sunday = calendar.date(byAdding: .day, value: -daysSinceSunday, to: focusedDay) ?? focusedDay
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: sunday) }
    }

    private func shiftCalendarFocus(by offset: Int) {
        let calendar = Calendar.current
        let component: Calendar.Component = calendarViewMode == .week ? .weekOfYear : .day
        guard let shifted = calendar.date(byAdding: component, value: offset, to: calendarFocusDate) else { return }
        withAnimation(.snappy) {
            calendarFocusDate = shifted
        }
    }

    @MainActor
    private func refreshSelectedTabIfNeeded() async {
        switch selectedTab {
        case .home:
            await refreshHomeDashboard()
        case .calendar:
            await refreshCalendarFromPlaid(force: false)
        case .budget, .margin:
            break
        }
    }

    @MainActor
    private func refreshCalendarFromPlaid(force: Bool) async {
        guard !isCalendarSyncing else { return }
        isCalendarSyncing = true
        defer { isCalendarSyncing = false }

        do {
            _ = try await PlaidSyncCoordinator.shared.sync(budget: budget, force: force)
            rebuildCalendarEventCache()
            if let lastSync = PlaidSyncCoordinator.shared.lastSuccessfulSyncAt {
                calendarSyncStatus = "Synced " + lastSync.formatted(date: .omitted, time: .shortened)
            }
        } catch {
            calendarSyncStatus = "Sync failed — tap refresh to retry"
        }
    }

    private var calendarWeekAgendaSection: some View {
        ScrollView {
            VStack(spacing: 10) {
                GlassCard(padding: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(focusedCalendarWeekDays.enumerated()), id: \.element) { index, day in
                            calendarWeekDayColumn(for: day)
                            if index < focusedCalendarWeekDays.count - 1 {
                                Divider()
                            }
                        }
                    }
                }

                Text("Tap a day header for the full day view.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, contentBottomPadding)
        }
        .scrollContentBackground(.hidden)
    }

    private func calendarWeekDayColumn(for date: Date) -> some View {
        let events = filteredCalendarEvents(for: date)
        let visibleEvents = Array(events.prefix(4))
        let hiddenCount = max(events.count - visibleEvents.count, 0)
        let isToday = Calendar.current.isDateInToday(date)

        return VStack(spacing: 6) {
            Button {
                calendarFocusDate = date
                withAnimation(.snappy) { calendarViewMode = .day }
            } label: {
                VStack(spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(date.formatted(.dateTime.day()))
                        .font(.subheadline.weight(isToday ? .bold : .semibold))
                        .foregroundStyle(isToday ? appAccent : Color.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isToday ? appAccent.opacity(0.10) : Color.clear)
            }
            .buttonStyle(.plain)

            Divider()

            if visibleEvents.isEmpty {
                Circle()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(width: 5, height: 5)
                    .padding(.top, 10)
            } else {
                ForEach(visibleEvents) { event in
                    calendarWeekEventTile(event)
                }
            }

            if hiddenCount > 0 {
                Button("+\(hiddenCount)") {
                    selectedCalendarEventList = CalendarDaySelection(date: date)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 310, alignment: .top)
        .padding(.horizontal, 2)
        .background(isToday ? appAccent.opacity(0.035) : Color.clear)
    }

    private func calendarWeekEventTile(_ event: CalendarEventItem) -> some View {
        Button {
            openCalendarEvent(event)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(event.tint)
                    .frame(height: 3)
                Image(systemName: event.iconName)
                    .font(.caption2)
                    .foregroundStyle(event.tint)
                Text(event.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)
                if event.amount > 0 {
                    Text(calendarWeekAmountText(for: event))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(event.isIncome ? Color.green : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .padding(.horizontal, 3)
            .padding(.vertical, 5)
            .background(event.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func calendarWeekAmountText(for event: CalendarEventItem) -> String {
        let amount = event.amount
        let compact: String
        if amount >= 1_000_000 {
            compact = String(format: "$%.1fM", amount / 1_000_000)
        } else if amount >= 1_000 {
            compact = String(format: "$%.1fK", amount / 1_000)
        } else {
            compact = String(format: "$%.0f", amount)
        }
        if event.isTransfer { return compact }
        return (event.isIncome ? "+" : "-") + compact
    }

    private var calendarDayAgendaSection: some View {
        ScrollView {
            VStack(spacing: 12) {
                calendarAgendaDayCard(for: calendarFocusDate, showFullDate: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, contentBottomPadding)
        }
        .scrollContentBackground(.hidden)
    }

    private func calendarAgendaDayCard(for date: Date, showFullDate: Bool) -> some View {
        let events = filteredCalendarEvents(for: date)
        let hiddenCount = max(cachedCalendarEvents(for: date).count - events.count, 0)
        let isToday = Calendar.current.isDateInToday(date)

        return GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(showFullDate ? date.formatted(.dateTime.weekday(.wide).month(.wide).day()) : date.formatted(.dateTime.weekday(.wide)))
                            .font(.subheadline.weight(.bold))
                        if !showFullDate {
                            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isToday {
                        Text("Today")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(appAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(appAccent.opacity(0.12), in: Capsule())
                    }

                    Spacer()

                    Text("\(events.count) item\(events.count == 1 ? "" : "s")")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if events.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: hiddenCount > 0 ? "line.3.horizontal.decrease.circle" : "calendar.badge.checkmark")
                            .foregroundStyle(.secondary)
                        Text(hiddenCount > 0 ? "\(hiddenCount) item\(hiddenCount == 1 ? "" : "s") hidden by filters" : "Nothing scheduled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Add") {
                            selectedCalendarDay = CalendarDaySelection(date: date)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(events) { event in
                            calendarAgendaRow(event)
                            if event.id != events.last?.id {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                }
            }
        }
    }

    private func calendarAgendaRow(_ event: CalendarEventItem) -> some View {
        HStack(spacing: 10) {
            Button {
                openCalendarEvent(event)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: event.iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(event.tint)
                        .frame(width: 32, height: 32)
                        .background(event.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(event.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if event.isPlaidSynced {
                                Image(systemName: "link.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !event.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(event.paymentAccount)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if event.amount > 0 {
                        Text(calendarChipAmountText(for: event))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(event.isIncome ? Color.green : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let recurring = event.recurringPayment {
                Button {
                    markRecurringOccurrencePaid(recurring, on: event.date)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(event.name) paid")
            }
        }
        .padding(.vertical, 7)
    }

    private var backgroundView: some View {
        CuanTheme.background
        .ignoresSafeArea()
    }

    private var spendingProgress: Double {
        guard budget.monthlyIncome > 0 else { return 0 }
        let used = totalMonthlySpent
        return min(max(used / budget.monthlyIncome, 0), 1)
    }

    private var contentBottomPadding: CGFloat {
        120
    }

    private var remainingBudgetForMonth: Double {
        let needsRemaining = budget.totalNeedsAllocated - monthlyNeedsSpent
        let wantsRemaining = budget.totalWantsAllocated - monthlyWantsSpent
        let savingsRemaining = budget.savingsBudget - budget.totalSavingsAllocated
        return needsRemaining + wantsRemaining + savingsRemaining
    }

    private var homePortfolioNetValue: Double {
        let holdingsValue = budget.holdings.reduce(0) { partial, holding in
            let quote = budget.cachedQuotes[holding.ticker.uppercased()]?.price ?? holding.currentPrice
            return partial + (holding.shares * quote)
        }
        return holdingsValue + budget.portfolioSnapshot.cashBalance - budget.portfolioSnapshot.marginUsed
    }

    private var homeTotalNetWorth: Double {
        let totalBank = budget.bankAccounts.reduce(0) { $0 + $1.balance }
        let totalCredit = budget.creditAccounts
            .filter(\.isActive)
            .reduce(0) { $0 + creditAccountActualBalance($1) }
        return totalBank + homePortfolioNetValue - totalCredit
    }

    private var homeCashFlowNet: Double {
        totalMonthlyIncomeLogged - totalMonthlySpent
    }

    private var homeIncomeExpenseRatio: Double {
        guard totalMonthlySpent > 0 else { return totalMonthlyIncomeLogged > 0 ? 99 : 0 }
        return totalMonthlyIncomeLogged / totalMonthlySpent
    }

    private var homeLatestHoldingsUpdate: Date? {
        budget.cachedQuotes.values.map(\.updatedAt).max()
    }

    private var homeMonthlySavingsTargetProgress: Double {
        guard budget.totalSavingsAllocated > 0 else { return 0 }
        return min(max(autoSavedThisMonth / budget.totalSavingsAllocated, 0), 1)
    }

    private var autoSavedThisMonth: Double {
        let monthIncome = totalMonthlyIncomeLogged > 0 ? totalMonthlyIncomeLogged : budget.income(for: selectedMonth)
        return monthIncome - totalMonthlySpent
    }

    private var homeNetWorthHistoryPoints: [PortfolioValuePoint] {
        let sorted = budget.portfolioValueHistory.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let startDate: Date?
        switch selectedHomeNetWorthRange {
        case .oneDay:
            startDate = calendar.date(byAdding: .day, value: -1, to: now)
        case .oneWeek:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)
        case .oneMonth:
            startDate = calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths:
            startDate = calendar.date(byAdding: .month, value: -3, to: now)
        case .oneYear:
            startDate = calendar.date(byAdding: .year, value: -1, to: now)
        case .all:
            startDate = nil
        }

        guard let startDate else { return sorted }
        let filtered = sorted.filter { $0.date >= startDate }
        return filtered.isEmpty ? sorted : filtered
    }

    private var homeNetWorthDelta: Double {
        let points = homeNetWorthHistoryPoints
        guard let first = points.first, let last = points.last else { return 0 }
        return last.netValue - first.netValue
    }

    private var homeNetWorthDeltaPercent: Double {
        let points = homeNetWorthHistoryPoints
        guard let first = points.first, abs(first.netValue) > 0.01 else { return 0 }
        return homeNetWorthDelta / abs(first.netValue)
    }

    private var categorySummaryItems: [CategorySummaryItem] {
        var items: [CategorySummaryItem] = []
        for category in budget.needsCategories {
            let spent = needsSpentByCategoryId[category.id] ?? 0
            items.append(CategorySummaryItem(name: category.name, spent: spent, tint: .blue))
        }
        for category in budget.wantsCategories {
            let spent = wantsSpentByCategoryId[category.id] ?? 0
            items.append(CategorySummaryItem(name: category.name, spent: spent, tint: .orange))
        }
        return items.filter { $0.spent > 0 }.sorted { $0.spent > $1.spent }
    }

    private var planHighlightItems: [PlanHighlightItem] {
        [
            PlanHighlightItem(
                section: .needs,
                title: "Needs",
                systemImage: "house.fill",
                amount: budget.needsBudget,
                allocated: budget.totalNeedsAllocated,
                tint: .blue
            ),
            PlanHighlightItem(
                section: .wants,
                title: "Wants",
                systemImage: "sparkles",
                amount: budget.wantsBudget,
                allocated: budget.totalWantsAllocated,
                tint: .orange
            ),
            PlanHighlightItem(
                section: .savings,
                title: "Savings",
                systemImage: "banknote.fill",
                amount: budget.savingsBudget,
                allocated: budget.totalSavingsAllocated,
                tint: .green
            )
        ]
    }

    private var monthInterval: DateInterval? {
        let calendar = Calendar.current
        return calendar.dateInterval(of: .month, for: selectedMonth)
    }

    private var monthlySpendingExpenses: [Expense] {
        monthlyExpenses.filter { !budget.isCreditCardPayment($0) }
    }

    private var trendRangeStart: Date? {
        guard let interval = monthInterval else { return nil }
        let calendar = Calendar.current
        let endDay = endDay(for: interval)
        let proposedStart: Date
        switch selectedTrendRange {
        case .monthToDate:
            proposedStart = interval.start
        case .last7Days:
            proposedStart = calendar.date(byAdding: .day, value: -6, to: endDay) ?? interval.start
        case .last30Days:
            proposedStart = calendar.date(byAdding: .day, value: -29, to: endDay) ?? interval.start
        }
        return max(interval.start, proposedStart)
    }

    private var trendRangeEnd: Date? {
        guard let interval = monthInterval else { return nil }
        return endDay(for: interval)
    }

    private var trendSpendingPoints: [DailySpend] {
        guard let start = trendRangeStart, let end = trendRangeEnd else { return [] }
        return adjustedSeries(from: dailySpending, start: start, end: end)
    }

    private var trendIncomePoints: [DailySpend] {
        guard let start = trendRangeStart, let end = trendRangeEnd else { return [] }
        return adjustedSeries(from: dailyIncome, start: start, end: end)
    }

    private var trendTotal: Double {
        switch selectedLogTrend {
        case .spending:
            return trendSpendingPoints.last?.amount ?? 0
        case .income:
            return trendIncomePoints.last?.amount ?? 0
        }
    }

    private var trendAveragePerDay: Double {
        guard let start = trendRangeStart, let end = trendRangeEnd else { return 0 }
        let days = max(dayCount(from: start, to: end), 1)
        return trendTotal / Double(days)
    }

    private var trendEntriesInRange: Int {
        guard let start = trendRangeStart, let end = trendRangeEnd else { return 0 }
        switch selectedLogTrend {
        case .spending:
            return monthlySpendingExpenses.filter { $0.date >= start && $0.date <= end }.count
        case .income:
            return monthlyIncomes.filter { $0.date >= start && $0.date <= end }.count
        }
    }

    private var trendActiveDaysInRange: Int {
        guard let start = trendRangeStart, let end = trendRangeEnd else { return 0 }
        let calendar = Calendar.current
        switch selectedLogTrend {
        case .spending:
            return Set(monthlySpendingExpenses.filter { $0.date >= start && $0.date <= end }.map { calendar.startOfDay(for: $0.date) }).count
        case .income:
            return Set(monthlyIncomes.filter { $0.date >= start && $0.date <= end }.map { calendar.startOfDay(for: $0.date) }).count
        }
    }

    private var trendPeakDailyAmountInRange: Double {
        guard let start = trendRangeStart, let end = trendRangeEnd else { return 0 }
        let calendar = Calendar.current
        var totals: [Date: Double] = [:]
        switch selectedLogTrend {
        case .spending:
            for entry in monthlySpendingExpenses where entry.date >= start && entry.date <= end {
                let day = calendar.startOfDay(for: entry.date)
                totals[day, default: 0] += entry.amount
            }
        case .income:
            for entry in monthlyIncomes where entry.date >= start && entry.date <= end {
                let day = calendar.startOfDay(for: entry.date)
                totals[day, default: 0] += entry.amount
            }
        }
        return totals.values.max() ?? 0
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }

    private func updateMonthlyData() {
        guard let interval = monthInterval else {
            monthlyExpenses = []
            monthlyIncomes = []
            monthlySavingsEntries = []
            totalMonthlySpent = 0
            totalMonthlyIncomeLogged = 0
            needsSpentByCategoryId = [:]
            wantsSpentByCategoryId = [:]
            monthlyNeedsSpent = 0
            monthlyWantsSpent = 0
            savingsLoggedByGoalId = [:]
            monthlySavingsLogged = 0
            dailySpending = []
            dailyIncome = []
            return
        }

        monthlyExpenses = budget.expenses.filter { interval.contains($0.date) }
        monthlyIncomes = budget.incomes.filter { interval.contains($0.date) }
        monthlySavingsEntries = budget.savingsEntries.filter { interval.contains($0.date) }
        let spendingExpenses = monthlyExpenses.filter { !budget.isCreditCardPayment($0) }
        totalMonthlySpent = spendingExpenses.reduce(0) { $0 + $1.amount }
        totalMonthlyIncomeLogged = monthlyIncomes.reduce(0) { $0 + $1.amount }

        var needsTotals: [UUID: Double] = [:]
        var wantsTotals: [UUID: Double] = [:]
        for expense in spendingExpenses {
            switch expense.section {
            case .needs:
                needsTotals[expense.categoryId, default: 0] += expense.amount
            case .wants:
                wantsTotals[expense.categoryId, default: 0] += expense.amount
            }
        }
        needsSpentByCategoryId = needsTotals
        wantsSpentByCategoryId = wantsTotals
        monthlyNeedsSpent = needsTotals.values.reduce(0, +)
        monthlyWantsSpent = wantsTotals.values.reduce(0, +)

        var savingsTotals: [UUID: Double] = [:]
        for entry in monthlySavingsEntries {
            savingsTotals[entry.goalId, default: 0] += entry.amount
        }
        savingsLoggedByGoalId = savingsTotals
        monthlySavingsLogged = savingsTotals.values.reduce(0, +)

        dailySpending = buildDailySeries(
            interval: interval,
            amountsByDate: dailyTotals(from: spendingExpenses.map { ($0.date, $0.amount) })
        )
        dailyIncome = buildDailySeries(
            interval: interval,
            amountsByDate: dailyTotals(from: monthlyIncomes.map { ($0.date, $0.amount) })
        )
    }

    private func dailyTotals(from entries: [(Date, Double)]) -> [Date: Double] {
        var totals: [Date: Double] = [:]
        let calendar = Calendar.current
        for (date, amount) in entries {
            let day = calendar.startOfDay(for: date)
            totals[day, default: 0] += amount
        }
        return totals
    }

    private func buildDailySeries(interval: DateInterval, amountsByDate: [Date: Double]) -> [DailySpend] {
        let calendar = Calendar.current
        let endDay = endDay(for: interval)

        var points: [DailySpend] = []
        var day = calendar.startOfDay(for: interval.start)
        var runningTotal: Double = 0
        while day <= endDay {
            runningTotal += amountsByDate[day] ?? 0
            points.append(DailySpend(date: day, amount: runningTotal))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return points
    }

    private func endDay(for interval: DateInterval) -> Date {
        let calendar = Calendar.current
        if isCurrentMonth {
            return calendar.startOfDay(for: Date())
        }
        let startNextMonth = calendar.startOfDay(for: interval.end)
        return calendar.date(byAdding: .day, value: -1, to: startNextMonth) ?? calendar.startOfDay(for: interval.start)
    }

    private func adjustedSeries(from points: [DailySpend], start: Date, end: Date) -> [DailySpend] {
        let baseline = points.last(where: { $0.date < start })?.amount ?? 0
        return points
            .filter { $0.date >= start && $0.date <= end }
            .map { DailySpend(date: $0.date, amount: $0.amount - baseline) }
    }

    private func dayCount(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return days + 1
    }

    private func startAddExpense() {
        Haptics.light()
        expenseDraftSection = lastExpenseSection
        expenseDraftCategoryId = lastExpenseCategoryId ?? budget.needsCategories.first?.id ?? budget.wantsCategories.first?.id
        expenseDraft = ExpenseDraft(section: expenseDraftSection, categoryId: expenseDraftCategoryId)
    }

    private func startAddIncome() {
        Haptics.light()
        showingAddIncome = true
    }

    private func nearestPoint(in points: [DailySpend], to date: Date) -> DailySpend? {
        guard !points.isEmpty else { return nil }
        let target = date.timeIntervalSinceReferenceDate
        var low = 0
        var high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].date.timeIntervalSinceReferenceDate < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        if low == 0 {
            return points[0]
        }
        if low >= points.count {
            return points[points.count - 1]
        }
        let before = points[low - 1]
        let after = points[low]
        let beforeDiff = abs(before.date.timeIntervalSinceReferenceDate - target)
        let afterDiff = abs(after.date.timeIntervalSinceReferenceDate - target)
        return beforeDiff <= afterDiff ? before : after
    }

    private func shiftMonth(by offset: Int) {
        let calendar = Calendar.current
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: selectedMonth) else { return }
        if calendar.compare(newMonth, to: Date(), toGranularity: .month) == .orderedDescending {
            selectedMonth = Date()
        } else {
            selectedMonth = newMonth
        }
    }

    // MARK: - Overview Section
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleSectionHeader(
                title: "Overview",
                tint: .blue,
                isExpanded: $overviewExpanded,
                onAdd: nil,
                valueLabel: "Remaining",
                value: remainingBudgetForMonth
            )

            if overviewExpanded {
                GlassCard(padding: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            HStack(spacing: 6) {
                                Button(action: { shiftMonth(by: -1) }) {
                                    Image(systemName: "chevron.left")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .padding(8)
                                        .background(Color.primary.opacity(0.06), in: Circle())
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)

                                Text(selectedMonth, format: .dateTime.month(.wide).year())
                                    .font(.caption)
                                    .fontWeight(.semibold)

                                Button(action: { shiftMonth(by: 1) }) {
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .padding(8)
                                        .background(Color.primary.opacity(0.06), in: Circle())
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled(isCurrentMonth)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )

                            Spacer()

                            Text(budget.payFrequency.rawValue)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }

                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Monthly Income")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(budget.monthlyIncome, format: .currency(code: "USD"))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Remaining")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(remainingBudgetForMonth, format: .currency(code: "USD"))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(remainingBudgetForMonth >= 0 ? .green : .red)
                            }
                        }

                        if budget.income > 0 {
                            ProgressView(value: spendingProgress) {
                                Text("\(Int(spendingProgress * 100))% used")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tint(.blue)
                        } else {
                            Text("Add your income to start planning.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if budget.income == 0 {
                            Button("Set Income") {
                                Haptics.light()
                                selectedTab = .budget
                                scrollToIncome = true
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Set income")
                        }
                    }
                }
            }
        }
    }

    private var logMonthSwitcher: some View {
        HStack {
            Spacer()

            HStack(spacing: 10) {
                Button(action: { shiftMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(selectedMonth, format: .dateTime.month(.wide).year())
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Button(action: { shiftMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCurrentMonth)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)

            Spacer()
        }
    }

    private var logMonthHeaderSelector: some View {
        HStack(spacing: 4) {
            Button(action: { shiftMonth(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)

            Text(selectedMonth, format: .dateTime.month(.abbreviated).year())
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: { shiftMonth(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var calendarWeekdaySymbols: [String] {
        let symbols = Calendar.current.shortWeekdaySymbols
        let firstWeekdayIndex = Calendar.current.firstWeekday - 1
        let head = Array(symbols[firstWeekdayIndex...])
        let tail = Array(symbols[..<firstWeekdayIndex])
        return head + tail
    }

    private var calendarWeekdayHeader: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(calendarWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial)
    }

    private var calendarWeeks: [CalendarWeek] {
        let calendar = Calendar.current
        guard let firstMonth = calendar.date(byAdding: .month, value: -36, to: currentCalendarMonth),
              let lastMonth = calendar.date(byAdding: .month, value: 36, to: currentCalendarMonth),
              let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: firstMonth),
              let lastMonthInterval = calendar.dateInterval(of: .month, for: lastMonth),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: lastMonthInterval.end),
              let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay) else {
            return []
        }

        var weeks: [CalendarWeek] = []
        var weekStart = firstWeekInterval.start
        while weekStart <= lastWeekInterval.start {
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            weeks.append(CalendarWeek(startDate: weekStart, days: days))
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = nextWeek
        }
        return weeks
    }

    private var currentCalendarMonth: Date {
        Self.startOfMonth(for: Date())
    }

    private var currentCalendarWeekStart: Date {
        Calendar.current.dateInterval(of: .weekOfMonth, for: currentCalendarMonth)?.start ?? currentCalendarMonth
    }

    private var visibleCalendarMonth: Date {
        Self.startOfMonth(for: calendarMonthAnchor)
    }

    private var visibleCalendarMonthInterval: DateInterval? {
        Calendar.current.dateInterval(of: .month, for: visibleCalendarMonth)
    }

    private var visibleCalendarMonthDays: [Date] {
        let calendar = Calendar.current
        guard let interval = visibleCalendarMonthInterval else { return [] }
        var days: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            days.append(cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }
        return days
    }

    private var calendarVisibleIncome: Double {
        let oneTimeIncome = calendarShowIncome
            ? budget.incomes
                .filter { isInVisibleCalendarMonth($0.date) }
                .reduce(0) { $0 + $1.amount }
            : 0
        let recurringIncome = calendarShowIncome
            ? visibleCalendarMonthDays
                .flatMap(recurringOccurrences)
                .filter { $0.payment.kind == .income && !isRecurringOccurrencePaid($0.payment, on: $0.date) }
                .reduce(0) { $0 + $1.payment.amount }
            : 0
        let investmentIncome = calendarShowPortfolio
            ? budget.portfolioTransactions
                .filter { isInVisibleCalendarMonth($0.date) && ($0.type == .sell || $0.type == .dividend) }
                .reduce(0) { $0 + $1.amount }
            : 0
        return oneTimeIncome + recurringIncome + investmentIncome
    }

    private var calendarVisibleOutflow: Double {
        guard calendarShowExpenses else { return 0 }
        let oneTimeExpenses = budget.expenses
            .filter { isInVisibleCalendarMonth($0.date) && !budget.isCreditCardPayment($0) }
            .reduce(0) { $0 + $1.amount }
        let recurringExpenses = visibleCalendarMonthDays
            .flatMap(recurringOccurrences)
            .filter { $0.payment.kind == .expense && !isRecurringOccurrencePaid($0.payment, on: $0.date) }
            .reduce(0) { $0 + $1.payment.amount }
        return oneTimeExpenses + recurringExpenses
    }

    private var calendarVisibleCreditDue: Double {
        guard calendarShowCreditDue else { return 0 }
        return budget.creditAccounts
            .filter { account in
                account.isActive && visibleCalendarMonthDays.contains { date in
                    Calendar.current.component(.day, from: date) == recurringOccurrenceDay(in: date, paymentDay: account.dueDay)
                }
            }
            .reduce(0) { $0 + creditAccountActualBalance($1) }
    }

    private func isInVisibleCalendarMonth(_ date: Date) -> Bool {
        guard let interval = visibleCalendarMonthInterval else { return false }
        return date >= interval.start && date < interval.end
    }

    private func monthForCalendarWeek(startingAt weekStart: Date) -> Date {
        let calendar = Calendar.current
        let midpoint = calendar.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart
        return Self.startOfMonth(for: midpoint)
    }

    private func calendarGridDates(for month: Date) -> [Date?] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay) else {
            return []
        }

        var dates: [Date?] = []
        var cursor = firstWeekInterval.start
        while cursor < lastWeekInterval.end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private func monthGridHeight(for month: Date) -> CGFloat {
        let totalCells = calendarGridDates(for: month).count
        let rowCount = max(1, Int(ceil(Double(totalCells) / 7.0)))
        let weekdayHeaderHeight: CGFloat = 22
        let rowHeight: CGFloat = 86
        let rowSpacing: CGFloat = 8
        return weekdayHeaderHeight + (CGFloat(rowCount) * rowHeight) + (CGFloat(max(0, rowCount - 1)) * rowSpacing) + 10
    }

    private func recurringOccurrences(for date: Date) -> [CalendarOccurrence] {
        let calendar = Calendar.current
        return budget.recurringPayments
            .filter { payment in
                guard payment.isActive else { return false }
                guard calendar.startOfDay(for: date) >= calendar.startOfDay(for: payment.startDate) else { return false }
                return recurringOccurrenceDay(in: date, paymentDay: payment.dayOfMonth) == calendar.component(.day, from: date)
            }
            .map { CalendarOccurrence(payment: $0, date: date) }
            .sorted { lhs, rhs in
                if lhs.payment.kind == rhs.payment.kind {
                    return lhs.payment.amount > rhs.payment.amount
                }
                return lhs.payment.kind == .income
            }
    }

    private func recurringOccurrenceDay(in date: Date, paymentDay: Int) -> Int {
        let calendar = Calendar.current
        let maxDay = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        return min(max(paymentDay, 1), maxDay)
    }

    private var continuousChargeSummary: ContinuousChargeSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var totalDue: Double = 0
        var totalPaid: Double = 0
        var totalUnpaid: Double = 0
        var occurrenceCount = 0
        var paidCount = 0
        var unpaidCount = 0
        var topCharges: [TopRecurringCharge] = []

        for payment in budget.recurringPayments where payment.isActive && payment.kind == .expense {
            let dates = recurringOccurrenceDates(for: payment, through: today)
            guard !dates.isEmpty else { continue }
            let paidForPayment = dates.filter { isRecurringOccurrencePaid(payment, on: $0) }.count
            let unpaidForPayment = dates.count - paidForPayment
            let due = Double(dates.count) * payment.amount
            let paid = Double(paidForPayment) * payment.amount
            let unpaid = Double(unpaidForPayment) * payment.amount

            totalDue += due
            totalPaid += paid
            totalUnpaid += unpaid
            occurrenceCount += dates.count
            paidCount += paidForPayment
            unpaidCount += unpaidForPayment
            topCharges.append(
                TopRecurringCharge(
                    id: payment.id,
                    name: payment.name,
                    amount: due,
                    occurrences: dates.count,
                    paid: paidForPayment,
                    tint: colorFor(section: payment.section, categoryId: payment.categoryId, isIncome: false)
                )
            )
        }

        let nextExpense = budget.recurringPayments
            .filter { $0.isActive && $0.kind == .expense }
            .compactMap { payment -> (payment: RecurringPayment, date: Date)? in
                guard let date = nextRecurringOccurrenceDate(for: payment, after: today) else { return nil }
                return (payment, date)
            }
            .min { $0.date < $1.date }

        return ContinuousChargeSummary(
            totalDue: totalDue,
            totalPaid: totalPaid,
            totalUnpaid: totalUnpaid,
            occurrenceCount: occurrenceCount,
            paidCount: paidCount,
            unpaidCount: unpaidCount,
            nextDueDate: nextExpense?.date,
            nextDueName: nextExpense?.payment.name,
            topCharges: topCharges.sorted { $0.amount > $1.amount }
        )
    }

    private func recurringOccurrenceDates(for payment: RecurringPayment, through endDate: Date) -> [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: payment.startDate)
        guard start <= endDate else { return [] }

        var components = calendar.dateComponents([.year, .month], from: start)
        components.day = 1
        guard var cursor = calendar.date(from: components) else { return [] }

        var dates: [Date] = []
        while cursor <= endDate {
            let day = recurringOccurrenceDay(in: cursor, paymentDay: payment.dayOfMonth)
            if let date = calendar.date(from: DateComponents(
                year: calendar.component(.year, from: cursor),
                month: calendar.component(.month, from: cursor),
                day: day
            )) {
                let normalized = calendar.startOfDay(for: date)
                if normalized >= start && normalized <= endDate {
                    dates.append(normalized)
                }
            }
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = nextMonth
        }
        return dates
    }

    private func nextRecurringOccurrenceDate(for payment: RecurringPayment, after date: Date) -> Date? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: max(payment.startDate, date))
        var components = calendar.dateComponents([.year, .month], from: start)
        components.day = 1
        guard var cursor = calendar.date(from: components) else { return nil }

        for _ in 0..<36 {
            let day = recurringOccurrenceDay(in: cursor, paymentDay: payment.dayOfMonth)
            if let occurrence = calendar.date(from: DateComponents(
                year: calendar.component(.year, from: cursor),
                month: calendar.component(.month, from: cursor),
                day: day
            )) {
                let normalized = calendar.startOfDay(for: occurrence)
                if normalized >= start {
                    return normalized
                }
            }
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) else { return nil }
            cursor = nextMonth
        }
        return nil
    }

    private func recurringOccurrenceKey(paymentId: UUID, date: Date) -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        let day = comps.day ?? 0
        return "\(paymentId.uuidString)_\(String(format: "%04d-%02d-%02d", year, month, day))"
    }

    private func isRecurringOccurrencePaid(_ payment: RecurringPayment, on date: Date) -> Bool {
        payment.paidOccurrenceKeys.contains(recurringOccurrenceKey(paymentId: payment.id, date: date))
    }

    private func markRecurringOccurrencePaid(_ payment: RecurringPayment, on date: Date) {
        let key = recurringOccurrenceKey(paymentId: payment.id, date: date)
        guard let index = budget.recurringPayments.firstIndex(where: { $0.id == payment.id }) else { return }
        guard !budget.recurringPayments[index].paidOccurrenceKeys.contains(key) else { return }
        budget.recurringPayments[index].paidOccurrenceKeys.append(key)

        if payment.kind == .income {
            budget.addIncomeEntry(
                IncomeEntry(
                    name: payment.name,
                    amount: payment.amount,
                    date: date,
                    bankName: payment.paymentAccount
                )
            )
            return
        }

        let section = payment.section
        var categoryId = payment.categoryId
        let categories = section == .needs ? budget.needsCategories : budget.wantsCategories
        if categoryId == nil || !categories.contains(where: { $0.id == categoryId }) {
            if let fallback = categories.first {
                categoryId = fallback.id
            } else {
                let newCategory = Category(name: "Recurring", allocatedAmount: 0)
                if section == .needs {
                    budget.needsCategories.append(newCategory)
                } else {
                    budget.wantsCategories.append(newCategory)
                }
                categoryId = newCategory.id
            }
        }

        guard let categoryId else { return }
        budget.addExpense(
            Expense(
                name: payment.name,
                amount: payment.amount,
                date: date,
                section: section,
                categoryId: categoryId,
                paymentAccount: payment.paymentAccount,
                note: payment.note,
                creditCardPaymentTarget: payment.creditCardPaymentTarget
            )
        )
    }

    private struct CalendarEventItem: Identifiable {
        let id: UUID
        let name: String
        let amount: Double
        let isIncome: Bool
        let date: Date
        let recurringPayment: RecurringPayment?
        let expense: Expense?
        let income: IncomeEntry?
        let cashTransfer: CashTransfer?
        let isPaid: Bool
        let isTransfer: Bool
        let tint: Color
        let isCreditDue: Bool
        let paymentAccount: String
        let iconName: String
        let creditAccount: CreditAccount?
        let portfolioTransaction: PortfolioTransaction?

        var isPlaidSynced: Bool {
            expense?.plaidMetadata != nil ||
            income?.plaidMetadata != nil ||
            creditAccount?.plaidMetadata != nil ||
            portfolioTransaction?.plaidMetadata != nil
        }
    }

    private func calendarDayKey(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private var calendarCacheDates: [Date] {
        switch calendarViewMode {
        case .month:
            return calendarGridDates(for: visibleCalendarMonth).compactMap { $0 }
        case .week:
            return focusedCalendarWeekDays
        case .day:
            return [calendarDayKey(for: calendarFocusDate)]
        }
    }

    private func rebuildCalendarEventCache() {
        let dates = calendarCacheDates
        calendarEventCache = Dictionary(
            uniqueKeysWithValues: dates.map { date in
                (calendarDayKey(for: date), calendarEvents(for: date))
            }
        )
    }

    private func scheduleCalendarEventCacheRebuild() {
        calendarCacheRefreshTask?.cancel()
        calendarCacheRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            rebuildCalendarEventCache()
        }
    }

    private func cachedCalendarEvents(for date: Date) -> [CalendarEventItem] {
        calendarEventCache[calendarDayKey(for: date)] ?? calendarEvents(for: date)
    }

    private func calendarEventPassesFilters(_ event: CalendarEventItem) -> Bool {
        if event.portfolioTransaction != nil { return calendarShowPortfolio }
        if event.isCreditDue { return calendarShowCreditDue }
        if event.cashTransfer != nil { return calendarShowTransfers }
        if event.isIncome { return calendarShowIncome }
        return calendarShowExpenses
    }

    private func filteredCalendarEvents(for date: Date) -> [CalendarEventItem] {
        cachedCalendarEvents(for: date).filter(calendarEventPassesFilters)
    }

    private func calendarEvents(for date: Date) -> [CalendarEventItem] {
        let calendar = Calendar.current
        let recurring = recurringOccurrences(for: date)
            .filter { !isRecurringOccurrencePaid($0.payment, on: date) }
            .map {
            CalendarEventItem(
                id: UUID(),
                name: $0.payment.name,
                amount: $0.payment.amount,
                isIncome: $0.payment.kind == .income,
                date: date,
                recurringPayment: $0.payment,
                expense: nil,
                income: nil,
                cashTransfer: nil,
                isPaid: isRecurringOccurrencePaid($0.payment, on: date),
                isTransfer: false,
                tint: colorFor(section: $0.payment.section, categoryId: $0.payment.categoryId, isIncome: $0.payment.kind == .income),
                isCreditDue: false,
                paymentAccount: $0.payment.paymentAccount,
                iconName: iconName(for: $0.payment.name, isCreditDue: false, paymentAccount: $0.payment.paymentAccount),
                creditAccount: nil,
                portfolioTransaction: nil
            )
        }
        let oneTimeExpenses = budget.expenses
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .map {
                CalendarEventItem(
                    id: $0.id,
                    name: $0.name,
                    amount: $0.amount,
                    isIncome: false,
                    date: $0.date,
                    recurringPayment: nil,
                    expense: $0,
                    income: nil,
                    cashTransfer: nil,
                    isPaid: true,
                    isTransfer: false,
                    tint: colorFor(section: $0.section, categoryId: $0.categoryId, isIncome: false),
                    isCreditDue: false,
                    paymentAccount: $0.paymentAccount,
                    iconName: iconName(for: $0.name, isCreditDue: false, paymentAccount: $0.paymentAccount),
                    creditAccount: nil,
                    portfolioTransaction: nil
                )
            }
        let oneTimeIncome = budget.incomes
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .map {
                CalendarEventItem(
                    id: $0.id,
                    name: $0.name,
                    amount: $0.amount,
                    isIncome: true,
                    date: $0.date,
                    recurringPayment: nil,
                    expense: nil,
                    income: $0,
                    cashTransfer: nil,
                    isPaid: true,
                    isTransfer: false,
                    tint: colorFor(section: .needs, categoryId: nil, isIncome: true),
                    isCreditDue: false,
                    paymentAccount: "",
                    iconName: "dollarsign.circle",
                    creditAccount: nil,
                    portfolioTransaction: nil
                )
            }
        let portfolioItems: [CalendarEventItem]
        if calendarShowPortfolio {
            portfolioItems = budget.portfolioTransactions
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
                .map { transaction in
                    CalendarEventItem(
                        id: transaction.id,
                        name: portfolioEventName(transaction),
                        amount: transaction.amount,
                        isIncome: transaction.type == .sell || transaction.type == .dividend,
                        date: transaction.date,
                        recurringPayment: nil,
                        expense: nil,
                        income: nil,
                        cashTransfer: nil,
                        isPaid: true,
                        isTransfer: transaction.type == .contribution,
                        tint: portfolioEventColor(transaction),
                        isCreditDue: false,
                        paymentAccount: transaction.fundingBankAccount ?? "Investment Account",
                        iconName: portfolioEventIcon(transaction),
                        creditAccount: nil,
                        portfolioTransaction: transaction
                    )
                }
        } else {
            portfolioItems = []
        }
        let transferItems = budget.cashTransfers
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .map { transfer in
                CalendarEventItem(
                    id: transfer.id,
                    name: transfer.name,
                    amount: transfer.amount,
                    isIncome: false,
                    date: transfer.date,
                    recurringPayment: nil,
                    expense: nil,
                    income: nil,
                    cashTransfer: transfer,
                    isPaid: true,
                    isTransfer: true,
                    tint: .cyan,
                    isCreditDue: false,
                    paymentAccount: "\(transfer.fromAccountName) -> \(transfer.toAccountName)",
                    iconName: "arrow.left.arrow.right",
                    creditAccount: nil,
                    portfolioTransaction: nil
                )
            }
        let dueItems = budget.creditAccounts.compactMap { account -> CalendarEventItem? in
            guard account.isActive else { return nil }
            let dueDay = recurringOccurrenceDay(in: date, paymentDay: account.dueDay)
            guard calendar.component(.day, from: date) == dueDay else { return nil }
            return CalendarEventItem(
                id: account.id,
                name: "\(account.name) Due",
                amount: creditAccountActualBalance(account),
                isIncome: false,
                date: date,
                recurringPayment: nil,
                expense: nil,
                income: nil,
                cashTransfer: nil,
                isPaid: false,
                isTransfer: false,
                tint: colorForCreditAccount(account.id),
                isCreditDue: true,
                paymentAccount: account.name,
                iconName: "creditcard",
                creditAccount: account,
                portfolioTransaction: nil
            )
        }

        return (recurring + oneTimeIncome + oneTimeExpenses + transferItems + portfolioItems + dueItems).sorted { lhs, rhs in
            if lhs.isIncome == rhs.isIncome { return lhs.amount > rhs.amount }
            return lhs.isIncome && !rhs.isIncome
        }
    }

    private func portfolioEventName(_ transaction: PortfolioTransaction) -> String {
        let ticker = transaction.ticker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if transaction.type == .contribution {
            return "Transfer to Portfolio"
        }
        let base = transaction.type.title
        return ticker.isEmpty ? base : "\(base) \(ticker.uppercased())"
    }

    private func portfolioEventIcon(_ transaction: PortfolioTransaction) -> String {
        switch transaction.type {
        case .buy: return "arrow.down.circle"
        case .sell: return "arrow.up.circle"
        case .dividend: return "dollarsign.circle"
        case .contribution: return "plus.circle"
        case .billPaidByMargin: return "creditcard"
        case .marginInterest: return "percent"
        case .manualAdjustment: return "slider.horizontal.3"
        }
    }

    private func portfolioEventColor(_ transaction: PortfolioTransaction) -> Color {
        switch transaction.type {
        case .sell, .dividend:
            return .green
        case .buy, .billPaidByMargin, .marginInterest:
            return .orange
        case .contribution:
            return .mint
        case .manualAdjustment:
            return .indigo
        }
    }

    private func colorFor(section: BudgetSection, categoryId: UUID?, isIncome: Bool) -> Color {
        if isIncome { return .green }
        guard let categoryId else { return section == .needs ? .blue : .orange }
        return colorForCategory(categoryId)
    }

    private func creditAccountActualBalance(_ account: CreditAccount) -> Double {
        if account.plaidMetadata != nil {
            return account.startingBalance
        }
        let normalizedAccountName = account.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAccountName.isEmpty else { return 0 }
        return budget.expenses.reduce(account.startingBalance) { partial, expense in
            if let paidCard = budget.creditCardPaymentTarget(for: expense),
               paidCard.caseInsensitiveCompare(account.name) == .orderedSame {
                return partial - expense.amount
            }
            let paymentAccount = expense.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard paymentAccount == normalizedAccountName else { return partial }
            return partial + expense.amount
        }
    }

    private func creditCardPaymentTarget(from note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[CC_PAYMENT:") else { return nil }
        guard let endIndex = trimmed.firstIndex(of: "]") else { return nil }
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 12)
        guard startIndex < endIndex else { return nil }
        let accountName = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return accountName.isEmpty ? nil : accountName
    }

    private func colorForCategory(_ categoryId: UUID) -> Color {
        let palette: [Color] = [
            .blue, .teal, .mint, .cyan, .indigo, .purple, .orange, .pink
        ]
        return palette[stablePaletteIndex(for: categoryId, paletteCount: palette.count)]
    }

    private func colorForCreditAccount(_ accountId: UUID) -> Color {
        let palette: [Color] = [.blue, .indigo, .purple, .teal]
        return palette[stablePaletteIndex(for: accountId, paletteCount: palette.count)]
    }

    private func stablePaletteIndex(for id: UUID, paletteCount: Int) -> Int {
        let seed = id.uuidString.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return seed % max(paletteCount, 1)
    }

    private func iconName(for name: String, isCreditDue: Bool, paymentAccount: String) -> String {
        let lowered = name.lowercased()
        if isCreditDue { return "creditcard" }
        if lowered.contains("coffee") || lowered.contains("latte") || lowered.contains("espresso") || lowered.contains("cafe") {
            return "cup.and.saucer.fill"
        }
        if lowered.contains("grocery") || lowered.contains("market") || lowered.contains("supermarket") {
            return "cart.fill"
        }
        if lowered.contains("restaurant") || lowered.contains("dinner") || lowered.contains("lunch") || lowered.contains("breakfast") || lowered.contains("food") {
            return "fork.knife"
        }
        if lowered.contains("gas") || lowered.contains("fuel") {
            return "fuelpump.fill"
        }
        if lowered.contains("uber") || lowered.contains("lyft") || lowered.contains("taxi") || lowered.contains("ride") {
            return "car.fill"
        }
        if lowered.contains("flight") || lowered.contains("airline") || lowered.contains("trip") || lowered.contains("travel") || lowered.contains("hotel") {
            return "airplane"
        }
        if lowered.contains("movie") || lowered.contains("theater") || lowered.contains("concert") || lowered.contains("show") {
            return "ticket.fill"
        }
        if lowered.contains("gym") || lowered.contains("fitness") {
            return "dumbbell.fill"
        }
        if lowered.contains("rent") || lowered.contains("mortgage") || lowered.contains("lease") {
            return "house.fill"
        }
        if lowered.contains("utility") || lowered.contains("electric") || lowered.contains("water") || lowered.contains("gas") {
            return "bolt.fill"
        }
        if lowered.contains("subscription") || lowered.contains("stream") || lowered.contains("netflix") || lowered.contains("spotify") || lowered.contains("hulu") || lowered.contains("icloud") {
            return "repeat.circle.fill"
        }
        if lowered.contains("amazon") || lowered.contains("order") || lowered.contains("shopping") || lowered.contains("purchase") {
            return "bag.fill"
        }
        if !paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "wallet.pass.fill"
        }
        return "tag.fill"
    }

    private var logTransactionItems: [LogTransactionItem] {
        let expenses = monthlyExpenses.map { expense in
            LogTransactionItem(
                id: expense.id,
                title: expense.name,
                subtitle: budget.categoryName(for: expense),
                amount: expense.amount,
                date: expense.date,
                isInflow: false,
                iconName: iconName(for: expense.name, isCreditDue: false, paymentAccount: expense.paymentAccount),
                tint: colorFor(section: expense.section, categoryId: expense.categoryId, isIncome: false),
                kind: .expense(expense)
            )
        }
        let incomes = monthlyIncomes.map { income in
            LogTransactionItem(
                id: income.id,
                title: income.name,
                subtitle: income.bankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Income" : income.bankName,
                amount: income.amount,
                date: income.date,
                isInflow: true,
                iconName: "dollarsign.circle.fill",
                tint: .green,
                kind: .income(income)
            )
        }
        let savings = monthlySavingsEntries.map { entry in
            LogTransactionItem(
                id: entry.id,
                title: entry.name.isEmpty ? "Savings" : entry.name,
                subtitle: budget.savingsGoalName(for: entry),
                amount: entry.amount,
                date: entry.date,
                isInflow: false,
                iconName: "banknote.fill",
                tint: .mint,
                kind: .savings(entry)
            )
        }
        return (expenses + incomes + savings).sorted { $0.date > $1.date }
    }

    private var logTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleSectionHeader(
                title: "Transactions",
                tint: .primary,
                isExpanded: $logTransactionsExpanded,
                allowCollapse: true,
                showIndicator: true,
                onAdd: nil,
                valueLabel: nil,
                value: nil
            ) {
                Button("Expense History") {
                    showingExpenseHistory = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if logTransactionsExpanded {
                if logTransactionItems.isEmpty {
                GlassCard {
                    EmptyStateView(
                        title: "No transactions yet",
                        message: "Log income or expenses to see activity here.",
                        systemImage: "list.bullet.rectangle",
                        tips: [],
                        actionLabel: "Log Expense",
                        action: startAddExpense
                    )
                }
            } else {
                GlassCard(padding: 10) {
                    VStack(spacing: 8) {
                        ForEach(Array(logTransactionItems.prefix(20).enumerated()), id: \.element.id) { _, item in
                            HStack(spacing: 8) {
                                Image(systemName: item.iconName)
                                    .font(.subheadline)
                                    .foregroundStyle(item.tint)
                                    .frame(width: 24, height: 24)
                                    .background(item.tint.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline)
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(item.isInflow ? "+" : "-")\(item.amount, format: .currency(code: "USD"))")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(item.isInflow ? .green : .primary)
                                    Text(item.date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                switch item.kind {
                                case .expense(let expense):
                                    editingExpense = expense
                                case .income(let income):
                                    editingIncome = income
                                case .savings(let entry):
                                    editingSavingsEntry = entry
                                }
                            }
                            if item.id != logTransactionItems.prefix(20).last?.id {
                                Divider()
                            }
                        }
                    }
            }
        }
    }
}
}

    private var accountBalancesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleSectionHeader(
                title: "Account Balances",
                tint: .cyan,
                isExpanded: $accountBalancesExpanded,
                allowCollapse: true,
                showIndicator: true,
                onAdd: nil,
                valueLabel: nil,
                value: nil
            ) {
                Menu("Manage") {
                    Button("Transfer Cash") {
                        showingAddCashTransfer = true
                    }
                    Button("Banks") {
                        showingBankAccounts = true
                    }
                    Button("Cards") {
                        showingCreditAccounts = true
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if accountBalancesExpanded {
                let totalBank = budget.bankAccounts.reduce(0) { $0 + $1.balance }
            let portfolioNet = homePortfolioNetValue
            let totalCredit = budget.creditAccounts
                .filter(\.isActive)
                .reduce(0) { $0 + creditAccountActualBalance($1) }

            GlassCard {
                VStack(spacing: 10) {
                    metricRow("Bank Accounts", totalBank)
                    metricRow("Investments (Net)", portfolioNet)
                    metricRow("Credit Cards", -totalCredit)
                }
            }

            if !budget.bankAccounts.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bank Accounts")
                            .font(.headline)
                        ForEach(budget.bankAccounts) { account in
                            HStack {
                                Text(account.name)
                                Spacer()
                                Text(account.balance, format: .currency(code: "USD"))
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }

            if !budget.creditAccounts.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Credit Cards")
                            .font(.headline)
                        ForEach(budget.creditAccounts.filter(\.isActive)) { account in
                            HStack {
                                Text(account.name)
                                Spacer()
                                Text(creditAccountActualBalance(account), format: .currency(code: "USD"))
                                    .foregroundStyle(.red)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }

            if !budget.consolidatedHoldings.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Portfolio Holdings")
                            .font(.headline)
                        ForEach(budget.consolidatedHoldings.prefix(5)) { holding in
                            HStack {
                                Text(holding.ticker)
                                Spacer()
                                let price = budget.cachedQuotes[holding.ticker.uppercased()]?.price ?? holding.currentPrice
                            Text("\((holding.shares * price), format: .currency(code: "USD"))")
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
        }
    }

    @ViewBuilder
    private func recurringCalendarDayCell(for date: Date?, maxVisibleEvents: Int) -> some View {
        if let date {
            let events = filteredCalendarEvents(for: date)
            let visibleEvents = Array(events.prefix(maxVisibleEvents))
            let hiddenEventCount = max(events.count - visibleEvents.count, 0)
            let calendar = Calendar.current
            let isToday = calendar.isDateInToday(date)
            let isVisibleMonth = calendar.isDate(date, equalTo: visibleCalendarMonth, toGranularity: .month)

            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: calendarCellContentSpacing) {
                    ForEach(visibleEvents) { event in
                        calendarEventChip(event)
                    }

                    if hiddenEventCount > 0 {
                        calendarOverflowButton(date: date, hiddenEventCount: hiddenEventCount)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, calendarTransactionsTopInset)
                .padding(.horizontal, 2)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                HStack {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.title3.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isVisibleMonth ? Color.primary : Color.secondary.opacity(0.55))
                        .lineLimit(1)
                    Spacer()
                }
                .frame(height: calendarDayNumberHeight, alignment: .topLeading)
                .padding(.top, calendarCellTopInset)
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .background(
                Rectangle()
                    .fill(isToday ? appAccent.opacity(0.10) : Color(.secondarySystemGroupedBackground).opacity(isVisibleMonth ? 0.86 : 0.42))
                    .overlay(
                        Rectangle()
                            .stroke(isToday ? appAccent.opacity(0.40) : Color.primary.opacity(0.08), lineWidth: isToday ? 1.2 : 0.6)
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectedCalendarEventList = CalendarDaySelection(date: date)
            }
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Rectangle()
                        .fill(Color(.secondarySystemGroupedBackground).opacity(0.32))
                        .overlay(
                            Rectangle()
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.6)
                        )
                )
        }
    }

    private func calendarEventChip(_ event: CalendarEventItem) -> some View {
        Button {
            selectedCalendarEventList = CalendarDaySelection(date: event.date)
        } label: {
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.72))
                    .frame(width: 3, height: 14)
                Image(systemName: event.iconName)
                    .font(.system(size: 8, weight: .bold))
                Text(event.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .allowsTightening(true)
                Spacer(minLength: 0)
                if event.isPlaidSynced {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: calendarEventChipHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(calendarEventBackground(for: event))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendarMenuTitle(for: event))
    }

    private func calendarOverflowButton(date: Date, hiddenEventCount: Int) -> some View {
        Button {
            selectedCalendarEventList = CalendarDaySelection(date: date)
        } label: {
            Text("+\(hiddenEventCount)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hiddenEventCount) more calendar events")
    }

    private func calendarWeekRow(_ week: CalendarWeek, availableWidth: CGFloat) -> some View {
        let gridWidth = max(availableWidth, 1)
        let dayCellWidth = max(floor(gridWidth / 7), 1)
        let busiestDayEventCount = maxCalendarEventCount(in: week)
        let maxVisibleEvents = maxVisibleCalendarEvents(for: busiestDayEventCount)
        let dayCellHeight = dayCellHeight(availableWidth: gridWidth, visibleEventSlots: maxVisibleEvents, hasOverflow: busiestDayEventCount > maxVisibleEvents)

        return HStack(spacing: 0) {
            ForEach(week.days, id: \.self) { day in
                recurringCalendarDayCell(for: day, maxVisibleEvents: maxVisibleEvents)
                    .frame(width: dayCellWidth, height: dayCellHeight)
                    .clipped()
            }
        }
        .frame(width: gridWidth, height: dayCellHeight, alignment: .leading)
        .clipped()
    }

    private func openCalendarEvent(_ event: CalendarEventItem) {
        if let account = event.creditAccount {
            selectedCreditAccount = account
        } else if let portfolioTransaction = event.portfolioTransaction {
            selectedPortfolioTransaction = portfolioTransaction
        } else if let recurring = event.recurringPayment {
            editingRecurringPayment = recurring
        } else if let expense = event.expense {
            editingExpense = expense
        } else if let income = event.income {
            editingIncome = income
        } else if let transfer = event.cashTransfer {
            editingCashTransfer = transfer
        }
    }

    private func calendarMenuTitle(for event: CalendarEventItem) -> String {
        let amount = event.amount > 0 ? " \(calendarChipAmountText(for: event))" : ""
        return "\(event.name)\(amount)"
    }

    private func calendarChipAmountText(for event: CalendarEventItem) -> String {
        if event.isTransfer {
            return event.amount.formatted(.currency(code: "USD"))
        }
        return "\(event.isIncome ? "+" : "-")\(event.amount.formatted(.currency(code: "USD")))"
    }

    private func calendarEventBackground(for event: CalendarEventItem) -> Color {
        if event.isTransfer {
            return event.tint.opacity(0.68)
        }
        if event.isIncome {
            return Color.green.opacity(0.68)
        }
        if event.isCreditDue {
            return Color(red: 0.56, green: 0.28, blue: 0.17).opacity(0.88)
        }
        return event.tint.opacity(0.68)
    }

    private func maxCalendarEventCount(in week: CalendarWeek) -> Int {
        week.days
            .map { filteredCalendarEvents(for: $0).count }
            .max() ?? 0
    }

    private func maxVisibleCalendarEvents(for eventCount: Int) -> Int {
        min(max(eventCount, 1), 3)
    }

    private var calendarCellTopInset: CGFloat {
        10
    }

    private var calendarDayNumberHeight: CGFloat {
        30
    }

    private var calendarTransactionsTopInset: CGFloat {
        calendarCellTopInset + calendarDayNumberHeight + 4
    }

    private var calendarCellContentSpacing: CGFloat {
        4
    }

    private var calendarEventChipHeight: CGFloat {
        28
    }

    private var calendarOverflowMenuHeight: CGFloat {
        26
    }

    private func dayCellHeight(availableWidth: CGFloat, visibleEventSlots: Int, hasOverflow: Bool) -> CGFloat {
        let cellWidth = max(availableWidth / 7, 1)
        let baseHeight = max(floor(cellWidth * 1.18), calendarTransactionsTopInset + calendarEventChipHeight + 14)
        let eventSlots = max(visibleEventSlots, 1)
        let eventSpacing = CGFloat(max(eventSlots - 1, 0)) * calendarCellContentSpacing
        let overflowHeight = hasOverflow ? calendarCellContentSpacing + calendarOverflowMenuHeight : 0
        let contentHeight = calendarTransactionsTopInset
            + (CGFloat(eventSlots) * calendarEventChipHeight)
            + eventSpacing
            + overflowHeight
            + 10
        return max(baseHeight, contentHeight)
    }

    private static func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    private var firstTimeTipsSection: some View {
        GlassCard {
            EmptyStateView(
                title: "Start Your Plan",
                message: "Set your income, then add categories and goals for the month.",
                systemImage: "sparkles",
                tips: [
                    "Set allocations for needs, wants, and savings.",
                    "Log spending and keep categories updated."
                ],
                actionLabel: "Set Income",
                action: {
                    selectedTab = .budget
                    scrollToIncome = true
                }
            )
        }
    }

    private var nextStepSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Next Step")
                    .font(.headline)
                Text("Add your first category to start allocating your budget.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: { showingAddNeedsCategory = true }) {
                    Label("Add a Needs Category", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var planHighlightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleSectionHeader(
                title: "Plan Highlights",
                tint: .purple,
                isExpanded: $planHighlightsExpanded,
                onAdd: nil,
                valueLabel: budget.income > 0 ? "Budget" : nil,
                value: budget.income > 0 ? budget.monthlyIncome : nil
            )

            if planHighlightsExpanded {
                if budget.income > 0 {
                    HStack(spacing: 8) {
                        ForEach(planHighlightItems) { item in
                            Button {
                                selectedPlanHighlight = item.section
                            } label: {
                                PlanHighlightCard(
                                    title: item.title,
                                    systemImage: item.systemImage,
                                    tint: item.tint,
                                    amount: item.amount,
                                    allocated: item.allocated
                                )
                            }
                            .buttonStyle(PressableCardButtonStyle())
                            .frame(maxWidth: .infinity)
                            .layoutPriority(1)
                        }
                    }
                } else {
                    GlassCard(padding: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Unlock your plan targets")
                                    .font(.subheadline.weight(.semibold))
                                Text("Add income to see monthly goals for needs, wants, and savings.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
            }
        }
        }
        .sheet(item: $selectedPlanHighlight) { section in
            PlanHighlightMenuView(
                section: section,
                budget: budget,
                needsSpentByCategoryId: needsSpentByCategoryId,
                wantsSpentByCategoryId: wantsSpentByCategoryId,
                onAdd: {
                    switch section {
                    case .needs:
                        showingAddNeedsCategory = true
                    case .wants:
                        showingAddWantsCategory = true
                    case .savings:
                        showingAddSavingsGoal = true
                    }
                },
                onEditCategory: { category in
                    selectedPlanHighlight = nil
                    editingCategory = category
                },
                onDeleteCategory: { category, section in
                    withAnimation(.easeInOut) {
                        switch section {
                        case .needs:
                            budget.needsCategories.removeAll { $0.id == category.id }
                            budget.removeAllocation(for: category.id, section: .needs)
                            budget.removeExpenses(for: category.id)
                        case .wants:
                            budget.wantsCategories.removeAll { $0.id == category.id }
                            budget.removeAllocation(for: category.id, section: .wants)
                            budget.removeExpenses(for: category.id)
                        }
                    }
                    Haptics.warning()
                },
                onEditSavingsGoal: { goal in
                    selectedPlanHighlight = nil
                    editingSavingsGoal = goal
                },
                onDeleteSavingsGoal: { goal in
                    withAnimation(.easeInOut) {
                        budget.removeSavingsGoal(id: goal.id)
                    }
                    Haptics.warning()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Income Section
    private var incomeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleSectionHeader(
                title: "Income",
                tint: .green,
                isExpanded: $incomeExpanded,
                onAdd: nil,
                valueLabel: budget.income > 0 ? "Monthly" : nil,
                value: budget.income > 0 ? budget.monthlyIncome : nil
            )

            if incomeExpanded {
                GlassCard(padding: 10) {
                    VStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Amount")
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 10) {
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                                TextField("$0", value: $budget.income, format: .currency(code: "USD"))
                                    .keyboardType(.decimalPad)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .textFieldStyle(.plain)
                                    .focused($focusedField, equals: .income)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pay Frequency")
                                    .font(.subheadline.weight(.semibold))
                                Text("This controls your monthly roll-up.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("Pay Frequency", selection: $budget.payFrequency) {
                                ForEach(PayFrequency.allCases) { frequency in
                                    Text(frequency.rawValue).tag(frequency)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }

                        if budget.income > 0 {
                            Divider()
                            HStack {
                                Text("Monthly Income")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(budget.monthlyIncome, format: .currency(code: "USD"))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                    .scaleEffect(highlightMonthlyIncome ? 1.06 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: highlightMonthlyIncome)
                            }
                        }
                    }
                }
            }
        }
        .id("incomeSection")
        .onChange(of: budget.monthlyIncome) { _, _ in
            highlightMonthlyIncome = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                highlightMonthlyIncome = false
            }
        }
    }
    
    // MARK: - Budget Breakdown Section
    private var budgetBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleSectionHeader(
                title: "50/30/20 Budget Breakdown",
                tint: .purple,
                isExpanded: $budgetBreakdownExpanded,
                onAdd: nil,
                valueLabel: nil,
                value: nil
            )

            if budgetBreakdownExpanded {
                if budget.income > 0 {
                    GlassCard(padding: 10) {
                        VStack(spacing: 10) {
                        BudgetBarView(
                            title: "Needs (50%)",
                            allocated: budget.totalNeedsAllocated,
                            budget: budget.needsBudget,
                            color: .blue
                        )

                        BudgetBarView(
                            title: "Savings (30%)",
                            allocated: budget.totalSavingsAllocated,
                            budget: budget.savingsBudget,
                            color: .green
                        )

                        BudgetBarView(
                            title: "Wants (20%)",
                            allocated: budget.totalWantsAllocated,
                            budget: budget.wantsBudget,
                            color: .orange
                        )
                    }
                }
            } else {
                    GlassCard(padding: 10) {
                        Text("Enter your income to see budget breakdown")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - Log Trends Section
    private var logTrendsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleSectionHeader(
                title: "Trends",
                tint: .primary,
                isExpanded: $logTrendsExpanded,
                allowCollapse: true,
                showIndicator: false,
                onAdd: nil,
                valueLabel: selectedLogTrend == .income ? "Logged this month" : "Month to date",
                value: selectedLogTrend == .income ? totalMonthlyIncomeLogged : totalMonthlySpent
            )

            if logTrendsExpanded {
                Picker("Trend", selection: $selectedLogTrend) {
                    ForEach(LogTrend.allCases) { trend in
                        Text(trend.rawValue).tag(trend)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedTrendRange.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(trendTotal, format: .currency(code: "USD"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Avg / day")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(trendAveragePerDay, format: .currency(code: "USD"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }

                GlassCard {
                    HStack(spacing: 14) {
                        compactTrendMetric(title: "Entries", value: "\(trendEntriesInRange)")
                        compactTrendMetric(title: "Active Days", value: "\(trendActiveDaysInRange)")
                        compactTrendMetric(
                            title: selectedLogTrend == .income ? "Best Day" : "Peak Spend",
                            value: trendPeakDailyAmountInRange.formatted(.currency(code: "USD"))
                        )
                    }
                }

                Group {
                    if selectedLogTrend == .income {
                        incomeTrendContent
                    } else {
                        spendingTrendContent
                    }
                }

                trendRangeSelector
            }
        }
        .onChange(of: selectedTrendRange) { _, _ in
            selectedIncomePoint = nil
            selectedSpendingPoint = nil
        }
    }

    private var trendRangeSelector: some View {
        HStack(spacing: 8) {
            ForEach(TrendRange.allCases) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTrendRange = range
                    }
                } label: {
                    Text(range.title)
                        .font(.caption.weight(.bold))
                        .kerning(0.4)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selectedTrendRange == range ? .white : .primary)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedTrendRange == range ? appAccent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(appAccent.opacity(0.22), lineWidth: 1)
        )
    }

    private var homeNetWorthRangeSelector: some View {
        CuanSegmentedRange(values: HomeNetWorthRange.allCases, selection: $selectedHomeNetWorthRange) { range in
            Text(range.rawValue)
                .frame(maxWidth: .infinity)
        }
    }

    private func compactTrendMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var spendingTrendContent: some View {
        let points = trendSpendingPoints
        if points.isEmpty {
            GlassCard {
                EmptyStateView(
                    title: "No spending yet",
                    message: "Log expenses to see your monthly trend.",
                    systemImage: "chart.line.uptrend.xyaxis",
                    tips: [],
                    actionLabel: "Log Expense",
                    action: startAddExpense
                )
            }
        } else {
            GlassCard {
                Chart(points) { point in
                    AreaMark(
                        x: .value("Day", point.date),
                        y: .value("Spent", point.amount)
                    )
                    .foregroundStyle(.blue.opacity(0.2))

                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("Spent", point.amount)
                    )
                    .foregroundStyle(.blue)

                    if let selectedSpendingPoint {
                        RuleMark(x: .value("Day", selectedSpendingPoint.date))
                            .foregroundStyle(.blue.opacity(0.35))

                        PointMark(
                            x: .value("Day", selectedSpendingPoint.date),
                            y: .value("Spent", selectedSpendingPoint.amount)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount, format: .currency(code: "USD"))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 8)
                                        .onChanged { value in
                                            guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                                            if let plotFrameAnchor = proxy.plotFrame {
                                                let plotFrame = geometry[plotFrameAnchor]
                                                let xPosition = value.location.x - plotFrame.origin.x
                                                if let date: Date = proxy.value(atX: xPosition) {
                                                    selectedSpendingPoint = nearestPoint(in: points, to: date)
                                                }
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedSpendingPoint = nil
                                        }
                                )

                            if let selectedSpendingPoint,
                               let plotFrameAnchor = proxy.plotFrame {
                                let plotFrame = geometry[plotFrameAnchor]
                                let xPosition = proxy.position(forX: selectedSpendingPoint.date) ?? plotFrame.minX
                                let yPosition = proxy.position(forY: selectedSpendingPoint.amount) ?? plotFrame.minY
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedSpendingPoint.date, format: .dateTime.month().day())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(selectedSpendingPoint.amount, format: .currency(code: "USD"))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                                .padding(6)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .position(
                                    x: min(max(xPosition, plotFrame.minX + 70), plotFrame.maxX - 70),
                                    y: max(plotFrame.minY + 14, yPosition - 24)
                                )
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    @ViewBuilder
    private var incomeTrendContent: some View {
        let points = trendIncomePoints
        if points.isEmpty {
            GlassCard {
                EmptyStateView(
                    title: "No income yet",
                    message: "Log paychecks to see your monthly income.",
                    systemImage: "dollarsign.circle",
                    tips: [],
                    actionLabel: "Log Income",
                    action: startAddIncome
                )
            }
        } else {
            GlassCard {
                Chart(points) { point in
                    AreaMark(
                        x: .value("Day", point.date),
                        y: .value("Income", point.amount)
                    )
                    .foregroundStyle(.green.opacity(0.2))

                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("Income", point.amount)
                    )
                    .foregroundStyle(.green)

                    if let selectedIncomePoint {
                        RuleMark(x: .value("Day", selectedIncomePoint.date))
                            .foregroundStyle(.green.opacity(0.35))

                        PointMark(
                            x: .value("Day", selectedIncomePoint.date),
                            y: .value("Income", selectedIncomePoint.amount)
                        )
                        .foregroundStyle(.green)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount, format: .currency(code: "USD"))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 8)
                                        .onChanged { value in
                                            guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                                            if let plotFrameAnchor = proxy.plotFrame {
                                                let plotFrame = geometry[plotFrameAnchor]
                                                let xPosition = value.location.x - plotFrame.origin.x
                                                if let date: Date = proxy.value(atX: xPosition) {
                                                    selectedIncomePoint = nearestPoint(in: points, to: date)
                                                }
                                            }
                                        }
                                        .onEnded { _ in
                                            selectedIncomePoint = nil
                                        }
                                )

                            if let selectedIncomePoint,
                               let plotFrameAnchor = proxy.plotFrame {
                                let plotFrame = geometry[plotFrameAnchor]
                                let xPosition = proxy.position(forX: selectedIncomePoint.date) ?? plotFrame.minX
                                let yPosition = proxy.position(forY: selectedIncomePoint.amount) ?? plotFrame.minY
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedIncomePoint.date, format: .dateTime.month().day())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(selectedIncomePoint.amount, format: .currency(code: "USD"))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                                .padding(6)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .position(
                                    x: min(max(xPosition, plotFrame.minX + 70), plotFrame.maxX - 70),
                                    y: max(plotFrame.minY + 14, yPosition - 24)
                                )
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - Needs Section
    private var needsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let needsHeaderLabel = isLogFocus ? "Spent this month" : "Budget this month"
            let needsHeaderValue = isLogFocus ? monthlyNeedsSpent : budget.needsBudget
            collapsibleSectionHeader(
                title: "Needs",
                tint: .blue,
                isExpanded: $needsExpanded,
                onAdd: { showingAddNeedsCategory = true },
                valueLabel: needsHeaderLabel,
                value: needsHeaderValue
            )

            if isLogFocus, budget.income > 0 {
                HStack {
                    Text("Allocated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(budget.totalNeedsAllocated, format: .currency(code: "USD")) of \(budget.needsBudget, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if needsExpanded {
                if budget.needsCategories.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            title: "No needs yet",
                            message: "Add essentials like rent, utilities, and groceries.",
                            systemImage: "house",
                            tips: ["Tap + to add a category."],
                            actionLabel: "Add Needs Category",
                            action: { showingAddNeedsCategory = true }
                        )
                    }
                } else {
                    GlassCard(padding: 12) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(budget.needsCategories) { category in
                                CategoryRowView(
                                    category: category,
                                    showLogDetails: isLogFocus,
                                    onEdit: { editingCategory = category },
                                    onDelete: {
                                    withAnimation(.easeInOut) {
                                        budget.needsCategories.removeAll { $0.id == category.id }
                                        budget.removeAllocation(for: category.id, section: .needs)
                                        budget.removeExpenses(for: category.id)
                                    }
                                        Haptics.warning()
                                    },
                                    onAddExpense: isLogFocus ? {
                                        expenseDraftSection = .needs
                                        expenseDraftCategoryId = category.id
                                        expenseDraft = ExpenseDraft(section: expenseDraftSection, categoryId: expenseDraftCategoryId)
                                    } : nil,
                                    onTap: isLogFocus ? {
                                        categoryHistorySelection = CategoryHistorySelection(category: category)
                                    } : nil,
                                    spentAmount: needsSpentByCategoryId[category.id] ?? 0,
                                    pillLabel: "Spent",
                                    pillAmount: needsSpentByCategoryId[category.id] ?? 0
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Wants Section
    private var wantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let wantsHeaderLabel = isLogFocus ? "Spent this month" : "Budget this month"
            let wantsHeaderValue = isLogFocus ? monthlyWantsSpent : budget.wantsBudget
            collapsibleSectionHeader(
                title: "Wants",
                tint: .orange,
                isExpanded: $wantsExpanded,
                onAdd: { showingAddWantsCategory = true },
                valueLabel: wantsHeaderLabel,
                value: wantsHeaderValue
            )

            if isLogFocus, budget.income > 0 {
                HStack {
                    Text("Spent this month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(monthlyWantsSpent, format: .currency(code: "USD")) of \(budget.wantsBudget, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if wantsExpanded {
                if budget.wantsCategories.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            title: "No wants yet",
                            message: "Add fun categories to keep the 20% flexible.",
                            systemImage: "party.popper",
                            tips: ["Tap + to add a category."],
                            actionLabel: "Add Wants Category",
                            action: { showingAddWantsCategory = true }
                        )
                    }
                } else {
                    GlassCard(padding: 12) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(budget.wantsCategories) { category in
                                CategoryRowView(
                                    category: category,
                                    showLogDetails: isLogFocus,
                                    onEdit: { editingCategory = category },
                                    onDelete: {
                                    withAnimation(.easeInOut) {
                                        budget.wantsCategories.removeAll { $0.id == category.id }
                                        budget.removeAllocation(for: category.id, section: .wants)
                                        budget.removeExpenses(for: category.id)
                                    }
                                        Haptics.warning()
                                    },
                                    onAddExpense: isLogFocus ? {
                                        expenseDraftSection = .wants
                                        expenseDraftCategoryId = category.id
                                        expenseDraft = ExpenseDraft(section: expenseDraftSection, categoryId: expenseDraftCategoryId)
                                    } : nil,
                                    onTap: isLogFocus ? {
                                        categoryHistorySelection = CategoryHistorySelection(category: category)
                                    } : nil,
                                    showRemaining: !isLogFocus,
                                    spentAmount: wantsSpentByCategoryId[category.id] ?? 0,
                                    pillLabel: "Spent",
                                    pillAmount: wantsSpentByCategoryId[category.id] ?? 0
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Savings Section
    private var savingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            collapsibleSectionHeader(
                title: "Savings",
                tint: .green,
                isExpanded: $savingsExpanded,
                onAdd: { showingAddSavingsGoal = true },
                valueLabel: "Save this month",
                value: budget.savingsBudget
            )

            if isLogFocus, budget.income > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved this month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(autoSavedThisMonth, format: .currency(code: "USD")) of \(budget.savingsBudget, format: .currency(code: "USD"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !monthlySavingsEntries.isEmpty {
                        Button("History") {
                            showingSavingsHistory = true
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
            
            if savingsExpanded {
                if budget.savingsGoals.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            title: "No savings goals yet",
                            message: "Add a goal to track your progress.",
                            systemImage: "banknote",
                            tips: [],
                            actionLabel: "Add Savings Goal",
                            action: { showingAddSavingsGoal = true }
                        )
                    }
                } else {
                    GlassCard(padding: 12) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(budget.savingsGoals) { goal in
                                SavingsGoalRowView(
                                    goal: goal,
                                    onEdit: { editingSavingsGoal = goal },
                                    onDelete: {
                                        withAnimation(.easeInOut) {
                                            budget.removeSavingsGoal(id: goal.id)
                                        }
                                        Haptics.warning()
                                    },
                                    onHistory: isLogFocus ? {
                                        savingsHistorySelection = SavingsHistorySelection(goal: goal)
                                    } : nil,
                                    onLog: isLogFocus ? {
                                        savingsEntryDraft = SavingsEntryDraft(goalId: goal.id)
                                    } : nil,
                                    savedThisMonth: isLogFocus ? (savingsLoggedByGoalId[goal.id] ?? 0) : nil,
                                    showCurrentField: !isLogFocus,
                                    onCurrentChange: { amount in
                                        if let index = budget.savingsGoals.firstIndex(where: { $0.id == goal.id }) {
                                            budget.savingsGoals[index].currentAmount = max(amount, 0)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Summary Section
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            collapsibleSectionHeader(
                title: "Summary",
                tint: .primary,
                isExpanded: $summaryExpanded,
                onAdd: nil,
                valueLabel: nil,
                value: nil
            )
            
            if summaryExpanded {
                GlassCard {
                    VStack(spacing: 16) {
                        if budget.income > 0 {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                SummaryMetricCard(
                                    title: "Needs",
                                    amount: monthlyNeedsSpent,
                                    budget: budget.totalNeedsAllocated,
                                    color: .blue
                                )

                                SummaryMetricCard(
                                    title: "Wants",
                                    amount: monthlyWantsSpent,
                                    budget: budget.totalWantsAllocated,
                                    color: .orange
                                )

                                SummaryMetricCard(
                                    title: isLogFocus ? "Saved" : "Savings Planned",
                                    amount: isLogFocus ? autoSavedThisMonth : budget.totalSavingsAllocated,
                                    budget: budget.savingsBudget,
                                    color: .green
                                )
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Remaining Budget")
                                        .font(.headline)
                                    Text("After planned allocations")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(remainingBudgetForMonth, format: .currency(code: "USD"))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(remainingBudgetForMonth >= 0 ? .green : .red)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        (remainingBudgetForMonth >= 0 ? Color.green : Color.red).opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                        } else {
                            Text("Enter your income to see summary")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var categorySummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            collapsibleSectionHeader(
                title: "Category Summary",
                tint: .primary,
                isExpanded: $categorySummaryExpanded,
                onAdd: nil,
                valueLabel: nil,
                value: nil
            )

            if categorySummaryExpanded {
                if categorySummaryItems.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            title: "No category spend yet",
                            message: "Log expenses to see top categories.",
                            systemImage: "list.bullet.rectangle",
                            tips: [],
                            actionLabel: "Log Expense",
                            action: startAddExpense
                        )
                    }
                } else {
                    GlassCard {
                        VStack(spacing: 10) {
                            ForEach(categorySummaryItems) { item in
                                HStack {
                                    Circle()
                                        .fill(item.tint)
                                        .frame(width: 8, height: 8)
                                    Text(item.name)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(item.spent, format: .currency(code: "USD"))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, tint: Color, onAdd: @escaping () -> Void) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            Spacer()
            Button(action: onAdd) {
                Label("Add", systemImage: "plus.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(tint)
            }
            .accessibilityLabel("Add \(title)")
        }
    }

    private func collapsibleSectionHeader(
        title: String,
        tint: Color,
        isExpanded: Binding<Bool>,
        allowCollapse: Bool = true,
        showIndicator: Bool = true,
        onAdd: (() -> Void)?,
        valueLabel: String?,
        value: Double?
    ) -> some View {
        collapsibleSectionHeader(
            title: title,
            tint: tint,
            isExpanded: isExpanded,
            allowCollapse: allowCollapse,
            showIndicator: showIndicator,
            onAdd: onAdd,
            valueLabel: valueLabel,
            value: value
        ) {
            EmptyView()
        }
    }

    private func collapsibleSectionHeader<Trailing: View>(
        title: String,
        tint: Color,
        isExpanded: Binding<Bool>,
        allowCollapse: Bool,
        showIndicator: Bool,
        onAdd: (() -> Void)?,
        valueLabel: String?,
        value: Double?,
        @ViewBuilder trailingContent: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Group {
                if allowCollapse {
                    Button(action: {
                        withAnimation(.easeInOut) {
                            isExpanded.wrappedValue.toggle()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                                .foregroundStyle(.secondary)
                            if showIndicator {
                                Circle()
                                    .fill(tint)
                                    .frame(width: 8, height: 8)
                            }
                            Text(title)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 8) {
                        if showIndicator {
                            Circle()
                                .fill(tint)
                                .frame(width: 8, height: 8)
                        }
                        Text(title)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }
            }

            trailingContent()

            Spacer()

            if let valueLabel, let value {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(valueLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(value, format: .currency(code: "USD"))
                        .font(.headline)
                }
            }

            if let onAdd {
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(tint)
                }
                .accessibilityLabel("Add \(title)")
            }
        }
    }

    private func pageHeader<Trailing: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CuanTheme.primary)
                    .frame(width: 34, height: 34)
                    .background(Color.white, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(CuanTheme.text)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(CuanTheme.muted)
                }
            }
            Spacer()
            trailing()
        }
    }

    private var budgetHubSnapshotSection: some View {
        let charges = continuousChargeSummary
        return GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Budget Snapshot", systemImage: "chart.pie.fill")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(selectedMonth, format: .dateTime.month(.wide).year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(remainingBudgetForMonth, format: .currency(code: "USD"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(remainingBudgetForMonth >= 0 ? .green : .red)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.blue.opacity(0.75))
                                .frame(width: geometry.size.width * budgetSegmentWidth(budget.needsBudget))
                            Rectangle()
                                .fill(Color.green.opacity(0.75))
                                .frame(width: geometry.size.width * budgetSegmentWidth(budget.savingsBudget))
                            Rectangle()
                                .fill(Color.orange.opacity(0.78))
                                .frame(width: geometry.size.width * budgetSegmentWidth(budget.wantsBudget))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .frame(height: 8)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    insightMetricTile(title: "Spent", value: totalMonthlySpent, subtitle: "month to date", tint: .red, systemImage: "arrow.down.forward")
                    insightMetricTile(title: "Income", value: totalMonthlyIncomeLogged, subtitle: "logged", tint: .green, systemImage: "arrow.up.forward")
                    insightMetricTile(title: "Charges", value: charges.totalDue, subtitle: "continuous", tint: .pink, systemImage: "repeat.circle.fill")
                    insightMetricTile(title: "Unpaid", value: charges.totalUnpaid, subtitle: "\(charges.unpaidCount) open", tint: .orange, systemImage: "exclamationmark.circle.fill")
                }
            }
        }
    }

    private var recurringChargesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleSectionHeader(
                title: "Recurring Charges",
                tint: .pink,
                isExpanded: $recurringChargesExpanded,
                onAdd: nil,
                valueLabel: "Total",
                value: continuousChargeSummary.totalDue
            )

            if recurringChargesExpanded {
                RecurringChargesCard(summary: continuousChargeSummary)
            }
        }
    }

    private var homeInsightSummarySection: some View {
        let charges = continuousChargeSummary
        return VStack(spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Total Net Worth", systemImage: "wallet.pass.fill")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Portfolio, banks, and credit cards")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: homeTotalNetWorth >= 0 ? "chevron.up" : "chevron.down")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(homeTotalNetWorth >= 0 ? .green : .red)
                    }

                    Text(homeTotalNetWorth, format: .currency(code: "USD"))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(homeTotalNetWorth >= 0 ? .green : .red)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    Text("Portfolio \(homePortfolioNetValue, format: .currency(code: "USD"))  Cash flow \(homeCashFlowNet, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                insightMetricTile(title: "Runway", valueText: runwayText, subtitle: "based on current spending", tint: .primary, systemImage: "timer")
                insightMetricTile(title: "Savings Rate", value: autoSavedThisMonth, subtitle: "this month", tint: .green, systemImage: "checkmark.circle.fill")
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Income vs Expenses", systemImage: "arrow.left.arrow.right")
                            .font(.headline)
                        Spacer()
                        Text("\(homeIncomeExpenseRatio, specifier: "%.1f"):1")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.yellow.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(Color.yellow.opacity(0.55), lineWidth: 1))
                    }

                    incomeExpenseRow(title: "Income", amount: totalMonthlyIncomeLogged, tint: .green, systemImage: "arrow.up.forward")
                    incomeExpenseRow(title: "Expenses", amount: totalMonthlySpent, tint: .pink, systemImage: "arrow.down.forward")
                    Divider()
                    incomeExpenseRow(title: "Net", amount: homeCashFlowNet, tint: .purple, systemImage: "checkmark.circle.fill")
                }
            }

            if charges.occurrenceCount > 0 {
                recurringChargesSection
            }
        }
    }

    private var homeRollupSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Everything at a Glance")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    homeMetricTile("Monthly Income", value: budget.monthlyIncome, tint: .blue)
                    homeMetricTile("Spent MTD", value: totalMonthlySpent, tint: .red)
                    homeMetricTile("Saved MTD", value: autoSavedThisMonth, tint: .green)
                    homeMetricTile("Remaining Budget", value: remainingBudgetForMonth, tint: .orange)
                    homeMetricTile("Portfolio Net", value: homePortfolioNetValue, tint: .mint)
                    homeMetricTile("Margin Used", value: budget.portfolioSnapshot.marginUsed, tint: .purple)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Savings Goal Progress (MTD)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(homeMonthlySavingsTargetProgress * 100))%")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    ProgressView(value: homeMonthlySavingsTargetProgress)
                        .tint(.green)
                }
            }
        }
    }

    private var homeMarketSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Top Assets")
                        .font(.headline)
                    Spacer()
                    if isLoadingHomeMarkets {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Refresh") {
                            Task { await refreshHomeMarkets() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if let homeMarketError {
                    Text(homeMarketError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if homeMarketCards.isEmpty {
                    Text("Add a Finnhub API key in Settings to load market cards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(homeMarketCards) { card in
                            homeMarketCardView(card)
                        }
                    }
                }
            }
        }
    }

    private var homeCashFlowSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cash Flow")
                    .font(.headline)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Spending")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(totalMonthlySpent, format: .currency(code: "USD"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        homeMiniTrendChart(points: dailySpending, color: .red)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Income")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(totalMonthlyIncomeLogged, format: .currency(code: "USD"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        homeMiniTrendChart(points: dailyIncome, color: .green)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var homeWatchlistSection: some View {
        CuanCard {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                searchButtonRow
                errorRow
                if budget.watchlistTickers.isEmpty {
                    Text("Add a ticker to start tracking it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    watchlistGridFilterSortControls
                    if homeWatchlistRows.isEmpty && !isLoadingHomeWatchlist {
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !homeWatchlistRows.isEmpty {
                        watchlistGridContent
                        watchlistGridSummary
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Text("Watchlist")
                .font(.headline)
                .foregroundStyle(CuanTheme.text)
            Spacer()
            if isLoadingHomeWatchlist {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await refreshHomeWatchlist() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CuanTheme.primary)
                .frame(width: 30, height: 30)
                .background(CuanTheme.background, in: Circle())
                .accessibilityLabel("Refresh watchlist")
            }
        }
    }

    private var searchButtonRow: some View {
        Button {
            showingWatchlistSearch = true
        } label: {
            Label("Search stocks", systemImage: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(CuanTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(CuanTheme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var errorRow: some View {
        Group {
            if let homeWatchlistError {
                Text(homeWatchlistError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var watchlistGridContent: some View {
        VStack(spacing: 10) {
            ForEach(displayWatchlistRows) { row in
                watchlistGridRow(row)
            }
        }
    }

    private var watchlistGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 50), spacing: 4),
            GridItem(.fixed(78), spacing: 4, alignment: .trailing),
            GridItem(.fixed(72), spacing: 4, alignment: .trailing),
            GridItem(.fixed(66), spacing: 0, alignment: .trailing),
        ]
    }

    private var displayWatchlistRows: [HomeWatchlistRow] {
        let filtered: [HomeWatchlistRow]
        switch watchlistFilter {
        case .all:
            filtered = homeWatchlistRows
        case .gainers:
            filtered = homeWatchlistRows.filter { $0.percentChange > 0 }
        case .losers:
            filtered = homeWatchlistRows.filter { $0.percentChange < 0 }
        }
        return filtered.sorted { a, b in
            switch watchlistSortOption {
            case .ticker:
                return watchlistSortAscending ? a.symbol < b.symbol : a.symbol > b.symbol
            case .price:
                return watchlistSortAscending ? a.price < b.price : a.price > b.price
            case .changePercent:
                return watchlistSortAscending ? a.percentChange < b.percentChange : a.percentChange > b.percentChange
            case .changeDollar:
                return watchlistSortAscending ? a.change < b.change : a.change > b.change
            }
        }
    }

    private var watchlistGridFilterSortControls: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Filter", selection: $watchlistFilter) {
                    ForEach(WatchlistFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
            } label: {
                Label(watchlistFilter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(CuanTheme.primary.opacity(0.86))

            Menu {
                Picker("Sort", selection: $watchlistSortOption) {
                    ForEach(WatchlistSortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Label(watchlistSortOption.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(CuanTheme.primary)

            Button {
                watchlistSortAscending.toggle()
            } label: {
                Image(systemName: watchlistSortAscending ? "arrow.up" : "arrow.down")
                    .font(.caption.weight(.bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
            .tint(CuanTheme.primary)
            .accessibilityLabel(watchlistSortAscending ? "Sort ascending" : "Sort descending")

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func watchlistGridRow(_ row: HomeWatchlistRow) -> some View {
        Button {
            selectedHomeWatchlistTicker = TickerSelection(ticker: row.symbol)
        } label: {
            let change = CuanMarketChangeDisplay(change: row.change, percentChange: row.percentChange)
            let tint = CuanTheme.changeColor(for: change.direction)

            HStack(spacing: 11) {
                CuanTickerAvatar(symbol: row.symbol, tint: tint)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(row.symbol)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(CuanTheme.text)
                            .lineLimit(1)
                        if change.direction != .flat {
                            Image(systemName: change.direction == .gain ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(tint)
                        }
                    }
                    if let name = row.companyName, !name.isEmpty {
                        Text(name)
                            .font(.caption2)
                            .foregroundStyle(CuanTheme.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CuanSparkline(values: row.priceHistory.map(\.close), tint: tint)
                    .frame(width: 58)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(row.price, format: .currency(code: "USD").precision(.fractionLength(2)))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(CuanTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(change.percentChangeText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
            .padding(10)
            .background(CuanTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var watchlistGridSummary: some View {
        let winners = displayWatchlistRows.filter { $0.percentChange > 0 }.count
        let losers = displayWatchlistRows.filter { $0.percentChange < 0 }.count
        let averageChange = displayWatchlistRows.isEmpty ? 0 : displayWatchlistRows.reduce(0) { $0 + $1.percentChange } / Double(displayWatchlistRows.count)
        return HStack(spacing: 10) {
            Label("\(winners) ▲", systemImage: "arrow.up")
                .font(.caption)
                .foregroundStyle(.green)
            Label("\(losers) ▼", systemImage: "arrow.down")
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
            Text("Avg \(averageChange / 100, format: .percent.precision(.fractionLength(2)))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(averageChange >= 0 ? .green : .red)
        }
        .padding(.top, 6)
    }

    private var homeNetWorthChartSection: some View {
        CuanCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.headline)
                        .foregroundStyle(CuanTheme.primary)
                        .frame(width: 38, height: 38)
                        .background(CuanTheme.primary.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Total Portfolio")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CuanTheme.muted)
                        Text(homePortfolioNetValue, format: .currency(code: "USD"))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(CuanTheme.text)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(homeNetWorthDeltaPercent, format: .percent.precision(.fractionLength(1)))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(homeNetWorthDelta >= 0 ? CuanTheme.gain : CuanTheme.loss)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((homeNetWorthDelta >= 0 ? CuanTheme.gain : CuanTheme.loss).opacity(0.12), in: Capsule())
                        if let homeLatestHoldingsUpdate {
                            Text("Updated \(homeLatestHoldingsUpdate, format: .dateTime.month().day().year().hour().minute())")
                                .font(.caption2)
                                .foregroundStyle(CuanTheme.muted)
                        } else {
                            Text("Updated: --")
                                .font(.caption2)
                                .foregroundStyle(CuanTheme.muted)
                        }
                    }
                }

                let points = homeNetWorthHistoryPoints
                if points.count < 2 {
                    Text("Add more portfolio activity over time to see your trend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(points) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Net Worth", point.netValue)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [CuanTheme.gain.opacity(0.28), CuanTheme.gain.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Net Worth", point.netValue)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(CuanTheme.gain)
                        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                        if let selectedHomeNetWorthPoint {
                            RuleMark(x: .value("Date", selectedHomeNetWorthPoint.date))
                                .foregroundStyle(.secondary.opacity(0.35))
                            PointMark(
                                x: .value("Date", selectedHomeNetWorthPoint.date),
                                y: .value("Net Worth", selectedHomeNetWorthPoint.netValue)
                            )
                            .foregroundStyle(CuanTheme.gain)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount, format: .currency(code: "USD"))
                                }
                            }
                            .foregroundStyle(.secondary)
                            .font(.caption2)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.08))
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    switch selectedHomeNetWorthRange {
                                    case .oneDay:
                                        Text(date, format: .dateTime.hour().minute())
                                    case .oneWeek, .oneMonth:
                                        Text(date, format: .dateTime.month(.abbreviated).day())
                                    case .threeMonths, .oneYear:
                                        Text(date, format: .dateTime.month(.abbreviated))
                                    case .all:
                                        Text(date, format: .dateTime.month(.abbreviated).year(.twoDigits))
                                    }
                                }
                            }
                            .font(.caption2)
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            ZStack(alignment: .topLeading) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .simultaneousGesture(
                                        DragGesture(minimumDistance: 8)
                                            .onChanged { value in
                                                guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                                                guard let plotFrame = proxy.plotFrame.map({ geometry[$0] }) else { return }
                                                let xPosition = value.location.x - plotFrame.origin.x
                                                if let date: Date = proxy.value(atX: xPosition) {
                                                    selectedHomeNetWorthPoint = nearestHomeHistoryPoint(to: date, in: points)
                                                }
                                            }
                                            .onEnded { _ in
                                                selectedHomeNetWorthPoint = nil
                                            }
                                    )

                                if let selectedHomeNetWorthPoint,
                                   let plotFrame = proxy.plotFrame.map({ geometry[$0] }) {
                                    let xPosition = proxy.position(forX: selectedHomeNetWorthPoint.date) ?? plotFrame.minX
                                    let yPosition = proxy.position(forY: selectedHomeNetWorthPoint.netValue) ?? plotFrame.minY
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selectedHomeNetWorthPoint.date, format: .dateTime.month().day().year())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("Net \(selectedHomeNetWorthPoint.netValue, format: .currency(code: "USD"))")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Text("Gross \(selectedHomeNetWorthPoint.grossValue, format: .currency(code: "USD"))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(6)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .position(
                                        x: min(max(xPosition, plotFrame.minX + 90), plotFrame.maxX - 90),
                                        y: max(plotFrame.minY + 20, yPosition - 28)
                                    )
                                }
                            }
                        }
                    }
                    .frame(height: 240)

                    homeNetWorthRangeSelector

                    HStack(spacing: 14) {
                        Label("Net Worth", systemImage: "line.diagonal")
                            .foregroundStyle(CuanTheme.gain)
                        Text("\(homeNetWorthDelta >= 0 ? "+" : "")\(homeNetWorthDelta, format: .currency(code: "USD")) in range")
                            .foregroundStyle(CuanTheme.muted)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func nearestHomeHistoryPoint(to date: Date, in points: [PortfolioValuePoint]) -> PortfolioValuePoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func startHoldingsAutoRefreshLoop() {
        guard holdingsAutoRefreshTask == nil else { return }
        holdingsAutoRefreshTask = Task {
            await refreshHoldingsQuotes()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                if Task.isCancelled { break }
                await refreshHoldingsQuotes()
            }
        }
    }

    private func stopHoldingsAutoRefreshLoop() {
        holdingsAutoRefreshTask?.cancel()
        holdingsAutoRefreshTask = nil
    }

    private func startWatchlistAlertLoop() {
        guard watchlistAlertTask == nil else { return }
        watchlistAlertTask = Task {
            await refreshHomeWatchlist()
            await checkWatchlistAlerts()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                if Task.isCancelled { break }
                await refreshHomeWatchlist()
                await checkWatchlistAlerts()
            }
        }
    }

    private func stopWatchlistAlertLoop() {
        watchlistAlertTask?.cancel()
        watchlistAlertTask = nil
    }

    @MainActor
    private func checkWatchlistAlerts() async {
        guard budget.marketDataSettings.canFetchMarketData else { return }
        await BudgetNotificationService.shared.sendWatchlistAlertsIfNeeded(
            budget: budget,
            marketDataService: marketDataService
        )
    }

    private func scheduleBudgetNotifications() {
        Task {
            await BudgetNotificationService.shared.rescheduleNotifications(for: budget)
        }
    }

    private func consumePendingDeepLink() {
        guard let action = PendingDeepLink.action else { return }
        PendingDeepLink.action = nil
        switch action {
        case .ticker(let symbol):
            selectedHomeWatchlistTicker = TickerSelection(ticker: symbol)
        case .tab(let mode):
            selectedTab = mode
        case .addIncome:
            showingAddIncome = true
        case .addExpense:
            expenseDraftSection = lastExpenseSection
            expenseDraftCategoryId = lastExpenseCategoryId ?? budget.needsCategories.first?.id ?? budget.wantsCategories.first?.id
            expenseDraft = ExpenseDraft(section: expenseDraftSection, categoryId: expenseDraftCategoryId)
        }
    }

    @MainActor
    private func refreshHoldingsQuotes() async {
        guard !isRefreshingHoldingsQuotes else { return }
        guard budget.marketDataSettings.canFetchMarketData else { return }
        let tickers = Array(Set(budget.holdings.map { $0.ticker.uppercased() })).filter { !$0.isEmpty }
        guard !tickers.isEmpty else { return }

        isRefreshingHoldingsQuotes = true
        let previousNW = BudgetNotificationService.netWorth(for: budget)
        defer { isRefreshingHoldingsQuotes = false }

        let isAlphaVantage = budget.marketDataSettings.provider == .alphaVantage
        let isFinnhub = budget.marketDataSettings.provider == .finnhub
        for (index, ticker) in tickers.enumerated() {
            do {
                if isAlphaVantage && index > 0 {
                    try? await Task.sleep(nanoseconds: 26_000_000_000)
                }
                if isFinnhub && index > 0 {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
                let details = try await marketDataService.fetchQuoteDetails(
                    ticker: ticker,
                    settings: budget.marketDataSettings
                )
                budget.cachedQuotes[ticker] = CachedQuote(ticker: ticker, price: details.price, updatedAt: Date())
                for holdingIndex in budget.holdings.indices where budget.holdings[holdingIndex].ticker.uppercased() == ticker {
                    budget.holdings[holdingIndex].currentPrice = details.price
                    if let annualDividend = details.annualDividendPerShare, annualDividend >= 0 {
                        budget.holdings[holdingIndex].annualDividendPerShare = annualDividend
                    }
                }
            } catch {
                continue
            }
        }

        let currentNW = BudgetNotificationService.netWorth(for: budget)
        await BudgetNotificationService.shared.sendPortfolioUpdateIfNeeded(
            previousNetWorth: previousNW,
            updatedNetWorth: currentNW,
            budget: budget
        )
    }

    private func homeMetricTile(_ title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: "USD"))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var runwayText: String {
        guard totalMonthlySpent > 0 else { return "--" }
        let liquid = budget.bankAccounts.reduce(0) { $0 + $1.balance }
        let months = max(liquid / totalMonthlySpent, 0)
        if months >= 12 {
            return "\(Int(months / 12))y \(Int(months.truncatingRemainder(dividingBy: 12)))m"
        }
        return "\(Int(months.rounded(.down)))m"
    }

    private func budgetSegmentWidth(_ amount: Double) -> Double {
        let total = max(budget.needsBudget + budget.savingsBudget + budget.wantsBudget, 0)
        guard total > 0 else { return 0 }
        return min(max(amount / total, 0), 1)
    }

    private func insightMetricTile(title: String, value: Double, subtitle: String, tint: Color, systemImage: String) -> some View {
        insightMetricTile(
            title: title,
            valueText: value.formatted(.currency(code: "USD").precision(.fractionLength(0))),
            subtitle: subtitle,
            tint: tint,
            systemImage: systemImage
        )
    }

    private func insightMetricTile(title: String, valueText: String, subtitle: String, tint: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12), in: Circle())
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(valueText)
                .font(.title2.weight(.bold))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }

    private func incomeExpenseRow(title: String, amount: Double, tint: Color, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.headline)
            Spacer()
            Text(amount, format: .currency(code: "USD"))
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }

    private func recurringChargeRow(_ charge: TopRecurringCharge) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "creditcard.fill")
                .font(.subheadline)
                .foregroundStyle(charge.tint)
                .frame(width: 34, height: 34)
                .background(charge.tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(charge.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(charge.paid)/\(charge.occurrences) paid")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(charge.amount, format: .currency(code: "USD"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.pink)
        }
    }

    private func homeMarketCardView(_ card: HomeMarketCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(card.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if card.isUnavailable {
                        Text("N/A")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(card.percentChange / 100, format: .percent.precision(.fractionLength(2)))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(card.percentChange >= 0 ? .green : .red)
                        Text(card.change, format: .currency(code: "USD"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if card.isUnavailable {
                Text("Unavailable")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 58)
                    .overlay(
                        Text("No data")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    )
            } else {
                Text(card.price, format: .currency(code: "USD"))
                    .font(.headline)

                Chart(Array(card.sparkline.enumerated()), id: \.offset) { item in
                    let index = item.offset
                    let value = item.element
                    LineMark(
                        x: .value("Index", index),
                        y: .value("Price", value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(card.percentChange >= 0 ? .green : .red)
                    AreaMark(
                        x: .value("Index", index),
                        y: .value("Price", value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle((card.percentChange >= 0 ? Color.green : Color.red).opacity(0.18))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 58)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func homeMiniTrendChart(points: [DailySpend], color: Color) -> some View {
        let recent = Array(points.suffix(14))
        return Group {
            if recent.count < 2 {
                Text("Not enough data yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Chart(recent) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.amount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color.opacity(0.14))

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", point.amount)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel(format: Date.FormatStyle().month(.twoDigits).day(.twoDigits))
                    }
                }
                .frame(height: 90)
            }
        }
    }

    private func metricRow(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value, format: .currency(code: "USD"))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }

    @MainActor
    private func refreshHomeMarkets() async {
        guard budget.marketDataSettings.canFetchMarketData else {
            homeMarketCards = []
            homeMarketError = "Missing market data credentials in Settings."
            return
        }

        let symbols = ["SPY", "QQQ", "DIA", "VIX"]
        let titles: [String: String] = ["SPY": "S&P 500", "QQQ": "NASDAQ 100", "DIA": "Dow Jones", "VIX": "VIX"]
        let subtitles: [String: String] = ["SPY": "ETF", "QQQ": "ETF", "DIA": "ETF", "VIX": "Index"]

        isLoadingHomeMarkets = true
        defer { isLoadingHomeMarkets = false }

        var cards: [HomeMarketCard] = []
        for symbol in symbols {
            let quote = try? await marketDataService.fetchQuoteSnapshot(
                ticker: symbol,
                settings: budget.marketDataSettings
            )
            var latestPrice = quote?.price
            if latestPrice == nil {
                latestPrice = try? await marketDataService.fetchPrice(
                    ticker: symbol,
                    settings: budget.marketDataSettings
                )
            }
            if latestPrice == nil {
                latestPrice = try? await marketDataService.fetchHistoricalClose(
                    ticker: symbol,
                    onOrBefore: Date(),
                    settings: budget.marketDataSettings
                )
            }

            guard let finalPrice = latestPrice, finalPrice > 0 else {
                cards.append(
                    HomeMarketCard(
                        title: titles[symbol] ?? symbol,
                        subtitle: "\(subtitles[symbol] ?? "") • Unavailable",
                        price: 0,
                        change: 0,
                        percentChange: 0,
                        sparkline: [0, 0],
                        isUnavailable: true
                    )
                )
                continue
            }

            var sparkline = try? await marketDataService.fetchRecentCloses(
                ticker: symbol,
                settings: budget.marketDataSettings,
                days: 14
            )
            if sparkline == nil {
                sparkline = await fetchHistoricalFallbackSeries(
                    ticker: symbol,
                    settings: budget.marketDataSettings,
                    targetPoints: 14,
                    anchorPrice: finalPrice
                )
            }

            cards.append(
                HomeMarketCard(
                    title: titles[symbol] ?? symbol,
                    subtitle: subtitles[symbol] ?? "",
                    price: finalPrice,
                    change: quote?.change ?? 0,
                    percentChange: quote?.percentChange ?? 0,
                    sparkline: sparkline ?? [finalPrice, finalPrice],
                    isUnavailable: false
                )
            )
        }

        if cards.isEmpty {
            homeMarketCards = []
            homeMarketError = "No market cards loaded. Check API key/provider or try again."
            return
        }

        homeMarketCards = cards
        homeMarketError = nil
    }

    private func fetchHistoricalFallbackSeries(
        ticker: String,
        settings: MarketDataSettings,
        targetPoints: Int,
        anchorPrice: Double
    ) async -> [Double] {
        var values: [Double] = []
        let calendar = Calendar.current
        let today = Date()

        for dayOffset in 0..<28 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            if let close = try? await marketDataService.fetchHistoricalClose(
                ticker: ticker,
                onOrBefore: date,
                settings: settings
            ), close > 0 {
                if values.last != close {
                    values.append(close)
                }
            }
            if values.count >= targetPoints { break }
        }

        let ordered = Array(values.reversed())
        if ordered.count >= 2 {
            return ordered
        }
        return [anchorPrice, anchorPrice]
    }

    @MainActor
    private func refreshHomeDashboard() async {
        await refreshHoldingsQuotes()
        await refreshHomeMarkets()
        await refreshHomeWatchlist()
    }

    @MainActor
    private func refreshHomeWatchlist() async {
        let apiKey = budget.marketDataSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard budget.marketDataSettings.canFetchMarketData else {
            homeWatchlistRows = []
            homeWatchlistError = "Missing market data credentials in Settings."
            return
        }

        let symbols = budget.watchlistTickers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        guard !symbols.isEmpty else {
            homeWatchlistRows = []
            homeWatchlistError = "No watchlist tickers set. Add symbols in Settings."
            return
        }

        isLoadingHomeWatchlist = true
        defer { isLoadingHomeWatchlist = false }

        var rows: [HomeWatchlistRow] = []
        var failedSymbols: [String] = []
        var lastError: Error?

        for symbol in symbols {
            do {
                let quote = try await marketDataService.fetchQuoteSnapshot(
                    ticker: symbol,
                    settings: budget.marketDataSettings
                )
                budget.cachedQuotes[symbol.uppercased()] = CachedQuote(
                    ticker: symbol.uppercased(),
                    price: quote.price,
                    updatedAt: Date()
                )
                let profile = apiKey.isEmpty ? nil : try? await marketDataService.fetchCompanyProfile(
                    ticker: symbol,
                    provider: .finnhub,
                    apiKey: apiKey
                )
                let historicalHistory = (try? await marketDataService.fetchCompositeRecentPriceHistory(
                    ticker: symbol,
                    settings: budget.marketDataSettings,
                    days: 90
                )) ?? TickerPricePoint.estimated(from: [quote.price, quote.price])
                let indicatorCloses = TickerPricePoint.closesForIndicators(history: historicalHistory, currentPrice: quote.price)
                let macd = TickerIndicators.macd(indicatorCloses)
                rows.append(
                    HomeWatchlistRow(
                        symbol: symbol,
                        companyName: profile?.name,
                        exchange: profile?.exchange,
                        price: quote.price,
                        change: quote.change,
                        percentChange: quote.percentChange,
                        open: quote.open,
                        dayHigh: quote.high,
                        dayLow: quote.low,
                        previousClose: quote.previousClose,
                        sma20: TickerIndicators.sma(indicatorCloses, period: 20),
                        sma50: TickerIndicators.sma(indicatorCloses, period: 50),
                        ema20: TickerIndicators.ema(indicatorCloses, period: 20),
                        rsi14: TickerIndicators.rsi(indicatorCloses, period: 14),
                        macd: macd,
                        priceHistory: Array(historicalHistory.suffix(90))
                    )
                )
            } catch {
                lastError = error
                failedSymbols.append(symbol)
                if let fallbackPrice = budget.cachedQuotes[symbol]?.price, fallbackPrice > 0 {
                    let cachedHistory = (try? await marketDataService.fetchCompositeRecentPriceHistory(
                        ticker: symbol,
                        settings: budget.marketDataSettings,
                        days: 90
                    )) ?? TickerPricePoint.estimated(from: [fallbackPrice, fallbackPrice])
                    let indicatorCloses = TickerPricePoint.closesForIndicators(history: cachedHistory, currentPrice: fallbackPrice)
                    let macd = TickerIndicators.macd(indicatorCloses)
                    rows.append(
                        HomeWatchlistRow(
                            symbol: symbol,
                            companyName: nil,
                            exchange: nil,
                            price: fallbackPrice,
                            change: 0,
                            percentChange: 0,
                            open: nil,
                            dayHigh: nil,
                            dayLow: nil,
                            previousClose: nil,
                            sma20: TickerIndicators.sma(indicatorCloses, period: 20),
                            sma50: TickerIndicators.sma(indicatorCloses, period: 50),
                            ema20: TickerIndicators.ema(indicatorCloses, period: 20),
                            rsi14: TickerIndicators.rsi(indicatorCloses, period: 14),
                            macd: macd,
                            priceHistory: Array(cachedHistory.suffix(90))
                        )
                    )
                }
            }
        }

        homeWatchlistRows = rows
        if failedSymbols.isEmpty {
            homeWatchlistError = nil
        } else if rows.isEmpty {
            if let serviceError = lastError as? MarketDataServiceError, serviceError == .invalidResponse {
                homeWatchlistError = "Finnhub rejected the request. Confirm provider is Finnhub and API key is valid."
            } else {
                homeWatchlistError = lastError?.localizedDescription ?? "Failed to load watchlist data."
            }
        } else {
            homeWatchlistError = "Loaded \(rows.count) of \(symbols.count). Failed: \(failedSymbols.joined(separator: ", "))."
        }
    }

    private func removeHomeWatchlistTicker(_ ticker: String) {
        budget.watchlistTickers.removeAll { $0.uppercased() == ticker.uppercased() }
        budget.watchlistAlertSettings.removeValue(forKey: ticker.uppercased())
        homeWatchlistRows.removeAll { $0.symbol.uppercased() == ticker.uppercased() }
    }
}

private struct WatchlistAlertSettingsView: View {
    @ObservedObject var budget: BudgetModel
    let ticker: String
    @Environment(\.dismiss) private var dismiss

    @State private var isEnabled = true
    @State private var percentMoveThreshold = 1.5
    @State private var priceAbove = 0.0
    @State private var priceBelow = 0.0

    private var cleanTicker: String {
        ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alerts") {
                    Toggle("Enabled", isOn: $isEnabled)
                    LabeledContent("Move threshold") {
                        TextField("1.5%", value: $percentMoveThreshold, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Notify above") {
                        TextField("Optional", value: $priceAbove, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Notify below") {
                        TextField("Optional", value: $priceBelow, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Text("Leave a price alert at 0 to ignore that trigger. Move alerts compare the latest quote to the cached quote and the daily percentage change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("\(cleanTicker) Alerts")
            .onAppear {
                let settings = budget.watchlistAlertSettings(for: cleanTicker)
                isEnabled = settings.isEnabled
                percentMoveThreshold = settings.percentMoveThreshold
                priceAbove = settings.priceAbove ?? 0
                priceBelow = settings.priceBelow ?? 0
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        budget.setWatchlistAlertSettings(
                            WatchlistAlertSettings(
                                isEnabled: isEnabled,
                                percentMoveThreshold: percentMoveThreshold,
                                priceAbove: priceAbove > 0 ? priceAbove : nil,
                                priceBelow: priceBelow > 0 ? priceBelow : nil
                            ),
                            for: cleanTicker
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

enum BudgetMode: String, CaseIterable, Identifiable {
    case home
    case calendar
    case budget
    case margin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .calendar:
            return "Calendar"
        case .budget:
            return "Budget"
        case .margin:
            return "Margin"
        }
    }
}

enum MarginQuickAction {
    case addTransaction
    case addInvestment
    case addManualHolding
    case marginSettings
    case ledgerHistory
}

struct AppSettingsView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Market Data") {
                    Picker("Provider", selection: $budget.marketDataSettings.provider) {
                        ForEach(MarketDataProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    SecureField("API key", text: $budget.marketDataSettings.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    NavigationLink("Watchlist Tickers") {
                        WatchlistSettingsView(budget: budget)
                    }
                    Text("Used for SPY comparison and quote refresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Plaid") {
                    NavigationLink("Bank, Card, and Portfolio Sync") {
                        PlaidSettingsView(budget: budget)
                    }
                    if !budget.plaidConnectionStatuses.isEmpty {
                        Text("\(budget.plaidConnectionStatuses.count) linked institution\(budget.plaidConnectionStatuses.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !budget.plaidReviewItems.isEmpty {
                        Text("\(budget.plaidReviewItems.count) Plaid import\(budget.plaidReviewItems.count == 1 ? "" : "s") need review")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Alpaca Fallback") {
                    Toggle("Use Alpaca when primary provider fails", isOn: $budget.marketDataSettings.useAlpacaFallback)
                    SecureField("Alpaca API key ID", text: $budget.marketDataSettings.alpacaAPIKeyId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Alpaca secret key", text: $budget.marketDataSettings.alpacaSecretKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Data feed", selection: $budget.marketDataSettings.alpacaFeed) {
                        ForEach(AlpacaMarketDataFeed.allCases) { feed in
                            Text(feed.rawValue).tag(feed)
                        }
                    }
                    Text("IEX works for free stock market data; SIP requires an Alpaca market data subscription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Margin Defaults") {
                    TextField("Total margin available", value: $budget.marginSettings.totalMarginAvailable, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    TextField("Interest-free margin limit", value: $budget.marginSettings.interestFreeMarginLimit, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    TextField("Personal max margin cap", value: $budget.marginSettings.personalMarginCap, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct WatchlistSettingsView: View {
    @ObservedObject var budget: BudgetModel
    @State private var newTicker: String = ""
    @State private var selectedTicker: TickerSnapshotSelection?

    private struct TickerSnapshotSelection: Identifiable {
        let ticker: String
        var id: String { ticker }
    }

    var body: some View {
        Form {
            Section("Add Ticker") {
                HStack(spacing: 8) {
                    TextField("e.g. AAPL", text: $newTicker)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Add") {
                        addTicker()
                    }
                    .disabled(sanitizedNewTicker.isEmpty)
                }
                Text("Use stock symbols only (for example AAPL, MSFT, NVDA).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Current Watchlist") {
                if budget.watchlistTickers.isEmpty {
                    Text("No tickers yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(budget.watchlistTickers, id: \.self) { ticker in
                        Button {
                            selectedTicker = TickerSnapshotSelection(ticker: ticker.uppercased())
                        } label: {
                            Text(ticker)
                                .foregroundStyle(.primary)
                        }
                    }
                    .onDelete(perform: deleteTicker)
                    .onMove(perform: moveTicker)
                }
            }

            if !budget.watchlistTickers.isEmpty {
                Section("Live Quotes") {
                    TradingViewWatchlistBoard(symbols: budget.watchlistTickers) { ticker in
                        selectedTicker = TickerSnapshotSelection(ticker: ticker)
                    }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
        }
        .sheet(item: $selectedTicker) { selection in
            TickerSnapshotDetailView(
                budget: budget,
                ticker: selection.ticker
            )
        }
        .navigationTitle("Watchlist")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    private var sanitizedNewTicker: String {
        newTicker
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func addTicker() {
        let ticker = sanitizedNewTicker
        guard !ticker.isEmpty else { return }
        guard !budget.watchlistTickers.contains(ticker) else {
            newTicker = ""
            return
        }
        budget.watchlistTickers.append(ticker)
        newTicker = ""
    }

    private func deleteTicker(at offsets: IndexSet) {
        budget.watchlistTickers.remove(atOffsets: offsets)
    }

    private func moveTicker(from source: IndexSet, to destination: Int) {
        budget.watchlistTickers.move(fromOffsets: source, toOffset: destination)
    }
}

struct TickerSnapshotDetailView: View {
    @ObservedObject var budget: BudgetModel
    let ticker: String
    let companyName: String?
    let quoteSnapshot: MarketQuoteSnapshot?
    let historicalCloses: [Double]

    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: MarketQuoteSnapshot?
    @State private var priceHistory: [TickerPricePoint]
    @State private var noteDraft = ""
    @State private var editingNoteDraft: TickerNoteEditDraft?
    @State private var notePendingDelete: TickerNote?
    @State private var showAddNoteSheet = false
    @State private var addNoteTitle = ""
    @State private var addNoteText = ""
    @State private var addNoteURL = ""
    @State private var addNoteURLTitle = ""
    @State private var addNoteCategory = ""
    @State private var noteSortOption: TickerNoteSortOption = .newest
    @State private var expandedNoteIDs: Set<UUID> = []
    @State private var summaryText: String?
    @State private var isSummarizing = false
    @State private var isRefreshing = false
    @State private var selectedArticleURL: ArticleURL?
    @State private var refreshError: String?
    @State private var companyProfile: MarketCompanyProfile?
    @State private var showAlertSettings = false
    @State private var selectedTickerTransaction: PortfolioTransaction?
    private let marketDataService = MarketDataService()

    init(
        budget: BudgetModel,
        ticker: String,
        companyName: String? = nil,
        quoteSnapshot: MarketQuoteSnapshot? = nil,
        historicalCloses: [Double] = [],
        priceHistory: [TickerPricePoint]? = nil
    ) {
        self.budget = budget
        self.ticker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.companyName = companyName
        self.quoteSnapshot = quoteSnapshot
        self.historicalCloses = historicalCloses
        let resolvedHistory = priceHistory ?? TickerPricePoint.estimated(from: historicalCloses)
        _snapshot = State(initialValue: quoteSnapshot)
        _priceHistory = State(initialValue: resolvedHistory)
    }

    private var closes: [Double] { TickerPricePoint.closes(from: priceHistory) }
    private var indicatorCloses: [Double] {
        TickerPricePoint.closesForIndicators(history: priceHistory, currentPrice: snapshot?.price)
    }

    private var cleanTicker: String { ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    private var research: TickerResearch { budget.tickerResearch[cleanTicker] ?? TickerResearch() }
    private var notes: [TickerNote] { budget.notes(for: cleanTicker) }
    private var sortedNotes: [TickerNote] {
        switch noteSortOption {
        case .newest:
            return notes.sorted { $0.updatedAt > $1.updatedAt }
        case .oldest:
            return notes.sorted { $0.updatedAt < $1.updatedAt }
        case .category:
            return notes.sorted { lhs, rhs in
                let leftCategory = lhs.category ?? "Uncategorized"
                let rightCategory = rhs.category ?? "Uncategorized"
                if leftCategory.localizedCaseInsensitiveCompare(rightCategory) == .orderedSame {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return leftCategory.localizedCaseInsensitiveCompare(rightCategory) == .orderedAscending
            }
        }
    }
    private var latestPrice: Double { snapshot?.price ?? budget.cachedQuotes[cleanTicker]?.price ?? closes.last ?? 0 }
    private var priceChangeTint: Color { (snapshot?.percentChange ?? 0) >= 0 ? .green : .red }
    private var tickerTransactions: [PortfolioTransaction] {
        budget.portfolioTransactions
            .filter {
                $0.ticker?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == cleanTicker
            }
            .sorted { $0.date > $1.date }
    }

    private var sma20: Double? { TickerIndicators.sma(indicatorCloses, period: 20) }
    private var sma50: Double? { TickerIndicators.sma(indicatorCloses, period: 50) }
    private var ema20: Double? { TickerIndicators.ema(indicatorCloses, period: 20) }
    private var rsi14: Double? { TickerIndicators.rsi(indicatorCloses, period: 14) }
    private var macd: MACDResult? { TickerIndicators.macd(indicatorCloses) }

    private enum TickerNoteSortOption: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case oldest = "Oldest"
        case category = "Category"

        var id: String { rawValue }
    }

    private struct TickerNoteEditDraft: Identifiable {
        let id: UUID
        let ticker: String
        var title: String
        var text: String
        var url: String
        var urlTitle: String
        var category: String

        init(note: TickerNote) {
            id = note.id
            ticker = note.ticker
            title = note.title ?? ""
            text = note.text
            url = note.url ?? ""
            urlTitle = note.urlTitle ?? ""
            category = note.category ?? ""
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    chartSection
                    transactionActivitySection
                    financialsSection
                    notesSection
                    aiCaseSection
                    newsSection
                }
                .padding(.vertical)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refreshTickerData() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                    .accessibilityLabel("Refresh ticker")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAlertSettings = true
                    } label: {
                        let settings = budget.watchlistAlertSettings(for: ticker)
                        Image(systemName: settings.isEnabled ? "bell.badge.fill" : "bell.badge")
                    }
                    .accessibilityLabel("Alert settings")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if snapshot == nil || priceHistory.count < 2 || research.articles.isEmpty {
                    await refreshTickerData()
                }
            }
            .sheet(item: $selectedArticleURL) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showAlertSettings) {
                WatchlistAlertSettingsView(budget: budget, ticker: ticker)
            }
            .sheet(item: $selectedTickerTransaction) { transaction in
                PortfolioTransactionDetailView(transaction: transaction)
            }
            .sheet(item: $editingNoteDraft) { draft in
                TickerSnapshotNoteEditorView(
                    initialDraft: draft,
                    onCancel: {
                        editingNoteDraft = nil
                    },
                    onSave: { updatedDraft in
                        budget.updateTickerNote(
                            id: updatedDraft.id,
                            ticker: updatedDraft.ticker,
                            title: updatedDraft.title.nilIfEmpty,
                            text: updatedDraft.text,
                            url: updatedDraft.url.nilIfEmpty,
                            urlTitle: updatedDraft.urlTitle.nilIfEmpty,
                            category: updatedDraft.category.nilIfEmpty
                        )
                        editingNoteDraft = nil
                    }
                )
            }
            .sheet(isPresented: $showAddNoteSheet) {
                NavigationStack {
                    Form {
                        TextField("Title", text: $addNoteTitle)
                        TextEditor(text: $addNoteText)
                            .frame(minHeight: 140)
                        TextField("URL (e.g. article link)", text: $addNoteURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        TextField("URL Label", text: $addNoteURLTitle)
                        Picker("Category", selection: $addNoteCategory) {
                            Text("None").tag("")
                            ForEach(noteCategories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                    }
                    .navigationTitle("Add Note")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showAddNoteSheet = false
                                resetAddNoteFields()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                budget.addTickerNote(
                                    ticker: cleanTicker,
                                    title: addNoteTitle.nilIfEmpty,
                                    text: addNoteText,
                                    url: addNoteURL.nilIfEmpty,
                                    urlTitle: addNoteURLTitle.nilIfEmpty,
                                    category: addNoteCategory.nilIfEmpty
                                )
                                showAddNoteSheet = false
                                resetAddNoteFields()
                            }
                            .disabled(addNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete this note?",
                isPresented: Binding(
                    get: { notePendingDelete != nil },
                    set: { if !$0 { notePendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Note", role: .destructive) {
                    if let notePendingDelete {
                        budget.deleteTickerNote(notePendingDelete)
                    }
                    notePendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    notePendingDelete = nil
                }
            } message: {
                Text("This removes the note from the ticker.")
            }
        }
    }

    private var heroSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(companyName?.isEmpty == false ? companyName! : cleanTicker)
                            .font(.headline)
                        Text(latestPrice > 0 ? latestPrice.formatted(.currency(code: "USD")) : "--")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let snapshot {
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(snapshot.percentChange / 100, format: .percent.precision(.fractionLength(2)))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(priceChangeTint)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(priceChangeTint.opacity(0.12), in: Capsule())
                            Text(snapshot.change, format: .currency(code: "USD"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let updatedAt = budget.cachedQuotes[cleanTicker]?.updatedAt {
                    Label("Updated \(updatedAt, format: .dateTime.month().day().hour().minute())", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let refreshError {
                    Text(refreshError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let refreshError {
                Text(refreshError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            TradingViewTickerChartPanel(
                symbol: cleanTicker,
                fallbackPoints: priceHistory,
                trendIsPositive: (snapshot?.percentChange ?? 0) >= 0
            )
        }
    }

    private var financialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TradingViewWidgetContainer(
                kind: .fundamentalData(symbol: cleanTicker),
                height: 825,
                isUserInteractionEnabled: true,
                isScrollEnabled: true
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal)
    }

    private var transactionActivitySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Transactions", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Spacer()
                    Text("\(tickerTransactions.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }

                if tickerTransactions.isEmpty {
                    Text("No transactions recorded for \(cleanTicker).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tickerTransactions) { transaction in
                        Button {
                            selectedTickerTransaction = transaction
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: transactionSystemImage(transaction.type))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(transactionTint(transaction.type))
                                    .frame(width: 30, height: 30)
                                    .background(transactionTint(transaction.type).opacity(0.12), in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(transaction.type.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(transaction.date, format: .dateTime.month().day().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(transaction.amount, format: .currency(code: "USD"))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if let shares = transaction.shares {
                                        Text("\(shares.formatted(.number.precision(.fractionLength(0...4)))) shares")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func transactionSystemImage(_ type: PortfolioTransactionType) -> String {
        switch type {
        case .buy: return "arrow.down.circle"
        case .sell: return "arrow.up.circle"
        case .dividend: return "dollarsign.circle"
        case .contribution: return "plus.circle"
        case .billPaidByMargin: return "creditcard"
        case .marginInterest: return "percent"
        case .manualAdjustment: return "slider.horizontal.3"
        }
    }

    private func transactionTint(_ type: PortfolioTransactionType) -> Color {
        switch type {
        case .sell, .dividend: return .green
        case .buy, .billPaidByMargin, .marginInterest: return .orange
        case .contribution: return .mint
        case .manualAdjustment: return .indigo
        }
    }

    private var notesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Label("Notes", systemImage: "note.text")
                        .font(.headline)
                    Spacer()
                    if !notes.isEmpty {
                        Menu {
                            ForEach(TickerNoteSortOption.allCases) { option in
                                Button {
                                    noteSortOption = option
                                } label: {
                                    if noteSortOption == option {
                                        Label(option.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(option.rawValue)
                                    }
                                }
                            }
                        } label: {
                            Label(noteSortOption.rawValue, systemImage: "arrow.up.arrow.down")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("\(notes.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }
                HStack(alignment: .top, spacing: 8) {
                    TextField("Quick note", text: $noteDraft, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button {
                        budget.addTickerNote(ticker: cleanTicker, text: noteDraft)
                        noteDraft = ""
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add note")
                }

                HStack(spacing: 8) {
                    Button {
                        showAddNoteSheet = true
                    } label: {
                        Label("Add Detail", systemImage: "plus.square")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    if !notes.isEmpty {
                        Button {
                            Task { await generateNotesSummary() }
                        } label: {
                            if isSummarizing {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Label("Summarize", systemImage: "apple.intelligence")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSummarizing)
                    }
                }

                if let summaryText {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("AI Summary", systemImage: "apple.intelligence")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                        TickerMarkdownText(markdown: summaryText, baseFont: .caption, baseColor: .secondary, spacing: 5)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if notes.isEmpty {
                    Text("No notes for \(cleanTicker) yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedNotes) { note in
                        noteCard(note)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func noteCard(_ note: TickerNote) -> some View {
        let isExpanded = expandedNoteIDs.contains(note.id)
        let isLong = isLongNote(note)
        return VStack(alignment: .leading, spacing: 8) {
            if let title = note.title {
                TickerMarkdownText(markdown: title, spacing: 4, forceHeader1: true)
            }

            TickerMarkdownText(markdown: note.text, baseFont: .subheadline)
                .frame(maxHeight: isExpanded || !isLong ? nil : 96, alignment: .top)
                .clipped()

            if isLong {
                Button {
                    toggleNoteExpansion(note.id)
                } label: {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }

            if let url = note.url, let destination = noteURL(from: url) {
                Link(destination: destination) {
                    Label(note.urlTitle ?? url, systemImage: "link")
                        .font(.caption)
                        .lineLimit(1)
                }
                .tint(.blue)
            }

            HStack {
                if let category = note.category {
                    Text(category)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }
                Spacer()
                Text(note.updatedAt, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Button {
                    editingNoteDraft = TickerNoteEditDraft(note: note)
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .labelStyle(.titleAndIcon)
                }
                .font(.caption)
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    notePendingDelete = note
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func isLongNote(_ note: TickerNote) -> Bool {
        note.text.count > 220 || note.text.components(separatedBy: .newlines).count > 5
    }

    private func toggleNoteExpansion(_ id: UUID) {
        if expandedNoteIDs.contains(id) {
            expandedNoteIDs.remove(id)
        } else {
            expandedNoteIDs.insert(id)
        }
    }

    private func noteURL(from text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(text)")
    }

    private func resetAddNoteFields() {
        addNoteTitle = ""
        addNoteText = ""
        addNoteURL = ""
        addNoteURLTitle = ""
        addNoteCategory = ""
    }

    private func generateNotesSummary() async {
        isSummarizing = true
        summaryText = nil
        do {
            if #available(iOS 26.0, *) {
                summaryText = try await budget.summarizeNotes(for: cleanTicker)
            } else {
                summaryText = "Summarization requires iOS 26.0 or later with Apple Intelligence."
            }
        } catch {
            summaryText = "Summary unavailable: \(error.localizedDescription)"
        }
        isSummarizing = false
    }

    private struct TickerSnapshotNoteEditorView: View {
        let onCancel: () -> Void
        let onSave: (TickerNoteEditDraft) -> Void
        @State private var draft: TickerNoteEditDraft

        init(
            initialDraft: TickerNoteEditDraft,
            onCancel: @escaping () -> Void,
            onSave: @escaping (TickerNoteEditDraft) -> Void
        ) {
            self.onCancel = onCancel
            self.onSave = onSave
            _draft = State(initialValue: initialDraft)
        }

        var body: some View {
            NavigationStack {
                Form {
                    TextField("Title", text: $draft.title)
                    TextEditor(text: $draft.text)
                        .frame(minHeight: 140)
                    TextField("URL (e.g. article link)", text: $draft.url)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("URL Label", text: $draft.urlTitle)
                    Picker("Category", selection: $draft.category) {
                        Text("None").tag("")
                        ForEach(noteCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                }
                .navigationTitle("Edit Note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            var cleanDraft = draft
                            cleanDraft.text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            onSave(cleanDraft)
                        }
                        .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private var aiCaseSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("AI Case")
                        .font(.headline)
                    Spacer()
                    if let updatedAt = research.updatedAt {
                        Text(updatedAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Bull", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(research.bullCase.isEmpty ? "Refresh to generate a bull case from price action, indicators, and news." : research.bullCase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Bear", systemImage: "arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(research.bearCase.isEmpty ? "Refresh to generate a bear case from price action, indicators, and news." : research.bearCase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }

    private var newsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent News")
                    .font(.headline)
                if !research.newsSummary.isEmpty {
                    Text(research.newsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if research.articles.isEmpty {
                    Text("Recent articles will appear when Finnhub news is available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(research.articles) { article in
                        Button {
                            if let url = URL(string: article.url) {
                                selectedArticleURL = ArticleURL(url: url)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(article.source.isEmpty ? "News" : article.source)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(article.publishedAt, format: .dateTime.month().day())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(article.headline)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                if !article.summary.isEmpty {
                                    Text(article.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        if article.id != research.articles.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func tickerMetricPill(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.map { $0.formatted(.currency(code: "USD")) } ?? "--")
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func tickerNumberPill(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "--")
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func tickerTextPill(_ title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value?.isEmpty == false ? value! : "--")
                .font(.caption.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }


    @MainActor
    private func refreshTickerData() async {
        guard !isRefreshing else { return }
        guard budget.marketDataSettings.canFetchMarketData else {
            refreshError = "Missing market data credentials in Settings."
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        refreshError = nil

        do {
            let quote = try await marketDataService.fetchQuoteSnapshot(ticker: cleanTicker, settings: budget.marketDataSettings)
            snapshot = quote
            budget.cachedQuotes[cleanTicker] = CachedQuote(ticker: cleanTicker, price: quote.price, updatedAt: Date())
        } catch {
            refreshError = "Using cached quote data."
        }

        if let fetchedHistory = try? await marketDataService.fetchCompositeRecentPriceHistory(ticker: cleanTicker, settings: budget.marketDataSettings, days: 90),
           fetchedHistory.count >= 2 {
            priceHistory = fetchedHistory
        } else if priceHistory.count < 2, let snapshot {
            priceHistory = TickerPricePoint.estimated(from: compactTickerSessionPrices(from: snapshot))
        }

        let apiKey = budget.marketDataSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty,
           let profile = try? await marketDataService.fetchCompanyProfile(ticker: cleanTicker, provider: .finnhub, apiKey: apiKey) {
            companyProfile = profile
        }

        let articles = (try? await marketDataService.fetchRecentNews(ticker: cleanTicker, settings: budget.marketDataSettings, daysBack: 14)) ?? research.articles
        let generated = generatedResearch(articles: articles)
        budget.setTickerResearch(generated, for: cleanTicker)
    }

    private func generatedResearch(articles: [TickerNewsArticle]) -> TickerResearch {
        let trend = indicatorCloses.count >= 2 ? ((indicatorCloses.last ?? 0) - (indicatorCloses.first ?? 0)) / max(indicatorCloses.first ?? 1, 1) : 0
        let priceVsSMA = latestPrice - (sma20 ?? latestPrice)
        let currentRSI = rsi14
        let currentMACD = macd
        let topSources = Array(Set(articles.prefix(5).map(\.source).filter { !$0.isEmpty })).prefix(3).joined(separator: ", ")
        let newsLead = articles.first?.headline ?? "No fresh headline is cached yet"

        let bull = [
            trend >= 0 ? "Price trend is positive across the loaded history." : "The setup can improve if price reclaims the short-term average.",
            priceVsSMA >= 0 ? "Current price is above SMA 20, which supports near-term momentum." : "A move back over SMA 20 would improve the technical picture.",
            (currentRSI ?? 50) < 70 ? "RSI is not flashing an overbought reading." : "RSI is elevated, so upside may need consolidation.",
            (currentMACD?.histogram ?? 0) >= 0 ? "MACD histogram is positive." : "A bullish MACD turn would strengthen the case.",
            "Recent coverage led by: \(newsLead)."
        ].joined(separator: " ")

        let bear = [
            trend < 0 ? "Loaded price history is trending lower." : "Positive price action can still reverse if news or broad market risk weakens.",
            priceVsSMA < 0 ? "Current price is below SMA 20, showing short-term pressure." : "A break back below SMA 20 would weaken the setup.",
            (currentRSI ?? 50) > 70 ? "RSI is overbought." : "RSI could still deteriorate if sellers regain control.",
            (currentMACD?.histogram ?? 0) < 0 ? "MACD histogram is negative." : "A MACD rollover would weaken momentum.",
            articles.isEmpty ? "There are no cached articles to verify the narrative." : "News concentration from \(topSources.isEmpty ? "recent sources" : topSources) should be checked for one-sided coverage."
        ].joined(separator: " ")

        let summary = articles.prefix(4).map { article in
            "\(article.source.isEmpty ? "News" : article.source): \(article.headline)"
        }.joined(separator: " ")

        return TickerResearch(
            bullCase: bull,
            bearCase: bear,
            newsSummary: summary,
            articles: articles,
            updatedAt: Date()
        )
    }

    private func compactTickerSessionPrices(from snapshot: MarketQuoteSnapshot) -> [Double] {
        [snapshot.previousClose, snapshot.open, snapshot.low, snapshot.price, snapshot.high]
            .compactMap { $0 }
            .filter { $0 > 0 }
            .reduce(into: [Double]()) { values, value in
                if values.last != value {
                    values.append(value)
                }
            }
    }
}

private struct ArticleURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct TickerSearchView: View {
    @ObservedObject var budget: BudgetModel
    let onAdd: ([String]) -> Void
    let onSnapshot: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var results: [SymbolLookupResult] = []
    @State private var isSearching = false
    @State private var selectedTickers: Set<String> = []
    @State private var searchError: String?
    @State private var quoteSnapshots: [String: MarketQuoteSnapshot] = [:]
    @State private var marketOverview: [MarketOverviewItem] = []
    @State private var sectorQuotes: [String: MarketQuoteSnapshot] = [:]
    @State private var isLoadingOverview = false

    private let marketDataService = MarketDataService()

    private static let overviewSymbols: [(symbol: String, name: String)] = [
        ("SPY", "S&P 500"),
        ("GLD", "Gold"),
        ("USO", "Crude Oil"),
    ]

    private static let sectorSymbols: [(symbol: String, name: String)] = [
        ("XLK", "Technology"),
        ("XLF", "Financials"),
        ("XLV", "Healthcare"),
        ("XLE", "Energy"),
        ("XLI", "Industrials"),
        ("XLP", "Consumer Staples"),
        ("XLY", "Consumer Disc."),
        ("XLB", "Materials"),
        ("XLRE", "Real Estate"),
        ("XLU", "Utilities"),
        ("XLC", "Communication"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if searchText.isEmpty {
                    emptyStateContent
                } else if isSearching {
                    loadingContent
                } else if let error = searchError {
                    errorContent(error)
                } else if results.isEmpty {
                    noResultsContent
                } else {
                    searchResultsContent
                }
            }
            .searchable(text: $searchText, prompt: "Search ticker...")
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .navigationTitle("Add to Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedTickers.count))") {
                        onAdd(Array(selectedTickers))
                        dismiss()
                    }
                    .disabled(selectedTickers.isEmpty)
                }
            }
            .task {
                await loadMarketData()
            }
            .onChange(of: searchText) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    results = []
                    quoteSnapshots = [:]
                    searchError = nil
                    return
                }
                isSearching = true
                searchError = nil
                quoteSnapshots = [:]
                Task {
                    do {
                        let fetched = try await marketDataService.fetchSymbolLookup(
                            query: trimmed,
                            settings: budget.marketDataSettings
                        )
                        let topResults = Array(fetched.prefix(20))
                        await MainActor.run {
                            results = topResults
                            isSearching = false
                        }
                        await fetchQuotes(for: topResults)
                    } catch {
                        await MainActor.run {
                            searchError = error.localizedDescription
                            isSearching = false
                            results = []
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateContent: some View {
        if isLoadingOverview {
            VStack(spacing: 16) {
                Spacer().frame(height: 80)
                ProgressView()
                Text("Loading market data...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                marketOverviewSection
                sectorsSection
                hintText
            }
            .padding()
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 60)
            ProgressView()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorContent(_ error: String) -> some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 60)
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var noResultsContent: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 60)
            Text("No results found.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var marketOverviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Market Overview")
                .font(.headline)
            HStack(spacing: 10) {
                ForEach(marketOverview) { item in
                    marketOverviewCard(item)
                }
            }
        }
    }

    private func marketOverviewCard(_ item: MarketOverviewItem) -> some View {
        let isUp = item.quote?.percentChange ?? 0 >= 0
        return Button {
            onSnapshot(item.symbol)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(item.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                if let history = item.priceHistory, history.count >= 2 {
                    TickerPriceHistoryChart(
                        points: history,
                        trendIsPositive: isUp,
                        style: .compact
                    )
                    .frame(height: 52)
                }

                if let quote = item.quote {
                    Text(quote.price, format: .currency(code: "USD").precision(.fractionLength(2)))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Image(systemName: isUp ? "arrow.up" : "arrow.down")
                            .font(.caption.weight(.bold))
                        Text(quote.percentChange / 100, format: .percent.precision(.fractionLength(2)))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(isUp ? .green : .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sectors

    private var sectorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sectors")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 68), spacing: 8)
            ], spacing: 8) {
                ForEach(Self.sectorSymbols, id: \.symbol) { entry in
                    sectorTile(symbol: entry.symbol, name: entry.name, quote: sectorQuotes[entry.symbol])
                }
            }
        }
    }

    private func sectorTile(symbol: String, name: String, quote: MarketQuoteSnapshot?) -> some View {
        let pct = quote?.percentChange ?? 0
        let isUp = pct >= 0
        return Button {
            onSnapshot(symbol)
            dismiss()
        } label: {
            VStack(spacing: 4) {
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let quote {
                    HStack(spacing: 2) {
                        Image(systemName: isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 8))
                        Text(quote.percentChange / 100, format: .percent.precision(.fractionLength(1)))
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(isUp ? .green : .red)
                } else {
                    Text("--")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(name)
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((isUp ? Color.green : Color.red).opacity(quote != nil ? 0.08 : 0.03))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 58)
    }

    // MARK: - Hint

    private var hintText: some View {
        Text("Type above to search for any stock symbol.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: - Search Results

    private var searchResultsContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(results) { result in
                Button {
                    if selectedTickers.contains(result.symbol) {
                        selectedTickers.remove(result.symbol)
                    } else {
                        selectedTickers.insert(result.symbol)
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(result.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let quote = quoteSnapshots[result.symbol] {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(quote.price, format: .currency(code: "USD").precision(.fractionLength(2)))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                HStack(spacing: 3) {
                                    Image(systemName: quote.percentChange >= 0 ? "arrow.up" : "arrow.down")
                                        .font(.caption2.weight(.bold))
                                    Text(quote.percentChange / 100, format: .percent.precision(.fractionLength(2)))
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(quote.percentChange >= 0 ? .green : .red)
                            }
                            .frame(minWidth: 80, alignment: .trailing)
                        }
                        if selectedTickers.contains(result.symbol) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                                .font(.title3)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if result.id != results.last?.id {
                    Divider().padding(.leading, 20)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Data Loading

    private func loadMarketData() async {
        guard budget.marketDataSettings.canFetchMarketData else { return }
        isLoadingOverview = true
        defer { isLoadingOverview = false }

        // Load overview (SPY, GLD, USO) sequentially since it's just 3
        var items: [MarketOverviewItem] = []
        for entry in Self.overviewSymbols {
            let quote = try? await marketDataService.fetchQuoteSnapshot(
                ticker: entry.symbol,
                settings: budget.marketDataSettings
            )
            let history = try? await marketDataService.fetchCompositeRecentPriceHistory(
                ticker: entry.symbol,
                settings: budget.marketDataSettings,
                days: 30
            )
            items.append(MarketOverviewItem(
                symbol: entry.symbol,
                name: entry.name,
                quote: quote,
                priceHistory: history
            ))
        }

        // Load sector quotes in parallel
        var sectors: [String: MarketQuoteSnapshot] = [:]
        await withTaskGroup(of: (String, MarketQuoteSnapshot?).self) { group in
            for entry in Self.sectorSymbols {
                group.addTask {
                    do {
                        let quote = try await marketDataService.fetchQuoteSnapshot(
                            ticker: entry.symbol,
                            settings: budget.marketDataSettings
                        )
                        return (entry.symbol, quote)
                    } catch {
                        return (entry.symbol, nil)
                    }
                }
            }
            for await (symbol, quote) in group {
                if let quote {
                    sectors[symbol] = quote
                }
            }
        }

        await MainActor.run {
            marketOverview = items
            sectorQuotes = sectors
        }
    }

    private func fetchQuotes(for symbols: [SymbolLookupResult]) async {
        await withTaskGroup(of: (String, MarketQuoteSnapshot?).self) { group in
            for result in symbols {
                group.addTask {
                    do {
                        let quote = try await marketDataService.fetchQuoteSnapshot(
                            ticker: result.symbol,
                            settings: budget.marketDataSettings
                        )
                        return (result.symbol, quote)
                    } catch {
                        return (result.symbol, nil)
                    }
                }
            }
            var snapshots: [String: MarketQuoteSnapshot] = [:]
            for await (symbol, quote) in group {
                if let quote {
                    snapshots[symbol] = quote
                }
            }
            await MainActor.run {
                quoteSnapshots = snapshots
            }
        }
    }
}

private struct MarketOverviewItem: Identifiable {
    let id = UUID()
    let symbol: String
    let name: String
    let quote: MarketQuoteSnapshot?
    let priceHistory: [TickerPricePoint]?
}

struct TickerPriceHistoryChart: View {
    enum Style {
        case compact
        case detailed
    }

    let points: [TickerPricePoint]
    let trendIsPositive: Bool
    var style: Style = .detailed
    /// When set, renders a TradingView embed chart with Swift Charts fallback.
    var symbol: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPoint: TickerPricePoint?

    private var tint: Color { trendIsPositive ? .green : .red }

    private var yDomain: ClosedRange<Double> {
        let prices = points.map(\.close)
        guard let minPrice = prices.min(), let maxPrice = prices.max() else {
            return 0...1
        }
        if minPrice == maxPrice {
            let padding = max(minPrice * 0.02, 0.01)
            return (minPrice - padding)...(maxPrice + padding)
        }
        let range = maxPrice - minPrice
        let padding = max(range * 0.06, maxPrice * 0.002)
        return (minPrice - padding)...(maxPrice + padding)
    }

    private var xAxisDates: [Date] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        if style == .compact {
            return [first, last]
        }

        let calendar = Calendar.current
        let spanDays = max(calendar.dateComponents([.day], from: first, to: last).day ?? 0, 1)
        let strideDays: Int
        switch spanDays {
        case ..<10:
            strideDays = 1
        case ..<35:
            strideDays = 7
        case ..<120:
            strideDays = 14
        default:
            strideDays = 30
        }

        var marks: [Date] = []
        var cursor = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        while cursor <= end {
            marks.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: strideDays, to: cursor) else { break }
            cursor = next
        }
        if marks.last != last {
            marks.append(last)
        }
        return marks
    }

    private var periodChangePercent: Double? {
        guard let first = points.first?.close,
              let last = points.last?.close,
              first > 0 else { return nil }
        return ((last - first) / first) * 100
    }

    private var timeframeCaption: String {
        guard let first = points.first?.date, let last = points.last?.date else { return "" }

        let calendar = Calendar.current
        let spanDays = max(calendar.dateComponents([.day], from: first, to: last).day ?? 0, 1)
        let spanLabel: String
        if spanDays >= 56 {
            let months = max(Int(round(Double(spanDays) / 30.0)), 1)
            spanLabel = "~\(months) mo"
        } else if spanDays >= 14 {
            let weeks = max(Int(round(Double(spanDays) / 7.0)), 1)
            spanLabel = "~\(weeks) wk"
        } else {
            spanLabel = "\(spanDays)d"
        }

        let rangeLabel = "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
        return "\(points.count) sessions · \(spanLabel) · \(rangeLabel)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .detailed ? 8 : 4) {
            if style == .detailed {
                HStack(alignment: .firstTextBaseline) {
                    Text("Price History")
                        .font(.headline)
                    Spacer()
                    if let periodChangePercent {
                        Text(periodChangePercent / 100, format: .percent.sign(strategy: .always()).precision(.fractionLength(1)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(periodChangePercent >= 0 ? .green : .red)
                    }
                }
            }

            if let symbol, !symbol.isEmpty {
                if style == .detailed {
                    TradingViewTickerChartPanel(
                        symbol: symbol,
                        fallbackPoints: points,
                        trendIsPositive: trendIsPositive
                    )
                } else {
                    TradingViewCompactTickerChart(
                        symbol: symbol,
                        fallbackPoints: points,
                        trendIsPositive: trendIsPositive,
                        height: 80
                    )
                }
                if points.count >= 2 {
                    Text(timeframeCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if points.count >= 2 {
                chart
                Text(timeframeCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Date", point.date),
                yStart: .value("Baseline", yDomain.lowerBound),
                yEnd: .value("Close", point.close)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(tint.opacity(style == .detailed ? 0.18 : 0.16))

            LineMark(
                x: .value("Date", point.date),
                y: .value("Close", point.close)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(tint)
            .lineStyle(
                StrokeStyle(
                    lineWidth: style == .detailed ? 3 : 2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            if style == .detailed, let selectedPoint, selectedPoint.id == point.id {
                RuleMark(x: .value("Date", point.date))
                    .foregroundStyle(tint.opacity(0.35))

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Close", point.close)
                )
                .foregroundStyle(tint)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: (points.first?.date ?? .now)...(points.last?.date ?? .now))
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .chartXAxis {
            AxisMarks(values: xAxisDates) { value in
                if style == .detailed {
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.08))
                }
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
            }
        }
        .chartYAxis {
            if style == .detailed {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.10))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        }
                    }
                    .font(.caption2)
                }
            } else {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Color.clear)
                }
            }
        }
        .chartOverlay { proxy in
            if style == .detailed {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 8)
                                    .onChanged { value in
                                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                                        guard let plotFrameAnchor = proxy.plotFrame else { return }
                                        let plotFrame = geometry[plotFrameAnchor]
                                        let xPosition = value.location.x - plotFrame.origin.x
                                        if let date: Date = proxy.value(atX: xPosition) {
                                            selectedPoint = nearestPoint(to: date)
                                        }
                                    }
                                    .onEnded { _ in
                                        selectedPoint = nil
                                    }
                            )

                        if let selectedPoint,
                           let plotFrameAnchor = proxy.plotFrame {
                            let plotFrame = geometry[plotFrameAnchor]
                            let xPosition = proxy.position(forX: selectedPoint.date) ?? plotFrame.minX
                            let yPosition = proxy.position(forY: selectedPoint.close) ?? plotFrame.minY
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedPoint.date, format: .dateTime.month(.abbreviated).day().year())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(selectedPoint.close, format: .currency(code: "USD"))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(6)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .position(
                                x: min(max(xPosition, plotFrame.minX + 70), plotFrame.maxX - 70),
                                y: max(plotFrame.minY + 14, yPosition - 24)
                            )
                        }
                    }
                }
            }
        }
        .frame(height: style == .detailed ? 220 : 56)
        .clipped()
    }

    private func nearestPoint(to date: Date) -> TickerPricePoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct GlassCard<Content: View>: View {
    let content: Content
    let padding: CGFloat

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

enum PlanHighlightSection: String, Identifiable, CaseIterable {
    case needs
    case wants
    case savings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needs:
            return "Needs"
        case .wants:
            return "Wants"
        case .savings:
            return "Savings"
        }
    }
}

struct PlanHighlightItem: Identifiable {
    let section: PlanHighlightSection
    var id: String { section.id }
    let title: String
    let systemImage: String
    let amount: Double
    let allocated: Double
    let tint: Color
}

struct PlanHighlightCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let amount: Double
    let allocated: Double

    private var progress: Double {
        guard amount > 0 else { return 0 }
        return min(allocated / amount, 1.0)
    }

    private var remaining: Double {
        max(amount - allocated, 0)
    }

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(tint)
                        .padding(8)
                        .background(tint.opacity(0.12), in: Circle())
                    Spacer()
                    Text(amount, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .minimumScaleFactor(0.8)
                }

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                ProgressView(value: progress)
                    .tint(tint)

                HStack {
                    Text("\(Int(progress * 100))% allocated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Left \(remaining, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundStyle(remaining > 0 ? Color.secondary : Color.red)
                }
            }
        }
    }
}

struct PressableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PlanHighlightMenuView: View {
    let section: PlanHighlightSection
    @ObservedObject var budget: BudgetModel
    let needsSpentByCategoryId: [UUID: Double]
    let wantsSpentByCategoryId: [UUID: Double]
    let onAdd: () -> Void
    let onEditCategory: (Category) -> Void
    let onDeleteCategory: (Category, BudgetSection) -> Void
    let onEditSavingsGoal: (SavingsGoal) -> Void
    let onDeleteSavingsGoal: (SavingsGoal) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Planned this month")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(sectionBudget, format: .currency(code: "USD"))
                                .font(.title3)
                                .fontWeight(.semibold)

                            BudgetBarView(
                                title: "\(section.title) Allocation",
                                allocated: sectionAllocated,
                                budget: sectionBudget,
                                color: sectionTint
                            )
                        }
                    }

                    if isEmpty {
                        GlassCard {
                            EmptyStateView(
                                title: "No items yet",
                                message: "Add your first \(section.title.lowercased()) item to start planning.",
                                systemImage: "tray",
                                tips: ["Tap + to add one."]
                            )
                        }
                    } else {
                        GlassCard(padding: 12) {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                switch section {
                                case .needs:
                                    ForEach(budget.needsCategories) { category in
                                        CategoryRowView(
                                            category: category,
                                            showLogDetails: true,
                                            onEdit: { onEditCategory(category) },
                                            onDelete: { onDeleteCategory(category, .needs) },
                                            onAddExpense: nil,
                                            onTap: nil,
                                            showRemaining: true,
                                            spentAmount: needsSpentByCategoryId[category.id] ?? 0
                                        )
                                    }
                                case .wants:
                                    ForEach(budget.wantsCategories) { category in
                                        CategoryRowView(
                                            category: category,
                                            showLogDetails: true,
                                            onEdit: { onEditCategory(category) },
                                            onDelete: { onDeleteCategory(category, .wants) },
                                            onAddExpense: nil,
                                            onTap: nil,
                                            showRemaining: true,
                                            spentAmount: wantsSpentByCategoryId[category.id] ?? 0
                                        )
                                    }
                                case .savings:
                                    ForEach(budget.savingsGoals) { goal in
                                        SavingsGoalRowView(
                                            goal: goal,
                                            onEdit: { onEditSavingsGoal(goal) },
                                            onDelete: { onDeleteSavingsGoal(goal) },
                                            onHistory: nil,
                                            onLog: nil,
                                            savedThisMonth: nil,
                                            showCurrentField: false,
                                            onCurrentChange: { _ in }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle(section.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add \(section.title)")
                }
            }
        }
    }

    private var sectionBudget: Double {
        switch section {
        case .needs:
            return budget.needsBudget
        case .wants:
            return budget.wantsBudget
        case .savings:
            return budget.savingsBudget
        }
    }

    private var sectionAllocated: Double {
        switch section {
        case .needs:
            return budget.totalNeedsAllocated
        case .wants:
            return budget.totalWantsAllocated
        case .savings:
            return budget.totalSavingsAllocated
        }
    }

    private var sectionTint: Color {
        switch section {
        case .needs:
            return .blue
        case .wants:
            return .orange
        case .savings:
            return .green
        }
    }

    private var isEmpty: Bool {
        switch section {
        case .needs:
            return budget.needsCategories.isEmpty
        case .wants:
            return budget.wantsCategories.isEmpty
        case .savings:
            return budget.savingsGoals.isEmpty
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    let tips: [String]
    let actionLabel: String?
    let action: (() -> Void)?

    init(
        title: String,
        message: String,
        systemImage: String,
        tips: [String],
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tips = tips
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !tips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tips, id: \.self) { tip in
                        Text("• \(tip)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BudgetBarView: View {
    let title: String
    let allocated: Double
    let budget: Double
    let color: Color
    
    var percentage: Double {
        guard budget > 0 else { return 0 }
        return min(allocated / budget, 1.0)
    }

    var rawPercentage: Double {
        guard budget > 0 else { return 0 }
        return allocated / budget
    }

    var overPercentage: Double {
        guard budget > 0 else { return 0 }
        return min(max(allocated / budget - 1.0, 0), 1.0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(allocated, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("/")
                    .foregroundColor(.secondary)
                Text(budget, format: .currency(code: "USD"))
                    .font(.subheadline)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray4).opacity(0.4))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * percentage, height: 8)
                        .cornerRadius(4)

                    if overPercentage > 0 {
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: geometry.size.width * overPercentage, height: 8)
                            .cornerRadius(4)
                            .offset(x: geometry.size.width - geometry.size.width * overPercentage)
                    }
                }
            }
            .frame(height: 8)
            
            HStack {
                Text("\(Int(rawPercentage * 100))% allocated")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if budget - allocated > 0 {
                    Text("Remaining: \(budget - allocated, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if allocated > budget {
                    Text("Over budget: \(allocated - budget, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

struct CategoryRowView: View {
    let category: Category
    let showLogDetails: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onAddExpense: (() -> Void)?
    let onTap: (() -> Void)?
    let showRemaining: Bool
    let spentAmount: Double
    let pillLabel: String
    let pillAmount: Double
    private var hasBudget: Bool { category.allocatedAmount > 0 }
    private var shouldShowPill: Bool {
        pillLabel != "Allocated" || pillAmount > 0 || hasBudget
    }

    private var progress: Double {
        guard hasBudget else { return 0 }
        return min(spentAmount / category.allocatedAmount, 1.0)
    }

    private var remainingAmount: Double {
        guard hasBudget else { return 0 }
        return category.allocatedAmount - spentAmount
    }
    
    init(
        category: Category,
        showLogDetails: Bool,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onAddExpense: (() -> Void)? = nil,
        onTap: (() -> Void)? = nil,
        showRemaining: Bool = true,
        spentAmount: Double? = nil,
        pillLabel: String = "Allocated",
        pillAmount: Double? = nil
    ) {
        self.category = category
        self.showLogDetails = showLogDetails
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onAddExpense = onAddExpense
        self.onTap = onTap
        self.showRemaining = showRemaining
        self.spentAmount = spentAmount ?? category.spentAmount
        self.pillLabel = pillLabel
        self.pillAmount = pillAmount ?? category.allocatedAmount
    }

    @State private var showingDeleteConfirm = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name)
                        .font(.headline)
                    Text("Allocated: \(category.allocatedAmount, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .opacity(hasBudget ? 1 : 0)
                        .accessibilityHidden(!hasBudget)
                }
                Spacer()
                Menu {
                    Button("Edit", action: onEdit)
                    Button("Delete", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Category actions")
            }

            if showLogDetails {
                HStack {
                    Text("Spent")
                        .font(.subheadline)
                    Spacer()
                    Text(spentAmount, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                if showRemaining {
                    HStack {
                        Text("Remaining:")
                            .font(.subheadline)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(remainingAmount, format: .currency(code: "USD"))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(remainingAmount >= 0 ? .green : .red)
                            if remainingAmount < 0 {
                                Text("Over budget")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .opacity(hasBudget ? 1 : 0)
                    .accessibilityHidden(!hasBudget)
                }
            } else {
                HStack {
                    Text(pillLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(pillAmount, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemFill), in: Capsule())
                }
                .opacity(shouldShowPill ? 1 : 0)
                .accessibilityHidden(!shouldShowPill)
            }

            ProgressView(value: progress) {
                Text("\(Int(progress * 100))% spent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tint(remainingAmount >= 0 ? .blue : .red)
            .opacity(hasBudget ? 1 : 0)
            .accessibilityHidden(!hasBudget)

            if let onAddExpense {
                Button(action: onAddExpense) {
                    Label("Log Expense", systemImage: "plus.circle")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hasBudget && remainingAmount < 0 ? Color.red.opacity(0.12) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .confirmationDialog(
            "Delete category?",
            isPresented: $showingDeleteConfirm
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

struct DailySpend: Identifiable {
    let id = UUID()
    let date: Date
    let amount: Double
}

struct CategorySummaryItem: Identifiable {
    let id = UUID()
    let name: String
    let spent: Double
    let tint: Color
}

struct CustomTabBar: View {
    enum CalendarQuickAction {
        case addCalendarEntry
        case transferCash
        case creditCards
    }

    @Binding var selectedTab: BudgetMode
    let minimized: Bool
    let onExpand: () -> Void
    let onAddExpense: () -> Void
    let onAddIncome: () -> Void
    let onCalendarQuickAction: (CalendarQuickAction) -> Void
    let onMarginQuickAction: (MarginQuickAction) -> Void

    var body: some View {
        HStack {
            if minimized {
                quickActionMenu(size: 38, includeShowTabs: true)
            } else {
                tabButton(.home, systemImage: "house.fill")
                Spacer()
                tabButton(.margin, systemImage: "chart.line.uptrend.xyaxis")
                Spacer()
                quickActionMenu(size: 42, includeShowTabs: false)
                Spacer()
                tabButton(.calendar, systemImage: "calendar")
                Spacer()
                tabButton(.budget, systemImage: "dollarsign")
            }
        }
        .padding(.horizontal, minimized ? 8 : 12)
        .padding(.vertical, minimized ? 8 : 8)
        .background(
            RoundedRectangle(cornerRadius: minimized ? 18 : 24, style: .continuous)
                .fill(CuanTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: minimized ? 18 : 24, style: .continuous)
                .stroke(CuanTheme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 10)
        .frame(maxWidth: minimized ? 56 : 356)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func quickActionMenu(size: CGFloat, includeShowTabs: Bool) -> some View {
        Menu {
            if selectedTab == .margin {
                Button("Add Transaction") { onMarginQuickAction(.addTransaction) }
                Button("Add Investment") { onMarginQuickAction(.addInvestment) }
                Button("Add Manual Holding") { onMarginQuickAction(.addManualHolding) }
                Button("Margin Settings") { onMarginQuickAction(.marginSettings) }
                Button("Activity Ledger") { onMarginQuickAction(.ledgerHistory) }
            } else if selectedTab == .calendar {
                Button("Add Calendar Entry") { onCalendarQuickAction(.addCalendarEntry) }
                Button("Transfer Cash") { onCalendarQuickAction(.transferCash) }
                Button("Credit Cards") { onCalendarQuickAction(.creditCards) }
            } else {
                Button(action: onAddExpense) {
                    Label("Add Expense", systemImage: "minus.circle")
                }
                Button(action: onAddIncome) {
                    Label("Add Income", systemImage: "plus.circle")
                }
                if selectedTab == .budget {
                    Button("Transfer Cash") { onCalendarQuickAction(.transferCash) }
                }
            }
            if includeShowTabs {
                Button("Show Tabs", action: onExpand)
            }
        } label: {
            Image(systemName: minimized ? "plus" : "plus")
                .font(.subheadline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(CuanTheme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, minimized ? 0 : 8)
        }
        .shadow(color: CuanTheme.primary.opacity(0.28), radius: minimized ? 0 : 10, x: 0, y: minimized ? 0 : 6)
        .accessibilityLabel("Quick add menu")
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if minimized {
                    onExpand()
                } else {
                    onExpand()
                }
            }
        )
    }

    private func tabButton(_ mode: BudgetMode, systemImage: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut) {
                selectedTab = mode
            }
        }) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                Text(mode.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(selectedTab == mode ? CuanTheme.primary : CuanTheme.muted)
            .frame(width: 56, height: 42)
            .background(selectedTab == mode ? CuanTheme.primary.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) tab")
    }
}

struct SavingsGoalRowView: View {
    let goal: SavingsGoal
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onHistory: (() -> Void)?
    let onLog: (() -> Void)?
    let savedThisMonth: Double?
    let showCurrentField: Bool
    let onCurrentChange: (Double) -> Void
    
    @State private var currentAmount: Double
    @State private var showingDeleteConfirm = false
    
    init(
        goal: SavingsGoal,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onHistory: (() -> Void)? = nil,
        onLog: (() -> Void)? = nil,
        savedThisMonth: Double? = nil,
        showCurrentField: Bool = true,
        onCurrentChange: @escaping (Double) -> Void
    ) {
        self.goal = goal
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onHistory = onHistory
        self.onLog = onLog
        self.savedThisMonth = savedThisMonth
        self.showCurrentField = showCurrentField
        self.onCurrentChange = onCurrentChange
        _currentAmount = State(initialValue: goal.currentAmount)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.displayName)
                        .font(.headline)
                    Text("Target: \(goal.targetAmount, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Monthly: \(goal.monthlyContribution, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            Spacer()
            Menu {
                if let onHistory {
                    Button("History", action: onHistory)
                }
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive) {
                    showingDeleteConfirm = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Savings goal actions")
            }
            
            if showCurrentField {
                HStack {
                    Text("Current:")
                        .font(.subheadline)
                    TextField("$0", value: $currentAmount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: currentAmount) { _, newValue in
                            onCurrentChange(newValue)
                        }
                        .onChange(of: goal.currentAmount) { _, newValue in
                            if abs(currentAmount - newValue) > 0.005 {
                                currentAmount = newValue
                            }
                        }
                }
            }

            if let savedThisMonth {
                HStack {
                    Text("Saved this month")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(savedThisMonth, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemFill), in: Capsule())
                }
            }
            
            ProgressView(value: goal.progress) {
                HStack {
                    Text("\(Int(goal.progress * 100))%")
                        .font(.caption)
                    Spacer()
                    Text("Remaining: \(goal.remaining, format: .currency(code: "USD"))")
                        .font(.caption)
                }
            }
            .tint(.green)

            if let onLog {
                Button(action: onLog) {
                    Label("Log Savings", systemImage: "plus.circle")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .confirmationDialog(
            "Delete savings goal?",
            isPresented: $showingDeleteConfirm
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

struct SummaryRowView: View {
    let title: String
    let amount: Double
    let budget: Double
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(amount, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if budget > 0 {
                    Text("of \(budget, format: .currency(code: "USD"))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct SummaryMetricCard: View {
    let title: String
    let amount: Double
    let budget: Double
    let color: Color

    private var progress: Double {
        guard budget > 0 else { return 0 }
        return min(amount / budget, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Text(amount, format: .currency(code: "USD"))
                .font(.headline)
                .fontWeight(.semibold)

            if budget > 0 {
                Text("of \(budget, format: .currency(code: "USD"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct ExpenseRowView: View {
    let expense: Expense
    let categoryName: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteConfirm = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.name)
                    .font(.subheadline)
                Text(categoryName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(expense.amount, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(expense.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive) {
                    showingDeleteConfirm = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Expense actions")
        }
        .confirmationDialog(
            "Delete expense?",
            isPresented: $showingDeleteConfirm
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

struct IncomeRowView: View {
    let income: IncomeEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteConfirm = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(income.name)
                    .font(.subheadline)
                Text(income.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !income.bankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(income.bankName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(income.amount, format: .currency(code: "USD"))
                .font(.subheadline)
                .fontWeight(.semibold)
            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive) {
                    showingDeleteConfirm = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Income actions")
        }
        .confirmationDialog(
            "Delete income?",
            isPresented: $showingDeleteConfirm
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

struct IncomeHistoryView: View {
    @ObservedObject var budget: BudgetModel
    let monthlyIncomes: [IncomeEntry]
    let onEdit: (IncomeEntry) -> Void
    let onDelete: (IncomeEntry) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var deleteCandidate: IncomeEntry?
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationView {
            List {
                if monthlyIncomes.isEmpty {
                    Text("No income entries this month.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monthlyIncomes.sorted(by: { $0.date > $1.date })) { income in
                        IncomeRowView(
                            income: income,
                            onEdit: { onEdit(income); dismiss() },
                            onDelete: { onDelete(income) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteCandidate = income
                                showingDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Income History")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Delete income?",
                isPresented: $showingDeleteConfirm,
                presenting: deleteCandidate
            ) { candidate in
                Button("Delete", role: .destructive) {
                    onDelete(candidate)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This cannot be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct ExpenseHistoryView: View {
    @ObservedObject var budget: BudgetModel
    let monthlyExpenses: [Expense]
    let onEdit: (Expense) -> Void
    let onDelete: (Expense) -> Void
    let title: String
    @Environment(\.dismiss) var dismiss
    @State private var deleteCandidate: Expense?
    @State private var showingDeleteConfirm = false

    init(
        budget: BudgetModel,
        monthlyExpenses: [Expense],
        onEdit: @escaping (Expense) -> Void,
        onDelete: @escaping (Expense) -> Void,
        title: String = "Expense History"
    ) {
        self.budget = budget
        self.monthlyExpenses = monthlyExpenses
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.title = title
    }

    var body: some View {
        NavigationView {
            List {
                if monthlyExpenses.isEmpty {
                    Text("No expenses this month.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monthlyExpenses.sorted(by: { $0.date > $1.date })) { expense in
                        ExpenseRowView(
                            expense: expense,
                            categoryName: budget.categoryName(for: expense),
                            onEdit: { onEdit(expense); dismiss() },
                            onDelete: { onDelete(expense) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteCandidate = expense
                                showingDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Delete expense?",
                isPresented: $showingDeleteConfirm,
                presenting: deleteCandidate
            ) { candidate in
                Button("Delete", role: .destructive) {
                    onDelete(candidate)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This cannot be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct SavingsEntryRowView: View {
    let entry: SavingsEntry
    let goalName: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showingDeleteConfirm = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name.isEmpty ? "Savings" : entry.name)
                    .font(.subheadline)
                Text(goalName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.amount, format: .currency(code: "USD"))
                .font(.subheadline)
                .fontWeight(.semibold)
            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive) {
                    showingDeleteConfirm = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Savings entry actions")
        }
        .confirmationDialog(
            "Delete savings entry?",
            isPresented: $showingDeleteConfirm
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

struct SavingsHistoryView: View {
    @ObservedObject var budget: BudgetModel
    let monthlySavings: [SavingsEntry]
    let onEdit: (SavingsEntry) -> Void
    let onDelete: (SavingsEntry) -> Void
    let title: String
    @Environment(\.dismiss) var dismiss
    @State private var deleteCandidate: SavingsEntry?
    @State private var showingDeleteConfirm = false

    init(
        budget: BudgetModel,
        monthlySavings: [SavingsEntry],
        onEdit: @escaping (SavingsEntry) -> Void,
        onDelete: @escaping (SavingsEntry) -> Void,
        title: String = "Savings History"
    ) {
        self.budget = budget
        self.monthlySavings = monthlySavings
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.title = title
    }

    var body: some View {
        NavigationView {
            List {
                if monthlySavings.isEmpty {
                    Text("No savings logged this month.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monthlySavings.sorted(by: { $0.date > $1.date })) { entry in
                        SavingsEntryRowView(
                            entry: entry,
                            goalName: budget.savingsGoalName(for: entry),
                            onEdit: { onEdit(entry); dismiss() },
                            onDelete: { onDelete(entry) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteCandidate = entry
                                showingDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Delete savings entry?",
                isPresented: $showingDeleteConfirm,
                presenting: deleteCandidate
            ) { candidate in
                Button("Delete", role: .destructive) {
                    onDelete(candidate)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This cannot be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add/Edit Views

enum CategoryType {
    case needs
    case wants
}

struct Haptics {
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

struct AddCategoryView: View {
    @ObservedObject var budget: BudgetModel
    let categoryType: CategoryType
    let selectedMonth: Date
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String = ""
    @State private var amount: Double = 0
    
    var availableBudget: Double {
        categoryType == .needs ? budget.needsRemaining : budget.wantsRemaining
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Category Name", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Category Details")
                } footer: {
                    Text("Available budget: \(availableBudget, format: .currency(code: "USD"))")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let category = Category(name: name, allocatedAmount: amount)
                        if categoryType == .needs {
                            withAnimation(.easeInOut) {
                                budget.needsCategories.append(category)
                            }
                            budget.setAllocation(amount, for: category.id, section: .needs, date: selectedMonth)
                        } else {
                            withAnimation(.easeInOut) {
                                budget.wantsCategories.append(category)
                            }
                            budget.setAllocation(amount, for: category.id, section: .wants, date: selectedMonth)
                        }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.isEmpty || amount <= 0)
                }
            }
        }
    }
}

struct EditCategoryView: View {
    @ObservedObject var budget: BudgetModel
    let category: Category
    let selectedMonth: Date
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String
    @State private var allocatedAmount: Double
    
    init(budget: BudgetModel, category: Category, selectedMonth: Date) {
        self.budget = budget
        self.category = category
        self.selectedMonth = selectedMonth
        _name = State(initialValue: category.name)
        _allocatedAmount = State(initialValue: category.allocatedAmount)
    }
    
    var isNeeds: Bool {
        budget.needsCategories.contains { $0.id == category.id }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Category Name", text: $name)
                    TextField("Allocated Amount", value: $allocatedAmount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Category Details")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isNeeds, let index = budget.needsCategories.firstIndex(where: { $0.id == category.id }) {
                            budget.needsCategories[index].name = name
                            budget.needsCategories[index].allocatedAmount = allocatedAmount
                            budget.setAllocation(allocatedAmount, for: category.id, section: .needs, date: selectedMonth)
                        } else if let index = budget.wantsCategories.firstIndex(where: { $0.id == category.id }) {
                            budget.wantsCategories[index].name = name
                            budget.wantsCategories[index].allocatedAmount = allocatedAmount
                            budget.setAllocation(allocatedAmount, for: category.id, section: .wants, date: selectedMonth)
                        }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.isEmpty || allocatedAmount < 0)
                }
            }
        }
    }
}

struct AddSavingsGoalView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String = ""
    @State private var targetAmount: Double = 0
    @State private var monthlyContribution: Double = 0
    
    var availableBudget: Double {
        budget.savingsRemaining
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Goal / Account Name", text: $name)
                    TextField("Target Amount", value: $targetAmount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    TextField("Monthly Contribution", value: $monthlyContribution, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Savings Goal Details")
                } footer: {
                    Text("Available savings budget: \(availableBudget, format: .currency(code: "USD"))")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Savings Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let goal = SavingsGoal(
                            name: name,
                            targetAmount: targetAmount,
                            currentAmount: 0,
                            monthlyContribution: monthlyContribution,
                            accountName: name
                        )
                        withAnimation(.easeInOut) {
                            budget.savingsGoals.append(goal)
                        }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.isEmpty || targetAmount <= 0 || monthlyContribution < 0)
                }
            }
        }
    }
}

struct EditSavingsGoalView: View {
    @ObservedObject var budget: BudgetModel
    let savingsGoal: SavingsGoal
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String
    @State private var targetAmount: Double
    @State private var currentAmount: Double
    @State private var monthlyContribution: Double
    
    init(budget: BudgetModel, savingsGoal: SavingsGoal) {
        self.budget = budget
        self.savingsGoal = savingsGoal
        _name = State(initialValue: savingsGoal.name)
        _targetAmount = State(initialValue: savingsGoal.targetAmount)
        _currentAmount = State(initialValue: savingsGoal.currentAmount)
        _monthlyContribution = State(initialValue: savingsGoal.monthlyContribution)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Goal / Account Name", text: $name)
                    TextField("Target Amount", value: $targetAmount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    TextField("Monthly Contribution", value: $monthlyContribution, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    TextField("Current Amount", value: $currentAmount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Savings Goal Details")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Savings Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let index = budget.savingsGoals.firstIndex(where: { $0.id == savingsGoal.id }) {
                            budget.savingsGoals[index].name = name
                            budget.savingsGoals[index].targetAmount = targetAmount
                            budget.savingsGoals[index].currentAmount = currentAmount
                            budget.savingsGoals[index].accountName = name
                            budget.savingsGoals[index].monthlyContribution = monthlyContribution
                        }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.isEmpty || targetAmount < 0 || currentAmount < 0 || monthlyContribution < 0)
                }
            }
        }
    }
}

struct AddExpenseView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var amount: Double = 0
    @State private var date: Date = Date()
    @State private var section: BudgetSection = .needs
    @State private var categoryId: UUID?
    @State private var useCustomCategory = false
    @State private var customCategoryName: String = ""
    @State private var paymentAccount: String = ""
    @State private var note: String = ""
    @State private var isCreditCardPayment = false
    @State private var targetCreditAccountName = ""

    private var categories: [Category] {
        section == .needs ? budget.needsCategories : budget.wantsCategories
    }

    private var paymentAccountOptions: [String] {
        let names = (budget.creditAccounts.map(\.name) + budget.bankAccounts.map(\.name) + [paymentAccount])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    private var bankPaymentAccountOptions: [String] {
        let names = (budget.bankAccounts.map(\.name) + [paymentAccount])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    private var creditCardOptions: [String] {
        budget.creditAccounts
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private func creditCardPaymentCategoryId() -> UUID {
        let paymentCategoryName = "Credit Card Payment"
        if let existing = budget.needsCategories.first(where: { $0.name.caseInsensitiveCompare(paymentCategoryName) == .orderedSame }) {
            return existing.id
        }
        let newCategory = Category(name: paymentCategoryName, allocatedAmount: 0)
        budget.needsCategories.append(newCategory)
        return newCategory.id
    }

    private let preselectedSection: BudgetSection
    private let preselectedCategoryId: UUID?
    private let onSave: ((Expense) -> Void)?

    init(
        budget: BudgetModel,
        preselectedSection: BudgetSection = .needs,
        preselectedCategoryId: UUID? = nil,
        onSave: ((Expense) -> Void)? = nil
    ) {
        self.budget = budget
        self.preselectedSection = preselectedSection
        self.preselectedCategoryId = preselectedCategoryId
        self.onSave = onSave
        _section = State(initialValue: preselectedSection)
        _categoryId = State(initialValue: preselectedCategoryId)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Description", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Section", selection: $section) {
                        ForEach(BudgetSection.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    if section == .wants && categories.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Quick add popular wants")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let defaults = ["Dining Out", "Entertainment", "Shopping", "Travel"]
                            ForEach(defaults, id: \.self) { title in
                                Button(title) {
                                    let newCategory = Category(name: title, allocatedAmount: 0)
                                    budget.wantsCategories.append(newCategory)
                                    categoryId = newCategory.id
                                }
                                .font(.caption)
                            }
                        }
                    }

                    Toggle("Credit Card Payment", isOn: $isCreditCardPayment)
                    if isCreditCardPayment {
                        if creditCardOptions.isEmpty {
                            Text("Add a credit card in Credit Accounts first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Apply to card", selection: $targetCreditAccountName) {
                                ForEach(creditCardOptions, id: \.self) { accountName in
                                    Text(accountName).tag(accountName)
                                }
                            }
                        }
                    } else {
                        Toggle("Other category", isOn: $useCustomCategory)

                        if useCustomCategory {
                            TextField("Custom category", text: $customCategoryName)
                        } else if categories.isEmpty {
                            Text("Add a category in Plan Mode first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Category", selection: $categoryId) {
                                ForEach(categories) { category in
                                    Text(category.name).tag(Optional(category.id))
                                }
                            }
                        }
                    }
                    Picker(isCreditCardPayment ? "Pay from" : "Paid with", selection: $paymentAccount) {
                        Text("None").tag("")
                        ForEach(isCreditCardPayment ? bankPaymentAccountOptions : paymentAccountOptions, id: \.self) { accountName in
                            Text(accountName).tag(accountName)
                        }
                    }
                    TextField("Note", text: $note, axis: .vertical)
                } header: {
                    Text("Expense Details")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                section = preselectedSection
                useCustomCategory = false
                customCategoryName = ""
                if let preselectedCategoryId, categories.contains(where: { $0.id == preselectedCategoryId }) {
                    categoryId = preselectedCategoryId
                } else {
                    categoryId = categories.first?.id
                }
                if targetCreditAccountName.isEmpty {
                    targetCreditAccountName = creditCardOptions.first ?? ""
                }
            }
            .onChange(of: section) { _, _ in
                if let categoryId, categories.contains(where: { $0.id == categoryId }) {
                    return
                }
                categoryId = categories.first?.id
                useCustomCategory = false
                customCategoryName = ""
            }
            .onChange(of: isCreditCardPayment) { _, newValue in
                if newValue && targetCreditAccountName.isEmpty {
                    targetCreditAccountName = creditCardOptions.first ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let resolvedCategoryId: UUID?
                        if isCreditCardPayment {
                            guard !targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            resolvedCategoryId = creditCardPaymentCategoryId()
                        } else if useCustomCategory {
                            let trimmed = customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let newCategory = Category(name: trimmed, allocatedAmount: 0)
                            if section == .needs {
                                budget.needsCategories.append(newCategory)
                            } else {
                                budget.wantsCategories.append(newCategory)
                            }
                            resolvedCategoryId = newCategory.id
                        } else {
                            resolvedCategoryId = categoryId
                        }

                        guard let categoryId = resolvedCategoryId else { return }
                        let expense = Expense(
	                            name: name,
	                            amount: amount,
	                            date: date,
	                            section: isCreditCardPayment ? .needs : section,
	                            categoryId: categoryId,
	                            paymentAccount: paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines),
	                            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
	                            creditCardPaymentTarget: isCreditCardPayment ? targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
	                        )
                        withAnimation(.easeInOut) {
                            budget.addExpense(expense)
                        }
                        onSave?(expense)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.isEmpty || amount <= 0 || (!isCreditCardPayment && !useCustomCategory && categoryId == nil) || (isCreditCardPayment && targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
    }
}

struct AddSavingsEntryView: View {
    @ObservedObject var budget: BudgetModel
    let selectedMonth: Date
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var amount: Double = 0
    @State private var date: Date = Date()
    @State private var goalId: UUID?

    private let preselectedGoalId: UUID?

    private var monthInterval: DateInterval? {
        Calendar.current.dateInterval(of: .month, for: selectedMonth)
    }

    private var defaultDate: Date {
        guard let interval = monthInterval else { return Date() }
        if Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month) {
            return Date()
        }
        return interval.start
    }

    init(
        budget: BudgetModel,
        selectedMonth: Date,
        preselectedGoalId: UUID? = nil
    ) {
        self.budget = budget
        self.selectedMonth = selectedMonth
        self.preselectedGoalId = preselectedGoalId
        _goalId = State(initialValue: preselectedGoalId)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Description", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    if budget.savingsGoals.isEmpty {
                        Text("Add a savings goal in Plan Mode first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Goal", selection: $goalId) {
                            ForEach(budget.savingsGoals) { goal in
                                Text(goal.displayName).tag(Optional(goal.id))
                            }
                        }
                    }
                } header: {
                    Text("Savings Details")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Log Savings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                date = defaultDate
                if let selectedGoalId = goalId, budget.savingsGoals.contains(where: { $0.id == selectedGoalId }) {
                    return
                }
                goalId = budget.savingsGoals.first?.id
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let goalId else { return }
                        let entry = SavingsEntry(
                            name: name.isEmpty ? "Savings" : name,
                            amount: amount,
                            date: date,
                            goalId: goalId
                        )
                        withAnimation(.easeInOut) {
                            budget.addSavingsEntry(entry)
                        }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(amount <= 0 || goalId == nil)
                }
            }
        }
    }
}

struct AddIncomeView: View {
    @ObservedObject var budget: BudgetModel
    let selectedMonth: Date
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var amount: Double = 0
    @State private var date: Date = Date()
    @State private var bankName: String = ""

    private var bankAccountOptions: [String] {
        let names = (budget.bankAccounts.map(\.name) + [bankName])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    private var monthInterval: DateInterval? {
        Calendar.current.dateInterval(of: .month, for: selectedMonth)
    }

    private var defaultDate: Date {
        guard let interval = monthInterval else { return Date() }
        if Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month) {
            return Date()
        }
        return interval.start
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Description", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Bank Account", text: $bankName)
                    if !bankAccountOptions.isEmpty {
                        Picker("Saved Accounts", selection: $bankName) {
                            Text("None").tag("")
                            ForEach(bankAccountOptions, id: \.self) { accountName in
                                Text(accountName).tag(accountName)
                            }
                        }
                    }
                } header: {
                    Text("Income Details")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Income")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                date = defaultDate
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let entry = IncomeEntry(
                            name: name.isEmpty ? "Income" : name,
                            amount: amount,
                            date: date,
                            bankName: bankName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        withAnimation(.easeInOut) {
                            budget.addIncomeEntry(entry)
                        }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
    }
}

struct EditIncomeView: View {
    @ObservedObject var budget: BudgetModel
    let income: IncomeEntry
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var amount: Double
    @State private var date: Date
    @State private var bankName: String

    private var bankAccountOptions: [String] {
        let names = (budget.bankAccounts.map(\.name) + [bankName])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    init(budget: BudgetModel, income: IncomeEntry) {
        self.budget = budget
        self.income = income
        _name = State(initialValue: income.name)
        _amount = State(initialValue: income.amount)
        _date = State(initialValue: income.date)
        _bankName = State(initialValue: income.bankName)
    }

    private var entryTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Edit Income" : trimmed
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Description", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Bank Account", text: $bankName)
                    if !bankAccountOptions.isEmpty {
                        Picker("Saved Accounts", selection: $bankName) {
                            Text("None").tag("")
                            ForEach(bankAccountOptions, id: \.self) { accountName in
                                Text(accountName).tag(accountName)
                            }
                        }
                    }
                } header: {
                    Text("Income Details")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(entryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        budget.updateIncomeEntry(
                            IncomeEntry(
                                id: income.id,
                                name: name.isEmpty ? "Income" : name,
                                amount: amount,
                                date: date,
                                bankName: bankName.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        )
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
    }
}

struct EditExpenseView: View {
    @ObservedObject var budget: BudgetModel
    let expense: Expense
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var amount: Double
    @State private var date: Date
    @State private var section: BudgetSection
    @State private var categoryId: UUID?
    @State private var useCustomCategory = false
    @State private var customCategoryName: String = ""
    @State private var paymentAccount: String
    @State private var note: String
    @State private var isCreditCardPayment: Bool
    @State private var targetCreditAccountName: String

    private var categories: [Category] {
        section == .needs ? budget.needsCategories : budget.wantsCategories
    }

    private var paymentAccountOptions: [String] {
        let names = (budget.creditAccounts.map(\.name) + budget.bankAccounts.map(\.name) + [paymentAccount])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    private var bankPaymentAccountOptions: [String] {
        let names = (budget.bankAccounts.map(\.name) + [paymentAccount])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    private var creditCardOptions: [String] {
        budget.creditAccounts
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private func creditCardPaymentCategoryId() -> UUID {
        let paymentCategoryName = "Credit Card Payment"
        if let existing = budget.needsCategories.first(where: { $0.name.caseInsensitiveCompare(paymentCategoryName) == .orderedSame }) {
            return existing.id
        }
        let newCategory = Category(name: paymentCategoryName, allocatedAmount: 0)
        budget.needsCategories.append(newCategory)
        return newCategory.id
    }

    init(budget: BudgetModel, expense: Expense) {
        self.budget = budget
        self.expense = expense
        _name = State(initialValue: expense.name)
        _amount = State(initialValue: expense.amount)
        _date = State(initialValue: expense.date)
        _section = State(initialValue: expense.section)
        _categoryId = State(initialValue: expense.categoryId)
        _paymentAccount = State(initialValue: expense.paymentAccount)
        _note = State(initialValue: expense.note)
        let target = budget.creditCardPaymentTarget(for: expense) ?? ""
        _isCreditCardPayment = State(initialValue: !target.isEmpty)
        _targetCreditAccountName = State(initialValue: target)
    }

    private var entryTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Edit Expense" : trimmed
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Description", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Section", selection: $section) {
                        ForEach(BudgetSection.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Toggle("Credit Card Payment", isOn: $isCreditCardPayment)
                    if isCreditCardPayment {
                        if creditCardOptions.isEmpty {
                            Text("Add a credit card in Credit Accounts first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Apply to card", selection: $targetCreditAccountName) {
                                ForEach(creditCardOptions, id: \.self) { accountName in
                                    Text(accountName).tag(accountName)
                                }
                            }
                        }
                    } else {
                        Toggle("Other category", isOn: $useCustomCategory)

                        if useCustomCategory {
                            TextField("Custom category", text: $customCategoryName)
                        } else if categories.isEmpty {
                            Text("Add a category in Plan Mode first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Category", selection: $categoryId) {
                                ForEach(categories) { category in
                                    Text(category.name).tag(Optional(category.id))
                                }
                            }
                        }
                    }
                    Picker(isCreditCardPayment ? "Pay from" : "Paid with", selection: $paymentAccount) {
                        Text("None").tag("")
                        ForEach(isCreditCardPayment ? bankPaymentAccountOptions : paymentAccountOptions, id: \.self) { accountName in
                            Text(accountName).tag(accountName)
                        }
                    }
                    TextField("Note", text: $note, axis: .vertical)
                } header: {
                    Text("Expense Details")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(entryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: section) { _, _ in
                categoryId = categories.first?.id
                useCustomCategory = false
                customCategoryName = ""
            }
            .onAppear {
                if isCreditCardPayment && targetCreditAccountName.isEmpty {
                    targetCreditAccountName = creditCardOptions.first ?? ""
                }
            }
            .onChange(of: isCreditCardPayment) { _, newValue in
                if newValue && targetCreditAccountName.isEmpty {
                    targetCreditAccountName = creditCardOptions.first ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let resolvedCategoryId: UUID?
                        if isCreditCardPayment {
                            guard !targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            resolvedCategoryId = creditCardPaymentCategoryId()
                        } else if useCustomCategory {
                            let trimmed = customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let newCategory = Category(name: trimmed, allocatedAmount: 0)
                            if section == .needs {
                                budget.needsCategories.append(newCategory)
                            } else {
                                budget.wantsCategories.append(newCategory)
                            }
                            resolvedCategoryId = newCategory.id
                        } else {
                            resolvedCategoryId = categoryId
                        }

                        guard let categoryId = resolvedCategoryId else { return }
                        budget.updateExpense(
                            Expense(
                                id: expense.id,
                                name: name,
                                amount: amount,
                                date: date,
                                section: isCreditCardPayment ? .needs : section,
                                categoryId: categoryId,
                                paymentAccount: paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines),
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                creditCardPaymentTarget: isCreditCardPayment ? targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                            )
                        )
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.isEmpty || amount <= 0 || (!isCreditCardPayment && !useCustomCategory && categoryId == nil) || (isCreditCardPayment && targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
    }
}

struct EditSavingsEntryView: View {
    @ObservedObject var budget: BudgetModel
    let savingsEntry: SavingsEntry
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var amount: Double
    @State private var date: Date
    @State private var goalId: UUID?

    init(budget: BudgetModel, savingsEntry: SavingsEntry) {
        self.budget = budget
        self.savingsEntry = savingsEntry
        _name = State(initialValue: savingsEntry.name)
        _amount = State(initialValue: savingsEntry.amount)
        _date = State(initialValue: savingsEntry.date)
        _goalId = State(initialValue: savingsEntry.goalId)
    }

    private var entryTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Edit Savings" : trimmed
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Description", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Goal", selection: $goalId) {
                        ForEach(budget.savingsGoals) { goal in
                            Text(goal.displayName).tag(Optional(goal.id))
                        }
                    }
                } header: {
                    Text("Savings Details")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(entryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let goalId else { return }
                        let updatedEntry = SavingsEntry(
                            id: savingsEntry.id,
                            name: name,
                            amount: amount,
                            date: date,
                            goalId: goalId
                        )
                        budget.updateSavingsEntry(updatedEntry)

                        Haptics.success()
                        dismiss()
                    }
                    .disabled(amount <= 0 || goalId == nil)
                }
            }
        }
    }
}

struct CalendarEntryEditorView: View {
    @ObservedObject var budget: BudgetModel
    var selectedDate: Date
    var existingRecurringPayment: RecurringPayment?
    @Environment(\.dismiss) private var dismiss

    private enum EntryMode: String, CaseIterable, Identifiable {
        case recurring = "Recurring"
        case oneTime = "One-Time"
        var id: String { rawValue }
    }

    @State private var name: String
    @State private var amount: Double
    @State private var date: Date
    @State private var mode: EntryMode
    @State private var kind: RecurringPaymentKind
    @State private var isActive: Bool
    @State private var section: BudgetSection = .needs
    @State private var categoryId: UUID?
    @State private var useCustomCategory = false
    @State private var customCategoryName = ""
    @State private var paymentAccount = ""
    @State private var isCreditCardPayment = false
    @State private var targetCreditAccountName = ""
    @State private var note = ""

    private var categories: [Category] {
        section == .needs ? budget.needsCategories : budget.wantsCategories
    }

    private var paymentAccountOptions: [String] {
        let names = (budget.creditAccounts.map(\.name) + budget.bankAccounts.map(\.name) + [paymentAccount])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    private var bankPaymentAccountOptions: [String] {
        let names = (budget.bankAccounts.map(\.name) + [paymentAccount])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    private var creditCardOptions: [String] {
        budget.creditAccounts
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private static func userNoteWithoutCreditCardPaymentMarker(_ note: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[CC_PAYMENT:"),
              let endIndex = trimmed.firstIndex(of: "]") else {
            return trimmed
        }
        let afterMarker = trimmed.index(after: endIndex)
        return String(trimmed[afterMarker...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func creditCardPaymentTarget(from note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[CC_PAYMENT:"),
              let endIndex = trimmed.firstIndex(of: "]") else {
            return nil
        }
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 12)
        guard startIndex < endIndex else { return nil }
        let accountName = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return accountName.isEmpty ? nil : accountName
    }

    private func markedCreditCardPaymentNote(targetCard: String) -> String {
        let prefix = "[CC_PAYMENT:\(targetCard.trimmingCharacters(in: .whitespacesAndNewlines))]"
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNote.isEmpty ? prefix : "\(prefix)\n\(trimmedNote)"
    }

    init(
        budget: BudgetModel,
        selectedDate: Date,
        existingRecurringPayment: RecurringPayment? = nil
    ) {
        self.budget = budget
        self.selectedDate = selectedDate
        self.existingRecurringPayment = existingRecurringPayment
        let existingNote = existingRecurringPayment?.note ?? ""
        let existingTargetCard = existingRecurringPayment?.creditCardPaymentTarget
            ?? (existingNote.isEmpty ? nil : Self.creditCardPaymentTarget(from: existingNote))
            ?? ""
        _name = State(initialValue: existingRecurringPayment?.name ?? "")
        _amount = State(initialValue: existingRecurringPayment?.amount ?? 0)
        _date = State(initialValue: existingRecurringPayment?.startDate ?? selectedDate)
        _mode = State(initialValue: existingRecurringPayment == nil ? .oneTime : .recurring)
        _kind = State(initialValue: existingRecurringPayment?.kind ?? .expense)
        _isActive = State(initialValue: existingRecurringPayment?.isActive ?? true)
        _section = State(initialValue: existingRecurringPayment?.section ?? .needs)
        _categoryId = State(initialValue: existingRecurringPayment?.categoryId ?? budget.needsCategories.first?.id)
        _paymentAccount = State(initialValue: existingRecurringPayment?.paymentAccount ?? "")
        _isCreditCardPayment = State(initialValue: !existingTargetCard.isEmpty)
        _targetCreditAccountName = State(initialValue: existingTargetCard)
        _note = State(initialValue: Self.userNoteWithoutCreditCardPaymentMarker(existingNote))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    if existingRecurringPayment == nil {
                        Picker("Mode", selection: $mode) {
                            ForEach(EntryMode.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("Kind", selection: $kind) {
                        Text("Expense").tag(RecurringPaymentKind.expense)
                        Text("Income").tag(RecurringPaymentKind.income)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    DatePicker(
                        mode == .recurring || existingRecurringPayment != nil ? "Start date" : "Date",
                        selection: $date,
                        displayedComponents: .date
                    )
                }

                Section(kind == .expense ? "Payment" : "Account") {
                    if kind == .expense {
                        Toggle("Credit card payment", isOn: $isCreditCardPayment)

                        if isCreditCardPayment {
                            if creditCardOptions.isEmpty {
                                Text("Add a credit card in Credit Accounts first.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("Apply to card", selection: $targetCreditAccountName) {
                                    ForEach(creditCardOptions, id: \.self) { accountName in
                                        Text(accountName).tag(accountName)
                                    }
                                }
                            }
                            Picker("Pay from", selection: $paymentAccount) {
                                Text("None").tag("")
                                ForEach(bankPaymentAccountOptions, id: \.self) { accountName in
                                    Text(accountName).tag(accountName)
                                }
                            }
                        } else {
                            Picker("Section", selection: $section) {
                                ForEach(BudgetSection.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }

                            if categories.isEmpty {
                                Text("Add a category in Plan first.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Category name", text: $customCategoryName)
                            } else {
                                Picker("Category", selection: $categoryId) {
                                    ForEach(categories) { category in
                                        Text(category.name).tag(Optional(category.id))
                                    }
                                }
                                Toggle("Custom category", isOn: $useCustomCategory)
                                if useCustomCategory {
                                    TextField("Category name", text: $customCategoryName)
                                }
                            }

                            Picker("Paid with", selection: $paymentAccount) {
                                Text("None").tag("")
                                ForEach(paymentAccountOptions, id: \.self) { accountName in
                                    Text(accountName).tag(accountName)
                                }
                            }
                        }
                    } else {
                        Picker("Deposit to", selection: $paymentAccount) {
                            Text("None").tag("")
                            ForEach(paymentAccountOptions, id: \.self) { accountName in
                                Text(accountName).tag(accountName)
                            }
                        }
                    }
                }

                Section("Note") {
                    TextField("Note", text: $note, axis: .vertical)
                }

                if mode == .recurring || existingRecurringPayment != nil {
                    Section {
                        Toggle("Active", isOn: $isActive)
                    }
                }
            }
            .navigationTitle(existingRecurringPayment == nil ? "Add Calendar Entry" : "Edit Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: section) { _, _ in
                categoryId = categories.first?.id
                useCustomCategory = false
                customCategoryName = ""
            }
            .onAppear {
                if targetCreditAccountName.isEmpty {
                    targetCreditAccountName = creditCardOptions.first ?? ""
                }
            }
            .onChange(of: isCreditCardPayment) { _, newValue in
                if newValue && targetCreditAccountName.isEmpty {
                    targetCreditAccountName = creditCardOptions.first ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty, amount > 0 else { return }

                        if mode == .recurring || existingRecurringPayment != nil {
                            let day = Calendar.current.component(.day, from: date)
                            let resolvedRecurringCategoryId: UUID?
                            if kind == .expense {
                                if isCreditCardPayment {
                                    let normalized = targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !normalized.isEmpty else { return }
                                    let paymentCategoryName = "Credit Card Payment"
                                    if let existing = budget.needsCategories.first(where: { $0.name.caseInsensitiveCompare(paymentCategoryName) == .orderedSame }) {
                                        resolvedRecurringCategoryId = existing.id
                                    } else {
                                        let newCategory = Category(name: paymentCategoryName, allocatedAmount: 0)
                                        budget.needsCategories.append(newCategory)
                                        resolvedRecurringCategoryId = newCategory.id
                                    }
                                    section = .needs
                                } else if useCustomCategory {
                                    let custom = customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !custom.isEmpty else { return }
                                    let newCategory = Category(name: custom, allocatedAmount: 0)
                                    if section == .needs {
                                        budget.needsCategories.append(newCategory)
                                    } else {
                                        budget.wantsCategories.append(newCategory)
                                    }
                                    resolvedRecurringCategoryId = newCategory.id
                                } else {
                                    resolvedRecurringCategoryId = categoryId
                                }
                            } else {
                                resolvedRecurringCategoryId = nil
                            }

                            let payment = RecurringPayment(
                                id: existingRecurringPayment?.id ?? UUID(),
                                name: trimmedName,
                                amount: amount,
                                dayOfMonth: day,
                                startDate: date,
                                kind: kind,
                                isActive: isActive
                                ,
                                paidOccurrenceKeys: existingRecurringPayment?.paidOccurrenceKeys ?? [],
                                section: (kind == .expense && isCreditCardPayment) ? .needs : section,
                                categoryId: resolvedRecurringCategoryId,
                                paymentAccount: paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines),
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                creditCardPaymentTarget: (kind == .expense && isCreditCardPayment) ? targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                            )
                            if let index = budget.recurringPayments.firstIndex(where: { $0.id == payment.id }) {
                                budget.recurringPayments[index] = payment
                            } else {
                                budget.recurringPayments.append(payment)
                            }
                        } else if kind == .income {
                            budget.addIncomeEntry(
                                IncomeEntry(
                                    name: trimmedName,
                                    amount: amount,
                                    date: date,
                                    bankName: paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines)
                                )
                            )
                        } else {
                            let resolvedCategoryId: UUID?
                            if isCreditCardPayment {
                                let normalized = targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !normalized.isEmpty else { return }
                                let paymentCategoryName = "Credit Card Payment"
                                if let existing = budget.needsCategories.first(where: { $0.name.caseInsensitiveCompare(paymentCategoryName) == .orderedSame }) {
                                    resolvedCategoryId = existing.id
                                } else {
                                    let newCategory = Category(name: paymentCategoryName, allocatedAmount: 0)
                                    budget.needsCategories.append(newCategory)
                                    resolvedCategoryId = newCategory.id
                                }
                            } else if useCustomCategory {
                                let custom = customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !custom.isEmpty else { return }
                                let newCategory = Category(name: custom, allocatedAmount: 0)
                                if section == .needs {
                                    budget.needsCategories.append(newCategory)
                                } else {
                                    budget.wantsCategories.append(newCategory)
                                }
                                resolvedCategoryId = newCategory.id
                            } else {
                                resolvedCategoryId = categoryId
                            }
                            guard let resolvedCategoryId else { return }
                            budget.addExpense(
                                Expense(
                                    name: trimmedName,
                                    amount: amount,
                                    date: date,
                                    section: isCreditCardPayment ? .needs : section,
                                    categoryId: resolvedCategoryId
                                    ,
                                    paymentAccount: paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines),
                                    note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                    creditCardPaymentTarget: isCreditCardPayment ? targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                                )
                            )
                        }

                        Haptics.success()
                        dismiss()
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        amount <= 0 ||
                        (kind == .expense && !isCreditCardPayment && !useCustomCategory && categoryId == nil) ||
                        (kind == .expense && isCreditCardPayment && targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                }
            }
        }
    }
}

struct CreditAccountsView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddAccount = false

    private func actualBalance(for account: CreditAccount) -> Double {
        if account.plaidMetadata != nil {
            return account.startingBalance
        }
        let normalizedAccountName = account.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAccountName.isEmpty else { return 0 }
        return budget.expenses.reduce(account.startingBalance) { partial, expense in
            if let paidCard = budget.creditCardPaymentTarget(for: expense),
               paidCard.caseInsensitiveCompare(account.name) == .orderedSame {
                return partial - expense.amount
            }
            let paymentAccount = expense.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard paymentAccount == normalizedAccountName else { return partial }
            return partial + expense.amount
        }
    }

    private func utilization(for account: CreditAccount) -> Double {
        guard account.creditLimit > 0 else { return 0 }
        return max(0, actualBalance(for: account) / account.creditLimit)
    }

    private func creditCardPaymentTarget(from note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[CC_PAYMENT:") else { return nil }
        guard let endIndex = trimmed.firstIndex(of: "]") else { return nil }
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 12)
        guard startIndex < endIndex else { return nil }
        let accountName = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return accountName.isEmpty ? nil : accountName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Add") {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Label("Add Credit Account", systemImage: "plus.circle")
                    }
                }

                Section("Accounts") {
                    if budget.creditAccounts.isEmpty {
                        Text("No accounts added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($budget.creditAccounts) { $account in
                            NavigationLink {
                                EditCreditAccountView(account: $account)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(account.name)
                                        .font(.headline)
                                    Text("Closing: \(account.closingDay)  Due: \(account.dueDay)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("Actual: \(actualBalance(for: account), format: .currency(code: "USD"))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("Utilization: \(utilization(for: account) * 100, specifier: "%.1f")%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            budget.creditAccounts.remove(atOffsets: offsets)
                        }
                    }
                }
            }
            .navigationTitle("Credit Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddCreditAccountView(budget: budget)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

struct AddCreditAccountView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var closingDay: Int = 1
    @State private var dueDay: Int = 1
    @State private var startingBalance: Double = 0
    @State private var creditLimit: Double = 0
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Details") {
                    LabeledContent("Account Name") {
                        TextField("Account name", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Closing Day") {
                        TextField("1-31", value: $closingDay, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Due Day") {
                        TextField("1-31", value: $dueDay, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Balances") {
                    LabeledContent("Starting Balance") {
                        TextField("0.00", value: $startingBalance, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Total Credit Limit") {
                        TextField("0.00", value: $creditLimit, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Notes") {
                    TextField("Optional note", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Add Credit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        budget.creditAccounts.append(
                            CreditAccount(
                                name: trimmed,
                                closingDay: min(max(closingDay, 1), 31),
                                dueDay: min(max(dueDay, 1), 31),
                                startingBalance: startingBalance,
                                creditLimit: max(creditLimit, 0),
                                isActive: true,
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        )
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct EditCreditAccountView: View {
    @Binding var account: CreditAccount

    var body: some View {
        Form {
            Section("Account Details") {
                LabeledContent("Account Name") {
                    TextField("Account name", text: $account.name)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Closing Day") {
                    TextField(
                        "1-31",
                        value: Binding(
                            get: { account.closingDay },
                            set: { account.closingDay = min(max($0, 1), 31) }
                        ),
                        format: .number
                    )
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                }
                LabeledContent("Due Day") {
                    TextField(
                        "1-31",
                        value: Binding(
                            get: { account.dueDay },
                            set: { account.dueDay = min(max($0, 1), 31) }
                        ),
                        format: .number
                    )
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                }
                Toggle("Active", isOn: $account.isActive)
            }

            Section("Balances") {
                LabeledContent("Starting Balance") {
                    TextField(
                        "0.00",
                        value: $account.startingBalance,
                        format: .currency(code: "USD")
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }
                LabeledContent("Total Credit Limit") {
                    TextField(
                        "0.00",
                        value: Binding(
                            get: { account.creditLimit },
                            set: { account.creditLimit = max($0, 0) }
                        ),
                        format: .currency(code: "USD")
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }
            }

            Section("Notes") {
                TextField("Optional note", text: $account.note, axis: .vertical)
            }
        }
        .navigationTitle("Edit Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CreditAccountDetailView: View {
    let account: CreditAccount
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss

    private var actualBalance: Double {
        if account.plaidMetadata != nil {
            return account.startingBalance
        }
        let normalizedAccountName = account.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAccountName.isEmpty else { return 0 }
        return budget.expenses.reduce(account.startingBalance) { partial, expense in
            if let paidCard = budget.creditCardPaymentTarget(for: expense),
               paidCard.caseInsensitiveCompare(account.name) == .orderedSame {
                return partial - expense.amount
            }
            let paymentAccount = expense.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard paymentAccount == normalizedAccountName else { return partial }
            return partial + expense.amount
        }
    }

    private func creditCardPaymentTarget(from note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[CC_PAYMENT:") else { return nil }
        guard let endIndex = trimmed.firstIndex(of: "]") else { return nil }
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 12)
        guard startIndex < endIndex else { return nil }
        let accountName = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return accountName.isEmpty ? nil : accountName
    }

    private var utilization: Double {
        guard account.creditLimit > 0 else { return 0 }
        return max(0, actualBalance / account.creditLimit)
    }

    private var transactionHistory: [(date: Date, name: String, amount: Double)] {
        let normalizedAccountName = account.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAccountName.isEmpty else { return [] }

        var entries: [(Date, String, Double)] = budget.expenses.compactMap { expense in
            let expenseAccount = expense.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard expenseAccount == normalizedAccountName else { return nil }
            return (expense.date, expense.name, expense.amount)
        }

        entries.append(contentsOf: budget.expenses.compactMap { expense in
            guard let paidCard = budget.creditCardPaymentTarget(for: expense),
                  paidCard.caseInsensitiveCompare(account.name) == .orderedSame else {
                return nil
            }
            return (expense.date, "Payment: \(expense.name)", -expense.amount)
        })

        return entries.sorted(by: { $0.0 > $1.0 })
    }

    var body: some View {
        NavigationStack {
            List {
                HStack {
                    Text("Account")
                    Spacer()
                    Text(account.name)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Closing day")
                    Spacer()
                    Text("\(account.closingDay)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Due day")
                    Spacer()
                    Text("\(account.dueDay)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Actual balance")
                    Spacer()
                    Text(actualBalance, format: .currency(code: "USD"))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Total credit limit")
                    Spacer()
                    Text(account.creditLimit, format: .currency(code: "USD"))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Utilization")
                    Spacer()
                    Text("\(utilization * 100, specifier: "%.1f")%")
                        .foregroundStyle(utilization >= 0.8 ? .red : .secondary)
                }

                Section("Transaction History") {
                    if transactionHistory.isEmpty {
                        Text("No transactions found for this card yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(transactionHistory.prefix(40).enumerated()), id: \.offset) { _, item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline)
                                    Text(item.date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.amount, format: .currency(code: "USD"))
                                    .font(.subheadline)
                                    .foregroundStyle(item.amount < 0 ? .green : .primary)
                            }
                        }
                    }
                }
                if !account.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note")
                        Text(account.note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Card Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct PortfolioTransactionDetailView: View {
    let transaction: PortfolioTransaction
    @Environment(\.dismiss) private var dismiss

    private var signedAmount: Double {
        switch transaction.type {
        case .sell, .dividend, .contribution:
            return transaction.amount
        default:
            return -transaction.amount
        }
    }

    private var entryTitle: String {
        let ticker = transaction.ticker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if transaction.type == .contribution {
            return "Transfer to Portfolio"
        }
        let base = transaction.type.title
        return ticker.isEmpty ? base : "\(base) \(ticker.uppercased())"
    }

    var body: some View {
        NavigationStack {
            List {
                HStack {
                    Text("Type")
                    Spacer()
                    Text(transaction.type.title)
                        .foregroundStyle(.secondary)
                }
                if let ticker = transaction.ticker, !ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack {
                        Text("Ticker")
                        Spacer()
                        Text(ticker.uppercased())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Date")
                    Spacer()
                    Text(transaction.date, style: .date)
                        .foregroundStyle(.secondary)
                }
                if let shares = transaction.shares {
                    HStack {
                        Text("Shares")
                        Spacer()
                        Text(shares, format: .number.precision(.fractionLength(0...4)))
                            .foregroundStyle(.secondary)
                    }
                }
                if let price = transaction.pricePerShare {
                    HStack {
                        Text("Price/Share")
                        Spacer()
                        Text(price, format: .currency(code: "USD"))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Amount")
                    Spacer()
                    Text(signedAmount, format: .currency(code: "USD"))
                        .foregroundStyle(signedAmount >= 0 ? .green : .primary)
                }
                if transaction.type == .contribution,
                   let fundingBankAccount = transaction.fundingBankAccount,
                   !fundingBankAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack {
                        Text("From Account")
                        Spacer()
                        Text(fundingBankAccount)
                            .foregroundStyle(.secondary)
                    }
                }
                if let notes = transaction.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(entryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct CashTransferEditorView: View {
    @ObservedObject var budget: BudgetModel
    let selectedDate: Date
    var existingTransfer: CashTransfer?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var amount: Double
    @State private var date: Date
    @State private var fromAccountName: String
    @State private var toAccountName: String
    @State private var note: String

    private var accountOptions: [String] {
        budget.bankAccounts
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let from = fromAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = toAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && amount > 0 && !from.isEmpty && !to.isEmpty && from.caseInsensitiveCompare(to) != .orderedSame
    }

    init(budget: BudgetModel, selectedDate: Date, existingTransfer: CashTransfer? = nil) {
        self.budget = budget
        self.selectedDate = selectedDate
        self.existingTransfer = existingTransfer
        let accounts = budget.bankAccounts
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        _name = State(initialValue: existingTransfer?.name ?? "Cash Transfer")
        _amount = State(initialValue: existingTransfer?.amount ?? 0)
        _date = State(initialValue: existingTransfer?.date ?? selectedDate)
        _fromAccountName = State(initialValue: existingTransfer?.fromAccountName ?? accounts.first ?? "")
        _toAccountName = State(initialValue: existingTransfer?.toAccountName ?? accounts.dropFirst().first ?? "")
        _note = State(initialValue: existingTransfer?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if accountOptions.count < 2 {
                    Section {
                        Text("Add at least two bank accounts before transferring cash.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Transfer Details") {
                    TextField("Name", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Accounts") {
                    Picker("From", selection: $fromAccountName) {
                        ForEach(accountOptions, id: \.self) { accountName in
                            Text(accountName).tag(accountName)
                        }
                    }

                    Picker("To", selection: $toAccountName) {
                        ForEach(accountOptions, id: \.self) { accountName in
                            Text(accountName).tag(accountName)
                        }
                    }

                    if !fromAccountName.isEmpty,
                       !toAccountName.isEmpty,
                       fromAccountName.caseInsensitiveCompare(toAccountName) == .orderedSame {
                        Text("Choose two different accounts.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Note") {
                    TextField("Optional note", text: $note, axis: .vertical)
                }

                if existingTransfer != nil {
                    Section {
                        Button("Delete Transfer", role: .destructive) {
                            if let existingTransfer {
                                budget.deleteCashTransfer(id: existingTransfer.id)
                            }
                            Haptics.warning()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingTransfer == nil ? "Transfer Cash" : "Edit Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                normalizeAccountSelections()
            }
            .onChange(of: budget.bankAccounts) { _, _ in
                normalizeAccountSelections()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let transfer = CashTransfer(
                            id: existingTransfer?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            amount: amount,
                            date: date,
                            fromAccountName: fromAccountName.trimmingCharacters(in: .whitespacesAndNewlines),
                            toAccountName: toAccountName.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        if existingTransfer == nil {
                            budget.addCashTransfer(transfer)
                        } else {
                            budget.updateCashTransfer(transfer)
                        }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(accountOptions.count < 2 || !canSave)
                }
            }
        }
    }

    private func normalizeAccountSelections() {
        guard accountOptions.count >= 2 else { return }
        if !accountOptions.contains(fromAccountName) {
            fromAccountName = accountOptions.first ?? ""
        }
        if !accountOptions.contains(toAccountName) || fromAccountName.caseInsensitiveCompare(toAccountName) == .orderedSame {
            toAccountName = accountOptions.first(where: { $0.caseInsensitiveCompare(fromAccountName) != .orderedSame }) ?? ""
        }
    }
}

struct BankAccountsView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddAccount = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Add") {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Label("Add Bank Account", systemImage: "plus.circle")
                    }
                }

                Section("Accounts") {
                    if budget.bankAccounts.isEmpty {
                        Text("No bank accounts added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($budget.bankAccounts) { $account in
                            NavigationLink {
                                EditBankAccountView(account: $account)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(account.name)
                                        .font(.headline)
                                    Text(account.balance, format: .currency(code: "USD"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if !account.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(account.note)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            budget.bankAccounts.remove(atOffsets: offsets)
                        }
                    }
                }
            }
            .navigationTitle("Bank Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddBankAccountView(budget: budget)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

struct AddBankAccountView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var balance: Double = 0
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Details") {
                    LabeledContent("Account Name") {
                        TextField("Account name", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Balance") {
                        TextField("0.00", value: $balance, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Notes") {
                    TextField("Optional note", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Add Bank Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        budget.bankAccounts.append(
                            BankAccount(
                                name: trimmed,
                                balance: balance,
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        )
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct EditBankAccountView: View {
    @Binding var account: BankAccount

    var body: some View {
        Form {
            Section("Account Details") {
                LabeledContent("Account Name") {
                    TextField("Account name", text: $account.name)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Balance") {
                    TextField("0.00", value: $account.balance, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Notes") {
                TextField("Optional note", text: $account.note, axis: .vertical)
            }
        }
        .navigationTitle("Edit Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView()
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
