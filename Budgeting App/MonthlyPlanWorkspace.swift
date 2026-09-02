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

    private var plannedIncome: Double {
        budget.income(for: selectedMonth)
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

    var body: some View {
        VStack(spacing: 12) {
            monthNavigator
            assignmentSummary
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

            Text("Your category list, monthly targets, and Plaid merchant category choices carry forward automatically. You can still change a single month's target without rewriting older months.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .onAppear {
            budget.applyMonthlyAllocations(for: selectedMonth)
        }
    }

    private var monthNavigator: some View {
        GlassCard(padding: 10) {
            HStack(spacing: 10) {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")

                VStack(spacing: 2) {
                    Text(selectedMonth, format: .dateTime.month(.wide).year())
                        .font(.headline)
                    Text("Monthly plan")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next month")
            }
        }
    }

    private var assignmentSummary: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(unassigned >= 0 ? "Unassigned" : "Over planned")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(abs(unassigned), format: .currency(code: "USD"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(unassigned >= 0 ? Color.primary : Color.red)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Assigned")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(totalAssigned, format: .currency(code: "USD"))
                            .font(.headline.monospacedDigit())
                    }
                }

                HStack(spacing: 8) {
                    Text("Income")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField(
                        "0",
                        value: $budget.income,
                        format: .number.precision(.fractionLength(0...2))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 110)
                }
                .padding(.top, 2)

                if plannedIncome > 0 {
                    ProgressView(value: min(max(totalAssigned / plannedIncome, 0), 1))
                }
            }
        }
    }

    private var planTotals: some View {
        HStack(spacing: 8) {
            planTotalCard(title: "Needs", planned: plannedNeeds, actual: needsSpent, tint: .blue)
            planTotalCard(title: "Wants", planned: plannedWants, actual: wantsSpent, tint: .orange)
            planTotalCard(title: "Savings", planned: plannedSavings, actual: savingsLogged, tint: .mint)
        }
    }

    private func planTotalCard(title: String, planned: Double, actual: Double, tint: Color) -> some View {
        GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
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
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
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
                .font(.subheadline.monospacedDigit())
                .frame(width: 90)
            }

            HStack {
                Text("Spent \(spent.formatted(.currency(code: "USD")))")
                Spacer()
                Text("\(remaining >= 0 ? "Left" : "Over") \(abs(remaining).formatted(.currency(code: "USD")))")
                    .foregroundStyle(remaining >= 0 ? Color.secondary : Color.red)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if planned > 0 {
                ProgressView(value: min(max(spent / planned, 0), 1))
                    .tint(remaining >= 0 ? tint : .red)
            }
        }
        .padding(.vertical, 2)
    }

    private var savingsSection: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "banknote.fill")
                        .foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Savings")
                            .font(.headline)
                        Text("Monthly contributions toward your goals")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
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
                    Text("No savings goals yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(budget.savingsGoals) { goal in
                        Divider()
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
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
                                Text("\(savedThisMonth(for: goal.id).formatted(.currency(code: "USD"))) saved this month")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(goal.monthlyContribution, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
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
                budget.setAllocation(max(value, 0), for: category.id, section: section, date: selectedMonth)
            }
        )
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
