from pathlib import Path

path = Path("Budgeting App/ContentView.swift")
text = path.read_text()


def replace_once(old: str, new: str, label: str):
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 match, found {count}")
    text = text.replace(old, new, 1)

replace_once(
'''    @State private var calendarEventCache: [Date: [CalendarEventItem]] = [:]\n    @State private var selectedPortfolioTransaction: PortfolioTransaction?\n''',
'''    @State private var calendarEventCache: [Date: [CalendarEventItem]] = [:]\n    @State private var calendarCacheRefreshTask: Task<Void, Never>?\n    @State private var selectedPortfolioTransaction: PortfolioTransaction?\n''',
"cache task state"
)

replace_once(
'''            .onDisappear {\n                stopHoldingsAutoRefreshLoop()\n                stopWatchlistAlertLoop()\n            }\n''',
'''            .onDisappear {\n                stopHoldingsAutoRefreshLoop()\n                stopWatchlistAlertLoop()\n                calendarCacheRefreshTask?.cancel()\n            }\n''',
"on disappear cache cancellation"
)

replace_once(
'''            .onChange(of: budget.expenses) { _, _ in\n                updateMonthlyData()\n                rebuildCalendarEventCache()\n            }\n            .onChange(of: budget.incomes) { _, _ in\n                updateMonthlyData()\n                rebuildCalendarEventCache()\n            }\n            .onChange(of: budget.savingsEntries) { _, _ in\n                updateMonthlyData()\n            }\n            .onChange(of: budget.creditAccounts) { _, _ in\n                rebuildCalendarEventCache()\n            }\n            .onChange(of: budget.portfolioTransactions) { _, _ in\n                rebuildCalendarEventCache()\n            }\n            .onChange(of: budget.cashTransfers) { _, _ in\n                rebuildCalendarEventCache()\n            }\n            .onChange(of: budget.recurringPayments) { _, _ in\n                rebuildCalendarEventCache()\n            }\n''',
'''            .onChange(of: budget.expenses) { _, _ in\n                updateMonthlyData()\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: budget.incomes) { _, _ in\n                updateMonthlyData()\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: budget.savingsEntries) { _, _ in\n                updateMonthlyData()\n            }\n            .onChange(of: budget.creditAccounts) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: budget.portfolioTransactions) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: budget.cashTransfers) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: budget.recurringPayments) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: visibleCalendarWeekStart) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: calendarFocusDate) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: calendarViewMode) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n''',
"debounced calendar change handlers"
)

replace_once(
'''    private func rebuildCalendarEventCache() {\n        calendarEventCache = Dictionary(\n            uniqueKeysWithValues: calendarWeeks.flatMap(\\.days).map { date in\n                (calendarDayKey(for: date), calendarEvents(for: date))\n            }\n        )\n    }\n\n    private func cachedCalendarEvents(for date: Date) -> [CalendarEventItem] {\n        calendarEventCache[calendarDayKey(for: date)] ?? []\n    }\n''',
'''    private var calendarCacheDates: [Date] {\n        let calendar = Calendar.current\n        let anchor = calendarViewMode == .month ? visibleCalendarMonth : calendarFocusDate\n        guard let month = calendar.dateInterval(of: .month, for: anchor),\n              let start = calendar.date(byAdding: .month, value: -1, to: month.start),\n              let end = calendar.date(byAdding: .month, value: 2, to: month.start) else {\n            return [calendarDayKey(for: anchor)]\n        }\n\n        var dates: [Date] = []\n        var cursor = calendar.startOfDay(for: start)\n        while cursor < end {\n            dates.append(cursor)\n            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }\n            cursor = next\n        }\n        return dates\n    }\n\n    private func rebuildCalendarEventCache() {\n        let dates = calendarCacheDates\n        calendarEventCache = Dictionary(\n            uniqueKeysWithValues: dates.map { date in\n                (calendarDayKey(for: date), calendarEvents(for: date))\n            }\n        )\n    }\n\n    private func scheduleCalendarEventCacheRebuild() {\n        calendarCacheRefreshTask?.cancel()\n        calendarCacheRefreshTask = Task { @MainActor in\n            try? await Task.sleep(nanoseconds: 150_000_000)\n            guard !Task.isCancelled else { return }\n            rebuildCalendarEventCache()\n        }\n    }\n\n    private func cachedCalendarEvents(for date: Date) -> [CalendarEventItem] {\n        calendarEventCache[calendarDayKey(for: date)] ?? calendarEvents(for: date)\n    }\n''',
"visible range calendar cache"
)

path.write_text(text)
