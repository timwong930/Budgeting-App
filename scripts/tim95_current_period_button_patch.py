from pathlib import Path

path = Path("Budgeting App/ContentView.swift")
text = path.read_text()

old = '''                Spacer()
                Button {
                    Task { await refreshCalendarFromPlaid(force: true) }
                } label: {
'''
new = '''                Spacer()
                Button {
                    resetCalendarToCurrentPeriod()
                } label: {
                    Label(calendarCurrentPeriodButtonTitle, systemImage: calendarViewMode == .week ? "calendar" : "location.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(appAccent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(appAccent)
                .accessibilityLabel(calendarCurrentPeriodButtonTitle)

                Button {
                    Task { await refreshCalendarFromPlaid(force: true) }
                } label: {
'''
if text.count(old) != 1:
    raise RuntimeError(f"toolbar insertion: expected 1 match, found {text.count(old)}")
text = text.replace(old, new, 1)

old = '''    private var calendarFilterSummary: String {
'''
new = '''    private var calendarCurrentPeriodButtonTitle: String {
        calendarViewMode == .week ? "This Week" : "Today"
    }

    private func resetCalendarToCurrentPeriod() {
        let now = Date()
        withAnimation(.snappy) {
            calendarFocusDate = now
            if calendarViewMode == .month {
                visibleCalendarWeekStart = currentCalendarWeekStart
            }
        }
        scheduleCalendarEventCacheRebuild()
    }

    private var calendarFilterSummary: String {
'''
if text.count(old) != 1:
    raise RuntimeError(f"helper insertion: expected 1 match, found {text.count(old)}")
text = text.replace(old, new, 1)

old = '''            Button {
                withAnimation(.snappy) { calendarFocusDate = Date() }
            } label: {
                VStack(spacing: 1) {
                    Text(calendarFocusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Tap for today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
'''
new = '''            VStack(spacing: 1) {
                Text(calendarFocusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(calendarViewMode == .week ? "Sunday – Saturday" : "Selected day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
'''
if text.count(old) != 1:
    raise RuntimeError(f"navigation center: expected 1 match, found {text.count(old)}")
text = text.replace(old, new, 1)

path.write_text(text)
