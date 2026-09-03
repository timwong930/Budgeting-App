import SwiftUI

struct MonthlyPlanWorkspaceView: View {
    @ObservedObject var budget: BudgetModel
    @Binding var selectedMonth: Date

    let onAddNeeds: () -> Void
    let onAddWants: () -> Void
    let onAddSavings: () -> Void
    let onEditCategory: (Category) -> Void
    let onEditSavingsGoal: (SavingsGoal) -> Void

    private var monthKey: String {
        BudgetModel.monthKey(for: selectedMonth)
    }

    private var incomePerPayPeriod: Double {
        budget.income(for: selectedMonth)
    }

    private var monthlyIncomeMultiplier: Double {
        budget.payFrequency.multiplier / 12.0
    }

    private var plannedIncome: Double {
        incomePerPayPeriod * monthlyIncomeMultiplier
    }

    private var incomeBinding: Binding<Double> {
        Binding(
            get: { plannedIncome },
            set: { value in
                let multiplier = max(monthlyIncomeMultiplier, 0.0001)
                budget.setIncome(max(value, 0) / multiplier, for: selectedMonth)
            }
        )
    }

    private var plannedNeeds: Double {
        budget.needsCategories.reduce(0) { $0 + allocation(for: $1, section: .needs) }
    }

    private var plannedWants: Double {
        budget.wantsCategories.reduce(0) { $0 + allocation(for: $1, section: .wants) }
    }

    private var plannedSavings: Double {
        budget.savingsGoals.reduce(0) { $0 + max($1.monthlyContribution, 0) }
    }

    private var totalAssigned: Double {
        plannedNeeds + plannedWants + plannedSavings
    }

    private var unassigned: Double {
        plannedIncome - totalAssigned
    }

    private var monthExpenses: [Expense] {
        budget.expenses.filter { expense in
            Calendar.current.isDate(expense.date, equalTo: selectedMonth, toGranularity: .month) &&
                !budget.isCreditCardPayment(expense)
        }
    }

    private var needsSpent: Double {
        monthExpenses.filter { $0.section == .needs }.reduce(0) { $0 + $1.amount }
    }

    private var wantsSpent: Double {
        monthExpenses.filter { $0.section == .wants }.reduce(0) { $0 + $1.amount }
    }

    private var savingsLogged: Double {
        budget.savingsEntries
            .filter { Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    private var assignmentProgress: Double {
        guard plannedIncome > 0 else { return 0 }
        return min(max(totalAssigned / plannedIncome, 0), 1)
    }

    private var planStatus: (title: String, message: String, systemImage: String, tint: Color) {
        if plannedIncome <= 0 {
            return (
                "Start with income",
                "Add the income you expect this month, then give it a job.",
                "dollarsign.circle.fill",
                .orange
            )
        }
        if unassigned > 0.01 {
            return (
                "Still needs a plan",
                "Assign the remaining \(unassigned.formatted(.currency(code: "USD"))) before the month gets busy.",
                "arrow.down.circle.fill",
                .blue
            )
        }
        if unassigned < -0.01 {
            return (
                "Plan needs attention",
                "Reduce planned spending by \(abs(unassigned).formatted(.currency(code: "USD"))).",
                "exclamationmark.triangle.fill",
                .red
            )
        }
        return (
            "Plan is balanced",
            "Every expected dollar has a job for this month.",
            "checkmark.circle.fill",
            .green
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            planHero
            planTotals
            categorySection(
                title: "Needs",
                subtitle: "Required monthly spending",
                systemImage: "house.fill",
                tint: .blue,
                categories: budget.needsCategories,
                section: .needs,
                onAdd: onAddNeeds
            )
            categorySection(
                title: "Wants",
                subtitle: "Flexible monthly spending",
                systemImage: "sparkles",
                tint: .orange,
                categories: budget.wantsCategories,
                section: .wants,
                onAdd: onAddWants
            )
            savingsSection

            Text("Your categories carry forward. Only the monthly amounts change, so each new month starts from your latest plan instead of a blank slate.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .onAppear {
            ensureMonthlyPlan(for: selectedMonth)
        }
        .onChange(of: selectedMonth) { _, month in
            ensureMonthlyPlan(for: month)
        }
    }

    private var planHero: some View {
        let status = planStatus
        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button { shiftMonth(-1) } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 32, height: 32)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous month")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedMonth, format: .dateTime.month(.wide).year())
                            .font(.headline)
                        Text("Monthly plan")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button { shiftMonth(1) } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 32, height: 32)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next month")
                }

                Divider()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: status.systemImage)
                        .font(.headline)
                        .foregroundStyle(status.tint)
                        .frame(width: 34, height: 34)
                        .background(status.tint.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(status.title)
                            .font(.subheadline.weight(.bold))
                        Text(status.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Expected monthly income")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            Text("$")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField(
                                "0",
                                value: incomeBinding,
                                format: .number.precision(.fractionLength(0...2))
                            )
                            .keyboardType(.decimalPad)
                            .font(.headline.monospacedDigit())
                        }
                        Text("\(budget.payFrequency.rawValue) schedule · \(incomePerPayPeriod.formatted(.currency(code: "USD"))) per pay period")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                        .frame(height: 46)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(unassigned >= 0 ? "Unassigned" : "Over planned")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(abs(unassigned), format: .currency(code: "USD"))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(unassigned < -0.01 ? Color.red : Color.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if plannedIncome > 0 {
                    VStack(spacing: 5) {
                        ProgressView(value: assignmentProgress)
                            .tint(unassigned < -0.01 ? .red : status.tint)
                        HStack {
                            Text("\(totalAssigned.formatted(.currency(code: "USD"))) assigned")
                            Spacer()
                            Text("\((assignmentProgress * 100).formatted(.number.precision(.fractionLength(0))))% planned")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var planTotals: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            planTotalCard(
                title: "Needs",
                systemImage: "house.fill",
                planned: plannedNeeds,
                actual: needsSpent,
                tint: .blue
            )
            planTotalCard(
                title: "Wants",
                systemImage: "sparkles",
                planned: plannedWants,
                actual: wantsSpent,
                tint: .orange
            )
            planTotalCard(
                title: "Savings",
                systemImage: "banknote.fill",
                planned: plannedSavings,
                actual: savingsLogged,
                tint: .mint
            )
        }
    }

    private func planTotalCard(
        title: String,
        systemImage: String,
        planned: Double,
        actual: Double,
        tint: Color
    ) -> some View {
        let remaining = planned - actual
        let progress = planned > 0 ? min(max(actual / planned, 0), 1) : 0

        return GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                    Text(title)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(tint)

                Text(planned, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("\(actual.formatted(.currency(code: "USD"))) used")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)

                if planned > 0 {
                    ProgressView(value: progress)
                        .tint(remaining >= 0 ? tint : .red)
                }

                Text(remaining >= 0
                     ? "\(remaining.formatted(.currency(code: "USD"))) left"
                     : "\(abs(remaining).formatted(.currency(code: "USD"))) over")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(remaining >= 0 ? Color.secondary : Color.red)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func categorySection(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        categories: [Category],
        section: BudgetSection,
        onAdd: @escaping () -> Void
    ) -> some View {
        let planned = categories.reduce(0) { $0 + allocation(for: $1, section: section) }
        let spent = categories.reduce(0) { $0 + self.spent(for: $1.id, section: section) }

        return GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                        .frame(width: 30, height: 30)
                        .background(tint.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(planned, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text("\(spent.formatted(.currency(code: "USD"))) used")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(tint.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(title) category")
                }

                if categories.isEmpty {
                    Text("No categories yet. Add one to start assigning this month's income.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(categories) { category in
                        Divider()
                        categoryRow(category, section: section, tint: tint)
                    }
                }
            }
        }
    }

    private func categoryRow(_ category: Category, section: BudgetSection, tint: Color) -> some View {
        let planned = allocation(for: category, section: section)
        let spent = spent(for: category.id, section: section)
        let remaining = planned - spent
        let progress = planned > 0 ? min(max(spent / planned, 0), 1) : 0

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Button {
                    onEditCategory(category)
                } label: {
                    HStack(spacing: 6) {
                        Text(category.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Text("$")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "0",
                    value: allocationBinding(for: category, section: section),
                    format: .number.precision(.fractionLength(0...2))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 90)
            }

            HStack {
                Text("Spent \(spent.formatted(.currency(code: "USD")))")
                Spacer()
                Text("\(remaining >= 0 ? "Left" : "Over") \(abs(remaining).formatted(.currency(code: "USD")))")
                    .fontWeight(.semibold)
                    .foregroundStyle(remaining >= 0 ? Color.secondary : Color.red)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if planned > 0 {
                ProgressView(value: progress)
                    .tint(remaining >= 0 ? tint : .red)
            }
        }
        .padding(.vertical, 2)
    }

    private var savingsSection: some View {
        let remaining = plannedSavings - savingsLogged

        return GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "banknote.fill")
                        .foregroundStyle(.mint)
                        .frame(width: 30, height: 30)
                        .background(Color.mint.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Savings")
                            .font(.headline)
                        Text("Monthly contributions toward your goals")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(plannedSavings, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text(remaining >= 0
                             ? "\(remaining.formatted(.currency(code: "USD"))) left"
                             : "Goal exceeded")
                            .font(.caption2)
                            .foregroundStyle(remaining >= 0 ? Color.secondary : Color.green)
                    }
                    Button(action: onAddSavings) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(Color.mint.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add savings goal")
                }

                if budget.savingsGoals.isEmpty {
                    Text("No savings goals yet. Add one to make saving part of the monthly plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(budget.savingsGoals) { goal in
                        let saved = savedThisMonth(for: goal.id)
                        let contribution = max(goal.monthlyContribution, 0)
                        let goalRemaining = contribution - saved
                        let progress = contribution > 0 ? min(max(saved / contribution, 0), 1) : 0

                        Divider()
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Button {
                                    onEditSavingsGoal(goal)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(goal.displayName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Image(systemName: "pencil")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Text(contribution, format: .currency(code: "USD"))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                            }

                            HStack {
                                Text("Saved \(saved.formatted(.currency(code: "USD")))")
                                Spacer()
                                Text(goalRemaining >= 0
                                     ? "Left \(goalRemaining.formatted(.currency(code: "USD")))"
                                     : "Ahead \(abs(goalRemaining).formatted(.currency(code: "USD")))")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(goalRemaining >= 0 ? Color.secondary : Color.green)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            if contribution > 0 {
                                ProgressView(value: progress)
                                    .tint(.mint)
                            }
                        }
                    }
                }
            }
        }
    }

    private func allocation(for category: Category, section: BudgetSection) -> Double {
        switch section {
        case .needs:
            return budget.needsAllocationsByMonth[monthKey]?[category.id] ?? category.allocatedAmount
        case .wants:
            return budget.wantsAllocationsByMonth[monthKey]?[category.id] ?? category.allocatedAmount
        }
    }

    private func allocationBinding(for category: Category, section: BudgetSection) -> Binding<Double> {
        Binding(
            get: { allocation(for: category, section: section) },
            set: { value in
                let amount = max(value, 0)
                switch section {
                case .needs:
                    var month = budget.needsAllocationsByMonth[monthKey] ?? [:]
                    month[category.id] = amount
                    budget.needsAllocationsByMonth[monthKey] = month
                case .wants:
                    var month = budget.wantsAllocationsByMonth[monthKey] ?? [:]
                    month[category.id] = amount
                    budget.wantsAllocationsByMonth[monthKey] = month
                }
            }
        )
    }

    private func ensureMonthlyPlan(for date: Date) {
        let key = BudgetModel.monthKey(for: date)

        if budget.incomeByMonth[key] == nil {
            let priorIncome = budget.incomeByMonth.keys
                .filter { $0 < key }
                .sorted(by: >)
                .compactMap { budget.incomeByMonth[$0] }
                .first
            budget.incomeByMonth[key] = priorIncome ?? budget.income
        }

        var needsMonth = budget.needsAllocationsByMonth[key] ?? [:]
        for category in budget.needsCategories where needsMonth[category.id] == nil {
            needsMonth[category.id] = latestPriorAllocation(
                in: budget.needsAllocationsByMonth,
                before: key,
                categoryId: category.id
            ) ?? category.allocatedAmount
        }
        budget.needsAllocationsByMonth[key] = needsMonth

        var wantsMonth = budget.wantsAllocationsByMonth[key] ?? [:]
        for category in budget.wantsCategories where wantsMonth[category.id] == nil {
            wantsMonth[category.id] = latestPriorAllocation(
                in: budget.wantsAllocationsByMonth,
                before: key,
                categoryId: category.id
            ) ?? category.allocatedAmount
        }
        budget.wantsAllocationsByMonth[key] = wantsMonth
    }

    private func latestPriorAllocation(
        in allocations: [String: [UUID: Double]],
        before monthKey: String,
        categoryId: UUID
    ) -> Double? {
        for key in allocations.keys.filter({ $0 < monthKey }).sorted(by: >) {
            if let value = allocations[key]?[categoryId] {
                return value
            }
        }
        return nil
    }

    private func spent(for categoryId: UUID, section: BudgetSection) -> Double {
        monthExpenses
            .filter { $0.section == section && $0.categoryId == categoryId }
            .reduce(0) { $0 + $1.amount }
    }

    private func savedThisMonth(for goalId: UUID) -> Double {
        budget.savingsEntries
            .filter {
                $0.goalId == goalId &&
                    Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
            }
            .reduce(0) { $0 + $1.amount }
    }

    private func shiftMonth(_ offset: Int) {
        guard let shifted = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) else { return }
        withAnimation(.snappy) {
            selectedMonth = shifted
        }
    }
}