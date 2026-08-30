from pathlib import Path

path = Path("Budgeting App/ContentView.swift")
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    "    private enum CalendarViewMode: String, CaseIterable, Identifiable {",
    "    private enum CalendarViewMode: String, CaseIterable, Identifiable, Equatable {",
    "calendar view equatable",
)

replace_once(
    '''    private var calendarActionDate: Date {\n        calendarViewMode == .month ? visibleCalendarMonth : calendarFocusDate\n    }\n''',
    '''    private var calendarActionDate: Date {\n        if calendarViewMode != .month { return calendarFocusDate }\n        if Calendar.current.isDate(visibleCalendarMonth, equalTo: Date(), toGranularity: .month) {\n            return Date()\n        }\n        return visibleCalendarMonth\n    }\n''',
    "calendar action date",
)

header_filter_start = '''\n                        Menu {\n                            Toggle("Spending & bills", isOn: $calendarShowExpenses)\n                            Toggle("Income", isOn: $calendarShowIncome)\n                            Toggle("Transfers", isOn: $calendarShowTransfers)\n                            Toggle("Credit card due dates", isOn: $calendarShowCreditDue)\n                            Toggle("Portfolio activity", isOn: $calendarShowPortfolio)\n                            Divider()\n                            Button("Show everything") {\n                                calendarShowExpenses = true\n                                calendarShowIncome = true\n                                calendarShowTransfers = true\n                                calendarShowCreditDue = true\n                                calendarShowPortfolio = true\n                            }\n                            Button("Reset recommended filters") {\n                                calendarShowExpenses = true\n                                calendarShowIncome = true\n                                calendarShowTransfers = true\n                                calendarShowCreditDue = true\n                                calendarShowPortfolio = false\n                            }\n                        } label: {\n                            Image(systemName: "line.3.horizontal.decrease.circle")\n                                .font(.headline)\n                                .foregroundStyle(.primary)\n                                .frame(width: 36, height: 36)\n                                .background(.thinMaterial, in: Circle())\n                        }\n                        .accessibilityLabel("Calendar Filters")\n'''
replace_once(header_filter_start, "", "duplicate header filter")

transfer_block = '''                        Button {\n                            showingAddCashTransfer = true\n                        } label: {\n                            Image(systemName: "arrow.left.arrow.right")\n                                .font(.headline)\n                                .foregroundStyle(.primary)\n                                .frame(width: 36, height: 36)\n                                .background(.thinMaterial, in: Circle())\n                        }\n                        .buttonStyle(.plain)\n                        .accessibilityLabel("Transfer Cash")\n'''
credit_block = transfer_block + '''\n                        Button {\n                            showingCreditAccounts = true\n                        } label: {\n                            Image(systemName: "creditcard")\n                                .font(.headline)\n                                .foregroundStyle(.primary)\n                                .frame(width: 36, height: 36)\n                                .background(.thinMaterial, in: Circle())\n                        }\n                        .buttonStyle(.plain)\n                        .accessibilityLabel("Credit Cards")\n'''
replace_once(transfer_block, credit_block, "restore credit card shortcut")

path.write_text(text)
