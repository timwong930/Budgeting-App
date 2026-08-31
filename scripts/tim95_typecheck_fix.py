from pathlib import Path

path = Path("Budgeting App/ContentView.swift")
text = path.read_text()

old_task = '''            .task(id: selectedTab) {
                switch selectedTab {
                case .home:
                    await refreshHomeDashboard()
                case .calendar:
                    await refreshCalendarFromPlaid(force: false)
                case .budget, .margin:
                    break
                }
            }
'''
new_task = '''            .task(id: selectedTab) {
                await refreshSelectedTabIfNeeded()
            }
'''

if text.count(old_task) != 1:
    raise SystemExit(f"task block: expected 1 match, found {text.count(old_task)}")
text = text.replace(old_task, new_task, 1)

marker = '''    @MainActor
    private func refreshCalendarFromPlaid(force: Bool) async {
'''
helper = '''    @MainActor
    private func refreshSelectedTabIfNeeded() async {
        switch selectedTab {
        case .home:
            await refreshHomeDashboard()
        case .calendar:
            await refreshCalendarFromPlaid(force: false)
        case .budget, .margin:
            break
        }
    }

'''

if text.count(marker) != 1:
    raise SystemExit(f"helper marker: expected 1 match, found {text.count(marker)}")
text = text.replace(marker, helper + marker, 1)

path.write_text(text)
