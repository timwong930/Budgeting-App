from pathlib import Path

path = Path("Budgeting App/ContentView.swift")
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    text = text.replace(old, new, 1)

replace_once(
'''    private var observedTabContent: some View {\n        lifecycleTabContent\n''',
'''    private var financialObservedTabContent: some View {\n        lifecycleTabContent\n''',
"rename financial observer stage",
)

replace_once(
'''            .onChange(of: budget.recurringPayments) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: calendarMonthAnchor) { _, _ in\n''',
'''            .onChange(of: budget.recurringPayments) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n    }\n\n    private var observedTabContent: some View {\n        financialObservedTabContent\n            .onChange(of: calendarMonthAnchor) { _, _ in\n''',
"split financial and calendar observers",
)

replace_once(
'''    private var presentedContent: some View {\n        NavigationStack {\n            observedTabContent\n        }\n''',
'''    private var setupPresentedContent: some View {\n        NavigationStack {\n            observedTabContent\n        }\n''',
"rename first presentation stage",
)

replace_once(
'''        .sheet(item: $editingSavingsGoal) { goal in\n            EditSavingsGoalView(budget: budget, savingsGoal: goal)\n                .presentationDetents([.medium])\n                .presentationDragIndicator(.visible)\n        }\n        .sheet(item: $expenseDraft) { draft in\n''',
'''        .sheet(item: $editingSavingsGoal) { goal in\n            EditSavingsGoalView(budget: budget, savingsGoal: goal)\n                .presentationDetents([.medium])\n                .presentationDragIndicator(.visible)\n        }\n    }\n\n    private var transactionPresentedContent: some View {\n        setupPresentedContent\n        .sheet(item: $expenseDraft) { draft in\n''',
"split setup and transaction sheets",
)

replace_once(
'''        .sheet(item: $editingIncome) { income in\n            EditIncomeView(budget: budget, income: income)\n                .presentationDetents([.medium])\n                .presentationDragIndicator(.visible)\n        }\n        .sheet(isPresented: $showingAddCashTransfer) {\n''',
'''        .sheet(item: $editingIncome) { income in\n            EditIncomeView(budget: budget, income: income)\n                .presentationDetents([.medium])\n                .presentationDragIndicator(.visible)\n        }\n    }\n\n    private var presentedContent: some View {\n        transactionPresentedContent\n        .sheet(isPresented: $showingAddCashTransfer) {\n''',
"split transaction and calendar sheets",
)

path.write_text(text)
