import SwiftUI
import Charts

private enum HoldingsViewMode: String, CaseIterable, Identifiable {
    case minimized = "Minimized"
    case full = "Full"
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

    @State private var holdingsViewMode: HoldingsViewMode = .full
    @State private var isRefreshingPrices = false
    @State private var selectedHolding: PortfolioHolding?
    @State private var selectedNetWorthRange: NetWorthRange = .threeMonths
    @State private var selectedNetWorthPoint: PortfolioValuePoint?
    @State private var showSnapshotDetails = false
    @State private var refreshProgressTotal = 0
    @State private var refreshProgressCompleted = 0
    @State private var refreshCurrentTicker = ""
    @State private var holdingQuoteSnapshots: [String: MarketQuoteSnapshot] = [:]
    @State private var holdingQuoteCloses: [String: [Double]] = [:]
    @State private var holdingsSortOption: HoldingsSortOption = .ticker
    @State private var holdingsSortAscending = true
    @State private var holdingsAssetFilter: HoldingsAssetFilter = .all

    private let marketDataService = MarketDataService()
    private let drawdowns: [Double] = [0.20, 0.35, 0.50]

    private var displayHoldings: [PortfolioHolding] {
        let filtered = budget.holdings.filter { holding in
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
                return sort(allocation(for: lhs), allocation(for: rhs))
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

    private var sortedHoldings: [PortfolioHolding] {
        budget.holdings.sorted { $0.ticker.uppercased() < $1.ticker.uppercased() }
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
        sortedHoldings.reduce(0) { $0 + ($1.shares * resolvedPrice(for: $1)) }
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
        sortedHoldings.reduce(0) { $0 + ($1.shares * $1.annualDividendPerShare) }
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
        budget.portfolioSnapshot.marginUsed * 0.05 / 12.0
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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                titleHeader
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
        .task {
            await runHoldingsAutoRefreshLoop()
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
            HoldingTickerDetailView(
                budget: budget,
                holdingID: holding.id
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Margin & Dividend Tracker")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            Spacer()
        }
    }

    private var portfolioSnapshotCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Portfolio Snapshot")
                        .font(.headline)
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
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Holdings")
                        .font(.headline)
                    Spacer()
                    Button("Refresh Price") {
                        Task { await refreshPrices() }
                    }
                        .buttonStyle(.bordered)
                        .disabled(isRefreshingPrices)
                }

                if isRefreshingPrices {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Refreshing \(refreshCurrentTicker)...")
                            Spacer()
                            Text("\(refreshProgressCompleted)/\(refreshProgressTotal)")
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                        ProgressView(
                            value: Double(refreshProgressCompleted),
                            total: Double(max(refreshProgressTotal, 1))
                        )
                    }
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

                if budget.holdings.isEmpty {
                    Text("No holdings yet. Use + to add investment or manual holding.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if displayHoldings.isEmpty {
                    Text("No holdings match the current filter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("Ticker")
                        Spacer()
                        Text("Value")
                        Spacer()
                        Text("Monthly")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    ForEach(displayHoldings) { holding in
                        let marketValue = holding.shares * resolvedPrice(for: holding)
                        let totalCost = holding.shares * holding.averageCost
                        let annualIncome = holding.shares * holding.annualDividendPerShare
                        let monthlyIncome = annualIncome / 12.0
                        let allocation = allocation(for: holding)
                        let unrealized = marketValue - totalCost
                        Button {
                            selectedHolding = holding
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(holding.ticker)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(color(for: holding.assetType))
                                    Spacer()
                                    Text(marketValue, format: .currency(code: "USD"))
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(monthlyIncome, format: .currency(code: "USD"))
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Text("\(holding.shares, format: .number.precision(.fractionLength(0...4))) shares")
                                    Spacer()
                                    Text(holding.assetType.rawValue)
                                        .lineLimit(1)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .foregroundStyle(color(for: holding.assetType))
                                        .background(color(for: holding.assetType).opacity(0.16), in: Capsule())
                                    Spacer()
                                    Text("Alloc \(allocation, format: .percent.precision(.fractionLength(1)))")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if holdingsViewMode == .full {
                                    HStack {
                                        Text("Monthly \(monthlyIncome, format: .currency(code: "USD"))")
                                        Spacer()
                                        Text("Yield \(currentYield(for: holding), format: .percent.precision(.fractionLength(2)))")
                                        Spacer()
                                        Text("Unrealized \(unrealized, format: .currency(code: "USD"))")
                                            .foregroundStyle(unrealized >= 0 ? .green : .red)
                                    }
                                    .font(.caption)

                                    holdingTickerSnapshot(for: holding)
                                }
                            }
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()
                metricRow("Portfolio Monthly Income", monthlyDividends)
                metricRow("Portfolio Annual Income", annualDividendsFromHoldings)
            }
        }
    }

    private var netWorthChartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text("Net Worth Over Time")
                        .font(.headline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(netPortfolioValue, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.semibold))
                        if let latestHoldingsUpdate {
                            Text("Updated \(latestHoldingsUpdate, format: .dateTime.month().day().year().hour().minute())")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Updated: --")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                let points = netWorthHistoryPoints
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
                        .foregroundStyle(.green.opacity(0.18))

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Net Worth", point.netValue)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.green)

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Gross Portfolio", point.grossValue)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.blue.opacity(0.7))

                        if let selectedNetWorthPoint {
                            RuleMark(x: .value("Date", selectedNetWorthPoint.date))
                                .foregroundStyle(.secondary.opacity(0.35))
                            PointMark(
                                x: .value("Date", selectedNetWorthPoint.date),
                                y: .value("Net Worth", selectedNetWorthPoint.netValue)
                            )
                            .foregroundStyle(.green)
                        }
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
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisTick()
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
                    .frame(height: 220)

                    marginNetWorthRangeSelector

                    HStack(spacing: 14) {
                        Label("Net Worth", systemImage: "line.diagonal")
                            .foregroundStyle(.green)
                        Label("Gross Portfolio", systemImage: "line.diagonal")
                            .foregroundStyle(.blue)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var marginNetWorthRangeSelector: some View {
        HStack(spacing: 8) {
            ForEach(NetWorthRange.allCases) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedNetWorthRange = range
                    }
                } label: {
                    Text(range.title)
                        .font(.caption.weight(.bold))
                        .kerning(0.4)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selectedNetWorthRange == range ? .white : .primary)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedNetWorthRange == range ? Color.accentColor : Color.clear)
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
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
    }

    private var dividendForecastCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Dividend Forecast")
                    .font(.headline)
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
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Bill Tracking")
                        .font(.headline)
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
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Safety Dashboard")
                    .font(.headline)

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

    private func holdingTickerSnapshot(for holding: PortfolioHolding) -> some View {
        let ticker = holding.ticker.uppercased()
        let snapshot = holdingQuoteSnapshot(for: holding)
        let changeTint: Color = snapshot.percentChange >= 0 ? .green : .red
        let closes = holdingQuoteCloses[ticker] ?? compactSessionPrices(from: snapshot)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: snapshot.percentChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(snapshot.percentChange / 100, format: .percent.precision(.fractionLength(2)))
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(changeTint)
                Text(snapshot.change, format: .currency(code: "USD"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let updatedAt = budget.cachedQuotes[ticker]?.updatedAt {
                    Text("Updated \(updatedAt, format: .dateTime.month().day().hour().minute())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                tickerSnapshotPill("Open", value: snapshot.open)
                tickerSnapshotPill("Prev", value: snapshot.previousClose)
                tickerSnapshotPill("Low", value: snapshot.low)
                tickerSnapshotPill("High", value: snapshot.high)
            }

            if let dayLow = snapshot.low, let dayHigh = snapshot.high, dayHigh > dayLow {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Day range")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(dayLow, format: .currency(code: "USD")) - \(dayHigh, format: .currency(code: "USD"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(max((snapshot.price - dayLow) / (dayHigh - dayLow), 0), 1))
                        .tint(changeTint)
                }
            }

            if closes.count >= 2 {
                Chart(Array(closes.enumerated()), id: \.offset) { item in
                    LineMark(
                        x: .value("Point", item.offset),
                        y: .value("Price", item.element)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(changeTint)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 38)
            }
        }
        .padding(.top, 4)
    }

    private func tickerSnapshotPill(_ label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let value {
                Text(value, format: .currency(code: "USD"))
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("N/A")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func sum(_ items: [PortfolioTransaction], type: PortfolioTransactionType) -> Double {
        items.filter { $0.type == type }.reduce(0) { $0 + $1.amount }
    }

    private func currentYield(for holding: PortfolioHolding) -> Double {
        let price = resolvedPrice(for: holding)
        guard price > 0 else { return 0 }
        return holding.annualDividendPerShare / price
    }

    private func allocation(for holding: PortfolioHolding) -> Double {
        guard totalMarketValue > 0 else { return 0 }
        return (holding.shares * resolvedPrice(for: holding)) / totalMarketValue
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
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Experiment Status")
                        .font(.headline)
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
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Monthly Summary")
                    .font(.headline)
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
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Monthly Dividends vs Margin Interest")
                    .font(.headline)

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

    private func runHoldingsAutoRefreshLoop() async {
        await refreshPrices()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            if Task.isCancelled { break }
            await refreshPrices()
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
                holdingQuoteCloses[ticker] = compactSessionPrices(from: snapshot)
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
    @Environment(\.dismiss) private var dismiss
    @State private var showEditHolding = false
    @State private var selectedTransaction: PortfolioTransaction?

    private var holding: PortfolioHolding? {
        budget.holdings.first(where: { $0.id == holdingID })
    }

    private var lastUpdated: Date? {
        guard let holding else { return nil }
        return budget.cachedQuotes[holding.ticker.uppercased()]?.updatedAt
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
                        VStack(alignment: .leading, spacing: 14) {
                            performanceHero(
                                marketValue: marketValue,
                                unrealized: unrealized,
                                unrealizedPct: unrealizedPct
                            )
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
                            if !holding.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(holding.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 4)
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
            .navigationTitle(holding?.ticker ?? "Holding")
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
                            )
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
                    DelayedCurrencyField(title: "Amount", value: $amount)
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
                                ticker: ticker.nilIfBlank,
                                shares: shares > 0 ? shares : nil,
                                pricePerShare: pricePerShare > 0 ? pricePerShare : nil,
                                amount: amount,
                                notes: notes.nilIfBlank
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

private struct AddInvestmentView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss

    @State private var ticker = ""
    @State private var dollarsInvested = 0.0
    @State private var sharesBought = 0.0
    @State private var pricePerShare = 0.0
    @State private var date = Date()
    @State private var fundingSource: InvestmentFundingSource = .cash

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
                Section("Notes & Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Funding Source", selection: $fundingSource) {
                        ForEach(InvestmentFundingSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                }
            }
            .navigationTitle("Add Investment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        budget.addInvestment(
                            ticker: ticker,
                            dollarsInvested: dollarsInvested,
                            sharesBought: sharesBought,
                            pricePerShare: pricePerShare,
                            date: date,
                            fundingSource: fundingSource
                        )
                        dismiss()
                    }
                    .disabled(ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dollarsInvested <= 0 || sharesBought <= 0)
                }
            }
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
                        guard let transactionIndex else { return }
                        budget.portfolioTransactions.remove(at: transactionIndex)
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
                        budget.portfolioTransactions[transactionIndex].date = date
                        budget.portfolioTransactions[transactionIndex].type = type
                        budget.portfolioTransactions[transactionIndex].ticker = ticker.nilIfBlank?.uppercased()
                        budget.portfolioTransactions[transactionIndex].shares = shares > 0 ? shares : nil
                        budget.portfolioTransactions[transactionIndex].pricePerShare = pricePerShare > 0 ? pricePerShare : nil
                        budget.portfolioTransactions[transactionIndex].amount = amount
                        budget.portfolioTransactions[transactionIndex].notes = notes.nilIfBlank
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
