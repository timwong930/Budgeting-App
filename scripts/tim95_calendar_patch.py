from pathlib import Path

path = Path("Budgeting App/ContentView.swift")
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 match, found {count}")
    text = text.replace(old, new, 1)


def replace_between(start: str, end: str, replacement: str, label: str) -> None:
    global text
    start_index = text.find(start)
    if start_index == -1:
        raise RuntimeError(f"{label}: start marker not found")
    end_index = text.find(end, start_index)
    if end_index == -1:
        raise RuntimeError(f"{label}: end marker not found")
    text = text[:start_index] + replacement + text[end_index:]


replace_once(
    '''    @State private var selectedCalendarDay: CalendarDaySelection?\n    @State private var selectedCalendarEventList: CalendarDaySelection?\n    @State private var visibleCalendarWeekStart: Date?\n    @State private var calendarEventCache: [Date: [CalendarEventItem]] = [:]\n''',
    '''    @State private var selectedCalendarDay: CalendarDaySelection?\n    @State private var selectedCalendarEventList: CalendarDaySelection?\n    @State private var visibleCalendarWeekStart: Date?\n    @State private var calendarFocusDate: Date = Date()\n    @AppStorage("calendar.viewMode") private var calendarViewMode: CalendarViewMode = .month\n    @AppStorage("calendar.showExpenses") private var calendarShowExpenses = true\n    @AppStorage("calendar.showIncome") private var calendarShowIncome = true\n    @AppStorage("calendar.showTransfers") private var calendarShowTransfers = true\n    @AppStorage("calendar.showCreditDue") private var calendarShowCreditDue = true\n    @AppStorage("calendar.showPortfolio") private var calendarShowPortfolio = false\n    @State private var calendarEventCache: [Date: [CalendarEventItem]] = [:]\n''',
    "calendar state",
)

replace_once(
    '''    private struct CalendarDaySelection: Identifiable {\n        let id = UUID()\n        let date: Date\n    }\n\n''',
    '''    private struct CalendarDaySelection: Identifiable {\n        let id = UUID()\n        let date: Date\n    }\n\n    private enum CalendarViewMode: String, CaseIterable, Identifiable, Equatable {\n        case month = "Month"\n        case week = "Week"\n        case day = "Day"\n\n        var id: String { rawValue }\n\n        var systemImage: String {\n            switch self {\n            case .month: return "calendar"\n            case .week: return "rectangle.split.3x1"\n            case .day: return "list.bullet.rectangle"\n            }\n        }\n    }\n\n''',
    "calendar view enum",
)

replace_once(
    '''                        case .addCalendarEntry:\n                            selectedCalendarDay = CalendarDaySelection(date: visibleCalendarMonth)\n''',
    '''                        case .addCalendarEntry:\n                            selectedCalendarDay = CalendarDaySelection(date: calendarActionDate)\n''',
    "calendar quick add date",
)

replace_once(
    '''            CashTransferEditorView(budget: budget, selectedDate: selectedTab == .calendar ? visibleCalendarMonth : selectedMonth)\n''',
    '''            CashTransferEditorView(budget: budget, selectedDate: selectedTab == .calendar ? calendarActionDate : selectedMonth)\n''',
    "calendar transfer date",
)

replace_once(
    '''                events: cachedCalendarEvents(for: selection.date),\n''',
    '''                events: filteredCalendarEvents(for: selection.date),\n''',
    "filtered day sheet",
)

calendar_tab = '''    private var calendarTab: some View {\n        VStack(spacing: 0) {\n            VStack(spacing: 10) {\n                pageHeader(\n                    title: "Calendar",\n                    subtitle: "Plan cash flow without the transaction noise.",\n                    systemImage: "calendar"\n                ) {\n                    HStack(spacing: 8) {\n                        Button {\n                            Haptics.light()\n                            selectedCalendarDay = CalendarDaySelection(date: calendarActionDate)\n                        } label: {\n                            Image(systemName: "plus")\n                                .font(.headline.weight(.semibold))\n                                .foregroundStyle(.white)\n                                .frame(width: 36, height: 36)\n                                .background(appAccent, in: Circle())\n                        }\n                        .buttonStyle(.plain)\n                        .accessibilityLabel("Add Calendar Entry")\n\n                        Button {\n                            showingAddCashTransfer = true\n                        } label: {\n                            Image(systemName: "arrow.left.arrow.right")\n                                .font(.headline)\n                                .foregroundStyle(.primary)\n                                .frame(width: 36, height: 36)\n                                .background(.thinMaterial, in: Circle())\n                        }\n                        .buttonStyle(.plain)\n                        .accessibilityLabel("Transfer Cash")\n\n                        Button {\n                            showingCreditAccounts = true\n                        } label: {\n                            Image(systemName: "creditcard")\n                                .font(.headline)\n                                .foregroundStyle(.primary)\n                                .frame(width: 36, height: 36)\n                                .background(.thinMaterial, in: Circle())\n                        }\n                        .buttonStyle(.plain)\n                        .accessibilityLabel("Credit Cards")\n                    }\n                }\n\n                calendarViewControls\n\n                if calendarViewMode == .month {\n                    calendarSummarySection\n                }\n            }\n            .padding(.horizontal, 16)\n            .padding(.bottom, 8)\n\n            Group {\n                switch calendarViewMode {\n                case .month:\n                    recurringCalendarSection\n                case .week:\n                    calendarWeekAgendaSection\n                case .day:\n                    calendarDayAgendaSection\n                }\n            }\n            .frame(maxHeight: .infinity, alignment: .top)\n        }\n        .padding(.top, 22)\n        .padding(.bottom, 0)\n        .background(backgroundView)\n        .onChange(of: calendarViewMode) { oldValue, newValue in\n            guard oldValue != newValue, newValue != .month else { return }\n            if Calendar.current.isDate(visibleCalendarMonth, equalTo: Date(), toGranularity: .month) {\n                calendarFocusDate = Date()\n            } else {\n                calendarFocusDate = visibleCalendarMonth\n            }\n        }\n    }\n\n'''
replace_between(
    "    private var calendarTab: some View {\n",
    "    private var calendarNetWorth: Double {\n",
    calendar_tab,
    "calendar tab",
)

calendar_helpers = '''    private var calendarActionDate: Date {\n        if calendarViewMode != .month { return calendarFocusDate }\n        if Calendar.current.isDate(visibleCalendarMonth, equalTo: Date(), toGranularity: .month) {\n            return Date()\n        }\n        return visibleCalendarMonth\n    }\n\n    private var calendarViewControls: some View {\n        VStack(spacing: 8) {\n            HStack(spacing: 10) {\n                Picker("Calendar View", selection: $calendarViewMode) {\n                    ForEach(CalendarViewMode.allCases) { mode in\n                        Text(mode.rawValue).tag(mode)\n                    }\n                }\n                .pickerStyle(.segmented)\n\n                Menu {\n                    Toggle("Spending & bills", isOn: $calendarShowExpenses)\n                    Toggle("Income", isOn: $calendarShowIncome)\n                    Toggle("Transfers", isOn: $calendarShowTransfers)\n                    Toggle("Credit due", isOn: $calendarShowCreditDue)\n                    Toggle("Portfolio", isOn: $calendarShowPortfolio)\n                    Divider()\n                    Button("Show everything") {\n                        calendarShowExpenses = true\n                        calendarShowIncome = true\n                        calendarShowTransfers = true\n                        calendarShowCreditDue = true\n                        calendarShowPortfolio = true\n                    }\n                    Button("Reset recommended") {\n                        calendarShowExpenses = true\n                        calendarShowIncome = true\n                        calendarShowTransfers = true\n                        calendarShowCreditDue = true\n                        calendarShowPortfolio = false\n                    }\n                } label: {\n                    Image(systemName: "line.3.horizontal.decrease")\n                        .font(.subheadline.weight(.semibold))\n                        .frame(width: 34, height: 32)\n                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))\n                }\n                .buttonStyle(.plain)\n                .accessibilityLabel("Calendar Filters")\n            }\n\n            HStack(spacing: 6) {\n                Image(systemName: calendarShowPortfolio ? "eye.fill" : "eye.slash.fill")\n                    .font(.caption2)\n                    .foregroundStyle(calendarShowPortfolio ? appAccent : Color.secondary)\n                Text(calendarFilterSummary)\n                    .font(.caption2)\n                    .foregroundStyle(.secondary)\n                Spacer()\n            }\n\n            if calendarViewMode != .month {\n                calendarFocusNavigation\n            }\n        }\n    }\n\n    private var calendarFilterSummary: String {\n        let allCoreVisible = calendarShowExpenses && calendarShowIncome && calendarShowTransfers && calendarShowCreditDue\n        if allCoreVisible && !calendarShowPortfolio {\n            return "Portfolio activity hidden · recommended"\n        }\n        if allCoreVisible && calendarShowPortfolio {\n            return "Showing all activity"\n        }\n        return "Custom filters active"\n    }\n\n    private var calendarFocusNavigation: some View {\n        HStack(spacing: 10) {\n            Button { shiftCalendarFocus(by: -1) } label: {\n                Image(systemName: "chevron.left")\n                    .frame(width: 32, height: 32)\n                    .background(.thinMaterial, in: Circle())\n            }\n            .buttonStyle(.plain)\n\n            Button {\n                withAnimation(.snappy) { calendarFocusDate = Date() }\n            } label: {\n                VStack(spacing: 1) {\n                    Text(calendarFocusTitle)\n                        .font(.subheadline.weight(.semibold))\n                        .foregroundStyle(.primary)\n                    Text("Tap for today")\n                        .font(.caption2)\n                        .foregroundStyle(.secondary)\n                }\n                .frame(maxWidth: .infinity)\n                .padding(.vertical, 6)\n            }\n            .buttonStyle(.plain)\n\n            Button { shiftCalendarFocus(by: 1) } label: {\n                Image(systemName: "chevron.right")\n                    .frame(width: 32, height: 32)\n                    .background(.thinMaterial, in: Circle())\n            }\n            .buttonStyle(.plain)\n        }\n    }\n\n    private var calendarFocusTitle: String {\n        switch calendarViewMode {\n        case .month:\n            return visibleCalendarMonth.formatted(.dateTime.month(.wide).year())\n        case .week:\n            guard let first = focusedCalendarWeekDays.first, let last = focusedCalendarWeekDays.last else {\n                return calendarFocusDate.formatted(.dateTime.month(.abbreviated).day())\n            }\n            if Calendar.current.isDate(first, equalTo: last, toGranularity: .month) {\n                return "\\(first.formatted(.dateTime.month(.abbreviated).day())) – \\(last.formatted(.dateTime.day()))"\n            }\n            return "\\(first.formatted(.dateTime.month(.abbreviated).day())) – \\(last.formatted(.dateTime.month(.abbreviated).day()))"\n        case .day:\n            return calendarFocusDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())\n        }\n    }\n\n    private var focusedCalendarWeekDays: [Date] {\n        let calendar = Calendar.current\n        guard let interval = calendar.dateInterval(of: .weekOfYear, for: calendarFocusDate) else {\n            return [calendar.startOfDay(for: calendarFocusDate)]\n        }\n        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }\n    }\n\n    private func shiftCalendarFocus(by offset: Int) {\n        let calendar = Calendar.current\n        let component: Calendar.Component = calendarViewMode == .week ? .weekOfYear : .day\n        guard let shifted = calendar.date(byAdding: component, value: offset, to: calendarFocusDate) else { return }\n        withAnimation(.snappy) {\n            calendarFocusDate = shifted\n        }\n    }\n\n    private var calendarWeekAgendaSection: some View {\n        ScrollView {\n            LazyVStack(spacing: 10) {\n                ForEach(focusedCalendarWeekDays, id: \\.self) { day in\n                    calendarAgendaDayCard(for: day, showFullDate: false)\n                }\n            }\n            .padding(.horizontal, 16)\n            .padding(.top, 4)\n            .padding(.bottom, contentBottomPadding)\n        }\n    }\n\n    private var calendarDayAgendaSection: some View {\n        ScrollView {\n            VStack(spacing: 12) {\n                calendarAgendaDayCard(for: calendarFocusDate, showFullDate: true)\n            }\n            .padding(.horizontal, 16)\n            .padding(.top, 4)\n            .padding(.bottom, contentBottomPadding)\n        }\n    }\n\n    private func calendarAgendaDayCard(for date: Date, showFullDate: Bool) -> some View {\n        let events = filteredCalendarEvents(for: date)\n        let hiddenCount = max(cachedCalendarEvents(for: date).count - events.count, 0)\n        let isToday = Calendar.current.isDateInToday(date)\n\n        return GlassCard(padding: 12) {\n            VStack(alignment: .leading, spacing: 10) {\n                HStack(alignment: .center, spacing: 10) {\n                    VStack(alignment: .leading, spacing: 2) {\n                        Text(showFullDate ? date.formatted(.dateTime.weekday(.wide).month(.wide).day()) : date.formatted(.dateTime.weekday(.wide)))\n                            .font(.subheadline.weight(.bold))\n                        if !showFullDate {\n                            Text(date.formatted(.dateTime.month(.abbreviated).day()))\n                                .font(.caption)\n                                .foregroundStyle(.secondary)\n                        }\n                    }\n\n                    if isToday {\n                        Text("Today")\n                            .font(.caption2.weight(.bold))\n                            .foregroundStyle(appAccent)\n                            .padding(.horizontal, 8)\n                            .padding(.vertical, 4)\n                            .background(appAccent.opacity(0.12), in: Capsule())\n                    }\n\n                    Spacer()\n\n                    Text("\\(events.count) item\\(events.count == 1 ? "" : "s")")\n                        .font(.caption2.weight(.semibold))\n                        .foregroundStyle(.secondary)\n                }\n\n                if events.isEmpty {\n                    HStack(spacing: 8) {\n                        Image(systemName: hiddenCount > 0 ? "line.3.horizontal.decrease.circle" : "calendar.badge.checkmark")\n                            .foregroundStyle(.secondary)\n                        Text(hiddenCount > 0 ? "\\(hiddenCount) item\\(hiddenCount == 1 ? "" : "s") hidden by filters" : "Nothing scheduled")\n                            .font(.caption)\n                            .foregroundStyle(.secondary)\n                        Spacer()\n                        Button("Add") {\n                            selectedCalendarDay = CalendarDaySelection(date: date)\n                        }\n                        .font(.caption.weight(.semibold))\n                        .buttonStyle(.borderless)\n                    }\n                    .padding(.vertical, 4)\n                } else {\n                    VStack(spacing: 0) {\n                        ForEach(events) { event in\n                            calendarAgendaRow(event)\n                            if event.id != events.last?.id {\n                                Divider().padding(.leading, 42)\n                            }\n                        }\n                    }\n                }\n            }\n        }\n    }\n\n    private func calendarAgendaRow(_ event: CalendarEventItem) -> some View {\n        HStack(spacing: 10) {\n            Button {\n                openCalendarEvent(event)\n            } label: {\n                HStack(spacing: 10) {\n                    Image(systemName: event.iconName)\n                        .font(.subheadline.weight(.semibold))\n                        .foregroundStyle(event.tint)\n                        .frame(width: 32, height: 32)\n                        .background(event.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))\n\n                    VStack(alignment: .leading, spacing: 2) {\n                        HStack(spacing: 5) {\n                            Text(event.name)\n                                .font(.subheadline.weight(.semibold))\n                                .foregroundStyle(.primary)\n                                .lineLimit(1)\n                            if event.isPlaidSynced {\n                                Image(systemName: "link.circle.fill")\n                                    .font(.caption2)\n                                    .foregroundStyle(.secondary)\n                            }\n                        }\n                        if !event.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {\n                            Text(event.paymentAccount)\n                                .font(.caption2)\n                                .foregroundStyle(.secondary)\n                                .lineLimit(1)\n                        }\n                    }\n\n                    Spacer(minLength: 8)\n\n                    if event.amount > 0 {\n                        Text(calendarChipAmountText(for: event))\n                            .font(.subheadline.weight(.bold))\n                            .foregroundStyle(event.isIncome ? Color.green : Color.primary)\n                            .lineLimit(1)\n                            .minimumScaleFactor(0.75)\n                    }\n                }\n                .contentShape(Rectangle())\n            }\n            .buttonStyle(.plain)\n\n            if let recurring = event.recurringPayment {\n                Button {\n                    markRecurringOccurrencePaid(recurring, on: event.date)\n                } label: {\n                    Image(systemName: "checkmark.circle")\n                        .font(.title3)\n                        .foregroundStyle(.secondary)\n                        .frame(width: 36, height: 36)\n                }\n                .buttonStyle(.plain)\n                .accessibilityLabel("Mark \\(event.name) paid")\n            }\n        }\n        .padding(.vertical, 7)\n    }\n\n'''
insert_marker = "    private var backgroundView: some View {\n"
if insert_marker not in text:
    raise RuntimeError("calendar helper insertion marker not found")
text = text.replace(insert_marker, calendar_helpers + insert_marker, 1)

replace_once(
    '''    private func cachedCalendarEvents(for date: Date) -> [CalendarEventItem] {\n        calendarEventCache[calendarDayKey(for: date)] ?? []\n    }\n\n''',
    '''    private func cachedCalendarEvents(for date: Date) -> [CalendarEventItem] {\n        calendarEventCache[calendarDayKey(for: date)] ?? []\n    }\n\n    private func filteredCalendarEvents(for date: Date) -> [CalendarEventItem] {\n        cachedCalendarEvents(for: date).filter { event in\n            if event.portfolioTransaction != nil { return calendarShowPortfolio }\n            if event.isCreditDue { return calendarShowCreditDue }\n            if event.cashTransfer != nil { return calendarShowTransfers }\n            if event.isIncome { return calendarShowIncome }\n            return calendarShowExpenses\n        }\n    }\n\n''',
    "calendar filtering",
)

replace_once(
    '''            let events = cachedCalendarEvents(for: date)\n''',
    '''            let events = filteredCalendarEvents(for: date)\n''',
    "filtered month day",
)

replace_once(
    '''            .map { cachedCalendarEvents(for: $0).count }\n''',
    '''            .map { filteredCalendarEvents(for: $0).count }\n''',
    "filtered month sizing",
)

compact_chip = '''    private func calendarEventChip(_ event: CalendarEventItem) -> some View {\n        Button {\n            selectedCalendarEventList = CalendarDaySelection(date: event.date)\n        } label: {\n            HStack(spacing: 3) {\n                RoundedRectangle(cornerRadius: 1.5)\n                    .fill(Color.white.opacity(0.72))\n                    .frame(width: 3, height: 14)\n                Image(systemName: event.iconName)\n                    .font(.system(size: 8, weight: .bold))\n                Text(event.name)\n                    .font(.caption2.weight(.semibold))\n                    .lineLimit(1)\n                    .minimumScaleFactor(0.70)\n                    .allowsTightening(true)\n                Spacer(minLength: 0)\n                if event.isPlaidSynced {\n                    Image(systemName: "link.circle.fill")\n                        .font(.system(size: 8, weight: .bold))\n                }\n            }\n            .foregroundStyle(.white)\n            .padding(.horizontal, 4)\n            .frame(maxWidth: .infinity, alignment: .leading)\n            .frame(height: calendarEventChipHeight)\n            .background(\n                RoundedRectangle(cornerRadius: 6, style: .continuous)\n                    .fill(calendarEventBackground(for: event))\n            )\n            .contentShape(Rectangle())\n        }\n        .buttonStyle(.plain)\n        .accessibilityLabel(calendarMenuTitle(for: event))\n    }\n\n'''
replace_between(
    "    private func calendarEventChip(_ event: CalendarEventItem) -> some View {\n",
    "    private func calendarOverflowButton(date: Date, hiddenEventCount: Int) -> some View {\n",
    compact_chip,
    "compact month event chip",
)

replace_once(
    '''    private func maxVisibleCalendarEvents(for eventCount: Int) -> Int {\n        min(max(eventCount, 1), 5)\n    }\n''',
    '''    private func maxVisibleCalendarEvents(for eventCount: Int) -> Int {\n        min(max(eventCount, 1), 3)\n    }\n''',
    "month visible event limit",
)

replace_once(
    '''    private var calendarDayNumberHeight: CGFloat {\n        38\n    }\n''',
    '''    private var calendarDayNumberHeight: CGFloat {\n        30\n    }\n''',
    "month day number height",
)

replace_once(
    '''    private var calendarCellContentSpacing: CGFloat {\n        6\n    }\n\n    private var calendarEventChipHeight: CGFloat {\n        48\n    }\n\n    private var calendarOverflowMenuHeight: CGFloat {\n        31\n    }\n''',
    '''    private var calendarCellContentSpacing: CGFloat {\n        4\n    }\n\n    private var calendarEventChipHeight: CGFloat {\n        28\n    }\n\n    private var calendarOverflowMenuHeight: CGFloat {\n        26\n    }\n''',
    "compact month sizing",
)

replace_once(
    '''        return oneTimeIncome + recurringIncome + investmentIncome\n''',
    '''        let visibleCashIncome = calendarShowIncome ? oneTimeIncome + recurringIncome : 0\n        let visibleInvestmentIncome = calendarShowPortfolio ? investmentIncome : 0\n        return visibleCashIncome + visibleInvestmentIncome\n''',
    "filtered month income metric",
)

replace_once(
    '''        return oneTimeExpenses + recurringExpenses\n''',
    '''        return calendarShowExpenses ? oneTimeExpenses + recurringExpenses : 0\n''',
    "filtered month outflow metric",
)

replace_once(
    '''        budget.creditAccounts\n            .filter { account in\n                account.isActive && visibleCalendarMonthDays.contains { date in\n                    Calendar.current.component(.day, from: date) == recurringOccurrenceDay(in: date, paymentDay: account.dueDay)\n                }\n            }\n            .reduce(0) { $0 + creditAccountActualBalance($1) }\n''',
    '''        guard calendarShowCreditDue else { return 0 }\n        return budget.creditAccounts\n            .filter { account in\n                account.isActive && visibleCalendarMonthDays.contains { date in\n                    Calendar.current.component(.day, from: date) == recurringOccurrenceDay(in: date, paymentDay: account.dueDay)\n                }\n            }\n            .reduce(0) { $0 + creditAccountActualBalance($1) }\n''',
    "filtered credit due metric",
)

path.write_text(text)
