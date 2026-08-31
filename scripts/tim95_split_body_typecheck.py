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
'''    var body: some View {\n        NavigationStack {\n            activeTabContent\n''',
'''    var body: some View {\n        presentedContent\n    }\n\n    private var tabChromeContent: some View {\n        activeTabContent\n''',
"body root",
)

replace_once(
'''                .padding(.trailing, isTabBarMinimized ? 12 : 0)\n                .padding(.bottom, -16)\n            }\n            .onAppear {\n''',
'''                .padding(.trailing, isTabBarMinimized ? 12 : 0)\n                .padding(.bottom, -16)\n            }\n    }\n\n    private var lifecycleTabContent: some View {\n        tabChromeContent\n            .onAppear {\n''',
"chrome lifecycle split",
)

replace_once(
'''            .onChange(of: budget.income) { _, newValue in\n                budget.setIncome(newValue, for: selectedMonth)\n            }\n            .onChange(of: budget.expenses) { _, _ in\n''',
'''            .onChange(of: budget.income) { _, newValue in\n                budget.setIncome(newValue, for: selectedMonth)\n            }\n    }\n\n    private var observedTabContent: some View {\n        lifecycleTabContent\n            .onChange(of: budget.expenses) { _, _ in\n''',
"lifecycle observation split",
)

replace_once(
'''            .overlay(alignment: .top) {\n                InAppNotificationOverlay()\n            }\n        }\n        .sheet(isPresented: $showingAddNeedsCategory) {\n''',
'''            .overlay(alignment: .top) {\n                InAppNotificationOverlay()\n            }\n    }\n\n    private var presentedContent: some View {\n        NavigationStack {\n            observedTabContent\n        }\n        .sheet(isPresented: $showingAddNeedsCategory) {\n''',
"observer presentation split",
)

path.write_text(text)
