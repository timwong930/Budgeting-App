//
//  ContentView.swift
//  Budgeting App
//
//  Created by Timothy Wong on 1/16/26.
//

import SwiftUI
import UIKit
import Charts

struct ContentView: View {
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
    @State private var lastExpenseCategoryId: UUID?
    @State private var lastExpenseSection: BudgetSection = .needs
    @State private var selectedMonth: Date = Date()
    @State private var selectedSpendingPoint: DailySpend?
    @State private var selectedIncomePoint: DailySpend?
    @State private var selectedLogTrend: LogTrend = .spending
    @State private var selectedTrendRange: TrendRange = .monthToDate
    @State private var budgetPageFocus: BudgetPageFocus = .plan
    @State private var selectedCalendarDay: CalendarDaySelection?
    @State private var editingRecurringPayment: RecurringPayment?
    @State private var calendarPageIndex: Int = 12
    @State private var showingCreditAccounts = false
    @State private var showingBankAccounts = false
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
    @State private var spyComparison: SpyComparisonResult?
    @State private var isLoadingSpyComparison = false
    @State private var spyComparisonError: String?
    @State private var selectedHomeNetWorthRange: HomeNetWorthRange = .threeMonths
    @State private var selectedHomeNetWorthPoint: PortfolioValuePoint?
    @FocusState private var focusedField: FocusedField?
    private let marketDataService = MarketDataService()

    private struct SpyComparisonResult {
        let periodLabel: String
        let portfolioReturn: Double
        let spyReturn: Double
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
        case monthToDate = "Month to date"
        case last7Days = "Last 7 days"
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

    private enum BudgetPageFocus: String, CaseIterable, Identifiable {
        case plan = "Plan"
        case log = "Log"

        var id: String { rawValue }
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

    private struct CalendarDaySelection: Identifiable {
        let id = UUID()
        let date: Date
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch selectedTab {
                case .home:
                    homeTab
                case .calendar:
                    calendarTab
                case .budget:
                    budgetTab
                case .margin:
                    marginTab
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
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
                            selectedCalendarDay = CalendarDaySelection(date: selectedMonth)
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
                        case .electricBill:
                            showingMarginElectricBill = true
                        case .marginSettings:
                            showingMarginSettings = true
                        case .ledgerHistory:
                            showingMarginHistory = true
                        }
                    }
                )
                .frame(maxWidth: .infinity, alignment: isTabBarMinimized ? .trailing : .center)
                .padding(.trailing, isTabBarMinimized ? 12 : 0)
                .padding(.bottom, 8)
            }
            .onAppear {
                budget.income = budget.income(for: selectedMonth)
                budget.applyMonthlyAllocations(for: selectedMonth)
                updateMonthlyData()
            }
            .onChange(of: selectedMonth) { _, newValue in
                budget.income = budget.income(for: newValue)
                budget.applyMonthlyAllocations(for: newValue)
                updateMonthlyData()
            }
            .onChange(of: budget.income) { _, newValue in
                budget.setIncome(newValue, for: selectedMonth)
            }
            .onChange(of: budget.expenses) { _, _ in
                updateMonthlyData()
            }
            .onChange(of: budget.incomes) { _, _ in
                updateMonthlyData()
            }
            .onChange(of: budget.savingsEntries) { _, _ in
                updateMonthlyData()
            }
            .task(id: selectedTab) {
                guard selectedTab == .home else { return }
                await refreshSpyComparison()
            }
        }
        .sheet(isPresented: $showingAddNeedsCategory) {
            AddCategoryView(budget: budget, categoryType: .needs, selectedMonth: selectedMonth)
        }
        .sheet(isPresented: $showingAddWantsCategory) {
            AddCategoryView(budget: budget, categoryType: .wants, selectedMonth: selectedMonth)
        }
        .sheet(item: $editingCategory) { category in
            EditCategoryView(budget: budget, category: category, selectedMonth: selectedMonth)
        }
        .sheet(isPresented: $showingAddSavingsGoal) {
            AddSavingsGoalView(budget: budget)
        }
        .sheet(item: $editingSavingsGoal) { goal in
            EditSavingsGoalView(budget: budget, savingsGoal: goal)
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
        }
        .sheet(item: $savingsEntryDraft) { draft in
            AddSavingsEntryView(
                budget: budget,
                selectedMonth: selectedMonth,
                preselectedGoalId: draft.goalId
            )
        }
        .sheet(isPresented: $showingAddIncome) {
            AddIncomeView(budget: budget, selectedMonth: selectedMonth)
        }
        .sheet(isPresented: $showingIncomeHistory) {
            IncomeHistoryView(
                budget: budget,
                monthlyIncomes: monthlyIncomes,
                onEdit: { editingIncome = $0 },
                onDelete: { income in
                    withAnimation(.easeInOut) {
                        budget.incomes.removeAll { $0.id == income.id }
                    }
                    Haptics.warning()
                }
            )
        }
        .sheet(isPresented: $showingExpenseHistory) {
            ExpenseHistoryView(
                budget: budget,
                monthlyExpenses: monthlyExpenses,
                onEdit: { editingExpense = $0 },
                onDelete: { expense in
                    withAnimation(.easeInOut) {
                        budget.expenses.removeAll { $0.id == expense.id }
                    }
                    Haptics.warning()
                }
            )
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
        }
        .sheet(item: $categoryHistorySelection) { selection in
            ExpenseHistoryView(
                budget: budget,
                monthlyExpenses: monthlyExpenses.filter { $0.categoryId == selection.categoryId },
                onEdit: { editingExpense = $0 },
                onDelete: { expense in
                    withAnimation(.easeInOut) {
                        budget.expenses.removeAll { $0.id == expense.id }
                    }
                    Haptics.warning()
                },
                title: "\(selection.name) History"
            )
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
        }
        .sheet(item: $editingIncome) { income in
            EditIncomeView(budget: budget, income: income)
        }
        .sheet(item: $editingExpense) { expense in
            EditExpenseView(budget: budget, expense: expense)
        }
        .sheet(item: $editingSavingsEntry) { entry in
            EditSavingsEntryView(budget: budget, savingsEntry: entry)
        }
        .sheet(item: $selectedCalendarDay) { selection in
            CalendarEntryEditorView(
                budget: budget,
                selectedDate: selection.date
            )
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
        }
        .sheet(isPresented: $showingCreditAccounts) {
            CreditAccountsView(budget: budget)
        }
        .sheet(item: $selectedCreditAccount) { account in
            CreditAccountDetailView(account: account, budget: budget)
        }
        .sheet(isPresented: $showingBankAccounts) {
            BankAccountsView(budget: budget)
        }
        .sheet(isPresented: $showingAppSettings) {
            AppSettingsView(budget: budget)
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
                overviewSection
                homeRollupSection
                homeNetWorthChartSection
                homePortfolioVsSpySection
            }
            .padding(.horizontal)
            .padding(.top, 28)
            .padding(.bottom, contentBottomPadding)
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
            VStack(spacing: 20) {
                pageHeader(
                    title: "Budget Hub",
                    subtitle: "Plan targets and log activity.",
                    systemImage: "square.grid.2x2"
                )
                Picker("Budget Focus", selection: $budgetPageFocus) {
                    ForEach(BudgetPageFocus.allCases) { focus in
                        Text(focus.rawValue).tag(focus)
                    }
                }
                .pickerStyle(.segmented)

                if budgetPageFocus == .log {
                    logMonthSwitcher
                    logTrendsSection
                    accountBalancesSection
                } else {
                    planHighlightsSection
                }

                if budget.income == 0 && budget.needsCategories.isEmpty && budget.wantsCategories.isEmpty && budget.savingsGoals.isEmpty && budget.expenses.isEmpty {
                    firstTimeTipsSection
                }

                overviewSection
                incomeSection
                if budgetPageFocus == .plan && budget.income > 0 && budget.needsCategories.isEmpty && budget.wantsCategories.isEmpty && budget.savingsGoals.isEmpty {
                    nextStepSection
                }
                budgetBreakdownSection
                needsSection
                wantsSection
                savingsSection
                if budgetPageFocus == .log {
                    categorySummarySection
                }
                summarySection
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, contentBottomPadding)
        }
    }

    private var calendarTab: some View {
        VStack(spacing: 14) {
            pageHeader(
                title: "Calendar",
                subtitle: "Upcoming recurring and one-time cash flow.",
                systemImage: "calendar"
            )
            recurringCalendarSection
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, contentBottomPadding)
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
        budgetPageFocus == .log
    }

    private var recurringCalendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text((calendarMonths.indices.contains(calendarPageIndex) ? calendarMonths[calendarPageIndex] : selectedMonth), format: .dateTime.month(.wide).year())
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }

            GeometryReader { proxy in
                TabView(selection: $calendarPageIndex) {
                    ForEach(Array(calendarMonths.enumerated()), id: \.offset) { index, month in
                        monthCalendarGrid(
                            for: month,
                            dayCellHeight: dayCellHeight(for: month, availableHeight: proxy.size.height)
                        )
                        .tag(index)
                    }
                }
                .id(calendarRefreshKey)
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: calendarPageIndex) { _, newValue in
                    guard calendarMonths.indices.contains(newValue) else { return }
                    selectedMonth = calendarMonths[newValue]
                }
                .onAppear {
                    alignCalendarPageToSelectedMonth()
                }
                .onChange(of: selectedMonth) { _, _ in
                    alignCalendarPageToSelectedMonth()
                }
            }
        }
        .background(Color.clear)
    }

    private var backgroundView: some View {
        LinearGradient(
            colors: [Color(.systemGroupedBackground), Color(.secondarySystemGroupedBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var spendingProgress: Double {
        guard budget.monthlyIncome > 0 else { return 0 }
        let used = totalMonthlySpent
        return min(max(used / budget.monthlyIncome, 0), 1)
    }

    private var contentBottomPadding: CGFloat {
        128
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

    private var homeMonthlySavingsTargetProgress: Double {
        guard budget.totalSavingsAllocated > 0 else { return 0 }
        return min(max(monthlySavingsLogged / budget.totalSavingsAllocated, 0), 1)
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
        totalMonthlySpent = monthlyExpenses.reduce(0) { $0 + $1.amount }
        totalMonthlyIncomeLogged = monthlyIncomes.reduce(0) { $0 + $1.amount }

        var needsTotals: [UUID: Double] = [:]
        var wantsTotals: [UUID: Double] = [:]
        for expense in monthlyExpenses {
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
            amountsByDate: dailyTotals(from: monthlyExpenses.map { ($0.date, $0.amount) })
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
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
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
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(remainingBudgetForMonth, format: .currency(code: "USD"))
                            .font(.title3)
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
                        budgetPageFocus = .plan
                        scrollToIncome = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Set income")
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

    private var calendarWeekdaySymbols: [String] {
        let symbols = Calendar.current.shortWeekdaySymbols
        let firstWeekdayIndex = Calendar.current.firstWeekday - 1
        let head = Array(symbols[firstWeekdayIndex...])
        let tail = Array(symbols[..<firstWeekdayIndex])
        return head + tail
    }

    private var calendarMonths: [Date] {
        let base = Self.startOfMonth(for: Date())
        let calendar = Calendar.current
        return (-12...12).compactMap { calendar.date(byAdding: .month, value: $0, to: base) }
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
            if calendar.isDate(cursor, equalTo: month, toGranularity: .month) {
                dates.append(cursor)
            } else {
                dates.append(nil)
            }
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

    private var calendarRefreshKey: String {
        let paid = budget.recurringPayments.reduce(0) { $0 + $1.paidOccurrenceKeys.count }
        return "\(budget.expenses.count)-\(budget.incomes.count)-\(budget.recurringPayments.count)-\(budget.creditAccounts.count)-\(paid)-\(selectedMonth.timeIntervalSinceReferenceDate)"
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
            budget.incomes.append(
                IncomeEntry(name: payment.name, amount: payment.amount, date: date)
            )
            return
        }

        var section = payment.section
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
        budget.expenses.append(
            Expense(
                name: payment.name,
                amount: payment.amount,
                date: date,
                section: section,
                categoryId: categoryId,
                paymentAccount: payment.paymentAccount,
                note: payment.note
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
        let isPaid: Bool
        let tint: Color
        let isCreditDue: Bool
        let paymentAccount: String
        let iconName: String
        let creditAccount: CreditAccount?
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
                isPaid: isRecurringOccurrencePaid($0.payment, on: date),
                tint: colorFor(section: $0.payment.section, categoryId: $0.payment.categoryId, isIncome: $0.payment.kind == .income),
                isCreditDue: false,
                paymentAccount: $0.payment.paymentAccount,
                iconName: iconName(for: $0.payment.name, isCreditDue: false, paymentAccount: $0.payment.paymentAccount),
                creditAccount: nil
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
                    isPaid: true,
                    tint: colorFor(section: $0.section, categoryId: $0.categoryId, isIncome: false),
                    isCreditDue: false,
                    paymentAccount: $0.paymentAccount,
                    iconName: iconName(for: $0.name, isCreditDue: false, paymentAccount: $0.paymentAccount),
                    creditAccount: nil
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
                    isPaid: true,
                    tint: colorFor(section: .needs, categoryId: nil, isIncome: true),
                    isCreditDue: false,
                    paymentAccount: "",
                    iconName: "dollarsign.circle",
                    creditAccount: nil
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
                isPaid: false,
                tint: colorForCreditAccount(account.id),
                isCreditDue: true,
                paymentAccount: account.name,
                iconName: "creditcard",
                creditAccount: account
            )
        }

        return (recurring + oneTimeIncome + oneTimeExpenses + dueItems).sorted { lhs, rhs in
            if lhs.isIncome == rhs.isIncome { return lhs.amount > rhs.amount }
            return lhs.isIncome && !rhs.isIncome
        }
    }

    private func colorFor(section: BudgetSection, categoryId: UUID?, isIncome: Bool) -> Color {
        if isIncome { return .green }
        guard let categoryId else { return section == .needs ? .blue : .orange }
        return colorForCategory(categoryId)
    }

    private func creditAccountActualBalance(_ account: CreditAccount) -> Double {
        let normalizedAccountName = account.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAccountName.isEmpty else { return 0 }
        return budget.expenses.reduce(0) { partial, expense in
            if let paidCard = creditCardPaymentTarget(from: expense.note),
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
        if lowered.contains("rent") || lowered.contains("mortgage") || lowered.contains("lease") {
            return "house.fill"
        }
        if !paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "creditcard"
        }
        if lowered.contains("utility") || lowered.contains("electric") || lowered.contains("water") || lowered.contains("gas") {
            return "bolt.fill"
        }
        if lowered.contains("subscription") || lowered.contains("stream") || lowered.contains("apple") || lowered.contains("amazon") {
            return "shippingbox.fill"
        }
        return "tag.fill"
    }

    private var accountBalancesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Account Balances")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Manage Banks") {
                    showingBankAccounts = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Manage Cards") {
                    showingCreditAccounts = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

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

            if !budget.holdings.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Portfolio Holdings")
                            .font(.headline)
                        ForEach(budget.holdings.prefix(5)) { holding in
                            HStack {
                                Text(holding.ticker)
                                Spacer()
                                Text("\((holding.shares * holding.currentPrice), format: .currency(code: "USD"))")
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recurringCalendarDayCell(for date: Date?) -> some View {
        if let date {
            let events = calendarEvents(for: date)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.subheadline)
                        .fontWeight(Calendar.current.isDateInToday(date) ? .bold : .regular)
                    Spacer()
                }

                ForEach(events.prefix(4)) { event in
                    HStack(spacing: 4) {
                        Button {
                            if let account = event.creditAccount {
                                selectedCreditAccount = account
                            } else if let recurring = event.recurringPayment {
                                editingRecurringPayment = recurring
                            } else if let expense = event.expense {
                                editingExpense = expense
                            } else if let income = event.income {
                                editingIncome = income
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Image(systemName: event.iconName)
                                        .font(.caption2)
                                    Text(event.name)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .allowsTightening(true)
                                }
                                if event.amount > 0 {
                                    Text(event.amount.formatted(.currency(code: "USD")))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(event.tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(event.tint.opacity(0.16))
                            )
                        }
                        .buttonStyle(.plain)

                        if let recurring = event.recurringPayment {
                            Button {
                                markRecurringOccurrencePaid(recurring, on: event.date)
                            } label: {
                                Image(systemName: event.isPaid ? "checkmark.circle.fill" : "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(event.isPaid ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(event.isPaid ? "Marked paid" : "Mark paid")
                        }
                    }
                }

                if events.count > 4 {
                    Text("+\(events.count - 4) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                Rectangle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectedCalendarDay = CalendarDaySelection(date: date)
            }
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Rectangle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay(
                            Rectangle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
        }
    }

    private func monthCalendarGrid(for month: Date, dayCellHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(calendarWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(calendarGridDates(for: month), id: \.self) { cellDate in
                    recurringCalendarDayCell(for: cellDate)
                        .frame(height: dayCellHeight)
                }
            }
        }
    }

    private func dayCellHeight(for month: Date, availableHeight: CGFloat) -> CGFloat {
        let rows = max(calendarGridDates(for: month).count / 7, 1)
        let weekdayHeaderHeight: CGFloat = 30
        let usableHeight = max(availableHeight - weekdayHeaderHeight, 240)
        return floor(usableHeight / CGFloat(rows))
    }

    private func alignCalendarPageToSelectedMonth() {
        let current = Self.startOfMonth(for: selectedMonth)
        if let index = calendarMonths.firstIndex(where: { Calendar.current.isDate($0, equalTo: current, toGranularity: .month) }) {
            calendarPageIndex = index
        }
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
                    "Plan view: set allocations for needs, wants, and savings.",
                    "Log view: quickly record spending and keep categories updated."
                ],
                actionLabel: "Set Income",
                action: {
                    selectedTab = .budget
                    budgetPageFocus = .plan
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan Highlights")
                .font(.title3)
                .fontWeight(.semibold)

            if budget.income > 0 {
                HStack(spacing: 12) {
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
                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Unlock your plan targets")
                                .font(.headline)
                            Text("Add income to see monthly goals for needs, wants, and savings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Income Section
    private var incomeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Income")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Set what you take home and how often it lands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            GlassCard {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Amount")
                            .font(.headline)
                        HStack(spacing: 10) {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            TextField("$0", value: $budget.income, format: .currency(code: "USD"))
                                .keyboardType(.decimalPad)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .textFieldStyle(.plain)
                                .focused($focusedField, equals: .income)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pay Frequency")
                                .font(.headline)
                            Text("This controls your monthly roll-up.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Pay Frequency", selection: $budget.payFrequency) {
                            ForEach(PayFrequency.allCases) { frequency in
                                Text(frequency.rawValue).tag(frequency)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
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
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(budget.monthlyIncome, format: .currency(code: "USD"))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.12), in: Capsule())
                                .scaleEffect(highlightMonthlyIncome ? 1.06 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: highlightMonthlyIncome)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("50/30/20 Budget Breakdown")
                .font(.title2)
                .fontWeight(.bold)
            
            if budget.income > 0 {
                GlassCard {
                    VStack(spacing: 16) {
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
                GlassCard {
                    Text("Enter your income to see budget breakdown")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Log Trends Section
    private var logTrendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            collapsibleSectionHeader(
                title: "Trends",
                tint: .primary,
                isExpanded: $logTrendsExpanded,
                allowCollapse: false,
                showIndicator: false,
                onAdd: selectedLogTrend == .income ? startAddIncome : startAddExpense,
                valueLabel: selectedLogTrend == .income ? "Logged this month" : "Month to date",
                value: selectedLogTrend == .income ? totalMonthlyIncomeLogged : totalMonthlySpent
            ) {
                Button("View History") {
                    if selectedLogTrend == .income {
                        showingIncomeHistory = true
                    } else {
                        showingExpenseHistory = true
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            if logTrendsExpanded {
                Picker("Trend", selection: $selectedLogTrend) {
                    ForEach(LogTrend.allCases) { trend in
                        Text(trend.rawValue).tag(trend)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Range", selection: $selectedTrendRange) {
                    ForEach(TrendRange.allCases) { range in
                        Text(range.title).tag(range)
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

                Group {
                    if selectedLogTrend == .income {
                        incomeTrendContent
                    } else {
                        spendingTrendContent
                    }
                }
            }
        }
        .onChange(of: selectedTrendRange) { _, _ in
            selectedIncomePoint = nil
            selectedSpendingPoint = nil
        }
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
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
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
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
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
                        Text("\(monthlySavingsLogged, format: .currency(code: "USD")) of \(budget.savingsBudget, format: .currency(code: "USD"))")
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
                                    title: isLogFocus ? "Savings Logged" : "Savings Planned",
                                    amount: isLogFocus ? monthlySavingsLogged : budget.totalSavingsAllocated,
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
                    .font(.title3)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
    }

    private var homeRollupSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Everything at a Glance")
                    .font(.headline)

                metricRow("Monthly Income", budget.monthlyIncome)
                metricRow("Spent This Month", totalMonthlySpent)
                metricRow("Saved This Month", monthlySavingsLogged)
                metricRow("Remaining Budget", remainingBudgetForMonth)
                metricRow("Portfolio Net Value", homePortfolioNetValue)
                metricRow("Margin Used", budget.portfolioSnapshot.marginUsed)

                if budget.totalSavingsAllocated > 0 {
                    Divider()
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
    }

    private var homePortfolioVsSpySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Portfolio vs SPY")
                        .font(.headline)
                    Spacer()
                    if isLoadingSpyComparison {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Refresh") {
                            Task { await refreshSpyComparison() }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let spyComparison {
                    Text(spyComparison.periodLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        performancePill(title: "Portfolio", value: spyComparison.portfolioReturn, tint: .blue)
                        performancePill(title: "SPY", value: spyComparison.spyReturn, tint: .orange)
                    }

                    let delta = spyComparison.portfolioReturn - spyComparison.spyReturn
                    Text(delta >= 0 ? "Outperforming SPY by \(delta, format: .percent.precision(.fractionLength(2)))." : "Underperforming SPY by \((-delta), format: .percent.precision(.fractionLength(2))).")
                        .font(.caption)
                        .foregroundStyle(delta >= 0 ? .green : .red)
                } else if let spyComparisonError {
                    Text(spyComparisonError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add portfolio history and market data settings to compare against SPY.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var homeNetWorthChartSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Net Worth Over Time")
                    .font(.headline)

                Picker("Range", selection: $selectedHomeNetWorthRange) {
                    ForEach(HomeNetWorthRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

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

                        if let selectedHomeNetWorthPoint {
                            RuleMark(x: .value("Date", selectedHomeNetWorthPoint.date))
                                .foregroundStyle(.secondary.opacity(0.35))
                            PointMark(
                                x: .value("Date", selectedHomeNetWorthPoint.date),
                                y: .value("Net Worth", selectedHomeNetWorthPoint.netValue)
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
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            ZStack(alignment: .topLeading) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
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
                    .frame(height: 220)

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

    private func nearestHomeHistoryPoint(to date: Date, in points: [PortfolioValuePoint]) -> PortfolioValuePoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func performancePill(title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .percent.precision(.fractionLength(2)))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(value >= 0 ? .green : .red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    private func refreshSpyComparison() async {
        guard let firstPoint = budget.portfolioValueHistory.sorted(by: { $0.date < $1.date }).first,
              let lastPoint = budget.portfolioValueHistory.sorted(by: { $0.date < $1.date }).last else {
            spyComparison = nil
            spyComparisonError = "No portfolio history yet. Log portfolio activity first."
            return
        }

        let apiKey = budget.marketDataSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            spyComparison = nil
            spyComparisonError = "Missing market data API key in Margin settings."
            return
        }

        isLoadingSpyComparison = true
        defer { isLoadingSpyComparison = false }

        do {
            let startPrice = try await marketDataService.fetchHistoricalClose(
                ticker: "SPY",
                onOrBefore: firstPoint.date,
                provider: budget.marketDataSettings.provider,
                apiKey: apiKey
            )
            let endPrice = try await marketDataService.fetchPrice(
                ticker: "SPY",
                provider: budget.marketDataSettings.provider,
                apiKey: apiKey
            )

            guard firstPoint.netValue > 0, startPrice > 0 else {
                spyComparison = nil
                spyComparisonError = "Not enough baseline data to calculate returns."
                return
            }

            let portfolioReturn = (lastPoint.netValue / firstPoint.netValue) - 1
            let spyReturn = (endPrice / startPrice) - 1

            spyComparison = SpyComparisonResult(
                periodLabel: "\(firstPoint.date.formatted(date: .abbreviated, time: .omitted)) to \(lastPoint.date.formatted(date: .abbreviated, time: .omitted))",
                portfolioReturn: portfolioReturn,
                spyReturn: spyReturn
            )
            spyComparisonError = nil
        } catch {
            spyComparison = nil
            spyComparisonError = error.localizedDescription
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
    case electricBill
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
                    Text("Used for SPY comparison and quote refresh.")
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
                Menu {
                    if selectedTab == .margin {
                        Button("Add Transaction") { onMarginQuickAction(.addTransaction) }
                        Button("Add Investment") { onMarginQuickAction(.addInvestment) }
                        Button("Add Manual Holding") { onMarginQuickAction(.addManualHolding) }
                        Button("Electric Bill") { onMarginQuickAction(.electricBill) }
                        Button("Margin Settings") { onMarginQuickAction(.marginSettings) }
                        Button("Activity Ledger") { onMarginQuickAction(.ledgerHistory) }
                    } else if selectedTab == .calendar {
                        Button("Add Calendar Entry") { onCalendarQuickAction(.addCalendarEntry) }
                        Button("Credit Cards") { onCalendarQuickAction(.creditCards) }
                    } else {
                        Button(action: onAddExpense) {
                            Label("Add Expense", systemImage: "minus.circle")
                        }
                        Button(action: onAddIncome) {
                            Label("Add Income", systemImage: "plus.circle")
                        }
                    }
                    Button("Show Tabs", action: onExpand)
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Quick add menu")
            } else {
                tabButton(.home, systemImage: "house.fill")
                Spacer()
                tabButton(.margin, systemImage: "shield.lefthalf.filled")
                Spacer()
                Menu {
                    if selectedTab == .margin {
                        Button("Add Transaction") { onMarginQuickAction(.addTransaction) }
                        Button("Add Investment") { onMarginQuickAction(.addInvestment) }
                        Button("Add Manual Holding") { onMarginQuickAction(.addManualHolding) }
                        Button("Electric Bill") { onMarginQuickAction(.electricBill) }
                        Button("Margin Settings") { onMarginQuickAction(.marginSettings) }
                        Button("Activity Ledger") { onMarginQuickAction(.ledgerHistory) }
                    } else if selectedTab == .calendar {
                        Button("Add Calendar Entry") { onCalendarQuickAction(.addCalendarEntry) }
                        Button("Credit Cards") { onCalendarQuickAction(.creditCards) }
                    } else {
                        Button(action: onAddExpense) {
                            Label("Add Expense", systemImage: "minus.circle")
                        }
                        Button(action: onAddIncome) {
                            Label("Add Income", systemImage: "plus.circle")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        .padding(.bottom, 10)
                }
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 6)
                .accessibilityLabel("Quick add menu")
                Spacer()
                tabButton(.calendar, systemImage: "calendar")
                Spacer()
                tabButton(.budget, systemImage: "square.grid.2x2")
            }
        }
        .padding(.horizontal, minimized ? 10 : 20)
        .padding(.vertical, minimized ? 8 : 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: minimized ? 80 : 460)
        .padding(.horizontal, minimized ? 8 : 16)
        .padding(.bottom, 4)
    }

    private func tabButton(_ mode: BudgetMode, systemImage: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut) {
                selectedTab = mode
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                Text(mode.title)
                    .font(.footnote)
            }
            .foregroundStyle(selectedTab == mode ? Color.primary : Color.secondary)
            .frame(width: 72, height: 48)
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

    private var categories: [Category] {
        section == .needs ? budget.needsCategories : budget.wantsCategories
    }

    private var paymentAccountOptions: [String] {
        let names = (budget.creditAccounts.map(\.name) + budget.bankAccounts.map(\.name) + [paymentAccount])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
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
                    Picker("Paid with", selection: $paymentAccount) {
                        Text("None").tag("")
                        ForEach(paymentAccountOptions, id: \.self) { accountName in
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
            }
            .onChange(of: section) { _, _ in
                if let categoryId, categories.contains(where: { $0.id == categoryId }) {
                    return
                }
                categoryId = categories.first?.id
                useCustomCategory = false
                customCategoryName = ""
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let resolvedCategoryId: UUID?
                        if useCustomCategory {
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
                            section: section,
                            categoryId: categoryId,
                            paymentAccount: paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        withAnimation(.easeInOut) {
                            budget.expenses.append(expense)
                        }
                        onSave?(expense)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.isEmpty || amount <= 0 || (!useCustomCategory && categoryId == nil))
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
                        let entry = IncomeEntry(name: name.isEmpty ? "Income" : name, amount: amount, date: date)
                        withAnimation(.easeInOut) {
                            budget.incomes.append(entry)
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

    init(budget: BudgetModel, income: IncomeEntry) {
        self.budget = budget
        self.income = income
        _name = State(initialValue: income.name)
        _amount = State(initialValue: income.amount)
        _date = State(initialValue: income.date)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Description", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Income Details")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let index = budget.incomes.firstIndex(where: { $0.id == income.id }) {
                            budget.incomes[index].name = name
                            budget.incomes[index].amount = amount
                            budget.incomes[index].date = date
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

    private var categories: [Category] {
        section == .needs ? budget.needsCategories : budget.wantsCategories
    }

    private var paymentAccountOptions: [String] {
        let names = (budget.creditAccounts.map(\.name) + budget.bankAccounts.map(\.name) + [paymentAccount])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
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
                    Picker("Paid with", selection: $paymentAccount) {
                        Text("None").tag("")
                        ForEach(paymentAccountOptions, id: \.self) { accountName in
                            Text(accountName).tag(accountName)
                        }
                    }
                    TextField("Note", text: $note, axis: .vertical)
                } header: {
                    Text("Expense Details")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: section) { _, _ in
                categoryId = categories.first?.id
                useCustomCategory = false
                customCategoryName = ""
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let resolvedCategoryId: UUID?
                        if useCustomCategory {
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
                        if let index = budget.expenses.firstIndex(where: { $0.id == expense.id }) {
                            budget.expenses[index].name = name
                            budget.expenses[index].amount = amount
                            budget.expenses[index].date = date
                            budget.expenses[index].section = section
                            budget.expenses[index].categoryId = categoryId
                            budget.expenses[index].paymentAccount = paymentAccount
                            budget.expenses[index].note = note
                        }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.isEmpty || amount <= 0 || (!useCustomCategory && categoryId == nil))
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
            .navigationTitle("Edit Savings")
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

    private var creditCardOptions: [String] {
        budget.creditAccounts
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    init(
        budget: BudgetModel,
        selectedDate: Date,
        existingRecurringPayment: RecurringPayment? = nil
    ) {
        self.budget = budget
        self.selectedDate = selectedDate
        self.existingRecurringPayment = existingRecurringPayment
        _name = State(initialValue: existingRecurringPayment?.name ?? "")
        _amount = State(initialValue: existingRecurringPayment?.amount ?? 0)
        _date = State(initialValue: existingRecurringPayment?.startDate ?? selectedDate)
        _mode = State(initialValue: existingRecurringPayment == nil ? .oneTime : .recurring)
        _kind = State(initialValue: existingRecurringPayment?.kind ?? .expense)
        _isActive = State(initialValue: existingRecurringPayment?.isActive ?? true)
        _section = State(initialValue: existingRecurringPayment?.section ?? .needs)
        _categoryId = State(initialValue: existingRecurringPayment?.categoryId ?? budget.needsCategories.first?.id)
        _paymentAccount = State(initialValue: existingRecurringPayment?.paymentAccount ?? "")
        _note = State(initialValue: existingRecurringPayment?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry Type") {
                    if existingRecurringPayment == nil {
                        Picker("Mode", selection: $mode) {
                            ForEach(EntryMode.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Text("Recurring")
                            .foregroundStyle(.secondary)
                    }
                    Picker("Kind", selection: $kind) {
                        Text("Expense").tag(RecurringPaymentKind.expense)
                        Text("Income").tag(RecurringPaymentKind.income)
                    }
                }

                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)

                    DatePicker(
                        mode == .recurring || existingRecurringPayment != nil ? "Start date" : "Date",
                        selection: $date,
                        displayedComponents: (mode == .oneTime ? [.date] : [.date])
                    )

                    if kind == .expense {
                        Toggle("Credit Card Payment", isOn: $isCreditCardPayment)
                        if isCreditCardPayment {
                            if creditCardOptions.isEmpty {
                                Text("Add a credit card in Credit Accounts first.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("Credit Card", selection: $targetCreditAccountName) {
                                    ForEach(creditCardOptions, id: \.self) { accountName in
                                        Text(accountName).tag(accountName)
                                    }
                                }
                            }
                        }
                        Picker("Section", selection: $section) {
                            ForEach(BudgetSection.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        Toggle("Other category", isOn: $useCustomCategory)
                        if useCustomCategory {
                            TextField("Custom category", text: $customCategoryName)
                        } else if categories.isEmpty {
                            Text("Add a category in Plan first.")
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

                    if kind == .expense {
                        Picker("Paid with", selection: $paymentAccount) {
                            Text("None").tag("")
                            ForEach(paymentAccountOptions, id: \.self) { accountName in
                                Text(accountName).tag(accountName)
                            }
                        }
                    }
                    TextField("Note", text: $note, axis: .vertical)

                    if mode == .recurring || existingRecurringPayment != nil {
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

                            let markerNote: String
                            if kind == .expense && isCreditCardPayment {
                                let prefix = "[CC_PAYMENT:\(targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines))]"
                                let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                                markerNote = trimmedNote.isEmpty ? prefix : "\(prefix)\n\(trimmedNote)"
                            } else {
                                markerNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
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
                                note: markerNote
                            )
                            if let index = budget.recurringPayments.firstIndex(where: { $0.id == payment.id }) {
                                budget.recurringPayments[index] = payment
                            } else {
                                budget.recurringPayments.append(payment)
                            }
                        } else if kind == .income {
                            budget.incomes.append(
                                IncomeEntry(name: trimmedName, amount: amount, date: date)
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
                            let markerNote: String
                            if isCreditCardPayment {
                                let prefix = "[CC_PAYMENT:\(targetCreditAccountName.trimmingCharacters(in: .whitespacesAndNewlines))]"
                                let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                                markerNote = trimmedNote.isEmpty ? prefix : "\(prefix)\n\(trimmedNote)"
                            } else {
                                markerNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            budget.expenses.append(
                                Expense(
                                    name: trimmedName,
                                    amount: amount,
                                    date: date,
                                    section: isCreditCardPayment ? .needs : section,
                                    categoryId: resolvedCategoryId
                                    ,
                                    paymentAccount: paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines),
                                    note: markerNote
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
        let normalizedAccountName = account.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAccountName.isEmpty else { return 0 }
        return budget.expenses.reduce(0) { partial, expense in
            if let paidCard = creditCardPaymentTarget(from: expense.note),
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
        let normalizedAccountName = account.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAccountName.isEmpty else { return 0 }
        return budget.expenses.reduce(0) { partial, expense in
            if let paidCard = creditCardPaymentTarget(from: expense.note),
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

struct BankAccountsView: View {
    @ObservedObject var budget: BudgetModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var balance: Double = 0
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Add Bank Account") {
                    TextField("Account name", text: $name)
                    TextField("Balance", value: $balance, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    TextField("Note", text: $note)
                    Button("Add Account") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        budget.bankAccounts.append(
                            BankAccount(
                                name: trimmed,
                                balance: balance,
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        )
                        name = ""
                        balance = 0
                        note = ""
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Accounts") {
                    if budget.bankAccounts.isEmpty {
                        Text("No bank accounts added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($budget.bankAccounts) { $account in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Name", text: $account.name)
                                TextField("Balance", value: $account.balance, format: .currency(code: "USD"))
                                    .keyboardType(.decimalPad)
                                TextField("Note", text: $account.note)
                            }
                            .padding(.vertical, 4)
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
        }
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
