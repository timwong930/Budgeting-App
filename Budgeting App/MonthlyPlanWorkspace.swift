import SwiftUI

struct MonthlyPlanWorkspaceView: View {
    @ObservedObject var budget: BudgetModel
    @Binding var selectedMonth: Date

    let onAddNeeds: () -> Void
    let onAddWants: () -> Void
    let onAddSavings: () -> Void
    let onEditCategory: (Category) -> Void
    let onEditSavingsGoal: (SavingsGoal) -> Void

    private enum PlanBucket: String, Hashable {
        case needs
        case wants
        case savings
    }

    @State private var expandedBuckets: Set<PlanBucket> = []

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

    // Parent buckets are the source of truth. Categories only divide them further.
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

    private var planStatus: (title: String, message: String, systemImage: String, tint: Color) {
        if plannedIncome <= 0 {
            return (
                "Add monthly income",
                "Your plan will fill automatically once income is set.",
                "dollarsign.circle.fill",
                .orange
            )
        }

        if totalAllocationOverage > 0.01 {
            return (
                "Breakdown needs attention",
                "Categories are \(totalAllocationOverage.formatted(.currency(code: "USD"))) over their parent buckets.",
                "exclamationmark.triangle.fill",
                .red
            )
        }

        if totalUncategorized > 0.01 {
            return (
                "Monthly plan ready",
                "Everything is funded. Categorize the rest only when it is useful.",
                "checkmark.circle.fill",
                .green
            )
        }

        return (
            "Monthly plan ready",
            "Everything is funded and fully categorized.",
            "checkmark.circle.fill",
            .green
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            planHeader
            planBuckets
        }
        .onAppear {
            ensureMonthlyPlan(for: selectedMonth)
        }
        .onChange(of: selectedMonth) { _, month in
            ensureMonthlyPlan(for: month)
        }
    }

    private var planHeader: some View {
        let status = planStatus

        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    monthButton(systemImage: "chevron.left", label: "Previous month") {
                        shiftMonth(-1)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(selectedMonth, format: .dateTime.month(.wide).year())
                            .font(.headline)
                        Text("Monthly plan")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    monthButton(systemImage: "chevron.right", label: "Next month") {
                        shiftMonth(1)
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Expected income")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 3) {
                            Text("$")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField(
                                "0",
                                value: incomeBinding,
                                format: .number.precision(.fractionLength(0...2))
                            )
                            .keyboardType(.decimalPad)
                            .font(.title3.weight(.bold).monospacedDigit())
                        }

                        Text("\(budget.payFrequency.rawValue) · \(incomePerPayPeriod.formatted(.currency(code: "USD"))) / paycheck")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Rule")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("50 · 20 · 30")
                            .font(.headline.monospacedDigit())
                        Text("Needs · Wants · Save")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 9) {
                    Image(systemName: status.systemImage)
                        .foregroundStyle(status.tint)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.title)
                            .font(.caption.weight(.semibold))
                        Text(status.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func monthButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var planBuckets: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                bucketSection(
                    bucket: .needs,
                    title: "Needs",
                    percent: "50%",
                    systemImage: "house.fill",
                    tint: .blue,
                    target: needsTarget,
                    categorized: categorizedNeeds,
                    actual: needsSpent,
                    actionWord: "spent",
                    categories: budget.needsCategories,
                    section: .needs,
                    onAdd: onAddNeeds
                )

                Divider().padding(.leading, 52)

                bucketSection(
                    bucket: .wants,
                    title: "Wants",
                    percent: "20%",
                    systemImage: "sparkles",
                    tint: .orange,
                    target: wantsTarget,
                    categorized: categorizedWants,
                    actual: wantsSpent,
                    actionWord: "spent",
                    categories: budget.wantsCategories,
                    section: .wants,
                    onAdd: onAddWants
                )

                Divider().padding(.leading, 52)

                savingsBucketSection
            }
        }
    }

    private func bucketSection(
        bucket: PlanBucket,
        title: String,
        percent: String,
        systemImage: String,
        tint: Color,
        target: Double,
        categorized: Double,
        actual: Double,
        actionWord: String,
        categories: [Category],
        section: BudgetSection,
        onAdd: @escaping () -> Void
    ) -> some View {
        let isExpanded = expandedBuckets.contains(bucket)

        return VStack(spacing: 0) {
            bucketSummaryRow(
                bucket: bucket,
                title: title,
                percent: percent,
                systemImage: systemImage,
                tint: tint,
                target: target,
                categorized: categorized,
                actual: actual,
                actionWord: actionWord
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    allocationStrip(
                        title: title,
                        target: target,
                        categorized: categorized,
                        tint: tint,
                        noun: "categories"
                    )

                    if categories.isEmpty {
                        emptyBreakdown(
                            title: "No subcategories yet",
                            message: "The full \(title) amount is already planned. Add detail only when you want it."
                        )
                    } else {
                        ForEach(categories) { category in
                            categoryRow(category, section: section, tint: tint)
                        }
                    }

                    Button(action: onAdd) {
                        Label("Add \(title) subcategory", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tint)
                    .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var savingsBucketSection: some View {
        let bucket = PlanBucket.savings
        let isExpanded = expandedBuckets.contains(bucket)

        return VStack(spacing: 0) {
            bucketSummaryRow(
                bucket: bucket,
                title: "Savings",
                percent: "30%",
                systemImage: "banknote.fill",
                tint: .mint,
                target: savingsTarget,
                categorized: categorizedSavings,
                actual: savingsLogged,
                actionWord: "saved"
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    allocationStrip(
                        title: "Savings",
                        target: savingsTarget,
                        categorized: categorizedSavings,
                        tint: .mint,
                        noun: "goals"
                    )

                    if budget.savingsGoals.isEmpty {
                        emptyBreakdown(
                            title: "No savings goals yet",
                            message: "Your savings target is already planned. Add goals later to split it up."
                        )
                    } else {
                        ForEach(budget.savingsGoals) { goal in
                            savingsGoalRow(goal)
                        }
                    }

                    Button(action: onAddSavings) {
                        Label("Add savings goal", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.mint)
                    .background(Color.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func bucketSummaryRow(
        bucket: PlanBucket,
        title: String,
        percent: String,
        systemImage: String,
        tint: Color,
        target: Double,
        categorized: Double,
        actual: Double,
        actionWord: String
    ) -> some View {
        let isExpanded = expandedBuckets.contains(bucket)
        let remaining = target - actual
        let uncategorized = max(target - categorized, 0)
        let allocationOverage = max(categorized - target, 0)
        let progress = target > 0 ? min(max(actual / target, 0), 1) : 0

        return Button {
            toggle(bucket)
        } label: {
            VStack(spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(percent)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tint.opacity(0.10), in: Capsule())
                        }

                        Text(bucketDetailText(
                            uncategorized: uncategorized,
                            allocationOverage: allocationOverage,
                            remaining: remaining
                        ))
                        .font(.caption2)
                        .foregroundStyle(allocationOverage > 0.01 || remaining < 0 ? Color.red : Color.secondary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(target, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("\(actual.formatted(.currency(code: "USD"))) \(actionWord)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }

                if target > 0 {
                    ProgressView(value: progress)
                        .tint(remaining >= 0 ? tint : .red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(target.formatted(.currency(code: "USD"))) planned")
        .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")
    }

    private func bucketDetailText(
        uncategorized: Double,
        allocationOverage: Double,
        remaining: Double
    ) -> String {
        if allocationOverage > 0.01 {
            return "\(allocationOverage.formatted(.currency(code: "USD"))) over-allocated"
        }
        if remaining < -0.01 {
            return "\(abs(remaining).formatted(.currency(code: "USD"))) over budget"
        }
        if uncategorized > 0.01 {
            return "\(uncategorized.formatted(.currency(code: "USD"))) uncategorized"
        }
        return "Fully categorized"
    }

    private func allocationStrip(
        title: String,
        target: Double,
        categorized: Double,
        tint: Color,
        noun: String
    ) -> some View {
        let uncategorized = max(target - categorized, 0)
        let overage = max(categorized - target, 0)
        let progress = target > 0 ? min(max(categorized / target, 0), 1) : 0

        return VStack(spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(overage > 0.01 ? "Over-allocated" : "Breakdown")
                        .font(.caption.weight(.semibold))
                    Text(overage > 0.01
                         ? "Your \(noun) exceed the \(title) bucket."
                         : "\(categorized.formatted(.currency(code: "USD"))) categorized · \(uncategorized.formatted(.currency(code: "USD"))) open")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if overage > 0.01 {
                    Text(overage, format: .currency(code: "USD"))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.red)
                }
            }

            if target > 0 {
                ProgressView(value: progress)
                    .tint(overage > 0.01 ? .red : tint)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func emptyBreakdown(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func categoryRow(_ category: Category, section: BudgetSection, tint: Color) -> some View {
        let planned = allocation(for: category, section: section)
        let spent = spent(for: category.id, section: section)
        let remaining = planned - spent
        let progress = planned > 0 ? min(max(spent / planned, 0), 1) : 0

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    onEditCategory(category)
                } label: {
                    Text(category.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                TextField(
                    "0",
                    value: allocationBinding(for: category, section: section),
                    format: .currency(code: "USD")
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 105)
            }

            HStack {
                Text("\(spent.formatted(.currency(code: "USD"))) spent")
                Spacer()
                Text(remaining >= 0
                     ? "\(remaining.formatted(.currency(code: "USD"))) left"
                     : "\(abs(remaining).formatted(.currency(code: "USD"))) over")
                    .foregroundStyle(remaining >= 0 ? Color.secondary : Color.red)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if planned > 0 {
                ProgressView(value: progress)
                    .tint(remaining >= 0 ? tint : .red)
            }
        }
        .padding(.vertical, 5)
    }

    private func savingsGoalRow(_ goal: SavingsGoal) -> some View {
        let saved = savedThisMonth(for: goal.id)
        let planned = max(goal.monthlyContribution, 0)
        let remaining = planned - saved
        let progress = planned > 0 ? min(max(saved / planned, 0), 1) : 0

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    onEditSavingsGoal(goal)
                } label: {
                    Text(goal.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Text(planned, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }

            HStack {
                Text("\(saved.formatted(.currency(code: "USD"))) saved")
                Spacer()
                Text(remaining >= 0
                     ? "\(remaining.formatted(.currency(code: "USD"))) left"
                     : "\(abs(remaining).formatted(.currency(code: "USD"))) ahead")
                    .foregroundStyle(remaining >= 0 ? Color.secondary : Color.green)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if planned > 0 {
                ProgressView(value: progress)
                    .tint(.mint)
            }
        }
        .padding(.vertical, 5)
    }

    private func toggle(_ bucket: PlanBucket) {
        withAnimation(.snappy) {
            if expandedBuckets.contains(bucket) {
                expandedBuckets.remove(bucket)
            } else {
                expandedBuckets.insert(bucket)
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
