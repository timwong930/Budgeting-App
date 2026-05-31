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
    @State private var selectedTab: BudgetMode = .plan
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
    @FocusState private var focusedField: FocusedField?

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
    
    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                planTab
                logTab
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)
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
                    }
                )
                .frame(maxWidth: .infinity, alignment: isTabBarMinimized ? .trailing : .center)
                .padding(.trailing, isTabBarMinimized ? 12 : 0)
                .padding(.bottom, -4)
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
    }

    private var planTab: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    modeBadge(
                        title: "Plan Mode",
                        subtitle: "Set targets and allocations.",
                        systemImage: "list.bullet.rectangle",
                        tint: .blue
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
        .tag(BudgetMode.plan)
    }

    private var logTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                modeBadge(
                    title: "Log Mode",
                    subtitle: "Track spending and income.",
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: .green
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
        .tag(BudgetMode.log)
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
        96
    }

    private var remainingBudgetForMonth: Double {
        let needsRemaining = budget.totalNeedsAllocated - monthlyNeedsSpent
        let wantsRemaining = budget.totalWantsAllocated - monthlyWantsSpent
        let savingsRemaining = budget.savingsBudget - budget.totalSavingsAllocated
        return needsRemaining + wantsRemaining + savingsRemaining
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
                        selectedTab = .plan
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

    private var firstTimeTipsSection: some View {
        GlassCard {
            EmptyStateView(
                title: "Start Your Plan",
                message: "Set your income, then add categories and goals for the month.",
                systemImage: "sparkles",
                tips: [
                    "Plan Mode: set allocations for needs, wants, and savings.",
                    "Log Mode: quickly record spending and keep categories updated."
                ],
                actionLabel: "Set Income",
                action: {
                    selectedTab = .plan
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
            let needsHeaderLabel = selectedTab == .log ? "Spent this month" : "Budget this month"
            let needsHeaderValue = selectedTab == .log ? monthlyNeedsSpent : budget.needsBudget
            collapsibleSectionHeader(
                title: "Needs",
                tint: .blue,
                isExpanded: $needsExpanded,
                onAdd: { showingAddNeedsCategory = true },
                valueLabel: needsHeaderLabel,
                value: needsHeaderValue
            )

            if selectedTab == .log, budget.income > 0 {
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
                                    showLogDetails: selectedTab == .log,
                                    onEdit: { editingCategory = category },
                                    onDelete: {
                                    withAnimation(.easeInOut) {
                                        budget.needsCategories.removeAll { $0.id == category.id }
                                        budget.removeAllocation(for: category.id, section: .needs)
                                        budget.removeExpenses(for: category.id)
                                    }
                                        Haptics.warning()
                                    },
                                    onAddExpense: selectedTab == .log ? {
                                        expenseDraftSection = .needs
                                        expenseDraftCategoryId = category.id
                                        expenseDraft = ExpenseDraft(section: expenseDraftSection, categoryId: expenseDraftCategoryId)
                                    } : nil,
                                    onTap: selectedTab == .log ? {
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
            let wantsHeaderLabel = selectedTab == .log ? "Spent this month" : "Budget this month"
            let wantsHeaderValue = selectedTab == .log ? monthlyWantsSpent : budget.wantsBudget
            collapsibleSectionHeader(
                title: "Wants",
                tint: .orange,
                isExpanded: $wantsExpanded,
                onAdd: { showingAddWantsCategory = true },
                valueLabel: wantsHeaderLabel,
                value: wantsHeaderValue
            )

            if selectedTab == .log, budget.income > 0 {
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
                                    showLogDetails: selectedTab == .log,
                                    onEdit: { editingCategory = category },
                                    onDelete: {
                                    withAnimation(.easeInOut) {
                                        budget.wantsCategories.removeAll { $0.id == category.id }
                                        budget.removeAllocation(for: category.id, section: .wants)
                                        budget.removeExpenses(for: category.id)
                                    }
                                        Haptics.warning()
                                    },
                                    onAddExpense: selectedTab == .log ? {
                                        expenseDraftSection = .wants
                                        expenseDraftCategoryId = category.id
                                        expenseDraft = ExpenseDraft(section: expenseDraftSection, categoryId: expenseDraftCategoryId)
                                    } : nil,
                                    onTap: selectedTab == .log ? {
                                        categoryHistorySelection = CategoryHistorySelection(category: category)
                                    } : nil,
                                    showRemaining: selectedTab != .log,
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

            if selectedTab == .log, budget.income > 0 {
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
                                    onHistory: selectedTab == .log ? {
                                        savingsHistorySelection = SavingsHistorySelection(goal: goal)
                                    } : nil,
                                    onLog: selectedTab == .log ? {
                                        savingsEntryDraft = SavingsEntryDraft(goalId: goal.id)
                                    } : nil,
                                    savedThisMonth: selectedTab == .log ? (savingsLoggedByGoalId[goal.id] ?? 0) : nil,
                                    showCurrentField: selectedTab != .log,
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
                                    title: selectedTab == .log ? "Savings Logged" : "Savings Planned",
                                    amount: selectedTab == .log ? monthlySavingsLogged : budget.totalSavingsAllocated,
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

    private func modeBadge(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .padding(8)
                    .background(tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Supporting Views

enum BudgetMode: String, CaseIterable, Identifiable {
    case plan
    case log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan:
            return "Plan"
        case .log:
            return "Log"
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
    @Binding var selectedTab: BudgetMode
    let minimized: Bool
    let onExpand: () -> Void
    let onAddExpense: () -> Void
    let onAddIncome: () -> Void

    var body: some View {
        HStack {
            if minimized {
                if selectedTab == .log {
                    Menu {
                        Button(action: onAddExpense) {
                            Label("Add Expense", systemImage: "minus.circle")
                        }
                        Button(action: onAddIncome) {
                            Label("Add Income", systemImage: "plus.circle")
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
                    Button(action: onExpand) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expand tabs")
                }
            } else {
                tabButton(.plan, systemImage: "list.bullet.rectangle")
                Spacer()
                if selectedTab == .log {
                    Menu {
                        Button(action: onAddExpense) {
                            Label("Add Expense", systemImage: "minus.circle")
                        }
                        Button(action: onAddIncome) {
                            Label("Add Income", systemImage: "plus.circle")
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
                }
                Spacer()
                tabButton(.log, systemImage: "chart.line.uptrend.xyaxis")
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
        .frame(maxWidth: minimized ? 80 : 320)
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

    private var categories: [Category] {
        section == .needs ? budget.needsCategories : budget.wantsCategories
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
                        let expense = Expense(name: name, amount: amount, date: date, section: section, categoryId: categoryId)
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

    private var categories: [Category] {
        section == .needs ? budget.needsCategories : budget.wantsCategories
    }

    init(budget: BudgetModel, expense: Expense) {
        self.budget = budget
        self.expense = expense
        _name = State(initialValue: expense.name)
        _amount = State(initialValue: expense.amount)
        _date = State(initialValue: expense.date)
        _section = State(initialValue: expense.section)
        _categoryId = State(initialValue: expense.categoryId)
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
