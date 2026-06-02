import WidgetKit
import SwiftUI

struct BudgetWidgetEntry: TimelineEntry {
    let date: Date
    let monthlyIncome: Double
    let needsBudget: Double
    let wantsBudget: Double
    let savingsBudget: Double
    let needsAllocated: Double
    let wantsAllocated: Double
    let savingsAllocated: Double

    static let placeholder = BudgetWidgetEntry(
        date: Date(),
        monthlyIncome: 6000,
        needsBudget: 3000,
        wantsBudget: 1200,
        savingsBudget: 1800,
        needsAllocated: 2200,
        wantsAllocated: 950,
        savingsAllocated: 1400
    )

    var remainingBudget: Double {
        (needsBudget - needsAllocated) + (wantsBudget - wantsAllocated) + (savingsBudget - savingsAllocated)
    }
}

private struct BudgetWidgetDataStore {
    static let appGroupIdentifier = "group.Timothy-Wong.Budgeting-App"
    static let saveFileName = "budget.json"

    struct Snapshot: Codable {
        let income: Double
        let incomeByMonth: [String: Double]?
        let payFrequency: PayFrequency
        let needsCategories: [Category]
        let wantsCategories: [Category]
        let savingsGoals: [SavingsGoal]
    }

    enum PayFrequency: String, Codable {
        case weekly = "Weekly"
        case biWeekly = "Bi-Weekly"
        case monthly = "Monthly"
        case annually = "Annually"

        var multiplier: Double {
            switch self {
            case .weekly: return 52.0
            case .biWeekly: return 26.0
            case .monthly: return 12.0
            case .annually: return 1.0
            }
        }
    }

    struct Category: Codable {
        let allocatedAmount: Double
    }

    struct SavingsGoal: Codable {
        let monthlyContribution: Double
    }

    static func loadEntry() -> BudgetWidgetEntry {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return .placeholder
        }

        let saveURL = containerURL.appendingPathComponent(saveFileName)

        guard let data = try? Data(contentsOf: saveURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return .placeholder
        }

        let monthKey = DateFormatter.monthKey.string(from: Date())
        let currentIncome = snapshot.incomeByMonth?[monthKey] ?? snapshot.income
        let monthlyIncome = (currentIncome * snapshot.payFrequency.multiplier) / 12.0

        let needsBudget = monthlyIncome * 0.50
        let wantsBudget = monthlyIncome * 0.20
        let savingsBudget = monthlyIncome * 0.30

        let needsAllocated = snapshot.needsCategories.reduce(0) { $0 + $1.allocatedAmount }
        let wantsAllocated = snapshot.wantsCategories.reduce(0) { $0 + $1.allocatedAmount }
        let savingsAllocated = snapshot.savingsGoals.reduce(0) { $0 + $1.monthlyContribution }

        return BudgetWidgetEntry(
            date: Date(),
            monthlyIncome: monthlyIncome,
            needsBudget: needsBudget,
            wantsBudget: wantsBudget,
            savingsBudget: savingsBudget,
            needsAllocated: needsAllocated,
            wantsAllocated: wantsAllocated,
            savingsAllocated: savingsAllocated
        )
    }
}

private extension DateFormatter {
    static let monthKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}

struct BudgetWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetWidgetEntry) -> Void) {
        completion(BudgetWidgetDataStore.loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetWidgetEntry>) -> Void) {
        let entry = BudgetWidgetDataStore.loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct BudgetingWidgetsEntryView: View {
    var entry: BudgetWidgetProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Budget Left")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.remainingBudget, format: .currency(code: "USD"))
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            Text("Income: \(entry.monthlyIncome, format: .currency(code: "USD"))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This Month")
                .font(.headline)

            sectionRow(title: "Needs", used: entry.needsAllocated, total: entry.needsBudget, tint: .blue)
            sectionRow(title: "Wants", used: entry.wantsAllocated, total: entry.wantsBudget, tint: .orange)
            sectionRow(title: "Savings", used: entry.savingsAllocated, total: entry.savingsBudget, tint: .green)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func sectionRow(title: String, used: Double, total: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text("\(used, format: .currency(code: "USD"))/\(total, format: .currency(code: "USD"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: min(max(total > 0 ? (used / total) : 0, 0), 1.2))
                .tint(tint)
        }
    }
}

struct BudgetingWidgets: Widget {
    let kind: String = "BudgetingWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BudgetWidgetProvider()) { entry in
            BudgetingWidgetsEntryView(entry: entry)
        }
        .configurationDisplayName("Budget Summary")
        .description("Quick look at remaining budget and section progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    BudgetingWidgets()
} timeline: {
    BudgetWidgetEntry.placeholder
}

#Preview(as: .systemMedium) {
    BudgetingWidgets()
} timeline: {
    BudgetWidgetEntry.placeholder
}
