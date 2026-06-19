import SwiftUI
import Charts

private enum HoldingsViewMode: String, CaseIterable, Identifiable {
    case cards = "Cards"
    case classic = "Classic"
    var id: String { rawValue }
}

private enum HoldingsSortOption: String, CaseIterable, Identifiable {
    case ticker = "Ticker"
    case marketValue = "Value"
    case monthlyIncome = "Monthly"
    case allocation = "Allocation"
    case yield = "Yield"
    case unrealized = "Unrealized"
    case shares = "Shares"
    case price = "Price"

    var id: String { rawValue }
}

private enum HoldingsAssetFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case growthStock = "Growth"
    case dividendStock = "Dividend Stock"
    case dividendETF = "Dividend ETF"
    case coveredCallETF = "Covered Call ETF"
    case speculative = "Speculative"
    case cashLike = "Cash Like"

    var id: String { rawValue }

    var assetType: PortfolioAssetType? {
        switch self {
        case .all: return nil
        case .growthStock: return .growthStock
        case .dividendStock: return .dividendStock
        case .dividendETF: return .dividendETF
        case .coveredCallETF: return .coveredCallETF
        case .speculative: return .speculative
        case .cashLike: return .cashLike
        }
    }
}

private enum NetWorthRange: String, CaseIterable, Identifiable {
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case all = "All"

    var id: String { rawValue }

    var title: String { rawValue }
}

private struct MonthlyIncomeCostPoint: Identifiable {
    let id = UUID()
    let monthStart: Date
    let monthLabel: String
    let dividends: Double
    let interest: Double
}

private enum ExperimentStatus: String {
    case safe = "Safe"
    case watch = "Watch"
    case risky = "Risky"
    case stopExperiment = "Stop Experiment"

    var tint: Color {
        switch self {
        case .safe: return .green
        case .watch: return .yellow
        case .risky: return .orange
        case .stopExperiment: return .red
        }
    }

    var messages: [String] {
        switch self {
        case .safe:
            return ["Your margin is still within the free limit."]
        case .watch:
            return ["Your dividends do not cover the electric bill yet."]
        case .risky:
            return ["Your margin is growing faster than portfolio income."]
        case .stopExperiment:
            return ["You should stop using margin for bills until the balance is reduced."]
        }
    }
}

struct MarginDashboardView: View {
    @ObservedObject var budget: BudgetModel
    let bottomPadding: CGFloat
    @Binding var showAddTransaction: Bool
    @Binding var showAddInvestment: Bool
    @Binding var showElectricBill: Bool
    @Binding var showMarginSettings: Bool
    @Binding var showHistory: Bool
    @Binding var showManualHolding: Bool

    @AppStorage("margin.holdingsViewMode") private var holdingsViewMode: HoldingsViewMode = .cards
    @State private var isRefreshingPrices = false
    @State private var selectedHolding: PortfolioHolding?
    @AppStorage("margin.selectedNetWorthRange") private var selectedNetWorthRange: NetWorthRange = .threeMonths
    @State private var selectedNetWorthPoint: PortfolioValuePoint?
    @State private var showSnapshotDetails = false
    @State private var refreshProgressTotal = 0
    @State private var refreshProgressCompleted = 0
    @State private var refreshCurrentTicker = ""
    @State private var holdingQuoteSnapshots: [String: MarketQuoteSnapshot] = [:]
    @State private var holdingPriceHistory: [String: [TickerPricePoint]] = [:]
    @AppStorage("margin.holdingsSortOption") private var holdingsSortOption: HoldingsSortOption = .ticker
    @AppStorage("margin.holdingsSortAscending") private var holdingsSortAscending = true
    @AppStorage("margin.holdingsAssetFilter") private var holdingsAssetFilter: HoldingsAssetFilter = .all

    private let marketDataService = MarketDataService()
    private let drawdowns: [Double] = [0.20, 0.35, 0.50]

    private var holdingsGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 50), spacing: 4),
            GridItem(.flexible(minimum: 44), spacing: 8, alignment: .trailing),
            GridItem(.flexible(minimum: 50), spacing: 4, alignment: .trailing),
            GridItem(.flexible(minimum: 55), spacing: 4, alignment: .trailing),
            GridItem(.flexible(minimum: 36), spacing: 4, alignment: .trailing),
            GridItem(.flexible(minimum: 36), spacing: 4, alignment: .trailing),
            GridItem(.flexible(minimum: 55), spacing: 0, alignment: .trailing),
        ]
    }

    private var displayHoldings: [PortfolioHolding] {
        let consolidatedHoldings = budget.consolidatedHoldings
        let portfolioValue = holdingsMarketValue(for: consolidatedHoldings)
        let filtered = consolidatedHoldings.filter { holding in
            guard let assetType = holdingsAssetFilter.assetType else { return true }
            return holding.assetType == assetType
        }

        return filtered.sorted { lhs, rhs in
            switch holdingsSortOption {
            case .ticker:
                let comparison = lhs.ticker.uppercased().localizedStandardCompare(rhs.ticker.uppercased())
                return holdingsSortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
            case .marketValue:
                return sort(lhs.shares * resolvedPrice(for: lhs), rhs.shares * resolvedPrice(for: rhs))
            case .monthlyIncome:
                return sort((lhs.shares * lhs.annualDividendPerShare) / 12.0, (rhs.shares * rhs.annualDividendPerShare) / 12.0)
            case .allocation:
                return sort(allocation(for: lhs, totalMarketValue: portfolioValue), allocation(for: rhs, totalMarketValue: portfolioValue))
            case .yield:
                return sort(currentYield(for: lhs), currentYield(for: rhs))
            case .unrealized:
                return sort(unrealizedGain(for: lhs), unrealizedGain(for: rhs))
            case .shares:
                return sort(lhs.shares, rhs.shares)
            case .price:
                return sort(resolvedPrice(for: lhs), resolvedPrice(for: rhs))
            }
        }
    }

    private func color(for assetType: PortfolioAssetType) -> Color {
        switch assetType {
        case .growthStock:
            return .blue
        case .dividendStock:
            return .green
        case .dividendETF:
            return .teal
        case .coveredCallETF:
            return .orange
        case .speculative:
            return .red
        case .cashLike:
            return .gray
        }
    }

    private var monthInterval: DateInterval? {
        Calendar.current.dateInterval(of: .month, for: Date())
    }

    private var monthlyTransactions: [PortfolioTransaction] {
        guard let monthInterval else { return [] }
        return budget.portfolioTransactions.filter { monthInterval.contains($0.date) }
    }

    private var totalMarketValue: Double {
        holdingsMarketValue(for: budget.holdings)
    }

    private var grossPortfolioValue: Double {
        totalMarketValue + budget.portfolioSnapshot.cashBalance
    }

    private var netPortfolioValue: Double {
        grossPortfolioValue - budget.portfolioSnapshot.marginUsed
    }

    private var latestHoldingsUpdate: Date? {
        budget.cachedQuotes.values.map(\.updatedAt).max()
    }

    private var annualDividendsFromHoldings: Double {
        budget.holdings.reduce(0) { $0 + ($1.shares * $1.annualDividendPerShare) }
    }

    private var monthlyDividendsFromHoldings: Double {
        annualDividendsFromHoldings / 12.0
    }

    private var monthlyDividendsFromLedger: Double {
        sum(monthlyTransactions, type: .dividend)
    }

    private var monthlyDividends: Double {
        max(monthlyDividendsFromLedger, monthlyDividendsFromHoldings)
    }

    private var monthToDateContributions: Double { sum(monthlyTransactions, type: .contribution) }
    private var monthToDateBuys: Double { sum(monthlyTransactions, type: .buy) }
    private var monthToDateBills: Double { sum(monthlyTransactions, type: .billPaidByMargin) }
    private var monthToDateMarginInterest: Double { sum(monthlyTransactions, type: .marginInterest) }

    private var monthlyInterest: Double {
        MarginCalculator.monthlyInterest(
            marginUsed: budget.portfolioSnapshot.marginUsed,
            freeMarginLimit: budget.marginSettings.interestFreeMarginLimit,
            marginInterestRate: budget.marginSettings.marginInterestRate
        )
    }

    private var estimatedMonthlyMarginCostAtFivePercent: Double {
        MarginCalculator.monthlyInterest(
            marginUsed: budget.portfolioSnapshot.marginUsed,
            freeMarginLimit: budget.marginSettings.interestFreeMarginLimit,
            marginInterestRate: 0.05
        )
    }

    private var netMarginChangeThisMonth: Double {
        monthlyTransactions.reduce(0) { partial, tx in
            switch tx.type {
            case .billPaidByMargin, .marginInterest, .manualAdjustment:
                return partial + tx.amount
            case .sell:
                return partial - tx.amount
            default:
                return partial
            }
        }
    }

    private var expectedDividendsThisWeek: Double {
        forecastDividends(for: .weekOfYear)
    }

    private var expectedDividendsThisMonth: Double {
        forecastDividends(for: .month)
    }

    private var monthsUntilFreeLimit: Double {
        let expected = max(budget.recurringElectricBill.expectedAmount, 0)
        guard expected > 0 else { return 0 }
        let remaining = max(budget.marginSettings.interestFreeMarginLimit - budget.portfolioSnapshot.marginUsed, 0)
        return remaining / expected
    }

    private var maintenanceBufferEstimate: Double {
        let requirement = totalMarketValue * budget.marginSettings.maintenanceRequirementPercent
        return netPortfolioValue - requirement
    }

    private var interestFreeMarginRemaining: Double {
        max(budget.marginSettings.interestFreeMarginLimit - budget.portfolioSnapshot.marginUsed, 0)
    }

    private var paidMarginAmount: Double {
        MarginCalculator.paidMargin(
            marginUsed: budget.portfolioSnapshot.marginUsed,
            freeMarginLimit: budget.marginSettings.interestFreeMarginLimit
        )
    }

    private var dividendCoverageOfElectricBill: Double {
        let bill = max(budget.recurringElectricBill.expectedAmount, 0)
        guard bill > 0 else { return 0 }
        return monthlyDividends / bill
    }

    private var marginUtilizationPercent: Double {
        guard budget.marginSettings.totalMarginAvailable > 0 else { return 0 }
        return budget.portfolioSnapshot.marginUsed / budget.marginSettings.totalMarginAvailable
    }

    private var personalCapUtilizationPercent: Double {
        guard budget.marginSettings.personalMarginCap > 0 else { return 0 }
        return budget.portfolioSnapshot.marginUsed / budget.marginSettings.personalMarginCap
    }

    private var dividendInterestSpread: Double {
        monthlyDividends - monthlyInterest
    }

    private var trueMonthlySpread: Double {
        monthlyDividends - monthToDateBills - monthlyInterest
    }

    private var stressTestFails: Bool {
        (stressResults.first(where: { $0.drawdown == 0.35 })?.stressEquity ?? 0) <= 0
    }

    private var estimatedDropToMarginCall: Double {
        guard grossPortfolioValue > 0 else { return 0 }
        let maintenance = budget.marginSettings.maintenanceRequirementPercent
        let thresholdValue = budget.portfolioSnapshot.marginUsed / max(1 - maintenance, 0.01)
        let drop = 1 - (thresholdValue / grossPortfolioValue)
        return max(0, drop)
    }

    private var experimentStatus: ExperimentStatus {
        if stressTestFails || budget.portfolioSnapshot.marginUsed > budget.marginSettings.personalMarginCap {
            return .stopExperiment
        }
        if budget.portfolioSnapshot.marginUsed > budget.marginSettings.interestFreeMarginLimit || personalCapUtilizationPercent >= budget.marginSettings.warningThresholdPercent {
            return .risky
        }
        if dividendCoverageOfElectricBill < 1 {
            return .watch
        }
        return .safe
    }

    private var warningItems: [String] {
        var warnings: [String] = []
        if budget.portfolioSnapshot.marginUsed > budget.marginSettings.interestFreeMarginLimit {
            warnings.append("Margin used exceeds your interest-free limit.")
        }
        if budget.portfolioSnapshot.marginUsed > budget.marginSettings.personalMarginCap {
            warnings.append("Margin used exceeds your personal margin cap.")
        }
        if dividendCoverageOfElectricBill < 1, budget.recurringElectricBill.expectedAmount > 0 {
            warnings.append("Dividends do not currently cover the electric bill.")
        }
        if stressResults.first(where: { $0.drawdown == 0.35 })?.stressEquity ?? 0 <= 0 {
            warnings.append("-35% stress test leaves equity too low.")
        }
        return warnings
    }

    private var stressResults: [MarginScenarioResult] {
        drawdowns.map { drawdown in
            MarginScenarioResult(
                drawdown: drawdown,
                stressPortfolioValue: MarginCalculator.stressPortfolioValue(portfolioValue: grossPortfolioValue, drawdown: drawdown),
                stressEquity: MarginCalculator.stressEquity(portfolioValue: grossPortfolioValue, marginUsed: budget.portfolioSnapshot.marginUsed, drawdown: drawdown)
            )
        }
    }

    private var monthlyIncomeCostHistory: [MonthlyIncomeCostPoint] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"

        let grouped = Dictionary(grouping: budget.portfolioTransactions) { tx in
            calendar.date(from: calendar.dateComponents([.year, .month], from: tx.date)) ?? tx.date
        }

        let points = grouped.compactMap { monthStart, items -> MonthlyIncomeCostPoint? in
            let dividends = items.filter { $0.type == .dividend }.reduce(0) { $0 + $1.amount }
            let interest = items.filter { $0.type == .marginInterest }.reduce(0) { $0 + $1.amount }
            if dividends == 0, interest == 0 { return nil }
            return MonthlyIncomeCostPoint(
                monthStart: monthStart,
                monthLabel: formatter.string(from: monthStart),
                dividends: dividends,
                interest: interest
            )
        }

        return points.sorted { $0.monthStart < $1.monthStart }
    }

    private var netWorthHistoryPoints: [PortfolioValuePoint] {
        let sorted = budget.portfolioValueHistory.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let startDate: Date?
        switch selectedNetWorthRange {
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

    private var netWorthDelta: Double {
        let points = netWorthHistoryPoints
        guard let first = points.first, let last = points.last else { return 0 }
        return last.netValue - first.netValue
    }

    private var netWorthDeltaPercent: Double {
        let points = netWorthHistoryPoints
        guard let first = points.first, abs(first.netValue) > 0.01 else { return 0 }
        return netWorthDelta / abs(first.netValue)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                titleHeader
                marginInsightSummarySection
                experimentStatusCard
                netWorthChartCard
                portfolioSnapshotCard
                holdingsCard
                dividendForecastCard
                monthlyIncomeVsInterestHistoryCard
                monthlySummaryCard
                billTrackingCard
                safetyCard
                Text("For tracking only. Not financial advice. Dividends are not guaranteed. Positive dividend spread does not imply positive total return.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, max(120, bottomPadding))
        }
        .refreshable {
            await refreshPrices()
        }
        .onAppear {
            budget.synchronizeLegacyMarginStateFromLedger()
            syncPortfolioSnapshotAndHistory()
        }
        .onChange(of: budget.portfolioTransactions) { _, _ in
            budget.synchronizeLegacyMarginStateFromLedger()
            syncPortfolioSnapshotAndHistory()
        }
        .onChange(of: budget.holdings) { _, _ in
            syncPortfolioSnapshotAndHistory()
        }
        .sheet(isPresented: $showAddTransaction) { AddTransactionView(budget: budget) }
        .sheet(isPresented: $showAddInvestment) { AddInvestmentView(budget: budget) }
        .sheet(isPresented: $showElectricBill) { ElectricBillTrackerView(budget: budget) }
        .sheet(isPresented: $showMarginSettings) { MarginSettingsView(settings: $budget.marginSettings) }
        .sheet(isPresented: $showHistory) {
            LedgerHistoryView(
                budget: budget
            )
        }
        .sheet(isPresented: $showManualHolding) { ManualHoldingEntryView(budget: budget) }
        .sheet(item: $selectedHolding) { holding in
            let ticker = holding.ticker.uppercased()
            HoldingTickerDetailView(
                budget: budget,
                holdingID: holding.id,
                quoteSnapshot: holdingQuoteSnapshots[ticker],
                quotePriceHistory: holdingPriceHistory[ticker] ?? []
            )
        }
        .sheet(isPresented: $showSnapshotDetails) {
            SnapshotDetailSheet(
                budget: budget,
                totalMarketValue: totalMarketValue,
                grossPortfolioValue: grossPortfolioValue,
                netPortfolioValue: netPortfolioValue,
                interestFreeMarginRemaining: interestFreeMarginRemaining,
                paidMarginAmount: paidMarginAmount,
                monthToDateContributions: monthToDateContributions,
                monthToDateBills: monthToDateBills,
                monthToDateDividends: monthlyDividendsFromLedger,
                netMarginChangeThisMonth: netMarginChangeThisMonth,
                monthsUntilFreeLimit: monthsUntilFreeLimit,
                maintenanceBufferEstimate: maintenanceBufferEstimate,
                estimatedMonthlyMarginCostAtFivePercent: estimatedMonthlyMarginCostAtFivePercent
            )
        }
    }

    private var titleHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CuanTheme.primary)
                .frame(width: 34, height: 34)
                .background(CuanTheme.elevatedCard, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Portfolio")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CuanTheme.text)
                Text("Holdings, dividends, margin, and safety.")
                    .font(.subheadline)
                    .foregroundStyle(CuanTheme.muted)
            }
            Spacer()
            Button {
                showMarginSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.headline)
                    .foregroundStyle(CuanTheme.text)
                    .frame(width: 36, height: 36)
                    .background(CuanTheme.elevatedCard, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Margin settings")
        }
    }

    private var marginInsightSummarySection: some View {
        let grossText = grossPortfolioValue.formatted(.currency(code: "USD"))
        let marginText = budget.portfolioSnapshot.marginUsed.formatted(.currency(code: "USD"))
        let personalCapText = budget.marginSettings.personalMarginCap.formatted(.currency(code: "USD"))
        let monthsUntilFreeLimitText = monthsUntilFreeLimit.formatted(.number.precision(.fractionLength(1)))

        return VStack(spacing: 14) {
            CuanCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Total Portfolio", systemImage: "arrow.up.forward")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(CuanTheme.text)
                            Text("Net value after margin")
                                .font(.caption2)
                                .foregroundStyle(CuanTheme.muted)
                        }
                        Spacer()
                        Text(netWorthDeltaPercent, format: .percent.precision(.fractionLength(1)))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(netWorthDelta >= 0 ? CuanTheme.gain : CuanTheme.loss)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((netWorthDelta >= 0 ? CuanTheme.gain : CuanTheme.loss).opacity(0.12), in: Capsule())
                    }

                    Text(netPortfolioValue, format: .currency(code: "USD"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(CuanTheme.text)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)

                    Text("Gross \(grossText)  Margin \(marginText)")
                        .font(.caption2)
                        .foregroundStyle(CuanTheme.muted)

                    marginProgressStrip(
                        title: "Personal cap",
                        progress: personalCapUtilizationPercent,
                        value: "\(marginText) / \(personalCapText)",
                        tint: personalCapUtilizationPercent >= budget.marginSettings.dangerThresholdPercent ? .red : .pink
                    )
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                marginInsightTile(title: "Monthly Income", value: monthlyDividends, subtitle: "portfolio dividends", tint: .green, systemImage: "banknote.fill")
                marginInsightTile(title: "Interest", value: max(monthlyInterest, monthToDateMarginInterest), subtitle: "monthly cost", tint: .orange, systemImage: "percent")
                marginInsightTile(title: "Free Limit Left", value: interestFreeMarginRemaining, subtitle: "\(monthsUntilFreeLimitText) months", tint: .mint, systemImage: "shield.fill")
                marginInsightTile(title: "True Spread", value: trueMonthlySpread, subtitle: "dividends - bills - interest", tint: trueMonthlySpread >= 0 ? .green : .pink, systemImage: "arrow.left.arrow.right")
            }

            CuanCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Income vs Costs", systemImage: "arrow.left.arrow.right")
                            .font(.headline)
                        Spacer()
                        Text(dividendCoverageOfElectricBill, format: .percent.precision(.fractionLength(1)))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.yellow.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(Color.yellow.opacity(0.55), lineWidth: 1))
                    }

                    marginIncomeCostRow(title: "Dividends", amount: monthlyDividends, tint: .green, systemImage: "arrow.up.forward")
                    marginIncomeCostRow(title: "Bills", amount: monthToDateBills, tint: .pink, systemImage: "bolt.fill")
                    marginIncomeCostRow(title: "Interest", amount: max(monthlyInterest, monthToDateMarginInterest), tint: .orange, systemImage: "percent")
                    Divider()
                    marginIncomeCostRow(title: "Spread", amount: trueMonthlySpread, tint: trueMonthlySpread >= 0 ? .purple : .pink, systemImage: "checkmark.circle.fill")
                }
            }
        }
    }

    private var portfolioSnapshotCard: some View {
        CuanCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Portfolio Snapshot")
                        .font(.headline)
                        .foregroundStyle(CuanTheme.text)
                    Spacer()
                    Button("View Details") { showSnapshotDetails = true }
                        .buttonStyle(.bordered)
                }
                editableCurrencyRow("Cash Balance", value: $budget.portfolioSnapshot.cashBalance)
                metricRow("Holdings Value", totalMarketValue)
                metricRow("Margin Used", budget.portfolioSnapshot.marginUsed)
                metricRow("Net Portfolio Value", netPortfolioValue)
                metricRow("Gross Portfolio Value", grossPortfolioValue)
                editablePercentRow("Total Maintenance Requirement", value: $budget.marginSettings.maintenanceRequirementPercent)
                metricRow("Estimated Monthly Margin Cost (5%)", estimatedMonthlyMarginCostAtFivePercent)
            }
        }
    }

    private var holdingsCard: some View {
        let holdings = displayHoldings
        let portfolioMarketValue = totalMarketValue

        return CuanCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Holdings")
                        .font(.headline)
                        .foregroundStyle(CuanTheme.text)
                    Spacer()
                    Button("Refresh Price") {
                        Task { await refreshPrices() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshingPrices)
                }

                if isRefreshingPrices {
                    VStack(spacing: 4) {
                        ProgressView()
                            .progressViewStyle(.linear)
                        Text("Refreshing \(refreshCurrentTicker) (\(refreshProgressCompleted) of \(refreshProgressTotal))...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Picker("Holdings View", selection: $holdingsViewMode) {
                    ForEach(HoldingsViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                holdingsFilterSortControls

                if let warning = budget.marketDataWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                if budget.consolidatedHoldings.isEmpty {
                    VStack(spacing: 8) {
                        Text("No holdings yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button {
                                showAddInvestment = true
                            } label: {
                                Label("Add Investment", systemImage: "plus.circle")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            Button {
                                showManualHolding = true
                            } label: {
                                Label("Manual Holding", systemImage: "plus.circle")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else if holdings.isEmpty {
                    Text("No holdings match the current filter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if holdingsViewMode == .cards {
                        LazyVStack(spacing: 10) {
                            ForEach(holdings) { holding in
                                holdingCardRow(holding, totalMarketValue: portfolioMarketValue)
                            }
                        }
                    } else {
                        classicHoldingsRows(holdings, totalMarketValue: portfolioMarketValue)
                    }
                }

                Divider()
                HStack {
                    Text("Portfolio Monthly Income")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(monthlyDividends, format: .currency(code: "USD"))
                        .font(.caption.weight(.semibold))
                }
                .padding(.vertical, 2)
                HStack {
                    Text("Portfolio Annual Income")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(annualDividendsFromHoldings, format: .currency(code: "USD"))
                        .font(.caption.weight(.semibold))
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func classicHoldingsRows(_ holdings: [PortfolioHolding], totalMarketValue: Double) -> some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: holdingsGridColumns, spacing: 0) {
                Text("Ticker")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Shares").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text("Price").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text("Value").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text("Alloc").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text("Yield").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text("P&L").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)

            Divider()

            ForEach(holdings) { holding in
                classicHoldingRow(holding, totalMarketValue: totalMarketValue)
                if holding.id != holdings.last?.id {
                    Divider()
                }
            }
        }
    }

    private func classicHoldingRow(_ holding: PortfolioHolding, totalMarketValue: Double) -> some View {
        let price = resolvedPrice(for: holding)
        let marketValue = holding.shares * price
        let totalCost = holding.shares * holding.averageCost
        let allocationValue = allocation(for: holding, totalMarketValue: totalMarketValue)
        let yieldValue = currentYield(for: holding)
        let unrealized = marketValue - totalCost

        return Button {
            selectedHolding = holding
        } label: {
            LazyVGrid(columns: holdingsGridColumns, spacing: 0) {
                Text(holding.ticker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: holding.assetType))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(holding.shares, format: .number.precision(.fractionLength(2)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(price, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(marketValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(allocationValue, format: .percent.precision(.fractionLength(1)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(yieldValue, format: .percent.precision(.fractionLength(1)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(unrealized, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(unrealized >= 0 ? .green : .red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func holdingCardRow(_ holding: PortfolioHolding, totalMarketValue: Double) -> some View {
        let ticker = holding.ticker.uppercased()
        let price = resolvedPrice(for: holding)
        let marketValue = holding.shares * price
        let totalCost = holding.shares * holding.averageCost
        let allocationValue = allocation(for: holding, totalMarketValue: totalMarketValue)
        let yieldValue = currentYield(for: holding)
        let unrealized = marketValue - totalCost
        let snapshot = holdingQuoteSnapshot(for: holding)
        let change = CuanMarketChangeDisplay(change: snapshot.change, percentChange: snapshot.percentChange)
        let tint = snapshot.percentChange == 0 ? color(for: holding.assetType) : CuanTheme.changeColor(for: change.direction)
        let history = holdingPriceHistory[ticker]?.map(\.close) ?? compactSessionPrices(from: snapshot)

        return Button {
            selectedHolding = holding
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 11) {
                    CuanTickerAvatar(symbol: ticker, tint: tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ticker)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(CuanTheme.text)
                        Text(holding.assetType.rawValue)
                            .font(.caption2)
                            .foregroundStyle(CuanTheme.muted)
                            .lineLimit(1)
                    }

                    Spacer()

                    CuanSparkline(values: history, tint: tint)
                        .frame(width: 64)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(marketValue, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(CuanTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(unrealized, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(unrealized >= 0 ? CuanTheme.gain : CuanTheme.loss)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    holdingMiniMetric("Shares", value: holding.shares.formatted(.number.precision(.fractionLength(2))))
                    holdingMiniMetric("Price", value: price.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                    holdingMiniMetric("Alloc", value: allocationValue.formatted(.percent.precision(.fractionLength(1))))
                    holdingMiniMetric("Yield", value: yieldValue.formatted(.percent.precision(.fractionLength(1))))
                }
            }
            .padding(12)
            .background(CuanTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func holdingMiniMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(CuanTheme.muted)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CuanTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var netWorthChartCard: some View {
        CuanCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.headline)
                        .foregroundStyle(CuanTheme.primary)
                        .frame(width: 38, height: 38)
                        .background(CuanTheme.primary.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Portfolio Net Worth")
                            .font(.headline)
                            .foregroundStyle(CuanTheme.text)
                        Text(netPortfolioValue, format: .currency(code: "USD"))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(netPortfolioValue < 0 ? CuanTheme.loss : CuanTheme.text)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(netWorthDeltaPercent, format: .percent.precision(.fractionLength(1)))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(netWorthDelta >= 0 ? CuanTheme.gain : CuanTheme.loss)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((netWorthDelta >= 0 ? CuanTheme.gain : CuanTheme.loss).opacity(0.14), in: Capsule())
                        if let latestHoldingsUpdate {
                            Text("Updated \(latestHoldingsUpdate, format: .dateTime.month().day().year().hour().minute())")
                                .font(.caption2)
                                .foregroundStyle(CuanTheme.muted)
                        } else {
                            Text("Updated: --")
                                .font(.caption2)
                                .foregroundStyle(CuanTheme.muted)
                        }
                    }
                }

                let points = netWorthHistoryPoints
                if points.count < 2 {
                    Text("Add more portfolio activity over time to see your trend.")
                        .font(.caption)
                        .foregroundStyle(CuanTheme.muted)
                } else {
                    Chart(points) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Portfolio Net Worth", point.netValue)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [CuanTheme.primary.opacity(0.24), CuanTheme.primary.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Portfolio Net Worth", point.netValue)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(CuanTheme.primary)
                        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Gross Portfolio", point.grossValue)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(CuanTheme.gain.opacity(0.68))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        if let selectedNetWorthPoint {
                            RuleMark(x: .value("Date", selectedNetWorthPoint.date))
                                .foregroundStyle(.secondary.opacity(0.35))
                            PointMark(
                                x: .value("Date", selectedNetWorthPoint.date),
                                y: .value("Portfolio Net Worth", selectedNetWorthPoint.netValue)
                            )
                            .foregroundStyle(CuanTheme.primary)
                        }
                    }
                    .chartPlotStyle { $0.clipped() }
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
                    .chartYScale(domain: netWorthChartYDomain(for: points))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.08))
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    switch selectedNetWorthRange {
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
                                                    selectedNetWorthPoint = nearestHistoryPoint(to: date, in: points)
                                                }
                                            }
                                            .onEnded { _ in
                                                selectedNetWorthPoint = nil
                                            }
                                    )

                                if let selectedNetWorthPoint,
                                   let plotFrame = proxy.plotFrame.map({ geometry[$0] }) {
                                    let xPosition = proxy.position(forX: selectedNetWorthPoint.date) ?? plotFrame.minX
                                    let yPosition = proxy.position(forY: selectedNetWorthPoint.netValue) ?? plotFrame.minY
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selectedNetWorthPoint.date, format: .dateTime.month().day().year())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("Net \(selectedNetWorthPoint.netValue, format: .currency(code: "USD"))")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Text("Gross \(selectedNetWorthPoint.grossValue, format: .currency(code: "USD"))")
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

                    marginNetWorthRangeSelector

                    HStack(spacing: 14) {
                        Label("Portfolio Net Worth", systemImage: "line.diagonal")
                            .foregroundStyle(CuanTheme.primary)
                        Label("Gross Portfolio", systemImage: "line.diagonal")
                            .foregroundStyle(CuanTheme.gain)
                        Text("\(netWorthDelta >= 0 ? "+" : "")\(netWorthDelta, format: .currency(code: "USD")) in range")
                            .foregroundStyle(CuanTheme.muted)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var marginNetWorthRangeSelector: some View {
        CuanSegmentedRange(values: NetWorthRange.allCases, selection: $selectedNetWorthRange) { range in
            Text(range.title)
                .frame(maxWidth: .infinity)
        }
    }

    private var dividendForecastCard: some View {
        CuanCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Dividend Forecast")
                    .font(.headline)
                    .foregroundStyle(CuanTheme.text)
                metricRow("Expected dividends this week", expectedDividendsThisWeek)
                metricRow("Expected dividends this month", expectedDividendsThisMonth)
                metricRow("Projected annual dividends", annualDividendsFromHoldings)
                metricRow("Dividend coverage of electricity bill", dividendCoverageOfElectricBill, asPercent: true)
            }
        }
    }

    private var holdingsFilterSortControls: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Filter", selection: $holdingsAssetFilter) {
                    ForEach(HoldingsAssetFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
            } label: {
                Label(holdingsAssetFilter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.bordered)

            Menu {
                Picker("Sort", selection: $holdingsSortOption) {
                    ForEach(HoldingsSortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Label(holdingsSortOption.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.bordered)

            Button {
                holdingsSortAscending.toggle()
            } label: {
                Image(systemName: holdingsSortAscending ? "arrow.up" : "arrow.down")
                    .font(.caption.weight(.bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(holdingsSortAscending ? "Sort ascending" : "Sort descending")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var billTrackingCard: some View {
        CuanCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Bill Tracking")
                        .font(.headline)
                        .foregroundStyle(CuanTheme.text)
                    Spacer()
                    Button("Edit", action: { showElectricBill = true })
                        .buttonStyle(.bordered)
                }
                metricRow("Electric Bill (Expected)", budget.recurringElectricBill.expectedAmount)
                metricRow("Monthly Bills Paid by Margin", monthToDateBills)
                metricRow("Monthly Margin Interest", max(monthlyInterest, monthToDateMarginInterest))
                metricRow("Electric Bill Coverage", dividendCoverageOfElectricBill, asPercent: true)
            }
        }
    }

    private var safetyCard: some View {
        CuanCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Safety Dashboard")
                    .font(.headline)
                    .foregroundStyle(CuanTheme.text)

                HStack {
                    Label("Status", systemImage: "shield.lefthalf.filled")
                    Spacer()
                    Text(experimentStatus.rawValue)
                        .fontWeight(.semibold)
                        .foregroundStyle(experimentStatus.tint)
                }
                metricRow("Dividends - Margin Interest", monthlyDividends - monthlyInterest)
                metricRow("Dividends - Bills - Interest", monthlyDividends - monthToDateBills - monthlyInterest)
                metricRow("Estimated Drop to Margin Call Risk", estimatedDropToMarginCall, asPercent: true)
                HStack {
                    Text("Margin Used vs Free Limit")
                    Spacer()
                    Text("\(budget.portfolioSnapshot.marginUsed, format: .currency(code: "USD")) / \(budget.marginSettings.interestFreeMarginLimit, format: .currency(code: "USD"))")
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Margin Used vs Personal Cap")
                    Spacer()
                    Text("\(budget.portfolioSnapshot.marginUsed, format: .currency(code: "USD")) / \(budget.marginSettings.personalMarginCap, format: .currency(code: "USD"))")
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Margin Utilization")
                    Spacer()
                    Text(marginUtilizationPercent, format: .percent.precision(.fractionLength(1)))
                        .fontWeight(.semibold)
                        .foregroundStyle(marginUtilizationPercent == 0 ? .green : (marginUtilizationPercent >= budget.marginSettings.dangerThresholdPercent ? .red : .secondary))
                }
                ProgressView(value: min(max(marginUtilizationPercent, 0), 1))
                    .tint(marginUtilizationPercent >= budget.marginSettings.dangerThresholdPercent ? .red : .green)

                Divider()
                Text("Stress Tests")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                ForEach(Array(stressResults.enumerated()), id: \.offset) { _, result in
                    HStack {
                        Text("-\(Int(result.drawdown * 100))%")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(result.stressEquity, format: .currency(code: "USD"))
                            .fontWeight(.semibold)
                            .foregroundStyle(result.stressEquity >= 0 ? Color.primary : Color.red)
                    }
                }

                if !warningItems.isEmpty {
                    Divider()
                    ForEach(warningItems, id: \.self) { warning in
                        Text("• \(warning)")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
    }

    private func editableCurrencyRow(_ title: String, value: Binding<Double>) -> some View {
        DelayedCurrencyField(title: title, value: value)
    }

    private func editablePercentRow(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField("0%", value: value, format: .percent)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func metricRow(_ title: String, _ value: Double, asPercent: Bool = false, asPlain: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            if asPlain {
                Text(value, format: .number.precision(.fractionLength(1)))
                    .fontWeight(.semibold)
            } else if asPercent {
                Text(value, format: .percent.precision(.fractionLength(2)))
                    .fontWeight(.semibold)
            } else {
                Text(value, format: .currency(code: "USD"))
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
    }

    private func marginInsightTile(title: String, value: Double, subtitle: String, tint: Color, systemImage: String) -> some View {
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
                    .minimumScaleFactor(0.8)
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
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }

    private func marginIncomeCostRow(title: String, amount: Double, tint: Color, systemImage: String) -> some View {
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

    private func marginProgressStrip(title: String, progress: Double, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(tint)
        }
    }

    private func holdingTickerSnapshot(for holding: PortfolioHolding) -> some View {
        let ticker = holding.ticker.uppercased()
        let snapshot = holdingQuoteSnapshot(for: holding)
        let changeTint: Color = snapshot.percentChange >= 0 ? .green : .pink
        let priceHistory = holdingPriceHistory[ticker] ?? TickerPricePoint.estimated(from: compactSessionPrices(from: snapshot))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quote Snapshot")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.price, format: .currency(code: "USD"))
                        .font(.title3.weight(.bold))
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: snapshot.percentChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.bold))
                        Text(snapshot.percentChange / 100, format: .percent.precision(.fractionLength(2)))
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(changeTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(changeTint.opacity(0.14), in: Capsule())

                    Text(snapshot.change, format: .currency(code: "USD"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if priceHistory.count >= 2 || !ticker.isEmpty {
                TickerPriceHistoryChart(
                    points: priceHistory,
                    trendIsPositive: snapshot.percentChange >= 0,
                    style: .compact,
                    symbol: ticker
                )
            }

            if let dayLow = snapshot.low, let dayHigh = snapshot.high, dayHigh > dayLow {
                let rangeText = "\(dayLow.formatted(.currency(code: "USD"))) - \(dayHigh.formatted(.currency(code: "USD")))"
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Day range")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(rangeText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(max((snapshot.price - dayLow) / (dayHigh - dayLow), 0), 1))
                        .tint(changeTint)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                tickerSnapshotPill("Open", value: snapshot.open, tint: .blue, systemImage: "arrow.up.right")
                tickerSnapshotPill("Prev", value: snapshot.previousClose, tint: .purple, systemImage: "clock.fill")
                tickerSnapshotPill("Low", value: snapshot.low, tint: .pink, systemImage: "arrow.down")
                tickerSnapshotPill("High", value: snapshot.high, tint: .green, systemImage: "arrow.up")
            }

            if let updatedAt = budget.cachedQuotes[ticker]?.updatedAt {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("Updated \(updatedAt, format: .dateTime.month().day().hour().minute())")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(changeTint.opacity(0.20), lineWidth: 1)
        )
        .padding(.top, 4)
    }

    private func tickerSnapshotPill(_ label: String, value: Double?, tint: Color, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let value {
                    Text(value, format: .currency(code: "USD"))
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else {
                    Text("N/A")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sum(_ items: [PortfolioTransaction], type: PortfolioTransactionType) -> Double {
        items.filter { $0.type == type }.reduce(0) { $0 + $1.amount }
    }

    private func currentYield(for holding: PortfolioHolding) -> Double {
        let price = resolvedPrice(for: holding)
        guard price > 0 else { return 0 }
        return holding.annualDividendPerShare / price
    }

    private func allocation(for holding: PortfolioHolding, totalMarketValue: Double) -> Double {
        guard totalMarketValue > 0 else { return 0 }
        return (holding.shares * resolvedPrice(for: holding)) / totalMarketValue
    }

    private func holdingsMarketValue(for holdings: [PortfolioHolding]) -> Double {
        holdings.reduce(0) { $0 + ($1.shares * resolvedPrice(for: $1)) }
    }

    private func unrealizedGain(for holding: PortfolioHolding) -> Double {
        holding.shares * (resolvedPrice(for: holding) - holding.averageCost)
    }

    private func sort(_ lhs: Double, _ rhs: Double) -> Bool {
        holdingsSortAscending ? lhs < rhs : lhs > rhs
    }

    private func resolvedPrice(for holding: PortfolioHolding) -> Double {
        let ticker = holding.ticker.uppercased()
        if let quote = budget.cachedQuotes[ticker], quote.price > 0 {
            return quote.price
        }
        return holding.currentPrice
    }

    private func holdingQuoteSnapshot(for holding: PortfolioHolding) -> MarketQuoteSnapshot {
        let ticker = holding.ticker.uppercased()
        if let snapshot = holdingQuoteSnapshots[ticker] {
            return snapshot
        }

        let price = resolvedPrice(for: holding)
        return MarketQuoteSnapshot(
            price: price,
            change: 0,
            percentChange: 0,
            open: nil,
            high: nil,
            low: nil,
            previousClose: nil
        )
    }

    private func compactSessionPrices(from snapshot: MarketQuoteSnapshot) -> [Double] {
        let candidateValues: [Double?] = [
            snapshot.previousClose,
            snapshot.open,
            snapshot.low,
            snapshot.price,
            snapshot.high
        ]
        var rawValues: [Double] = []
        for candidate in candidateValues {
            if let value = candidate, value > 0 {
                rawValues.append(value)
            }
        }

        let uniqueValues = rawValues.reduce(into: [Double]()) { values, value in
            if values.last != value {
                values.append(value)
            }
        }

        if uniqueValues.count >= 2 {
            return uniqueValues
        }
        return [snapshot.price, snapshot.price].filter { $0 > 0 }
    }

    private func nearestHistoryPoint(to date: Date, in points: [PortfolioValuePoint]) -> PortfolioValuePoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func netWorthChartYDomain(for points: [PortfolioValuePoint]) -> ClosedRange<Double> {
        let values = points.flatMap { [$0.netValue, $0.grossValue] }
        guard let minValue = values.min(), let maxValue = values.max() else { return -1...1 }
        if minValue == maxValue {
            let padding = max(abs(minValue) * 0.1, 100)
            return (minValue - padding)...(maxValue + padding)
        }

        let range = maxValue - minValue
        let padding = max(range * 0.12, 50)
        var lower = minValue - padding
        var upper = maxValue + padding
        if minValue < 0, maxValue > 0 {
            lower = min(lower, -padding)
            upper = max(upper, padding)
        }
        return lower...upper
    }

    private func syncPortfolioSnapshotAndHistory() {
        budget.portfolioSnapshot.portfolioValue = grossPortfolioValue
        budget.portfolioSnapshot.freeMarginLimit = budget.marginSettings.interestFreeMarginLimit
        budget.portfolioSnapshot.marginInterestRate = budget.marginSettings.marginInterestRate

        let now = Date()
        if let last = budget.portfolioValueHistory.last, now.timeIntervalSince(last.date) < 60 {
            budget.portfolioValueHistory[budget.portfolioValueHistory.count - 1] = PortfolioValuePoint(
                id: last.id,
                date: now,
                grossValue: grossPortfolioValue,
                netValue: netPortfolioValue
            )
        } else {
            budget.portfolioValueHistory.append(
                PortfolioValuePoint(date: now, grossValue: grossPortfolioValue, netValue: netPortfolioValue)
            )
            if budget.portfolioValueHistory.count > 500 {
                budget.portfolioValueHistory = Array(budget.portfolioValueHistory.suffix(500))
            }
        }
    }

    private func forecastDividends(for component: Calendar.Component) -> Double {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: component, for: Date()) else { return 0 }
        return budget.holdings.reduce(0) { partial, holding in
            guard let nextPayDate = holding.nextPayDate else { return partial }
            let payout = holding.shares * (holding.annualDividendPerShare / holding.dividendFrequency.paymentsPerYear)
            guard payout > 0 else { return partial }
            return partial + payoutOccurrences(
                startDate: nextPayDate,
                frequency: holding.dividendFrequency,
                payoutAmount: payout,
                interval: interval
            )
        }
    }

    private func payoutOccurrences(startDate: Date, frequency: DividendFrequency, payoutAmount: Double, interval: DateInterval) -> Double {
        let calendar = Calendar.current
        var date = startDate
        var total = 0.0
        while date <= interval.end {
            if interval.contains(date) {
                total += payoutAmount
            }
            switch frequency {
            case .weekly:
                guard let next = calendar.date(byAdding: .day, value: 7, to: date) else { return total }
                date = next
            case .monthly:
                guard let next = calendar.date(byAdding: .month, value: 1, to: date) else { return total }
                date = next
            case .quarterly:
                guard let next = calendar.date(byAdding: .month, value: 3, to: date) else { return total }
                date = next
            case .annual:
                guard let next = calendar.date(byAdding: .year, value: 1, to: date) else { return total }
                date = next
            case .irregular:
                return total
            }
        }
        return total
    }

    private var experimentStatusCard: some View {
        CuanCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Experiment Status")
                        .font(.headline)
                        .foregroundStyle(CuanTheme.text)
                    Spacer()
                    Text(experimentStatus.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(experimentStatus.tint.opacity(0.2))
                        .foregroundStyle(experimentStatus.tint)
                        .clipShape(Capsule())
                }
                ForEach(experimentStatus.messages, id: \.self) { message in
                    Text("• \(message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var monthlySummaryCard: some View {
        CuanCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Monthly Summary")
                    .font(.headline)
                    .foregroundStyle(CuanTheme.text)
                metricRow("Contributions Added", monthToDateContributions)
                metricRow("Additional Investments", monthToDateBuys)
                metricRow("Bills Paid by Margin", monthToDateBills)
                metricRow("Dividends Received", monthlyDividendsFromLedger)
                metricRow("Margin Interest Charged", max(monthlyInterest, monthToDateMarginInterest))
                metricRow("Dividend-Interest Spread", dividendInterestSpread)
                metricRow("True Monthly Spread", trueMonthlySpread)
                metricRow("Margin Balance Change", netMarginChangeThisMonth)
                metricRow("Electric Bill Coverage %", dividendCoverageOfElectricBill, asPercent: true)
            }
        }
    }

    private var monthlyIncomeVsInterestHistoryCard: some View {
        CuanCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Monthly Dividends vs Margin Interest")
                    .font(.headline)
                    .foregroundStyle(CuanTheme.text)

                let points = monthlyIncomeCostHistory
                if points.isEmpty {
                    Text("Add dividend and margin-interest transactions to track monthly history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(points) { point in
                        BarMark(
                            x: .value("Month", point.monthStart),
                            y: .value("Dividends", point.dividends)
                        )
                        .position(by: .value("Type", "Dividends"))
                        .foregroundStyle(.green)

                        BarMark(
                            x: .value("Month", point.monthStart),
                            y: .value("Margin Interest", point.interest)
                        )
                        .position(by: .value("Type", "Margin Interest"))
                        .foregroundStyle(.orange)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: min(max(points.count, 3), 8))) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date, format: .dateTime.month(.abbreviated).year(.twoDigits))
                                }
                            }
                        }
                    }
                    .frame(height: 220)

                    Divider()
                    ForEach(points.suffix(6).reversed()) { point in
                        HStack {
                            Text(point.monthLabel)
                            Spacer()
                            Text("Div \(point.dividends, format: .currency(code: "USD"))")
                                .foregroundStyle(.green)
                            Text("Int \(point.interest, format: .currency(code: "USD"))")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    @MainActor
    private func refreshPrices() async {
        guard !isRefreshingPrices else { return }
        guard budget.marketDataSettings.canFetchMarketData else {
            budget.marketDataWarning = "Market data credentials are missing. Using manual/cached prices."
            return
        }
        let tickers = Array(Set(budget.holdings.map { $0.ticker.uppercased() })).filter { !$0.isEmpty }
        guard !tickers.isEmpty else { return }

        isRefreshingPrices = true
        budget.marketDataWarning = nil
        refreshProgressTotal = tickers.count
        refreshProgressCompleted = 0
        refreshCurrentTicker = tickers.first ?? ""

        var failures = 0
        var rateLimitedHits = 0
        let isAlphaVantage = budget.marketDataSettings.provider == .alphaVantage
        let isFinnhub = budget.marketDataSettings.provider == .finnhub
        for (index, ticker) in tickers.enumerated() {
            refreshCurrentTicker = ticker
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
                let quoteSnapshot = try? await marketDataService.fetchQuoteSnapshot(
                    ticker: ticker,
                    settings: budget.marketDataSettings
                )
                budget.cachedQuotes[ticker] = CachedQuote(ticker: ticker, price: details.price, updatedAt: Date())
                let snapshot = quoteSnapshot ?? MarketQuoteSnapshot(
                    price: details.price,
                    change: 0,
                    percentChange: 0,
                    open: nil,
                    high: nil,
                    low: nil,
                    previousClose: nil
                )
                holdingQuoteSnapshots[ticker] = snapshot
                if let history = try? await marketDataService.fetchCompositeRecentPriceHistory(
                    ticker: ticker,
                    settings: budget.marketDataSettings,
                    days: 90
                ), history.count >= 2 {
                    holdingPriceHistory[ticker] = history
                } else {
                    holdingPriceHistory[ticker] = TickerPricePoint.estimated(from: compactSessionPrices(from: snapshot))
                }
                for idx in budget.holdings.indices where budget.holdings[idx].ticker.uppercased() == ticker {
                    budget.holdings[idx].currentPrice = details.price
                    if let annualDividend = details.annualDividendPerShare, annualDividend >= 0 {
                        budget.holdings[idx].annualDividendPerShare = annualDividend
                    }
                }
            } catch {
                if let serviceError = error as? MarketDataServiceError, serviceError == .rateLimited {
                    rateLimitedHits += 1
                }
                failures += 1
            }

            refreshProgressCompleted = index + 1
        }

        if failures > 0 {
            let providerName = budget.marketDataSettings.useAlpacaFallback ? "\(budget.marketDataSettings.provider.rawValue)/Alpaca" : budget.marketDataSettings.provider.rawValue
            if rateLimitedHits > 0 {
                budget.marketDataWarning = "\(providerName) rate limit hit for \(rateLimitedHits) ticker(s). Showing last cached prices."
            } else {
                budget.marketDataWarning = "Failed to refresh \(failures) ticker(s). Showing last cached/manual prices."
            }
        }
        isRefreshingPrices = false
        refreshCurrentTicker = ""
        refreshProgressCompleted = 0
        refreshProgressTotal = 0
        syncPortfolioSnapshotAndHistory()
    }
}

private struct HoldingTickerDetailView: View {
    @ObservedObject var budget: BudgetModel
    let holdingID: UUID
    let quoteSnapshot: MarketQuoteSnapshot?
    let quotePriceHistory: [TickerPricePoint]
    @Environment(\.dismiss) private var dismiss
    @State private var showEditHolding = false
    @State private var selectedTransaction: PortfolioTransaction?
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

    private var holding: PortfolioHolding? {
        guard let original = budget.holdings.first(where: { $0.id == holdingID }) else { return nil }
        let ticker = original.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return budget.consolidatedHoldings.first { $0.ticker == ticker }
    }

    private var cleanTicker: String {
        holding?.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    }

    private var tickerNotes: [TickerNote] {
        budget.notes(for: cleanTicker)
    }

    private var sortedTickerNotes: [TickerNote] {
        switch noteSortOption {
        case .newest:
            return tickerNotes.sorted { $0.updatedAt > $1.updatedAt }
        case .oldest:
            return tickerNotes.sorted { $0.updatedAt < $1.updatedAt }
        case .category:
            return tickerNotes.sorted { lhs, rhs in
                let leftCategory = lhs.category ?? "Uncategorized"
                let rightCategory = rhs.category ?? "Uncategorized"
                if leftCategory.localizedCaseInsensitiveCompare(rightCategory) == .orderedSame {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return leftCategory.localizedCaseInsensitiveCompare(rightCategory) == .orderedAscending
            }
        }
    }

    private var lastUpdated: Date? {
        guard let holding else { return nil }
        return budget.cachedQuotes[holding.ticker.uppercased()]?.updatedAt
    }

    private var displayQuoteSnapshot: MarketQuoteSnapshot? {
        if let quoteSnapshot {
            return quoteSnapshot
        }
        guard let holding else { return nil }
        return MarketQuoteSnapshot(
            price: holding.currentPrice,
            change: 0,
            percentChange: 0,
            open: nil,
            high: nil,
            low: nil,
            previousClose: nil
        )
    }

    private var displayQuotePriceHistory: [TickerPricePoint] {
        guard let snapshot = displayQuoteSnapshot else { return [] }
        return quotePriceHistory.isEmpty
            ? TickerPricePoint.estimated(from: compactSessionPrices(from: snapshot))
            : quotePriceHistory
    }

    private var relatedTransactions: [PortfolioTransaction] {
        guard let holding else { return [] }
        return budget.portfolioTransactions
            .filter { ($0.ticker ?? "").uppercased() == holding.ticker.uppercased() }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if let holding {
                    let marketValue = holding.shares * holding.currentPrice
                    let costBasis = holding.shares * holding.averageCost
                    let unrealized = marketValue - costBasis
                    let annualIncome = holding.shares * holding.annualDividendPerShare
                    let unrealizedPct = costBasis > 0 ? unrealized / costBasis : 0
                    let yieldOnValue = holding.currentPrice > 0 ? holding.annualDividendPerShare / holding.currentPrice : 0
                    let yieldOnCost = holding.averageCost > 0 ? holding.annualDividendPerShare / holding.averageCost : 0

                    Section {
                        TradingViewWidgetContainer(
                            kind: .symbolInfo(symbol: holding.ticker),
                            height: 118,
                            fallback: { AnyView(EmptyView()) }
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 0, trailing: 8))

                    Section {
                        VStack(alignment: .leading, spacing: 14) {
                            performanceHero(
                                marketValue: marketValue,
                                unrealized: unrealized,
                                unrealizedPct: unrealizedPct
                            )
                            if let snapshot = displayQuoteSnapshot {
                                quoteSnapshotCard(snapshot: snapshot, priceHistory: displayQuotePriceHistory)
                            }
                            HStack(spacing: 10) {
                                compactMetricCard(
                                    title: "Shares",
                                    value: holding.shares.formatted(.number.precision(.fractionLength(0...4))),
                                    icon: "number"
                                )
                                compactMetricCard(
                                    title: "Current Price",
                                    value: holding.currentPrice.formatted(.currency(code: "USD")),
                                    icon: "dollarsign"
                                )
                            }
                            HStack(spacing: 10) {
                                compactMetricCard(
                                    title: "Cost Basis",
                                    value: costBasis.formatted(.currency(code: "USD")),
                                    icon: "banknote"
                                )
                                compactMetricCard(
                                    title: "Avg Cost",
                                    value: holding.averageCost.formatted(.currency(code: "USD")),
                                    icon: "chart.bar.doc.horizontal"
                                )
                            }
                            yieldBarRow(
                                yieldOnValue: yieldOnValue,
                                yieldOnCost: yieldOnCost
                            )
                            detailRow("Annual Dividend Income", value: annualIncome.formatted(.currency(code: "USD")))
                            detailRow("Asset Type", value: holding.assetType.rawValue)
                            detailRow("Dividend Reliability", value: holding.dividendReliability.rawValue)
                            if let nextExDate = holding.nextExDividendDate {
                                detailRow("Next Ex-Dividend", value: nextExDate.formatted(date: .abbreviated, time: .omitted))
                            }
                            if let nextPayDate = holding.nextPayDate {
                                detailRow("Next Pay Date", value: nextPayDate.formatted(date: .abbreviated, time: .omitted))
                            }
                            if let lastUpdated {
                                detailRow("Price Updated", value: lastUpdated.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))

                    Section {
                        holdingNotesSection
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))

                    Section("Related Ledger Activity") {
                        if relatedTransactions.isEmpty {
                            Text("No transactions for this ticker yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(relatedTransactions) { tx in
                                Button {
                                    selectedTransaction = tx
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(tx.type.title)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text(tx.amount, format: .currency(code: "USD"))
                                        }
                                        Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                } else {
                    Section("Holding") {
                        Text("This holding is no longer available.")
                            .foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                }
            }
            .contentMargins(.horizontal, 8, for: .scrollContent)
            .navigationTitle("Holding")
            .onAppear {
                migrateLegacyHoldingNoteIfNeeded()
            }
            .toolbar {
                if holding != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { showEditHolding = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showEditHolding) {
                if let holding {
                    EditHoldingView(budget: budget, holding: holding)
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                EditPortfolioTransactionView(
                    budget: budget,
                    transactionID: transaction.id
                )
            }
            .sheet(item: $editingNoteDraft) { draft in
                TickerNoteEditorView(
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
                                resetHoldingAddNoteFields()
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
                                resetHoldingAddNoteFields()
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

    private func resetHoldingAddNoteFields() {
        addNoteTitle = ""
        addNoteText = ""
        addNoteURL = ""
        addNoteURLTitle = ""
        addNoteCategory = ""
    }

    private var holdingNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Notes", systemImage: "note.text")
                    .font(.headline)
                Spacer()
                if !tickerNotes.isEmpty {
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
                Text("\(tickerNotes.count)")
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
                .disabled(cleanTicker.isEmpty || noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

                if !tickerNotes.isEmpty {
                    Button {
                        Task { await generateHoldingSummary() }
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

            if tickerNotes.isEmpty {
                Text("No notes for \(cleanTicker) yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedTickerNotes) { note in
                    noteCard(note)
                }
            }
        }
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

    private func generateHoldingSummary() async {
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

    private struct TickerNoteEditorView: View {
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

    private func migrateLegacyHoldingNoteIfNeeded() {
        guard let holding else { return }
        let legacyNote = holding.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacyNote.isEmpty else { return }
        let ticker = holding.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !ticker.isEmpty else { return }
        let alreadyExists = budget.notes(for: ticker).contains {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == legacyNote
        }
        if !alreadyExists {
            budget.addTickerNote(ticker: ticker, text: legacyNote)
        }
    }

    private func performanceHero(marketValue: Double, unrealized: Double, unrealizedPct: Double) -> some View {
        let gain = unrealized >= 0
        return VStack(alignment: .leading, spacing: 8) {
            Text("Position Value")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(marketValue.formatted(.currency(code: "USD")))
                .font(.title2.weight(.bold))
            HStack(spacing: 6) {
                Image(systemName: gain ? "arrow.up.right" : "arrow.down.right")
                Text(unrealized.formatted(.currency(code: "USD")))
                Text(unrealizedPct.formatted(.percent.precision(.fractionLength(2))))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(gain ? Color.green : Color.red)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    gain ? Color.green.opacity(0.20) : Color.red.opacity(0.20),
                    Color.secondary.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func quoteSnapshotCard(snapshot: MarketQuoteSnapshot, priceHistory: [TickerPricePoint]) -> some View {
        let changeTint: Color = snapshot.percentChange >= 0 ? .green : .pink
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quote Snapshot")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.price, format: .currency(code: "USD"))
                        .font(.title3.weight(.bold))
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: snapshot.percentChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.bold))
                        Text(snapshot.percentChange / 100, format: .percent.precision(.fractionLength(2)))
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(changeTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(changeTint.opacity(0.14), in: Capsule())

                    Text(snapshot.change, format: .currency(code: "USD"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if priceHistory.count >= 2 || !(holding?.ticker.isEmpty ?? true) {
                TickerPriceHistoryChart(
                    points: priceHistory,
                    trendIsPositive: snapshot.percentChange >= 0,
                    style: .compact,
                    symbol: holding?.ticker
                )
            }

            NavigationLink {
                if let holding {
                    TradingViewHoldingChartDetailView(
                        symbol: holding.ticker,
                        fallbackPoints: priceHistory,
                        trendIsPositive: snapshot.percentChange >= 0,
                        marketDataSettings: budget.marketDataSettings
                    )
                }
            } label: {
                Label("Full TradingView Chart", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.semibold))
            }
            .disabled(holding == nil)

            if let dayLow = snapshot.low, let dayHigh = snapshot.high, dayHigh > dayLow {
                let rangeText = "\(dayLow.formatted(.currency(code: "USD"))) - \(dayHigh.formatted(.currency(code: "USD")))"
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Day range")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(rangeText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(max((snapshot.price - dayLow) / (dayHigh - dayLow), 0), 1))
                        .tint(changeTint)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                tickerSnapshotPill("Open", value: snapshot.open, tint: .blue, systemImage: "arrow.up.right")
                tickerSnapshotPill("Prev", value: snapshot.previousClose, tint: .purple, systemImage: "clock.fill")
                tickerSnapshotPill("Low", value: snapshot.low, tint: .pink, systemImage: "arrow.down")
                tickerSnapshotPill("High", value: snapshot.high, tint: .green, systemImage: "arrow.up")
            }

            if let lastUpdated {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("Updated \(lastUpdated, format: .dateTime.month().day().hour().minute())")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(changeTint.opacity(0.20), lineWidth: 1)
        )
    }

    private func tickerSnapshotPill(_ label: String, value: Double?, tint: Color, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let value {
                    Text(value, format: .currency(code: "USD"))
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else {
                    Text("N/A")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func compactMetricCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func yieldBarRow(yieldOnValue: Double, yieldOnCost: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dividend Yields")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            yieldBar(title: "Yield on Current Value", value: yieldOnValue, tint: .blue)
            yieldBar(title: "Yield on Cost", value: yieldOnCost, tint: .green)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func yieldBar(title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value.formatted(.percent.precision(.fractionLength(2))))
                    .font(.caption.weight(.semibold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25))
                    Capsule().fill(tint.opacity(0.8))
                        .frame(width: geo.size.width * min(max(value / 0.10, 0), 1))
                }
            }
            .frame(height: 8)
        }
    }

    private func compactSessionPrices(from snapshot: MarketQuoteSnapshot) -> [Double] {
        let candidateValues: [Double?] = [
            snapshot.previousClose,
            snapshot.open,
            snapshot.low,
            snapshot.price,
            snapshot.high
        ]
        var rawValues: [Double] = []
        for candidate in candidateValues {
            if let value = candidate, value > 0 {
                rawValues.append(value)
            }
        }

        let uniqueValues = rawValues.reduce(into: [Double]()) { values, value in
            if values.last != value {
                values.append(value)
            }
        }

        if uniqueValues.count >= 2 {
            return uniqueValues
        }
        return [snapshot.price, snapshot.price].filter { $0 > 0 }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

private struct EditHoldingView: View {
    @ObservedObject var budget: BudgetModel
    let holding: PortfolioHolding
    @Environment(\.dismiss) private var dismiss
    private let marketDataService = MarketDataService()

    @State private var ticker: String
    @State private var shares: Double
    @State private var averageCost: Double
    @State private var currentPrice: Double
    @State private var annualDividendPerShare: Double
    @State private var dividendFrequency: DividendFrequency
    @State private var assetType: PortfolioAssetType
    @State private var reliability: DividendReliability
    @State private var notes: String
    @State private var quoteFetchTask: Task<Void, Never>?

    init(budget: BudgetModel, holding: PortfolioHolding) {
        self.budget = budget
        self.holding = holding
        _ticker = State(initialValue: holding.ticker)
        _shares = State(initialValue: holding.shares)
        _averageCost = State(initialValue: holding.averageCost)
        _currentPrice = State(initialValue: holding.currentPrice)
        _annualDividendPerShare = State(initialValue: holding.annualDividendPerShare)
        _dividendFrequency = State(initialValue: holding.dividendFrequency)
        _assetType = State(initialValue: holding.assetType)
        _reliability = State(initialValue: holding.dividendReliability)
        _notes = State(initialValue: holding.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Position Details") {
                    TextField("Ticker", text: $ticker)
                        .textInputAutocapitalization(.characters)
                    LabeledContent("Shares") {
                        TextField("0", value: $shares, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Average cost") {
                        TextField("0.00", value: $averageCost, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Current price") {
                        TextField("0.00", value: $currentPrice, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("Dividend & Classification") {
                    LabeledContent("Annual dividend/share") {
                        TextField("0.00", value: $annualDividendPerShare, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Dividend frequency", selection: $dividendFrequency) {
                        ForEach(DividendFrequency.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("Asset type", selection: $assetType) {
                        ForEach(PortfolioAssetType.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("Dividend reliability", selection: $reliability) {
                        ForEach(DividendReliability.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("Edit Holding")
            .onChange(of: ticker) { _, _ in
                queueQuoteFetchIfNeeded()
            }
            .onDisappear {
                quoteFetchTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let idx = budget.holdings.firstIndex(where: { $0.id == holding.id }) else { return }
                        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        guard !cleanTicker.isEmpty, shares > 0 else { return }
                        budget.holdings[idx].ticker = cleanTicker
                        budget.holdings[idx].shares = shares
                        budget.holdings[idx].averageCost = averageCost
                        budget.holdings[idx].currentPrice = currentPrice
                        budget.holdings[idx].annualDividendPerShare = annualDividendPerShare
                        budget.holdings[idx].dividendFrequency = dividendFrequency
                        budget.holdings[idx].assetType = assetType
                        budget.holdings[idx].dividendReliability = reliability
                        budget.holdings[idx].notes = notes
                        dismiss()
                    }
                    .disabled(ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || shares <= 0)
                }
            }
        }
    }

    private func queueQuoteFetchIfNeeded() {
        quoteFetchTask?.cancel()
        quoteFetchTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await fetchQuoteForTicker()
        }
    }

    @MainActor
    private func fetchQuoteForTicker() async {
        let symbol = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard symbol.count >= 1 else { return }

        ticker = symbol
        if let cached = budget.cachedQuotes[symbol], cached.price > 0 {
            currentPrice = cached.price
            return
        }

        guard budget.marketDataSettings.canFetchMarketData else { return }

        do {
            let details = try await marketDataService.fetchQuoteDetails(
                ticker: symbol,
                settings: budget.marketDataSettings
            )
            guard !Task.isCancelled else { return }
            currentPrice = details.price
            budget.cachedQuotes[symbol] = CachedQuote(ticker: symbol, price: details.price, updatedAt: Date())
            if let annualDividend = details.annualDividendPerShare, annualDividend >= 0 {
                annualDividendPerShare = annualDividend
            }
        } catch {
            // Keep manual value if quote lookup fails.
        }
    }
}

private struct ManualHoldingEntryView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss
    private let marketDataService = MarketDataService()

    @State private var ticker = ""
    @State private var shares = 0.0
    @State private var averageCost = 0.0
    @State private var currentPrice = 0.0
    @State private var annualDividendPerShare = 0.0
    @State private var dividendFrequency: DividendFrequency = .quarterly
    @State private var assetType: PortfolioAssetType = .dividendStock
    @State private var reliability: DividendReliability = .medium
    @State private var notes = ""
    @State private var date = Date()
    @State private var quoteFetchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Position Details") {
                    TextField("Ticker", text: $ticker)
                        .textInputAutocapitalization(.characters)
                    LabeledContent("Shares") {
                        TextField("0", value: $shares, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Average cost") {
                        TextField("0.00", value: $averageCost, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Current price") {
                        TextField("0.00", value: $currentPrice, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("Dividend & Classification") {
                    LabeledContent("Annual dividend/share") {
                        TextField("0.00", value: $annualDividendPerShare, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Dividend frequency", selection: $dividendFrequency) {
                        ForEach(DividendFrequency.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("Asset type", selection: $assetType) {
                        ForEach(PortfolioAssetType.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("Dividend reliability", selection: $reliability) {
                        ForEach(DividendReliability.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                }
                Section("Notes & Date") {
                    TextField("Notes", text: $notes)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Add Manual Holding")
            .onChange(of: ticker) { _, _ in
                queueQuoteFetchIfNeeded()
            }
            .onDisappear {
                quoteFetchTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        guard !cleanTicker.isEmpty, shares > 0 else { return }
                        budget.addPortfolioTransaction(
                            PortfolioTransaction(
                                date: date,
                                type: .buy,
                                ticker: cleanTicker,
                                shares: shares,
                                pricePerShare: averageCost,
                                amount: shares * averageCost,
                                notes: "Manual holding entry"
                            ),
                            affectsBalances: false
                        )
                        if let idx = budget.holdings.firstIndex(where: { $0.ticker.uppercased() == cleanTicker }) {
                            budget.holdings[idx].currentPrice = max(currentPrice, budget.holdings[idx].currentPrice)
                            budget.holdings[idx].annualDividendPerShare = annualDividendPerShare
                            budget.holdings[idx].dividendFrequency = dividendFrequency
                            budget.holdings[idx].assetType = assetType
                            budget.holdings[idx].dividendReliability = reliability
                            budget.holdings[idx].notes = notes
                        }
                        dismiss()
                    }
                    .disabled(ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || shares <= 0)
                }
            }
        }
    }

    private func queueQuoteFetchIfNeeded() {
        quoteFetchTask?.cancel()
        quoteFetchTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await fetchQuoteForTicker()
        }
    }

    @MainActor
    private func fetchQuoteForTicker() async {
        let symbol = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard symbol.count >= 1 else { return }

        ticker = symbol
        if let cached = budget.cachedQuotes[symbol], cached.price > 0 {
            currentPrice = cached.price
            return
        }

        guard budget.marketDataSettings.canFetchMarketData else { return }

        do {
            let details = try await marketDataService.fetchQuoteDetails(
                ticker: symbol,
                settings: budget.marketDataSettings
            )
            guard !Task.isCancelled else { return }
            currentPrice = details.price
            budget.cachedQuotes[symbol] = CachedQuote(ticker: symbol, price: details.price, updatedAt: Date())
            if let annualDividend = details.annualDividendPerShare, annualDividend >= 0 {
                annualDividendPerShare = annualDividend
            }
        } catch {
            // Keep manual value if quote lookup fails.
        }
    }
}

private struct SnapshotDetailSheet: View {
    @ObservedObject var budget: BudgetModel
    let totalMarketValue: Double
    let grossPortfolioValue: Double
    let netPortfolioValue: Double
    let interestFreeMarginRemaining: Double
    let paidMarginAmount: Double
    let monthToDateContributions: Double
    let monthToDateBills: Double
    let monthToDateDividends: Double
    let netMarginChangeThisMonth: Double
    let monthsUntilFreeLimit: Double
    let maintenanceBufferEstimate: Double
    let estimatedMonthlyMarginCostAtFivePercent: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Core Snapshot") {
                    metricRow("Holdings Value", totalMarketValue)
                    metricRow("Gross Portfolio Value", grossPortfolioValue)
                    metricRow("Net Portfolio Value", netPortfolioValue)
                    metricRow("Margin Used", budget.portfolioSnapshot.marginUsed)
                    metricRow("Interest-Free Margin Remaining", interestFreeMarginRemaining)
                    metricRow("Paid Margin Amount", paidMarginAmount)
                }

                Section("Limits & Costs") {
                    metricRow("Interest-Free Margin Limit", budget.marginSettings.interestFreeMarginLimit)
                    metricRow("Margin Interest Rate", budget.marginSettings.marginInterestRate, asPercent: true)
                    metricRow("Personal Cap Utilization", budget.portfolioSnapshot.marginUsed / max(budget.marginSettings.personalMarginCap, 1), asPercent: true)
                    metricRow("Monthly Margin Cost (5%)", estimatedMonthlyMarginCostAtFivePercent)
                }

                Section("Month to Date") {
                    metricRow("Contributions", monthToDateContributions)
                    metricRow("Bills Paid by Margin", monthToDateBills)
                    metricRow("Dividends", monthToDateDividends)
                    metricRow("Net Margin Change", netMarginChangeThisMonth)
                    metricRow("Months Until Free Margin Limit", monthsUntilFreeLimit, asPlain: true)
                    metricRow("Maintenance Buffer Estimate", maintenanceBufferEstimate)
                }
            }
            .navigationTitle("Snapshot Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func metricRow(_ title: String, _ value: Double, asPercent: Bool = false, asPlain: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            if asPlain {
                Text(value, format: .number.precision(.fractionLength(1))).fontWeight(.semibold)
            } else if asPercent {
                Text(value, format: .percent.precision(.fractionLength(2))).fontWeight(.semibold)
            } else {
                Text(value, format: .currency(code: "USD")).fontWeight(.semibold)
            }
        }
    }
}

private struct AddTransactionView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var type: PortfolioTransactionType = .contribution
    @State private var ticker = ""
    @State private var shares = 0.0
    @State private var pricePerShare = 0.0
    @State private var amount = 0.0
    @State private var notes = ""
    @State private var fundingBankAccount = ""

    private var bankAccountOptions: [String] {
        let names = (budget.bankAccounts.map(\.name) + [fundingBankAccount])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    private var cleanTicker: String {
        ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var transactionAmount: Double {
        amount != 0 ? amount : shares * pricePerShare
    }

    private var amountFieldTitle: String {
        switch type {
        case .marginInterest:
            return "Interest accrued"
        case .billPaidByMargin:
            return "Bill amount"
        case .dividend:
            return "Dividend received"
        case .contribution:
            return "Cash added"
        default:
            return "Amount"
        }
    }

    private var canSave: Bool {
        switch type {
        case .buy, .sell:
            return !cleanTicker.isEmpty && shares > 0 && transactionAmount > 0
        case .contribution:
            let hasFundingAccount = !fundingBankAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return transactionAmount > 0 && hasFundingAccount
        case .manualAdjustment:
            return transactionAmount != 0
        case .dividend, .billPaidByMargin, .marginInterest:
            return transactionAmount > 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Position Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Type", selection: $type) {
                        ForEach(PortfolioTransactionType.allCases) { txType in
                            Text(txType.title).tag(txType)
                        }
                    }
                    if type == .contribution {
                        Picker("From Account", selection: $fundingBankAccount) {
                            ForEach(bankAccountOptions, id: \.self) { accountName in
                                Text(accountName).tag(accountName)
                            }
                        }
                        if budget.bankAccounts.isEmpty {
                            Text("Add a bank account before recording a portfolio contribution.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let selectedAccount {
                            LabeledContent("Available", value: selectedAccount.balance.formatted(.currency(code: "USD")))
                        }
                    }
                    TextField("Ticker (optional)", text: $ticker)
                        .textInputAutocapitalization(.characters)
                    LabeledContent("Shares (optional)") {
                        TextField("0", value: $shares, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Price/share (optional)") {
                        TextField("0.00", value: $pricePerShare, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DelayedCurrencyField(title: amountFieldTitle, value: $amount)
                }
                if type == .marginInterest {
                    Section("Margin Interest") {
                        Text("This logs interest accrued and adds it to the margin balance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes)
                }
            }
            .navigationTitle("Add Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        budget.addPortfolioTransaction(
                            PortfolioTransaction(
                                date: date,
                                type: type,
                                ticker: cleanTicker.nilIfBlank,
                                shares: shares > 0 ? shares : nil,
                                pricePerShare: pricePerShare > 0 ? pricePerShare : nil,
                                amount: transactionAmount,
                                notes: notes.nilIfBlank,
                                fundingBankAccount: type == .contribution ? fundingBankAccount.nilIfBlank : nil
                            ),
                            fundingBankAccount: type == .contribution ? fundingBankAccount : nil
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if fundingBankAccount.isEmpty {
                    fundingBankAccount = budget.bankAccounts.first?.name ?? ""
                }
            }
            .onChange(of: type) { _, newValue in
                guard newValue == .contribution, fundingBankAccount.isEmpty else { return }
                fundingBankAccount = budget.bankAccounts.first?.name ?? ""
            }
        }
    }

    private var selectedAccount: BankAccount? {
        let selected = fundingBankAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return nil }
        return budget.bankAccounts.first { $0.name.caseInsensitiveCompare(selected) == .orderedSame }
    }
}

private struct AddInvestmentView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss
    private let marketDataService = MarketDataService()

    @State private var ticker = ""
    @State private var dollarsInvested = 0.0
    @State private var sharesBought = 0.0
    @State private var pricePerShare = 0.0
    @State private var annualDividendPerShare = 0.0
    @State private var dividendFrequency: DividendFrequency = .quarterly
    @State private var assetType: PortfolioAssetType = .dividendStock
    @State private var reliability: DividendReliability = .medium
    @State private var date = Date()
    @State private var quoteFetchTask: Task<Void, Never>?

    private var cleanTicker: String {
        ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var investmentAmount: Double {
        dollarsInvested > 0 ? dollarsInvested : sharesBought * pricePerShare
    }

    private var canSave: Bool {
        !cleanTicker.isEmpty && sharesBought > 0 && investmentAmount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Position Details") {
                    TextField("Ticker", text: $ticker)
                        .textInputAutocapitalization(.characters)
                    DelayedCurrencyField(title: "Dollars invested", value: $dollarsInvested)
                    LabeledContent("Shares bought") {
                        TextField("0", value: $sharesBought, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Price per share") {
                        TextField("0.00", value: $pricePerShare, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("Dividend & Classification") {
                    LabeledContent("Annual dividend/share") {
                        TextField("0.00", value: $annualDividendPerShare, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Dividend frequency", selection: $dividendFrequency) {
                        ForEach(DividendFrequency.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("Asset type", selection: $assetType) {
                        ForEach(PortfolioAssetType.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("Dividend reliability", selection: $reliability) {
                        ForEach(DividendReliability.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                }
                Section("Notes & Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    LabeledContent("Funding", value: "Cash/Margin")
                }
            }
            .navigationTitle("Add Investment")
            .onChange(of: ticker) { _, _ in
                applyExistingHoldingDefaults()
                queueQuoteFetchIfNeeded()
            }
            .onDisappear {
                quoteFetchTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let existingHolding = budget.holdings.first { $0.ticker.uppercased() == cleanTicker }
                        let dividendToSave = annualDividendPerShare > 0
                            ? annualDividendPerShare
                            : (existingHolding?.annualDividendPerShare ?? 0)
                        let frequencyToSave = annualDividendPerShare > 0 || existingHolding == nil
                            ? dividendFrequency
                            : (existingHolding?.dividendFrequency ?? dividendFrequency)
                        budget.addInvestment(
                            ticker: cleanTicker,
                            dollarsInvested: investmentAmount,
                            sharesBought: sharesBought,
                            pricePerShare: pricePerShare,
                            date: date,
                            fundingSource: .cash
                        )
                        if let idx = budget.holdings.firstIndex(where: { $0.ticker.uppercased() == cleanTicker }) {
                            budget.holdings[idx].annualDividendPerShare = dividendToSave
                            budget.holdings[idx].dividendFrequency = frequencyToSave
                            budget.holdings[idx].assetType = assetType
                            budget.holdings[idx].dividendReliability = reliability
                        }
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func applyExistingHoldingDefaults() {
        guard let holding = budget.holdings.first(where: { $0.ticker.uppercased() == cleanTicker }) else { return }
        if annualDividendPerShare <= 0 {
            annualDividendPerShare = holding.annualDividendPerShare
        }
        dividendFrequency = holding.dividendFrequency
        assetType = holding.assetType
        reliability = holding.dividendReliability
        if pricePerShare <= 0 {
            pricePerShare = holding.currentPrice
        }
    }

    private func queueQuoteFetchIfNeeded() {
        quoteFetchTask?.cancel()
        quoteFetchTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await fetchQuoteForTicker()
        }
    }

    @MainActor
    private func fetchQuoteForTicker() async {
        let symbol = cleanTicker
        guard !symbol.isEmpty else { return }
        ticker = symbol

        if let cached = budget.cachedQuotes[symbol], cached.price > 0, pricePerShare <= 0 {
            pricePerShare = cached.price
        }

        guard budget.marketDataSettings.canFetchMarketData else { return }
        do {
            let details = try await marketDataService.fetchQuoteDetails(
                ticker: symbol,
                settings: budget.marketDataSettings
            )
            guard !Task.isCancelled else { return }
            if pricePerShare <= 0 {
                pricePerShare = details.price
            }
            budget.cachedQuotes[symbol] = CachedQuote(ticker: symbol, price: details.price, updatedAt: Date())
            if let annualDividend = details.annualDividendPerShare, annualDividend > 0, annualDividendPerShare <= 0 {
                annualDividendPerShare = annualDividend
            }
        } catch {
            // Keep manually entered or existing holding values if lookup fails.
        }
    }
}

private struct ElectricBillTrackerView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss

    @State private var actualPaidAmount = 0.0
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill Settings") {
                    TextField("Bill name", text: $budget.recurringElectricBill.name)
                    DelayedCurrencyField(title: "Expected monthly amount", value: $budget.recurringElectricBill.expectedAmount)

                    Stepper(value: $budget.recurringElectricBill.dueDay, in: 1...31) {
                        Text("Due day: \(budget.recurringElectricBill.dueDay)")
                    }

                    Toggle("Active", isOn: $budget.recurringElectricBill.isActive)
                    Toggle("Paid by margin", isOn: $budget.recurringElectricBill.paidByMargin)
                }
                Section("Payment Log") {
                    DelayedCurrencyField(title: "Actual paid amount", value: $actualPaidAmount)
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)

                    Button("Mark Paid Using Margin") {
                        let paid = actualPaidAmount > 0 ? actualPaidAmount : budget.recurringElectricBill.expectedAmount
                        budget.markElectricBillPaidByMargin(actualAmount: paid, date: dueDate)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!budget.recurringElectricBill.paidByMargin || (actualPaidAmount <= 0 && budget.recurringElectricBill.expectedAmount <= 0))
                }
            }
            .navigationTitle("Electric Bill")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct MarginSettingsView: View {
    @Binding var settings: MarginSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Limits") {
                    DelayedCurrencyField(title: "Total margin available", value: $settings.totalMarginAvailable)
                    DelayedCurrencyField(title: "Interest-free margin limit", value: $settings.interestFreeMarginLimit)
                    DelayedCurrencyField(title: "Personal max margin cap", value: $settings.personalMarginCap)
                }

                Section("Rates & Requirements") {
                    TextField("Margin rate", value: $settings.marginInterestRate, format: .percent)
                        .keyboardType(.decimalPad)
                    TextField("Maintenance requirement %", value: $settings.maintenanceRequirementPercent, format: .percent)
                        .keyboardType(.decimalPad)
                    TextField("Warning threshold %", value: $settings.warningThresholdPercent, format: .percent)
                        .keyboardType(.decimalPad)
                    TextField("Danger threshold %", value: $settings.dangerThresholdPercent, format: .percent)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Margin Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct LedgerHistoryView: View {
    @ObservedObject var budget: BudgetModel
    @State private var selectedTransaction: PortfolioTransaction?

    private var monthGroups: [(String, [PortfolioTransaction])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        let groups = Dictionary(grouping: budget.portfolioTransactions.sorted { $0.date > $1.date }) { tx in
            formatter.string(from: tx.date)
        }
        return groups.sorted { lhs, rhs in
            let lhsDate = groups[lhs.key]?.first?.date ?? .distantPast
            let rhsDate = groups[rhs.key]?.first?.date ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !budget.portfolioValueHistory.isEmpty {
                    Section("Portfolio Value by Date") {
                        ForEach(budget.portfolioValueHistory.sorted(by: { $0.date > $1.date }).prefix(30)) { point in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(point.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Text("Portfolio")
                                    Spacer()
                                    Text(point.grossValue, format: .currency(code: "USD"))
                                }
                                HStack {
                                    Text("Net Equity")
                                    Spacer()
                                    Text(point.netValue, format: .currency(code: "USD"))
                                }
                            }
                        }
                    }
                }
                ForEach(monthGroups, id: \.0) { month, items in
                    Section(month) {
                        totalsHeader(items)
                        ForEach(items) { tx in
                            Button {
                                selectedTransaction = tx
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(tx.type.title)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        Text(tx.amount, format: .currency(code: "USD"))
                                    }
                                    HStack {
                                        if let ticker = tx.ticker, !ticker.isEmpty {
                                            Text(ticker)
                                        }
                                        if tx.type == .contribution, let account = tx.fundingBankAccount, !account.isEmpty {
                                            Text("From \(account)")
                                        }
                                        Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Activity Ledger")
            .sheet(item: $selectedTransaction) { transaction in
                EditPortfolioTransactionView(
                    budget: budget,
                    transactionID: transaction.id
                )
            }
        }
    }

    private func totalsHeader(_ items: [PortfolioTransaction]) -> some View {
        let contributions = sum(items, .contribution)
        let dividends = sum(items, .dividend)
        let bills = sum(items, .billPaidByMargin)
        let interest = sum(items, .marginInterest)
        let buys = sum(items, .buy)
        let sells = sum(items, .sell)
        let netMargin = items.reduce(0) { partial, tx in
            switch tx.type {
            case .billPaidByMargin, .marginInterest, .manualAdjustment:
                return partial + tx.amount
            case .sell:
                return partial - tx.amount
            default:
                return partial
            }
        }

        let trueSpread = dividends - bills - interest
        return VStack(alignment: .leading, spacing: 2) {
            Text("Contrib \(contributions, format: .currency(code: "USD"))  Div \(dividends, format: .currency(code: "USD"))")
            Text("Bills \(bills, format: .currency(code: "USD"))  Interest \(interest, format: .currency(code: "USD"))")
            Text("Buys \(buys, format: .currency(code: "USD"))  Sells \(sells, format: .currency(code: "USD"))")
            Text("Net Margin Change \(netMargin, format: .currency(code: "USD"))")
            Text("True Monthly Spread \(trueSpread, format: .currency(code: "USD"))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func sum(_ items: [PortfolioTransaction], _ type: PortfolioTransactionType) -> Double {
        items.filter { $0.type == type }.reduce(0) { $0 + $1.amount }
    }
}

private struct EditPortfolioTransactionView: View {
    @ObservedObject var budget: BudgetModel
    let transactionID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var type: PortfolioTransactionType = .contribution
    @State private var ticker = ""
    @State private var shares = 0.0
    @State private var pricePerShare = 0.0
    @State private var amount = 0.0
    @State private var notes = ""
    @State private var isLoaded = false

    private var transactionIndex: Int? {
        budget.portfolioTransactions.firstIndex(where: { $0.id == transactionID })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction Info") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Type", selection: $type) {
                        ForEach(PortfolioTransactionType.allCases) { txType in
                            Text(txType.title).tag(txType)
                        }
                    }
                }
                Section("Position Inputs") {
                    TextField("Ticker (optional)", text: $ticker)
                        .textInputAutocapitalization(.characters)
                    TextField("Shares (optional)", value: $shares, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Price/share (optional)", value: $pricePerShare, format: .number)
                        .keyboardType(.decimalPad)
                    DelayedCurrencyField(title: "Amount", value: $amount)
                    TextField("Notes (optional)", text: $notes)
                }
                Section("Danger Zone") {
                    Button("Delete Transaction", role: .destructive) {
                        guard transactionIndex != nil else { return }
                        budget.deletePortfolioTransaction(id: transactionID)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Transaction")
            .onAppear {
                guard !isLoaded else { return }
                guard let transactionIndex else {
                    dismiss()
                    return
                }
                let transaction = budget.portfolioTransactions[transactionIndex]
                date = transaction.date
                type = transaction.type
                ticker = transaction.ticker ?? ""
                shares = transaction.shares ?? 0
                pricePerShare = transaction.pricePerShare ?? 0
                amount = transaction.amount
                notes = transaction.notes ?? ""
                isLoaded = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let transactionIndex else { return }
                        let existing = budget.portfolioTransactions[transactionIndex]
                        budget.updatePortfolioTransaction(
                            PortfolioTransaction(
                                id: existing.id,
                                date: date,
                                type: type,
                                ticker: ticker.nilIfBlank?.uppercased(),
                                shares: shares > 0 ? shares : nil,
                                pricePerShare: pricePerShare > 0 ? pricePerShare : nil,
                                amount: amount,
                                notes: notes.nilIfBlank,
                                fundingBankAccount: existing.fundingBankAccount
                            )
                        )
                        dismiss()
                    }
                    .disabled(amount == 0)
                }
            }
        }
    }
}

private struct DelayedCurrencyField: View {
    let title: String
    @Binding var value: Double

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(title: String, value: Binding<Double>) {
        self.title = title
        self._value = value
        _text = State(initialValue: Self.editText(from: value.wrappedValue))
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        text = Self.editText(from: value)
                    } else {
                        commit()
                    }
                }
                .onSubmit { commit() }
        }
    }

    private func commit() {
        let parsed = Self.parseCurrency(text) ?? value
        value = parsed
        text = Self.displayText(from: parsed)
    }

    private static func parseCurrency(_ raw: String) -> Double? {
        let clean = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return 0 }
        return Double(clean)
    }

    private static func editText(from value: Double) -> String {
        let asInt = Int(value)
        if value == Double(asInt) {
            return String(asInt)
        }
        return String(value)
    }

    private static func displayText(from value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

private extension String {
    var nilIfBlank: String? {
        let clean = trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
