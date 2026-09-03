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

    private var needsTarget: Double {
        plannedIncome * 0.50
    }

    private var wantsTarget: Double {
        plannedIncome * 0.20
    }

    private var savingsTarget: Double {
        plannedIncome * 0.30
    }

    private var categorizedNeeds: Double {
        budget.needsCategories.reduce(0) { $0 + allocation(for: $1, section: .needs) }
    }

    private var categorizedWants: Double {
        budget.wantsCategories.reduce(0) { $0 + allocation(for: $1, section: .wants) }
    }

    private var categorizedSavings: Double {
        budget.savingsGoals.reduce(0) { $0 + max($1.monthlyContribution, 0) }
    }

    private var plannedNeeds: Double {
        max(needsTarget, categorizedNeeds)
    }

    private var plannedWants: Double {
        max(wantsTarget, categorizedWants)
    }

    private var plannedSavings: Double {
        max(savingsTarget, categorizedSavings)
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
                "Add the income you expect this month, then the app can fund your 50/20/30 buckets.",
                "dollarsign.circle.fill",
                .orange
            )
        }
        if unassigned < -0.01 {
            return (
                "Plan needs attention",
                "Your subcategories exceed their parent buckets by \(abs(unassigned).formatted(.currency(code: "USD"))).",
                "exclamationmark.triangle.fill",
                .red
            )
        }
        return (
            "50/20/30 plan funded",
            "Needs, Wants, and Savings are funded first. Subcategories are optional and can be added later.",
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
                subtitle: "50% parent bucket · subcategories optional",
                systemImage: "house.fill",
                tint: .blue,
                target: needsTarget,
                categories: budget.needsCategories,
                section: .needs,
                onAdd: onAddNeeds
            )
            categorySection(
                title: "Wants",
                subtitle: "20% parent bucket · subcategories optional",
                systemImage: "sparkles",
                tint: .orange,
                target: wantsTarget,
                categories: budget.wantsCategories,
                section: .wants,
                onAdd: onAddWants
            )
            savingsSection

            Text("Needs, Wants, and Savings are funded first using your 50/20/30 targets. Subcategories and savings goals only break those parent buckets down, so you can add detail whenever it becomes useful.")
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
                        Text(unassigned < -0.01 ? "Over planned" : "Parent buckets")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(unassigned < -0.01 ? abs(unassigned) : plannedIncome, format: .currency(code: "USD"))
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
                            Text(unassigned < -0.01
                                 ? "\(totalAssigned.formatted(.currency(code: "USD"))) planned"
                                 : "100% assigned to parent buckets")
                            Spacer()
                            Text("50 / 20 / 30")
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
                target: needsTarget,
                categorized: categorizedNeeds,
                actual: needsSpent,
                tint: .blue
            )
            planTotalCard(
                title: "Wants",
                systemImage: "sparkles",
                target: wantsTarget,
                categorized: categorizedWants,
                actual: wantsSpent,
                tint: .orange
            )
            planTotalCard(
                title: "Savings",
                systemImage: "banknote.fill",
                target: savingsTarget,
                categorized: categorizedSavings,
                actual: savingsLogged,
                tint: .mint
            )
        }
    }

    private func planTotalCard(
        title: String,
        systemImage: String,
        target: Double,
        categorized: Double,
        actual: Double,
        tint: Color
    ) -> some View {
        let effectivePlan = max(target, categorized)
        let remaining = effectivePlan - actual
        let progress = effectivePlan > 0 ? min(max(actual / effectivePlan, 0), 1) : 0
        let uncategorized = max(target - categorized, 0)
        let overTarget = max(categorized - target, 0)

        return GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                    Text(title)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(tint)

                Text(target, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(overTarget > 0.01
                     ? "\(overTarget.formatted(.currency(code: "USD"))) over target"
                     : "\(uncategorized.formatted(.currency(code: "USD"))) uncategorized")
                    .font(.caption2)
                    .foregroundStyle(overTarget > 0.01 ? Color.red : Color.secondary)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)

                if effectivePlan > 0 {
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
        target: Double,
        categories: [Category],
        section: BudgetSection,
        onAdd: @escaping () -> Void
    ) -> some View {
        let categorized = categories.reduce(0) { $0 + allocation(for: $1, section: section) }
        let spent = categories.reduce(0) { $0 + self.spent(for: $1.id, section: section) }
        let uncategorized = max(target - categorized, 0)
        let overTarget = max(categorized - target, 0)

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
                        Text(target, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text("parent target")
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
                    .accessibilityLabel("Add \(title) subcategory")
                }

                HStack(spacing: 8) {
                    Image(systemName: overTarget > 0.01 ? "exclamationmark.triangle.fill" : "tray.fill")
                        .font(.caption)
                        .foregroundStyle(overTarget > 0.01 ? Color.red : tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(overTarget > 0.01 ? "Subcategories exceed bucket" : "Uncategorized")
                            .font(.caption.weight(.semibold))
                        Text(overTarget > 0.01
                             ? "Reduce subcategory plans or increase income."
                             : "This money is still planned for \(title.lowercased()) even without a subcategory.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(overTarget > 0.01 ? overTarget : uncategorized, format: .currency(code: "USD"))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(overTarget > 0.01 ? Color.red : Color.primary)
                }
                .padding(9)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if categories.isEmpty {
                    Text("Subcategories are optional. Leave this as one \(title) bucket or add detail later when you want to track where it goes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    HStack {
                        Text("\(categorized.formatted(.currency(code: "USD"))) categorized")
                        Spacer()
                        Text("\(spent.formatted(.currency(code: "USD"))) spent")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

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
        let categorized = categorizedSavings
        let uncategorized = max(savingsTarget - categorized, 0)
        let overTarget = max(categorized - savingsTarget, 0)
        let effectivePlan = max(savingsTarget, categorized)
        let remaining = effectivePlan - savingsLogged

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
                        Text("30% parent bucket · goals optional")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(savingsTarget, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text("parent target")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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

                HStack(spacing: 8) {
                    Image(systemName: overTarget > 0.01 ? "exclamationmark.triangle.fill" : "tray.fill")
                        .font(.caption)
                        .foregroundStyle(overTarget > 0.01 ? Color.red : Color.mint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(overTarget > 0.01 ? "Goals exceed savings bucket" : "Uncategorized savings")
                            .font(.caption.weight(.semibold))
                        Text(overTarget > 0.01
                             ? "Reduce goal contributions or increase income."
                             : "This amount is still planned as savings even without a specific goal.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(overTarget > 0.01 ? overTarget : uncategorized, format: .currency(code: "USD"))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(overTarget > 0.01 ? Color.red : Color.primary)
                }
                .padding(9)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack {
                    Text("\(categorized.formatted(.currency(code: "USD"))) assigned to goals")
                    Spacer()
                    Text(remaining >= 0
                         ? "\(remaining.formatted(.currency(code: "USD"))) left to save"
                         : "\(abs(remaining).formatted(.currency(code: "USD"))) ahead")
                        .foregroundStyle(remaining >= 0 ? Color.secondary : Color.green)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if budget.savingsGoals.isEmpty {
                    Text("Savings goals are optional. The full parent amount still counts as planned savings; add goals later if you want to split it between emergency fund, travel, investing, or anything else.")
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