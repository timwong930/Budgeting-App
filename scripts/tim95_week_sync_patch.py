from pathlib import Path

path = Path("Budgeting App/ContentView.swift")
text = path.read_text()

old = '''                Text("Tap a day for the full transaction list.")\n                    .font(.caption2)\n                    .foregroundStyle(.secondary)\n                    .frame(maxWidth: .infinity, alignment: .leading)\n'''
new = '''                Text("Tap a day header for the full day view.")\n                    .font(.caption2)\n                    .foregroundStyle(.secondary)\n                    .frame(maxWidth: .infinity, alignment: .leading)\n'''
if text.count(old) != 1:
    raise RuntimeError(f"week helper text: expected 1 match, found {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        .padding(.horizontal, 2)\n        .background(isToday ? appAccent.opacity(0.035) : Color.clear)\n        .contentShape(Rectangle())\n        .onTapGesture {\n            selectedCalendarEventList = CalendarDaySelection(date: date)\n        }\n    }\n'''
new = '''        .padding(.horizontal, 2)\n        .background(isToday ? appAccent.opacity(0.035) : Color.clear)\n    }\n'''
if text.count(old) != 1:
    raise RuntimeError(f"week parent tap: expected 1 match, found {text.count(old)}")
text = text.replace(old, new, 1)

path.write_text(text)
