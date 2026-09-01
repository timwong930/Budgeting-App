from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new)


# Models.swift: remember Plaid category edits and make month carry-forward deterministic.
models_path = Path("Budgeting App/Models.swift")
models = models_path.read_text()

old_update_expense = '''    func updateExpense(_ updatedExpense: Expense) {
        guard let index = expenses.firstIndex(where: { $0.id == updatedExpense.id }) else { return }
        let previousExpense = expenses[index]
        applyBalanceImpact(for: previousExpense, multiplier: -1)
        let resolved = resolvingAccountReferences(for: updatedExpense)
        expenses[index] = resolved
        applyBalanceImpact(for: resolved, multiplier: 1)
    }'''
new_update_expense = '''    func updateExpense(_ updatedExpense: Expense) {
        guard let index = expenses.firstIndex(where: { $0.id == updatedExpense.id }) else { return }
        let previousExpense = expenses[index]
        applyBalanceImpact(for: previousExpense, multiplier: -1)
        let resolved = resolvingAccountReferences(for: updatedExpense)
        expenses[index] = resolved
        rememberPersistentCategoryRule(for: resolved, aliases: [previousExpense.name])
        applyBalanceImpact(for: resolved, multiplier: 1)
    }'''
models = replace_once(models, old_update_expense, new_update_expense, "updateExpense")

old_month = '''    func applyMonthlyAllocations(for date: Date) {
        let key = Self.monthKey(for: date)
        let previousKey = Self.monthKey(for: Calendar.current.date(byAdding: .month, value: -1, to: date) ?? date)

        if incomeByMonth[key] == nil {
            incomeByMonth[key] = incomeByMonth[previousKey] ?? income
        }

        var needsMonth = needsAllocationsByMonth[key] ?? [:]
        for index in needsCategories.indices {
            let id = needsCategories[index].id
            let value = needsMonth[id]
                ?? needsAllocationsByMonth[previousKey]?[id]
                ?? needsCategories[index].allocatedAmount
            needsMonth[id] = value
            needsCategories[index].allocatedAmount = value
        }
        needsAllocationsByMonth[key] = needsMonth

        var wantsMonth = wantsAllocationsByMonth[key] ?? [:]
        for index in wantsCategories.indices {
            let id = wantsCategories[index].id
            let value = wantsMonth[id]
                ?? wantsAllocationsByMonth[previousKey]?[id]
                ?? wantsCategories[index].allocatedAmount
            wantsMonth[id] = value
            wantsCategories[index].allocatedAmount = value
        }
        wantsAllocationsByMonth[key] = wantsMonth
    }

    func setAllocation(_ amount: Double, for categoryId: UUID, section: BudgetSection, date: Date) {
        let key = Self.monthKey(for: date)
        switch section {
        case .needs:
            var month = needsAllocationsByMonth[key] ?? [:]
            month[categoryId] = amount
            needsAllocationsByMonth[key] = month
        case .wants:
            var month = wantsAllocationsByMonth[key] ?? [:]
            month[categoryId] = amount
            wantsAllocationsByMonth[key] = month
        }
    }'''
new_month = '''    func applyMonthlyAllocations(for date: Date) {
        let key = Self.monthKey(for: date)

        if incomeByMonth[key] == nil {
            incomeByMonth[key] = latestPriorIncome(before: key) ?? income
        }

        var needsMonth = needsAllocationsByMonth[key] ?? [:]
        for index in needsCategories.indices {
            let id = needsCategories[index].id
            let value = needsMonth[id]
                ?? latestPriorAllocation(in: needsAllocationsByMonth, before: key, categoryId: id)
                ?? needsCategories[index].allocatedAmount
            needsMonth[id] = value
            needsCategories[index].allocatedAmount = value
        }
        needsAllocationsByMonth[key] = needsMonth

        var wantsMonth = wantsAllocationsByMonth[key] ?? [:]
        for index in wantsCategories.indices {
            let id = wantsCategories[index].id
            let value = wantsMonth[id]
                ?? latestPriorAllocation(in: wantsAllocationsByMonth, before: key, categoryId: id)
                ?? wantsCategories[index].allocatedAmount
            wantsMonth[id] = value
            wantsCategories[index].allocatedAmount = value
        }
        wantsAllocationsByMonth[key] = wantsMonth
    }

    private func latestPriorIncome(before monthKey: String) -> Double? {
        for key in incomeByMonth.keys.filter({ $0 < monthKey }).sorted(by: >) {
            if let value = incomeByMonth[key] { return value }
        }
        return nil
    }

    private func latestPriorAllocation(
        in allocations: [String: [UUID: Double]],
        before monthKey: String,
        categoryId: UUID
    ) -> Double? {
        for key in allocations.keys.filter({ $0 < monthKey }).sorted(by: >) {
            if let value = allocations[key]?[categoryId] { return value }
        }
        return nil
    }

    func setAllocation(_ amount: Double, for categoryId: UUID, section: BudgetSection, date: Date) {
        let key = Self.monthKey(for: date)
        switch section {
        case .needs:
            var month = needsAllocationsByMonth[key] ?? [:]
            month[categoryId] = amount
            needsAllocationsByMonth[key] = month
            if let index = needsCategories.firstIndex(where: { $0.id == categoryId }) {
                needsCategories[index].allocatedAmount = amount
            }
        case .wants:
            var month = wantsAllocationsByMonth[key] ?? [:]
            month[categoryId] = amount
            wantsAllocationsByMonth[key] = month
            if let index = wantsCategories.firstIndex(where: { $0.id == categoryId }) {
                wantsCategories[index].allocatedAmount = amount
            }
        }
    }'''
models = replace_once(models, old_month, new_month, "monthly allocation carry-forward")
models_path.write_text(models)


# Plaid reconciliation: apply learned merchant category rules to future transactions.
plaid_path = Path("Budgeting App/PlaidTransactionReconciliation.swift")
plaid = plaid_path.read_text()
old_mapped = '        let mapped = mappedReconciliationCategory(for: transaction.category)'
new_mapped = '        let mapped = persistentCategoryAssignment(for: transaction) ?? mappedReconciliationCategory(for: transaction.category)'
count = plaid.count(old_mapped)
if count != 2:
    raise SystemExit(f"Plaid mapped category: expected 2 matches, found {count}")
plaid = plaid.replace(old_mapped, new_mapped)
old_review = '''        if transaction.category == nil {
            let added = upsertPlaidReviewItem('''
new_review = '''        if transaction.category == nil && persistentCategoryAssignment(for: transaction) == nil {
            let added = upsertPlaidReviewItem('''
plaid = replace_once(plaid, old_review, new_review, "uncategorized Plaid review guard")
plaid_path.write_text(plaid)


# Account ledgers: make every row tappable and route to the existing transaction editors.
ledger_path = Path("Budgeting App/AccountTransactionLedger.swift")
ledger = ledger_path.read_text()
ledger = replace_once(
    ledger,
    '''struct BankAccountLedgerView: View {
    @Binding var account: BankAccount
    @ObservedObject var budget: BudgetModel
''',
    '''struct BankAccountLedgerView: View {
    @Binding var account: BankAccount
    @ObservedObject var budget: BudgetModel
    @State private var editingEntry: AccountLedgerEntry?
''',
    "bank ledger edit state"
)
ledger = replace_once(
    ledger,
    '''struct CreditAccountLedgerView: View {
    @Binding var account: CreditAccount
    @ObservedObject var budget: BudgetModel
''',
    '''struct CreditAccountLedgerView: View {
    @Binding var account: CreditAccount
    @ObservedObject var budget: BudgetModel
    @State private var editingEntry: AccountLedgerEntry?
''',
    "credit ledger edit state"
)

section_call = '            AccountLedgerSection(entries: entries)'
if ledger.count(section_call) != 2:
    raise SystemExit(f"ledger section calls: expected 2 matches, found {ledger.count(section_call)}")
ledger = ledger.replace(section_call, '            AccountLedgerSection(entries: entries, onEdit: { editingEntry = $0 })')

nav_anchor = '''        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {'''
nav_replacement = '''        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingEntry) { entry in
            AccountLedgerTransactionEditor(entry: entry, budget: budget)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .toolbar {'''
if ledger.count(nav_anchor) != 2:
    raise SystemExit(f"ledger sheet anchors: expected 2 matches, found {ledger.count(nav_anchor)}")
ledger = ledger.replace(nav_anchor, nav_replacement)

old_detail = '''    private func ledgerExpenseDetail(_ expense: Expense) -> String {
        let note = expense.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty, note != "Plaid pending transaction" {
            return note
        }
        return expense.section.title
    }'''
new_detail = '''    private func ledgerExpenseDetail(_ expense: Expense) -> String {
        let category = categoryName(for: expense)
        let categoryLabel = "\\(expense.section.title) • \\(category)"
        let note = expense.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty, note != "Plaid pending transaction" {
            return "\\(categoryLabel) • \\(note)"
        }
        return categoryLabel
    }'''
ledger = replace_once(ledger, old_detail, new_detail, "ledger category detail")

old_section = '''private struct AccountLedgerSection: View {
    let entries: [AccountLedgerEntry]

    var body: some View {
        Section("Transactions") {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Activity linked to this account will appear here.")
                )
            } else {
                ForEach(entries) { entry in
                    AccountLedgerRow(entry: entry)
                }
            }
        }
    }
}
'''
new_section = '''private struct AccountLedgerTransactionEditor: View {
    let entry: AccountLedgerEntry
    @ObservedObject var budget: BudgetModel

    private var parts: [Substring] { entry.id.split(separator: "|") }
    private var sourceKind: String? { parts.first.map(String.init) }
    private var sourceId: UUID? {
        guard parts.count > 1 else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    @ViewBuilder
    var body: some View {
        if let sourceId {
            switch sourceKind {
            case "expense", "purchase", "payment":
                if let expense = budget.expenses.first(where: { $0.id == sourceId }) {
                    EditExpenseView(budget: budget, expense: expense)
                } else {
                    missingTransaction
                }
            case "income", "refund":
                if let income = budget.incomes.first(where: { $0.id == sourceId }) {
                    EditIncomeView(budget: budget, income: income)
                } else {
                    missingTransaction
                }
            case "transfer", "card-transfer":
                if let transfer = budget.cashTransfers.first(where: { $0.id == sourceId }) {
                    CashTransferEditorView(
                        budget: budget,
                        selectedDate: transfer.date,
                        existingTransfer: transfer
                    )
                } else {
                    missingTransaction
                }
            default:
                missingTransaction
            }
        } else {
            missingTransaction
        }
    }

    private var missingTransaction: some View {
        ContentUnavailableView(
            "Transaction Unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("This transaction changed during sync. Close this sheet and open it again.")
        )
    }
}

private struct AccountLedgerSection: View {
    let entries: [AccountLedgerEntry]
    let onEdit: (AccountLedgerEntry) -> Void

    var body: some View {
        Section("Transactions") {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Activity linked to this account will appear here.")
                )
            } else {
                ForEach(entries) { entry in
                    Button {
                        onEdit(entry)
                    } label: {
                        AccountLedgerRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens transaction editing")
                }
            }
        }
    }
}
'''
ledger = replace_once(ledger, old_section, new_section, "editable ledger section")

old_amount = '''            Text(entry.signedAmount, format: .currency(code: "USD").sign(strategy: .always()))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(entry.signedAmount > 0 ? .green : .primary)
        }'''
new_amount = '''            Text(entry.signedAmount, format: .currency(code: "USD").sign(strategy: .always()))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(entry.signedAmount > 0 ? .green : .primary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }'''
ledger = replace_once(ledger, old_amount, new_amount, "ledger edit chevron")
ledger_path.write_text(ledger)


# Plan submenu: replace redundant summary blocks with one actionable monthly workspace.
content_path = Path("Budgeting App/ContentView.swift")
content = content_path.read_text()
old_plan = '''    private var budgetPlanSubmenu: some View {
        budgetSubmenuPage(title: "Plan", subtitle: "Budget setup and monthly targets.", systemImage: "slider.horizontal.3") {
            planHighlightsSection
            overviewSection
            incomeSection
            if budget.income > 0 && budget.needsCategories.isEmpty && budget.wantsCategories.isEmpty && budget.savingsGoals.isEmpty {
                nextStepSection
            }
            budgetBreakdownSection
            needsSection
            wantsSection
            savingsSection
        }
        .onAppear {
            planHighlightsExpanded = true
            overviewExpanded = true
            incomeExpanded = true
            budgetBreakdownExpanded = true
        }
    }'''
new_plan = '''    private var budgetPlanSubmenu: some View {
        budgetSubmenuPage(title: "Plan", subtitle: "Assign this month's income before you spend it.", systemImage: "slider.horizontal.3") {
            MonthlyPlanWorkspaceView(
                budget: budget,
                selectedMonth: $selectedMonth,
                onAddNeeds: { showingAddNeedsCategory = true },
                onAddWants: { showingAddWantsCategory = true },
                onAddSavings: { showingAddSavingsGoal = true },
                onEditCategory: { editingCategory = $0 },
                onEditSavingsGoal: { editingSavingsGoal = $0 }
            )
            if budget.income > 0 && budget.needsCategories.isEmpty && budget.wantsCategories.isEmpty && budget.savingsGoals.isEmpty {
                nextStepSection
            }
            incomeSection
            needsSection
            wantsSection
            savingsSection
        }
        .onAppear {
            incomeExpanded = true
            needsExpanded = true
            wantsExpanded = true
            savingsExpanded = true
            budget.applyMonthlyAllocations(for: selectedMonth)
        }
    }'''
content = replace_once(content, old_plan, new_plan, "Plan submenu workspace")
content_path.write_text(content)
