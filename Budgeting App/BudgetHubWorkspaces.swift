import SwiftUI
import Charts

// TIM-118: Purpose-built Budget Hub workspaces. The parent Budget Hub should answer
// a question quickly, while these destinations provide the detail only when requested.

struct BudgetActivityWorkspaceView: View {
    @ObservedObject var budget: BudgetModel
    @Binding var selectedMonth: Date

    let onAddExpense: () -> Void
    let onAddIncome: () -> Void
    let onAddSavings: () -> Void
    let onEditExpense: (Expense) -> Void
    let onEditIncome: (IncomeEntry) -> Void
    let onEditSavings: (SavingsEntry) -> Void
    let onEditRecurring: (RecurringPayment) -> Void

    private var monthInterval: DateInterval? {
        Calendar.current.dateInterval(of: .month, for: selectedMonth)
    }

    private var monthExpenses: [Expense] {
        guard let monthInterval else { return [] }
        return budget.expenses
            .filter { monthInterval.contains($0.date) && !budget.isCreditCardPayment($0) }
            .sorted { $0.date > $1.date }
    }

    private var monthIncome: [IncomeEntry] {
        guard let monthInterval else { return [] }
        return budget.incomes
            .filter { monthInterval.contains($0.date) }
            .sorted { $0.date > $1.date }
    }

    private var monthSavings: [SavingsEntry] {
        guard let monthInterval else { return [] }
        return budget.savingsEntries
            .filter { monthInterval.contains($0.date) }
            .sorted { $0.date > $1.date }
    }

    private var inflow: Double { monthIncome.reduce(0) { $0 + $1.amount } }
    private var spending: Double { monthExpenses.reduce(0) { $0 + $1.amount } }
    private var saved: Double { monthSavings.reduce(0) { $0 + $1.amount } }
    private var netAfterPlan: Double { inflow - spending - saved }

    private var recentItems: [BudgetActivityItem] {
        let expenses = monthExpenses.map(BudgetActivityItem.expense)
        let income = monthIncome.map(BudgetActivityItem.income)
        let savings = monthSavings.map(BudgetActivityItem.savings)
        return (expenses + income + savings).sorted { $0.date > $1.date }
    }

    private var activeRecurring: [RecurringPayment] {
        budget.recurringPayments
            .filter(\.isActive)
            .sorted {
                if $0.dayOfMonth == $1.dayOfMonth { return $0.name < $1.name }
                return $0.dayOfMonth < $1.dayOfMonth
            }
    }

    private var recurringOutflow: Double {
        activeRecurring.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var transactionCount: Int {
        monthExpenses.count + monthIncome.count + monthSavings.count
    }

    var body: some View {
        VStack(spacing: 12) {
            BudgetWorkspaceMonthSelector(selectedMonth: $selectedMonth)
            activityHero
            quickActions

            BudgetWorkspaceSectionHeader(
                title: "Recent activity",
                subtitle: transactionCount == 0 ? "Nothing logged yet" : "\(transactionCount) entries this month"
            )

            if recentItems.isEmpty {
                BudgetWorkspaceEmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "Your month is quiet",
                    message: "Log an expense or income and it will appear here immediately.",
                    actionTitle: "Log expense",
                    action: onAddExpense
                )
            } else {
                GlassCard(padding: 10) {
                    VStack(spacing: 0) {
                        ForEach(Array(recentItems.prefix(6).enumerated()), id: \.element.id) { index, item in
                            BudgetActivityRow(item: item) {
                                open(item)
                            }
                            if index < min(recentItems.count, 6) - 1 {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                }
            }

            BudgetWorkspaceSectionHeader(
                title: "Explore",
                subtitle: "Go deeper only when you need to"
            )

            VStack(spacing: 8) {
                NavigationLink {
                    BudgetActivityTransactionsView(
                        items: recentItems,
                        month: selectedMonth,
                        onOpen: open
                    )
                } label: {
                    BudgetWorkspaceNavigationRow(
                        title: "Transactions",
                        subtitle: "Full monthly ledger",
                        systemImage: "list.bullet.rectangle.portrait",
                        tint: .pink,
                        value: "\(transactionCount)"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    BudgetRecurringActivityView(
                        payments: activeRecurring,
                        onEdit: onEditRecurring
                    )
                } label: {
                    BudgetWorkspaceNavigationRow(
                        title: "Recurring",
                        subtitle: "Bills and repeating income",
                        systemImage: "repeat.circle.fill",
                        tint: .orange,
                        value: recurringOutflow.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    BudgetActivityTrendsView(
                        expenses: monthExpenses,
                        incomes: monthIncome,
                        savings: monthSavings,
                        month: selectedMonth
                    )
                } label: {
                    BudgetWorkspaceNavigationRow(
                        title: "Trends",
                        subtitle: "Daily movement and pace",
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: .purple,
                        value: netAfterPlan.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var activityHero: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Net movement")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(netAfterPlan, format: .currency(code: "USD"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(netAfterPlan >= 0 ? Color.green : Color.red)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(netAfterPlan >= 0 ? "On track" : "Outflow ahead")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(netAfterPlan >= 0 ? Color.green : Color.red)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background((netAfterPlan >= 0 ? Color.green : Color.red).opacity(0.10), in: Capsule())
                }

                HStack(spacing: 8) {
                    BudgetWorkspaceMetricPill(title: "In", value: inflow, tint: .green, systemImage: "arrow.down.left")
                    BudgetWorkspaceMetricPill(title: "Spent", value: spending, tint: .red, systemImage: "arrow.up.right")
                    BudgetWorkspaceMetricPill(title: "Saved", value: saved, tint: .mint, systemImage: "banknote.fill")
                }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            BudgetWorkspaceActionButton(title: "Expense", systemImage: "minus", tint: .red, action: onAddExpense)
            BudgetWorkspaceActionButton(title: "Income", systemImage: "plus", tint: .green, action: onAddIncome)
            BudgetWorkspaceActionButton(title: "Savings", systemImage: "banknote", tint: .mint, action: onAddSavings)
        }
    }

    private func open(_ item: BudgetActivityItem) {
        switch item {
        case .expense(let expense): onEditExpense(expense)
        case .income(let income): onEditIncome(income)
        case .savings(let savings): onEditSavings(savings)
        }
    }
}

private enum BudgetActivityItem: Identifiable {
    case expense(Expense)
    case income(IncomeEntry)
    case savings(SavingsEntry)

    var id: String {
        switch self {
        case .expense(let value): return "expense-\(value.id.uuidString)"
        case .income(let value): return "income-\(value.id.uuidString)"
        case .savings(let value): return "savings-\(value.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .expense(let value): return value.name
        case .income(let value): return value.name
        case .savings(let value): return value.name.isEmpty ? "Savings" : value.name
        }
    }

    var subtitle: String {
        switch self {
        case .expense(let value): return value.paymentAccount.isEmpty ? value.section.title : value.paymentAccount
        case .income(let value): return value.bankName.isEmpty ? "Income" : value.bankName
        case .savings: return "Savings"
        }
    }

    var amount: Double {
        switch self {
        case .expense(let value): return value.amount
        case .income(let value): return value.amount
        case .savings(let value): return value.amount
        }
    }

    var date: Date {
        switch self {
        case .expense(let value): return value.date
        case .income(let value): return value.date
        case .savings(let value): return value.date
        }
    }

    var isInflow: Bool {
        if case .income = self { return true }
        return false
    }

    var systemImage: String {
        switch self {
        case .expense: return "creditcard.fill"
        case .income: return "arrow.down.circle.fill"
        case .savings: return "banknote.fill"
        }
    }

    var tint: Color {
        switch self {
        case .expense: return .pink
        case .income: return .green
        case .savings: return .mint
        }
    }
}

private struct BudgetActivityRow: View {
    let item: BudgetActivityItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 32, height: 32)
                    .background(item.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(item.subtitle) · \(item.date.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(item.isInflow ? "+" : "-")\(item.amount.formatted(.currency(code: "USD")))")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(item.isInflow ? Color.green : Color.primary)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BudgetActivityTransactionsView: View {
    let items: [BudgetActivityItem]
    let month: Date
    let onOpen: (BudgetActivityItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BudgetWorkspaceSubpageHeader(
                    title: "Transactions",
                    subtitle: month.formatted(.dateTime.month(.wide).year()),
                    systemImage: "list.bullet.rectangle.portrait",
                    tint: .pink
                )

                if items.isEmpty {
                    BudgetWorkspaceEmptyState(
                        systemImage: "tray",
                        title: "No activity",
                        message: "There are no logged transactions for this month."
                    )
                } else {
                    GlassCard(padding: 10) {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                BudgetActivityRow(item: item) { onOpen(item) }
                                if index < items.count - 1 {
                                    Divider().padding(.leading, 42)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(CuanTheme.background.ignoresSafeArea())
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BudgetRecurringActivityView: View {
    let payments: [RecurringPayment]
    let onEdit: (RecurringPayment) -> Void

    private var monthlyOutflow: Double {
        payments.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var monthlyInflow: Double {
        payments.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BudgetWorkspaceSubpageHeader(
                    title: "Recurring",
                    subtitle: "Your predictable monthly movement",
                    systemImage: "repeat.circle.fill",
                    tint: .orange
                )

                HStack(spacing: 8) {
                    BudgetWorkspaceMetricCard(title: "Outflow", value: monthlyOutflow, tint: .red, systemImage: "arrow.up.right")
                    BudgetWorkspaceMetricCard(title: "Inflow", value: monthlyInflow, tint: .green, systemImage: "arrow.down.left")
                }

                if payments.isEmpty {
                    BudgetWorkspaceEmptyState(
                        systemImage: "repeat.circle",
                        title: "No recurring activity",
                        message: "Recurring bills and income will appear here."
                    )
                } else {
                    GlassCard(padding: 10) {
                        VStack(spacing: 0) {
                            ForEach(Array(payments.enumerated()), id: \.element.id) { index, payment in
                                Button { onEdit(payment) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: payment.kind == .income ? "arrow.down.circle.fill" : "repeat.circle.fill")
                                            .foregroundStyle(payment.kind == .income ? Color.green : Color.orange)
                                            .frame(width: 32, height: 32)
                                            .background((payment.kind == .income ? Color.green : Color.orange).opacity(0.11), in: Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(payment.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text("Day \(payment.dayOfMonth) · \(payment.kind == .income ? "income" : payment.section.title.lowercased())")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(payment.amount, format: .currency(code: "USD"))
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(payment.kind == .income ? Color.green : Color.primary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < payments.count - 1 {
                                    Divider().padding(.leading, 42)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(CuanTheme.background.ignoresSafeArea())
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BudgetActivityTrendsView: View {
    let expenses: [Expense]
    let incomes: [IncomeEntry]
    let savings: [SavingsEntry]
    let month: Date

    private struct Point: Identifiable {
        let date: Date
        let amount: Double
        var id: Date { date }
    }

    private var spendingPoints: [Point] { dailyPoints(expenses.map { ($0.date, $0.amount) }) }
    private var incomePoints: [Point] { dailyPoints(incomes.map { ($0.date, $0.amount) }) }

    private var peakSpend: Double { spendingPoints.map(\.amount).max() ?? 0 }
    private var averageSpend: Double {
        guard !spendingPoints.isEmpty else { return 0 }
        return spendingPoints.reduce(0) { $0 + $1.amount } / Double(spendingPoints.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BudgetWorkspaceSubpageHeader(
                    title: "Trends",
                    subtitle: month.formatted(.dateTime.month(.wide).year()),
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: .purple
                )

                HStack(spacing: 8) {
                    BudgetWorkspaceMetricCard(title: "Avg spend day", value: averageSpend, tint: .pink, systemImage: "calendar")
                    BudgetWorkspaceMetricCard(title: "Peak spend", value: peakSpend, tint: .orange, systemImage: "arrow.up.right")
                }

                trendCard(title: "Daily spending", points: spendingPoints, tint: .pink)
                trendCard(title: "Daily income", points: incomePoints, tint: .green)
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(CuanTheme.background.ignoresSafeArea())
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func trendCard(title: String, points: [Point], tint: Color) -> some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                if points.isEmpty {
                    Text("Not enough activity yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
                } else {
                    Chart(points) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Amount", point.amount)
                        )
                        .foregroundStyle(tint.opacity(0.12))
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Amount", point.amount)
                        )
                        .foregroundStyle(tint)
                        .interpolationMethod(.catmullRom)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.10))
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                }
                            }
                            .font(.caption2)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date, format: .dateTime.day())
                                }
                            }
                            .font(.caption2)
                        }
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    private func dailyPoints(_ entries: [(Date, Double)]) -> [Point] {
        let calendar = Calendar.current
        var totals: [Date: Double] = [:]
        for (date, amount) in entries {
            totals[calendar.startOfDay(for: date), default: 0] += amount
        }
        return totals.keys.sorted().map { Point(date: $0, amount: totals[$0] ?? 0) }
    }
}

struct BudgetAccountsWorkspaceView: View {
    @ObservedObject var budget: BudgetModel
    let onTransfer: () -> Void
    let onManageBanks: () -> Void
    let onManageCredit: () -> Void

    private var totalCash: Double { budget.bankAccounts.reduce(0) { $0 + $1.balance } }
    private var totalCredit: Double {
        budget.creditAccounts.filter(\.isActive).reduce(0) { $0 + actualBalance(for: $1) }
    }
    private var investmentNet: Double {
        let holdings = budget.holdings.reduce(0) { partial, holding in
            let quote = budget.cachedQuotes[holding.ticker.uppercased()]?.price ?? holding.currentPrice
            return partial + holding.shares * quote
        }
        return holdings + budget.portfolioSnapshot.cashBalance - budget.portfolioSnapshot.marginUsed
    }
    private var netPosition: Double { totalCash + investmentNet - totalCredit }

    private var highUtilizationCards: [CreditAccount] {
        budget.creditAccounts.filter { account in
            account.isActive && account.creditLimit > 0 && actualBalance(for: account) / account.creditLimit >= 0.30
        }
    }

    private var attentionCount: Int {
        highUtilizationCards.count + budget.plaidReviewItems.count
    }

    var body: some View {
        VStack(spacing: 12) {
            accountHero

            HStack(spacing: 8) {
                BudgetWorkspaceActionButton(title: "Transfer", systemImage: "arrow.left.arrow.right", tint: .cyan, action: onTransfer)
                BudgetWorkspaceActionButton(title: "Banks", systemImage: "building.columns", tint: .blue, action: onManageBanks)
                BudgetWorkspaceActionButton(title: "Cards", systemImage: "creditcard", tint: .orange, action: onManageCredit)
            }

            if attentionCount > 0 {
                attentionCard
            }

            BudgetWorkspaceSectionHeader(
                title: "Your accounts",
                subtitle: "Balances first, management one tap deeper"
            )

            VStack(spacing: 8) {
                NavigationLink {
                    BudgetBankAccountsWorkspaceView(budget: budget, onManage: onManageBanks)
                } label: {
                    BudgetWorkspaceNavigationRow(
                        title: "Bank accounts",
                        subtitle: "\(budget.bankAccounts.count) account\(budget.bankAccounts.count == 1 ? "" : "s")",
                        systemImage: "building.columns.fill",
                        tint: .blue,
                        value: totalCash.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    BudgetCreditAccountsWorkspaceView(budget: budget, onManage: onManageCredit)
                } label: {
                    BudgetWorkspaceNavigationRow(
                        title: "Credit cards",
                        subtitle: "\(budget.creditAccounts.filter(\.isActive).count) active",
                        systemImage: "creditcard.fill",
                        tint: .orange,
                        value: totalCredit.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    BudgetInvestmentsWorkspaceView(budget: budget)
                } label: {
                    BudgetWorkspaceNavigationRow(
                        title: "Investments",
                        subtitle: "Holdings, cash, and margin",
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: .mint,
                        value: investmentNet.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accountHero: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Net financial position")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(netPosition, format: .currency(code: "USD"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(netPosition >= 0 ? Color.primary : Color.red)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    BudgetWorkspaceMetricPill(title: "Cash", value: totalCash, tint: .blue, systemImage: "building.columns")
                    BudgetWorkspaceMetricPill(title: "Debt", value: totalCredit, tint: .orange, systemImage: "creditcard")
                    BudgetWorkspaceMetricPill(title: "Invested", value: investmentNet, tint: .mint, systemImage: "chart.line.uptrend.xyaxis")
                }
            }
        }
    }

    private var attentionCard: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Needs attention", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("\(attentionCount)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }

                if !highUtilizationCards.isEmpty {
                    Text("\(highUtilizationCards.count) card\(highUtilizationCards.count == 1 ? " is" : "s are") above 30% utilization.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !budget.plaidReviewItems.isEmpty {
                    Text("\(budget.plaidReviewItems.count) Plaid import\(budget.plaidReviewItems.count == 1 ? "" : "s") need review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func actualBalance(for account: CreditAccount) -> Double {
        if account.plaidMetadata != nil { return account.startingBalance }
        let normalized = account.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return 0 }
        return budget.expenses.reduce(account.startingBalance) { partial, expense in
            if let paidCard = budget.creditCardPaymentTarget(for: expense),
               paidCard.caseInsensitiveCompare(account.name) == .orderedSame {
                return partial - expense.amount
            }
            guard expense.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized else {
                return partial
            }
            return partial + expense.amount
        }
    }
}

private struct BudgetBankAccountsWorkspaceView: View {
    @ObservedObject var budget: BudgetModel
    let onManage: () -> Void

    private var total: Double { budget.bankAccounts.reduce(0) { $0 + $1.balance } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BudgetWorkspaceSubpageHeader(
                    title: "Bank accounts",
                    subtitle: "Cash you can actually deploy",
                    systemImage: "building.columns.fill",
                    tint: .blue
                )

                GlassCard(padding: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Available cash")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(total, format: .currency(code: "USD"))
                                .font(.title2.weight(.bold).monospacedDigit())
                        }
                        Spacer()
                        Button("Manage", action: onManage)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                if budget.bankAccounts.isEmpty {
                    BudgetWorkspaceEmptyState(
                        systemImage: "building.columns",
                        title: "No bank accounts",
                        message: "Add or sync an account to see cash balances here.",
                        actionTitle: "Manage accounts",
                        action: onManage
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(budget.bankAccounts) { account in
                            GlassCard(padding: 12) {
                                HStack(spacing: 10) {
                                    Image(systemName: "building.columns.fill")
                                        .foregroundStyle(.blue)
                                        .frame(width: 34, height: 34)
                                        .background(Color.blue.opacity(0.10), in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(account.plaidMetadata == nil ? "Manual account" : "Synced account")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(account.balance, format: .currency(code: "USD"))
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(CuanTheme.background.ignoresSafeArea())
        .navigationTitle("Banks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BudgetCreditAccountsWorkspaceView: View {
    @ObservedObject var budget: BudgetModel
    let onManage: () -> Void

    private var activeCards: [CreditAccount] { budget.creditAccounts.filter(\.isActive) }
    private var totalDebt: Double { activeCards.reduce(0) { $0 + actualBalance(for: $1) } }
    private var totalLimit: Double { activeCards.reduce(0) { $0 + max($1.creditLimit, 0) } }
    private var overallUtilization: Double { totalLimit > 0 ? totalDebt / totalLimit : 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BudgetWorkspaceSubpageHeader(
                    title: "Credit cards",
                    subtitle: "Debt, utilization, and due dates",
                    systemImage: "creditcard.fill",
                    tint: .orange
                )

                GlassCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Total card debt")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(totalDebt, format: .currency(code: "USD"))
                                    .font(.title2.weight(.bold).monospacedDigit())
                            }
                            Spacer()
                            Button("Manage", action: onManage)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        if totalLimit > 0 {
                            HStack {
                                Text("Overall utilization")
                                Spacer()
                                Text(overallUtilization, format: .percent.precision(.fractionLength(1)))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(utilizationTint(overallUtilization))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            ProgressView(value: min(max(overallUtilization, 0), 1))
                                .tint(utilizationTint(overallUtilization))
                        }
                    }
                }

                if activeCards.isEmpty {
                    BudgetWorkspaceEmptyState(
                        systemImage: "creditcard",
                        title: "No active cards",
                        message: "Add or sync a credit card to track balances and utilization.",
                        actionTitle: "Manage cards",
                        action: onManage
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(activeCards) { account in
                            NavigationLink {
                                BudgetCreditCardWorkspaceDetail(account: account, budget: budget)
                            } label: {
                                creditCardRow(account)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(CuanTheme.background.ignoresSafeArea())
        .navigationTitle("Credit")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creditCardRow(_ account: CreditAccount) -> some View {
        let balance = actualBalance(for: account)
        let utilization = account.creditLimit > 0 ? balance / account.creditLimit : 0
        return GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Due day \(account.dueDay) · closes \(account.closingDay)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(balance, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                if account.creditLimit > 0 {
                    ProgressView(value: min(max(utilization, 0), 1))
                        .tint(utilizationTint(utilization))
                    HStack {
                        Text("\(utilization.formatted(.percent.precision(.fractionLength(1)))) utilized")
                        Spacer()
                        Text("\(max(account.creditLimit - balance, 0).formatted(.currency(code: "USD"))) available")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func utilizationTint(_ utilization: Double) -> Color {
        if utilization >= 0.50 { return .red }
        if utilization >= 0.30 { return .orange }
        return .green
    }

    private func actualBalance(for account: CreditAccount) -> Double {
        if account.plaidMetadata != nil { return account.startingBalance }
        let normalized = account.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return 0 }
        return budget.expenses.reduce(account.startingBalance) { partial, expense in
            if let paidCard = budget.creditCardPaymentTarget(for: expense),
               paidCard.caseInsensitiveCompare(account.name) == .orderedSame {
                return partial - expense.amount
            }
            guard expense.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized else {
                return partial
            }
            return partial + expense.amount
        }
    }
}

private struct BudgetCreditCardWorkspaceDetail: View {
    let account: CreditAccount
    @ObservedObject var budget: BudgetModel

    private var balance: Double {
        if account.plaidMetadata != nil { return account.startingBalance }
        let normalized = account.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return budget.expenses.reduce(account.startingBalance) { partial, expense in
            if let paidCard = budget.creditCardPaymentTarget(for: expense),
               paidCard.caseInsensitiveCompare(account.name) == .orderedSame {
                return partial - expense.amount
            }
            guard expense.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized else { return partial }
            return partial + expense.amount
        }
    }

    private var utilization: Double { account.creditLimit > 0 ? balance / account.creditLimit : 0 }

    private var activity: [(id: String, date: Date, name: String, amount: Double, isPayment: Bool)] {
        let normalized = account.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let charges = budget.expenses.compactMap { expense -> (String, Date, String, Double, Bool)? in
            guard expense.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized else { return nil }
            return ("charge-\(expense.id.uuidString)", expense.date, expense.name, expense.amount, false)
        }
        let payments = budget.expenses.compactMap { expense -> (String, Date, String, Double, Bool)? in
            guard let target = budget.creditCardPaymentTarget(for: expense),
                  target.caseInsensitiveCompare(account.name) == .orderedSame else { return nil }
            return ("payment-\(expense.id.uuidString)", expense.date, expense.name, expense.amount, true)
        }
        return (charges + payments).sorted { $0.1 > $1.1 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BudgetWorkspaceSubpageHeader(
                    title: account.name,
                    subtitle: account.plaidMetadata == nil ? "Manual card" : "Synced card",
                    systemImage: "creditcard.fill",
                    tint: .orange
                )

                HStack(spacing: 8) {
                    BudgetWorkspaceMetricCard(title: "Balance", value: balance, tint: .orange, systemImage: "creditcard")
                    BudgetWorkspaceMetricCard(title: "Available", value: max(account.creditLimit - balance, 0), tint: .green, systemImage: "checkmark.circle")
                }

                GlassCard(padding: 12) {
                    VStack(spacing: 10) {
                        BudgetWorkspaceLabeledValue(title: "Utilization", value: utilization.formatted(.percent.precision(.fractionLength(1))))
                        BudgetWorkspaceLabeledValue(title: "Credit limit", value: account.creditLimit.formatted(.currency(code: "USD")))
                        BudgetWorkspaceLabeledValue(title: "Statement closes", value: "Day \(account.closingDay)")
                        BudgetWorkspaceLabeledValue(title: "Payment due", value: "Day \(account.dueDay)")
                    }
                }

                BudgetWorkspaceSectionHeader(title: "Recent card activity", subtitle: "Purchases and payments")
                if activity.isEmpty {
                    BudgetWorkspaceEmptyState(systemImage: "tray", title: "No card activity", message: "Transactions using this card will show here.")
                } else {
                    GlassCard(padding: 10) {
                        VStack(spacing: 0) {
                            ForEach(Array(activity.prefix(20).enumerated()), id: \.element.id) { index, item in
                                HStack(spacing: 10) {
                                    Image(systemName: item.isPayment ? "arrow.down.circle.fill" : "bag.fill")
                                        .foregroundStyle(item.isPayment ? Color.green : Color.orange)
                                        .frame(width: 30, height: 30)
                                        .background((item.isPayment ? Color.green : Color.orange).opacity(0.10), in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(item.date, format: .dateTime.month(.abbreviated).day().year())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(item.isPayment ? "-" : "+")\(item.amount.formatted(.currency(code: "USD")))")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(item.isPayment ? Color.green : Color.primary)
                                }
                                .padding(.vertical, 9)
                                if index < min(activity.count, 20) - 1 {
                                    Divider().padding(.leading, 40)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(CuanTheme.background.ignoresSafeArea())
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BudgetInvestmentsWorkspaceView: View {
    @ObservedObject var budget: BudgetModel

    private var holdingsValue: Double {
        budget.holdings.reduce(0) { partial, holding in
            let price = budget.cachedQuotes[holding.ticker.uppercased()]?.price ?? holding.currentPrice
            return partial + holding.shares * price
        }
    }

    private var net: Double { holdingsValue + budget.portfolioSnapshot.cashBalance - budget.portfolioSnapshot.marginUsed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BudgetWorkspaceSubpageHeader(
                    title: "Investments",
                    subtitle: "Holdings, cash, and margin exposure",
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: .mint
                )

                HStack(spacing: 8) {
                    BudgetWorkspaceMetricCard(title: "Net", value: net, tint: .mint, systemImage: "chart.line.uptrend.xyaxis")
                    BudgetWorkspaceMetricCard(title: "Margin", value: budget.portfolioSnapshot.marginUsed, tint: .purple, systemImage: "creditcard")
                }

                GlassCard(padding: 12) {
                    VStack(spacing: 10) {
                        BudgetWorkspaceLabeledValue(title: "Holdings", value: holdingsValue.formatted(.currency(code: "USD")))
                        BudgetWorkspaceLabeledValue(title: "Portfolio cash", value: budget.portfolioSnapshot.cashBalance.formatted(.currency(code: "USD")))
                        BudgetWorkspaceLabeledValue(title: "Margin used", value: budget.portfolioSnapshot.marginUsed.formatted(.currency(code: "USD")))
                    }
                }

                BudgetWorkspaceSectionHeader(title: "Holdings", subtitle: "Largest positions first")
                let holdings = budget.consolidatedHoldings.sorted { lhs, rhs in
                    let lhsPrice = budget.cachedQuotes[lhs.ticker.uppercased()]?.price ?? lhs.currentPrice
                    let rhsPrice = budget.cachedQuotes[rhs.ticker.uppercased()]?.price ?? rhs.currentPrice
                    return lhs.shares * lhsPrice > rhs.shares * rhsPrice
                }

                if holdings.isEmpty {
                    BudgetWorkspaceEmptyState(systemImage: "chart.line.uptrend.xyaxis", title: "No holdings", message: "Investment holdings will appear here once added or synced.")
                } else {
                    GlassCard(padding: 10) {
                        VStack(spacing: 0) {
                            ForEach(Array(holdings.enumerated()), id: \.element.id) { index, holding in
                                let price = budget.cachedQuotes[holding.ticker.uppercased()]?.price ?? holding.currentPrice
                                HStack(spacing: 10) {
                                    Text(holding.ticker.uppercased())
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.mint)
                                        .frame(width: 48, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(holding.shares, specifier: "%.3f") shares")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(price, format: .currency(code: "USD"))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Text(holding.shares * price, format: .currency(code: "USD"))
                                        .font(.subheadline.weight(.bold))
                                }
                                .padding(.vertical, 9)
                                if index < holdings.count - 1 {
                                    Divider().padding(.leading, 58)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(CuanTheme.background.ignoresSafeArea())
        .navigationTitle("Investments")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BudgetReportsWorkspaceView: View {
    @ObservedObject var budget: BudgetModel
    @Binding var selectedMonth: Date

    private var interval: DateInterval? { Calendar.current.dateInterval(of: .month, for: selectedMonth) }
    private var previousMonth: Date { Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth }

    private var expenses: [Expense] {
        guard let interval else { return [] }
        return budget.expenses.filter { interval.contains($0.date) && !budget.isCreditCardPayment($0) }
    }
    private var incomes: [IncomeEntry] {
        guard let interval else { return [] }
        return budget.incomes.filter { interval.contains($0.date) }
    }
    private var savings: [SavingsEntry] {
        guard let interval else { return [] }
        return budget.savingsEntries.filter { interval.contains($0.date) }
    }

    private var expectedIncome: Double {
        budget.income(for: selectedMonth) * budget.payFrequency.multiplier / 12.0
    }
    private var loggedIncome: Double { incomes.reduce(0) { $0 + $1.amount } }
    private var reportIncome: Double { loggedIncome > 0 ? loggedIncome : expectedIncome }
    private var totalSpent: Double { expenses.reduce(0) { $0 + $1.amount } }
    private var totalSaved: Double { savings.reduce(0) { $0 + $1.amount } }
    private var remaining: Double { reportIncome - totalSpent - totalSaved }
    private var savingsRate: Double { reportIncome > 0 ? totalSaved / reportIncome : 0 }

    var body: some View {
        VStack(spacing: 12) {
            BudgetWorkspaceMonthSelector(selectedMonth: $selectedMonth)
            reportHero

            BudgetWorkspaceSectionHeader(title: "Reports", subtitle: "Read the story, then drill into the why")

            VStack(spacing: 8) {
                NavigationLink {
                    BudgetCategoryReportView(budget: budget, month: selectedMonth)
                } label: {
                    BudgetWorkspaceNavigationRow(
                        title: "Category performance",
                        subtitle: "Where spending concentrated",
                        systemImage: "list.bullet.rectangle",
                        tint: .purple,
                        value: "\(categoryItems.count)"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    BudgetAllocationReportView(budget: budget, month: selectedMonth)
                } label: {
                    BudgetWorkspaceNavigationRow(
                        title: "50 / 20 / 30",
                        subtitle: "Targets compared with actuals",
                        systemImage: "chart.bar.fill",
                        tint: .blue,
                        value: remaining.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    BudgetMonthComparisonReportView(budget: budget, month: selectedMonth)
                } label: {
                    BudgetWorkspaceNavigationRow(
                        title: "Month comparison",
                        subtitle: "\(previousMonth.formatted(.dateTime.month(.abbreviated))) vs \(selectedMonth.formatted(.dateTime.month(.abbreviated)))",
                        systemImage: "arrow.left.arrow.right",
                        tint: .orange,
                        value: monthSpendDelta.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                    )
                }
                .buttonStyle(.plain)
            }

            if let top = categoryItems.first {
                GlassCard(padding: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                            .frame(width: 34, height: 34)
                            .background(Color.yellow.opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Largest category")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(top.name)
                                .font(.subheadline.weight(.bold))
                            Text("\(top.spent.formatted(.currency(code: "USD"))) spent this month")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var reportHero: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Remaining after spending + savings")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(remaining, format: .currency(code: "USD"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(remaining >= 0 ? Color.green : Color.red)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(savingsRate, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.mint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.mint.opacity(0.11), in: Capsule())
                }

                HStack(spacing: 8) {
                    BudgetWorkspaceMetricPill(title: "Income", value: reportIncome, tint: .green, systemImage: "arrow.down.left")
                    BudgetWorkspaceMetricPill(title: "Spent", value: totalSpent, tint: .red, systemImage: "arrow.up.right")
                    BudgetWorkspaceMetricPill(title: "Saved", value: totalSaved, tint: .mint, systemImage: "banknote")
                }
            }
        }
    }

    private var categoryItems: [BudgetCategoryReportItem] {
        BudgetReportData.categoryItems(budget: budget, month: selectedMonth)
    }

    private var monthSpendDelta: Double {
        BudgetReportData.totalSpend(budget: budget, month: selectedMonth)
            - BudgetReportData.totalSpend(budget: budget, month: previousMonth)
    }
}

private struct BudgetCategoryReportItem: Identifiable {
    let id: String
    let name: String
    let section: BudgetSection
    let planned: Double
    let spent: Double
}

private enum BudgetReportData {
    static func expectedIncome(budget: BudgetModel, month: Date) -> Double {
        budget.income(for: month) * budget.payFrequency.multiplier / 12.0
    }

    static func expenses(budget: BudgetModel, month: Date) -> [Expense] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return budget.expenses.filter { interval.contains($0.date) && !budget.isCreditCardPayment($0) }
    }

    static func incomes(budget: BudgetModel, month: Date) -> [IncomeEntry] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return budget.incomes.filter { interval.contains($0.date) }
    }

    static func savings(budget: BudgetModel, month: Date) -> [SavingsEntry] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return budget.savingsEntries.filter { interval.contains($0.date) }
    }

    static func totalSpend(budget: BudgetModel, month: Date) -> Double {
        expenses(budget: budget, month: month).reduce(0) { $0 + $1.amount }
    }

    static func categoryItems(budget: BudgetModel, month: Date) -> [BudgetCategoryReportItem] {
        let expenses = expenses(budget: budget, month: month)
        let key = BudgetModel.monthKey(for: month)
        var totals: [UUID: Double] = [:]
        for expense in expenses {
            totals[expense.categoryId, default: 0] += expense.amount
        }

        let needs = budget.needsCategories.map { category in
            BudgetCategoryReportItem(
                id: "needs-\(category.id.uuidString)",
                name: category.name,
                section: .needs,
                planned: budget.needsAllocationsByMonth[key]?[category.id] ?? category.allocatedAmount,
                spent: totals[category.id] ?? 0
            )
        }
        let wants = budget.wantsCategories.map { category in
            BudgetCategoryReportItem(
                id: "wants-\(category.id.uuidString)",
                name: category.name,
                section: .wants,
                planned: budget.wantsAllocationsByMonth[key]?[category.id] ?? category.allocatedAmount,
                spent: totals[category.id] ?? 0
            )
        }
        return (needs + wants)
            .filter { $0.planned > 0 || $0.spent > 0 }
            .sorted { $0.spent > $1.spent }
    }
}

private struct BudgetCategoryReportView: View {
    @ObservedObject var budget: BudgetModel
    let month: Date

    private var items: [BudgetCategoryReportItem] { BudgetReportData.categoryItems(budget: budget, month: month) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BudgetWorkspaceSubpageHeader(
                    title: "Categories",
                    subtitle: month.formatted(.dateTime.month(.wide).year()),
                    systemImage: "list.bullet.rectangle",
                    tint: .purple
                )

                if items.isEmpty {
                    BudgetWorkspaceEmptyState(systemImage: "tray", title: "No category activity", message: "Once spending is logged, category performance will show here.")
                } else {
                    GlassCard(padding: 10) {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                let remaining = item.planned - item.spent
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.subheadline.weight(.bold))
                                            Text(item.section.title)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(item.spent, format: .currency(code: "USD"))
                                                .font(.subheadline.weight(.bold))
                                            if item.planned > 0 {
                                                Text(remaining >= 0 ? "\(remaining.formatted(.currency(code: "USD"))) left" : "\(abs(remaining).formatted(.currency(code: "USD"))) over")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(remaining >= 0 ? Color.secondary : Color.red)
                                            }
                                        }
                                    }
                                    if item.planned > 0 {
                                        ProgressView(value: min(max(item.spent / item.planned, 0), 1))
                                            .tint(remaining >= 0 ? (item.section == .needs ? Color.blue : Color.orange) : Color.red)
                                    }
                                }
                                .padding(.vertical, 10)
                                if index < items.count - 1 { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(CuanTheme.background.ignoresSafeArea())
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BudgetAllocationReportView: View {
    @ObservedObject var budget: BudgetModel
    let month: Date

    private var income: Double {
        let logged = BudgetReportData.incomes(budget: budget, month: month).reduce(0) { $0 + $1.amount }
        return logged > 0 ? logged : BudgetReportData.expectedIncome(budget: budget, month: month)
    }
    private var expenses: [Expense] { BudgetReportData.expenses(budget: budget, month: month) }
    private var needsSpent: Double { expenses.filter { $0.section == .needs }.reduce(0) { $0 + $1.amount } }
    private var wantsSpent: Double { expenses.filter { $0.section == .wants }.reduce(0) { $0 + $1.amount } }
    private var savings: Double { BudgetReportData.savings(budget: budget, month: month).reduce(0) { $0 + $1.amount } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BudgetWorkspaceSubpageHeader(
                    title: "50 / 20 / 30",
                    subtitle: "Target allocation compared with actuals",
                    systemImage: "chart.bar.fill",
                    tint: .blue
                )

                allocationCard(title: "Needs", percentage: 0.50, actual: needsSpent, tint: .blue)
                allocationCard(title: "Wants", percentage: 0.20, actual: wantsSpent, tint: .orange)
                allocationCard(title: "Savings", percentage: 0.30, actual: savings, tint: .mint)
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(CuanTheme.background.ignoresSafeArea())
        .navigationTitle("Allocation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func allocationCard(title: String, percentage: Double, actual: Double, tint: Color) -> some View {
        let target = income * percentage
        let delta = target - actual
        let progress = target > 0 ? min(max(actual / target, 0), 1) : 0
        return GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.bold))
                        Text("\(percentage.formatted(.percent.precision(.fractionLength(0)))) target")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(target, format: .currency(code: "USD"))
                        .font(.subheadline.weight(.bold))
                }
                HStack {
                    Text("Actual \(actual.formatted(.currency(code: "USD")))")
                    Spacer()
                    Text(delta >= 0 ? "\(delta.formatted(.currency(code: "USD"))) remaining" : "\(abs(delta).formatted(.currency(code: "USD"))) over")
                        .foregroundStyle(delta >= 0 ? Color.secondary : Color.red)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if target > 0 {
                    ProgressView(value: progress)
                        .tint(delta >= 0 ? tint : .red)
                }
            }
        }
    }
}

private struct BudgetMonthComparisonReportView: View {
    @ObservedObject var budget: BudgetModel
    let month: Date

    private var previousMonth: Date { Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BudgetWorkspaceSubpageHeader(
                    title: "Month comparison",
                    subtitle: "\(previousMonth.formatted(.dateTime.month(.wide))) → \(month.formatted(.dateTime.month(.wide)))",
                    systemImage: "arrow.left.arrow.right",
                    tint: .orange
                )

                comparisonCard(title: "Spending", current: spend(month), previous: spend(previousMonth), lowerIsBetter: true, tint: .pink)
                comparisonCard(title: "Income", current: income(month), previous: income(previousMonth), lowerIsBetter: false, tint: .green)
                comparisonCard(title: "Savings", current: savings(month), previous: savings(previousMonth), lowerIsBetter: false, tint: .mint)
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(CuanTheme.background.ignoresSafeArea())
        .navigationTitle("Comparison")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func comparisonCard(title: String, current: Double, previous: Double, lowerIsBetter: Bool, tint: Color) -> some View {
        let delta = current - previous
        let isPositive = lowerIsBetter ? delta <= 0 : delta >= 0
        return GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Label(
                        delta == 0 ? "No change" : abs(delta).formatted(.currency(code: "USD")),
                        systemImage: delta > 0 ? "arrow.up.right" : (delta < 0 ? "arrow.down.right" : "minus")
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(delta == 0 ? Color.secondary : (isPositive ? Color.green : Color.red))
                }
                HStack(spacing: 8) {
                    monthValue(month: previousMonth, value: previous, tint: .secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    monthValue(month: month, value: current, tint: tint)
                }
            }
        }
    }

    private func monthValue(month: Date, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(month, format: .dateTime.month(.abbreviated))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: "USD"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func spend(_ date: Date) -> Double { BudgetReportData.totalSpend(budget: budget, month: date) }
    private func income(_ date: Date) -> Double { BudgetReportData.incomes(budget: budget, month: date).reduce(0) { $0 + $1.amount } }
    private func savings(_ date: Date) -> Double { BudgetReportData.savings(budget: budget, month: date).reduce(0) { $0 + $1.amount } }
}

private struct BudgetWorkspaceMonthSelector: View {
    @Binding var selectedMonth: Date

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous month")

            VStack(spacing: 1) {
                Text(selectedMonth, format: .dateTime.month(.wide).year())
                    .font(.subheadline.weight(.bold))
                Text(isCurrentMonth ? "Current month" : "Monthly view")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button { shift(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 4)
    }

    private func shift(_ offset: Int) {
        guard let shifted = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) else { return }
        let target = Calendar.current.compare(shifted, to: Date(), toGranularity: .month) == .orderedDescending ? Date() : shifted
        withAnimation(.snappy) { selectedMonth = target }
    }
}

private struct BudgetWorkspaceSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

private struct BudgetWorkspaceSubpageHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct BudgetWorkspaceMetricPill: View {
    let title: String
    let value: Double
    let tint: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.caption.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.62)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct BudgetWorkspaceMetricCard: View {
    let title: String
    let value: Double
    let tint: Color
    let systemImage: String

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.10), in: Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct BudgetWorkspaceActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct BudgetWorkspaceNavigationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let value: String

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(value)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct BudgetWorkspaceLabeledValue: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct BudgetWorkspaceEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
