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

    // Parent buckets are the source of truth. Subcategories only break a bucket down;
    // they never silently increase the parent plan.
    private var needsTarget: Double { plannedIncome * 0.50 }
    private var wantsTarget: Double { plannedIncome * 0.20 }
    private var savingsTarget: Double { plannedIncome * 0.30 }

    private var categorizedNeeds: Double {
        budget.needsCategories.reduce(0) { $0 + allocation(for: $1, section: .needs) }
    }

    private var categorizedWants: Double {
        budget.wantsCategories.reduce(0) { $0 + allocation(for: $1, section: .wants) }
    }

    private var categorizedSavings: Double {
        budget.savingsGoals.reduce(0) { $0 + max($1.monthlyContribution, 0) }
    }

    private var needsAllocationOverage: Double { max(categorizedNeeds - needsTarget, 0) }
    private var wantsAllocationOverage: Double { max(categorizedWants - wantsTarget, 0) }
    private var savingsAllocationOverage: Double { max(categorizedSavings - savingsTarget, 0) }

    private var totalAllocationOverage: Double {
        needsAllocationOverage + wantsAllocationOverage + savingsAllocationOverage
    }

    private var totalUncategorized: Double {
        max(needsTarget - categorizedNeeds, 0)
        + max(wantsTarget - categorizedWants, 0)
        + max(savingsTarget - categorizedSavings, 0)
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

    private var totalSpentOrSaved: Double {
        needsSpent + wantsSpent + savingsLogged
    }

    private var planStatus: (title: String, message: String, systemImage: String, tint: Color) {
        if plannedIncome <= 0 {
            return (
                "Start with income",
                "Add the income you expect this month so the app can calculate your parent buckets.",
                "dollarsign.circle.fill",
                .orange
            )
        }

        if totalAllocationOverage > 0.01 {
            return (
                "Breakdown needs attention",
                "Your subcategories exceed their parent buckets by \(totalAllocationOverage.formatted(.currency(code: "USD"))). The parent plan itself has not changed.",
                "exclamationmark.triangle.fill",
                .red
            )
        }

        if totalUncategorized > 0.01 {
            return (
                "Plan is funded",
                "All income is assigned to Needs, Wants, and Savings. \(totalUncategorized.formatted(.currency(code: "USD"))) can stay uncategorized until you want more detail.",
                "checkmark.circle.fill",
                .green
            )
        }

        return (
            "Plan is fully categorized",
            "Your parent buckets are funded and every planned dollar has been broken into a subcategory or savings goal.",
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
                subtitle: "50% parent bucket",
                systemImage: "house.fill",
                tint: .blue,
                target: needsTarget,
                actual: needsSpent,
                categories: budget.needsCategories,
                section: .needs,
                onAdd: onAddNeeds
            )

            categorySection(
                title: "Wants",
                subtitle: "20% parent bucket",
                systemImage: "sparkles",
                tint: .orange,
                target: wantsTarget,
                actual: wantsSpent,
                categories: budget.wantsCategories,
                section: .wants,
                onAdd: onAddWants
            )

            savingsSection

            Text("Parent buckets are the monthly plan. Subcategories are optional labels inside those buckets, so leaving money uncategorized does not mean it is unplanned.")
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

                        Text("\(budget.payFrequency.rawValue) · \(incomePerPayPeriod.formatted(.currency(code: "USD"))) per pay period")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                        .frame(height: 46)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(totalAllocationOverage > 0.01 ? "Over allocated" : "Parent plan")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(
                            totalAllocationOverage > 0.01 ? totalAllocationOverage : plannedIncome,
                            format: .currency(code: "USD")
                        )
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(totalAllocationOverage > 0.01 ? Color.red : Color.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if plannedIncome > 0 {
                    VStack(spacing: 5) {
                        ProgressView(value: min(max(totalSpentOrSaved / plannedIncome, 0), 1))
                            .tint(totalSpentOrSaved > plannedIncome ? .red : status.tint)

                        HStack {
                            Text("\(totalSpentOrSaved.formatted(.currency(code: "USD"))) spent / saved")
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
            bucketCard(
                title: "Needs",
                systemImage: "house.fill",
                target: needsTarget,
                categorized: categorizedNeeds,
                actual: needsSpent,
                actionWord: "spent",
                tint: .blue
            )

            bucketCard(
                title: "Wants",
                systemImage: "sparkles",
                target: wantsTarget,
                categorized: categorizedWants,
                actual: wantsSpent,
                actionWord: "spent",
                tint: .orange
            )

            bucketCard(
                title: "Savings",
                systemImage: "banknote.fill",
                target: savingsTarget,
                categorized: categorizedSavings,
                actual: savingsLogged,
                actionWord: "saved",
                tint: .mint
            )
        }
    }

    private func bucketCard(
        title: String,
        systemImage: String,
        target: Double,
        categorized: Double,
        actual: Double,
        actionWord: String,
        tint: Color
    ) -> some View {
        let uncategorized = max(target - categorized, 0)
        let allocationOverage = max(categorized - target, 0)
        let remaining = target - actual
        let progress = target > 0 ? min(max(actual / target, 0), 1) : 0

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

                Text("\(actual.formatted(.currency(code: "USD"))) \(actionWord)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)

                if target > 0 {
                    ProgressView(value: progress)
                        .tint(remaining >= 0 ? tint : .red)
                }

                if allocationOverage > 0.01 {
                    Text("\(allocationOverage.formatted(.currency(code: "USD"))) over-allocated")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                } else if uncategorized > 0.01 {
                    Text("\(uncategorized.formatted(.currency(code: "USD"))) uncategorized")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                } else {
                    Text("Fully categorized")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
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
        actual: Double,
        categories: [Category],
        section: BudgetSection,
        onAdd: @escaping () -> Void
    ) -> some View {
        let categorized = categories.reduce(0) { $0 + allocation(for: $1, section: section) }
        let uncategorized = max(target - categorized, 0)
        let allocationOverage = max(categorized - target, 0)
        let remainingToSpend = target - actual

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
                        Text(remainingToSpend >= 0 ? "\(remainingToSpend.formatted(.currency(code: "USD"))) left" : "\(abs(remainingToSpend).formatted(.currency(code: "USD"))) over")
                            .font(.caption2)
                            .foregroundStyle(remainingToSpend >= 0 ? Color.secondary : Color.red)
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

                allocationSummary(
                    title: title,
                    target: target,
                    categorized: categorized,
                    tint: tint,
                    noun: "subcategory"
                )

                if categories.isEmpty {
                    Text("No subcategories yet. That is okay — the full \(title) parent bucket is still part of your plan. Add subcategories only when you want more detail.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(categories) { category in
                        Divider()
                        categoryRow(category, section: section, tint: tint)
                    }
                }

                if allocationOverage <= 0.01 && uncategorized <= 0.01 && !categories.isEmpty {
                    Label("Every planned \(title.lowercased()) dollar is categorized.", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func allocationSummary(
        title: String,
        target: Double,
        categorized: Double,
        tint: Color,
        noun: String
    ) -> some View {
        let uncategorized = max(target - categorized, 0)
        let allocationOverage = max(categorized - target, 0)
        let categoryProgress = target > 0 ? min(max(categorized / target, 0), 1) : 0

        return VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: allocationOverage > 0.01 ? "exclamationmark.triangle.fill" : "tray.fill")
                    .font(.caption)
                    .foregroundStyle(allocationOverage > 0.01 ? Color.red : tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(allocationOverage > 0.01 ? "Over-allocated" : "Uncategorized")
                        .font(.caption.weight(.semibold))
                    Text(allocationOverage > 0.01
                         ? "Your \(noun)s total more than the \(title) parent bucket."
                         : "This stays inside \(title) until you decide to split it further.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(allocationOverage > 0.01 ? allocationOverage : uncategorized, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(allocationOverage > 0.01 ? Color.red : Color.primary)
            }

            if target > 0 {
                ProgressView(value: categoryProgress)
                    .tint(allocationOverage > 0.01 ? .red : tint)
            }

            HStack {
                Text("\(categorized.formatted(.currency(code: "USD"))) categorized")
                Spacer()
                Text("\(target.formatted(.currency(code: "USD"))) bucket")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        let remainingToSave = savingsTarget - savingsLogged

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
                        Text("30% parent bucket")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(savingsTarget, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text(remainingToSave >= 0 ? "\(remainingToSave.formatted(.currency(code: "USD"))) left" : "\(abs(remainingToSave).formatted(.currency(code: "USD"))) ahead")
                            .font(.caption2)
                            .foregroundStyle(remainingToSave >= 0 ? Color.secondary : Color.green)
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

                allocationSummary(
                    title: "Savings",
                    target: savingsTarget,
                    categorized: categorized,
                    tint: .mint,
                    noun: "goal"
                )

                if budget.savingsGoals.isEmpty {
                    Text("No savings goals yet. The full savings target is still planned. Add goals later if you want to split it between emergency fund, travel, investing, or anything else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(budget.savingsGoals) { goal in
                        Divider()
                        savingsGoalRow(goal)
                    }
                }
            }
        }
    }

    private func savingsGoalRow(_ goal: SavingsGoal) -> some View {
        let saved = savedThisMonth(for: goal.id)
        let planned = max(goal.monthlyContribution, 0)
        let remaining = planned - saved
        let progress = planned > 0 ? min(max(saved / planned, 0), 1) : 0

        return VStack(alignment: .leading, spacing: 7) {
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

                Text(planned, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }

            HStack {
                Text("Saved \(saved.formatted(.currency(code: "USD")))")
                Spacer()
                Text(remaining >= 0
                     ? "Left \(remaining.formatted(.currency(code: "USD")))"
                     : "Ahead \(abs(remaining).formatted(.currency(code: "USD")))")
                    .fontWeight(.semibold)
                    .foregroundStyle(remaining >= 0 ? Color.secondary : Color.green)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if planned > 0 {
                ProgressView(value: progress)
                    .tint(.mint)
            }
        }
        .padding(.vertical, 2)
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
