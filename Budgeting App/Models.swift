//
//  Models.swift
//  Budgeting App
//
//  Created by Timothy Wong on 1/16/26.
//

import Foundation
import Combine
import OSLog

enum PayFrequency: String, CaseIterable, Identifiable, Codable, Sendable {
    case weekly = "Weekly"
    case biWeekly = "Bi-Weekly"
    case monthly = "Monthly"
    case annually = "Annually"
    
    var id: String { rawValue }
    
    var multiplier: Double {
        switch self {
        case .weekly: return 52.0
        case .biWeekly: return 26.0
        case .monthly: return 12.0
        case .annually: return 1.0
        }
    }
}

enum BudgetSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case needs
    case wants

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needs:
            return "Needs"
        case .wants:
            return "Wants"
        }
    }
}

struct Category: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var allocatedAmount: Double
    var spentAmount: Double
    
    init(id: UUID = UUID(), name: String, allocatedAmount: Double, spentAmount: Double = 0) {
        self.id = id
        self.name = name
        self.allocatedAmount = allocatedAmount
        self.spentAmount = spentAmount
    }
    
    var remaining: Double {
        allocatedAmount - spentAmount
    }
}

struct Expense: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var amount: Double
    var date: Date
    var section: BudgetSection
    var categoryId: UUID

    init(id: UUID = UUID(), name: String, amount: Double, date: Date = Date(), section: BudgetSection, categoryId: UUID) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
        self.section = section
        self.categoryId = categoryId
    }
}

struct SavingsEntry: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var amount: Double
    var date: Date
    var goalId: UUID

    init(id: UUID = UUID(), name: String, amount: Double, date: Date = Date(), goalId: UUID) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
        self.goalId = goalId
    }
}

struct IncomeEntry: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var amount: Double
    var date: Date

    init(id: UUID = UUID(), name: String, amount: Double, date: Date = Date()) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
    }
}

struct SavingsGoal: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var targetAmount: Double
    var currentAmount: Double
    var monthlyContribution: Double
    var accountName: String
    
    init(id: UUID = UUID(), name: String, targetAmount: Double, currentAmount: Double = 0, monthlyContribution: Double = 0, accountName: String) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.monthlyContribution = monthlyContribution
        self.accountName = accountName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case targetAmount
        case currentAmount
        case monthlyContribution
        case accountName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        targetAmount = try container.decode(Double.self, forKey: .targetAmount)
        currentAmount = try container.decode(Double.self, forKey: .currentAmount)
        monthlyContribution = try container.decodeIfPresent(Double.self, forKey: .monthlyContribution) ?? 0
        accountName = try container.decode(String.self, forKey: .accountName)
    }
    
    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentAmount / targetAmount, 1.0)
    }
    
    var remaining: Double {
        max(targetAmount - currentAmount, 0)
    }

    var displayName: String {
        if !name.isEmpty {
            return name
        }
        return accountName
    }
}

private struct BudgetSnapshotStore: Codable, Sendable {
    let income: Double
    let incomeByMonth: [String: Double]?
    let needsAllocationsByMonth: [String: [UUID: Double]]?
    let wantsAllocationsByMonth: [String: [UUID: Double]]?
    let payFrequency: PayFrequency
    let needsCategories: [Category]
    let wantsCategories: [Category]
    let savingsGoals: [SavingsGoal]
    let incomes: [IncomeEntry]?
    let expenses: [Expense]
    let savingsEntries: [SavingsEntry]?

    enum CodingKeys: String, CodingKey {
        case income
        case incomeByMonth
        case needsAllocationsByMonth
        case wantsAllocationsByMonth
        case payFrequency
        case needsCategories
        case wantsCategories
        case savingsGoals
        case incomes
        case expenses
        case savingsEntries
    }

    init(
        income: Double,
        incomeByMonth: [String: Double],
        needsAllocationsByMonth: [String: [UUID: Double]],
        wantsAllocationsByMonth: [String: [UUID: Double]],
        payFrequency: PayFrequency,
        needsCategories: [Category],
        wantsCategories: [Category],
        savingsGoals: [SavingsGoal],
        incomes: [IncomeEntry],
        expenses: [Expense],
        savingsEntries: [SavingsEntry]
    ) {
        self.income = income
        self.incomeByMonth = incomeByMonth
        self.needsAllocationsByMonth = needsAllocationsByMonth
        self.wantsAllocationsByMonth = wantsAllocationsByMonth
        self.payFrequency = payFrequency
        self.needsCategories = needsCategories
        self.wantsCategories = wantsCategories
        self.savingsGoals = savingsGoals
        self.incomes = incomes
        self.expenses = expenses
        self.savingsEntries = savingsEntries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        income = try container.decode(Double.self, forKey: .income)
        incomeByMonth = try container.decodeIfPresent([String: Double].self, forKey: .incomeByMonth)
        needsAllocationsByMonth = try container.decodeIfPresent([String: [UUID: Double]].self, forKey: .needsAllocationsByMonth)
        wantsAllocationsByMonth = try container.decodeIfPresent([String: [UUID: Double]].self, forKey: .wantsAllocationsByMonth)
        payFrequency = try container.decode(PayFrequency.self, forKey: .payFrequency)
        needsCategories = try container.decode([Category].self, forKey: .needsCategories)
        wantsCategories = try container.decode([Category].self, forKey: .wantsCategories)
        savingsGoals = try container.decode([SavingsGoal].self, forKey: .savingsGoals)
        incomes = try container.decodeIfPresent([IncomeEntry].self, forKey: .incomes)
        expenses = try container.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        savingsEntries = try container.decodeIfPresent([SavingsEntry].self, forKey: .savingsEntries)
    }
}

class BudgetModel: ObservableObject {
    @Published var income: Double = 0
    @Published var incomeByMonth: [String: Double] = [:]
    @Published var needsAllocationsByMonth: [String: [UUID: Double]] = [:]
    @Published var wantsAllocationsByMonth: [String: [UUID: Double]] = [:]
    @Published var payFrequency: PayFrequency = .monthly
    @Published var needsCategories: [Category] = []
    @Published var wantsCategories: [Category] = []
    @Published var savingsGoals: [SavingsGoal] = []
    @Published var incomes: [IncomeEntry] = []
    @Published var expenses: [Expense] = [] {
        didSet {
            recalculateSpent()
        }
    }
    @Published var savingsEntries: [SavingsEntry] = []

    private let saveURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("budget.json")
    private var saveCancellable: AnyCancellable?
    private let saveQueue = DispatchQueue(label: "BudgetModel.save", qos: .utility)
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Timothy-Wong.Budgeting-App",
        category: "BudgetModel"
    )

    init() {
        load()
        saveCancellable = objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleSave()
            }
    }
    
    var annualIncome: Double {
        income * payFrequency.multiplier
    }
    
    var monthlyIncome: Double {
        annualIncome / 12.0
    }
    
    var needsBudget: Double {
        monthlyIncome * 0.50
    }
    
    var savingsBudget: Double {
        monthlyIncome * 0.30
    }
    
    var wantsBudget: Double {
        monthlyIncome * 0.20
    }
    
    var totalNeedsAllocated: Double {
        needsCategories.reduce(0) { $0 + $1.allocatedAmount }
    }
    
    var totalNeedsSpent: Double {
        needsCategories.reduce(0) { $0 + $1.spentAmount }
    }
    
    var totalWantsAllocated: Double {
        wantsCategories.reduce(0) { $0 + $1.allocatedAmount }
    }
    
    var totalWantsSpent: Double {
        wantsCategories.reduce(0) { $0 + $1.spentAmount }
    }
    
    var totalSavingsAllocated: Double {
        savingsGoals.reduce(0) { $0 + $1.monthlyContribution }
    }
    
    var totalSavingsCurrent: Double {
        savingsGoals.reduce(0) { $0 + $1.currentAmount }
    }
    
    var needsRemaining: Double {
        needsBudget - totalNeedsAllocated
    }
    
    var wantsRemaining: Double {
        wantsBudget - totalWantsAllocated
    }
    
    var savingsRemaining: Double {
        savingsBudget - totalSavingsAllocated
    }
    
    var totalRemainingBudget: Double {
        needsRemaining + wantsRemaining + savingsRemaining
    }

    private func scheduleSave() {
        let snapshot = BudgetSnapshotStore(
            income: income,
            incomeByMonth: incomeByMonth,
            needsAllocationsByMonth: needsAllocationsByMonth,
            wantsAllocationsByMonth: wantsAllocationsByMonth,
            payFrequency: payFrequency,
            needsCategories: needsCategories,
            wantsCategories: wantsCategories,
            savingsGoals: savingsGoals,
            incomes: incomes,
            expenses: expenses,
            savingsEntries: savingsEntries
        )

        let saveURL = saveURL
        let logger = logger
        saveQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: saveURL, options: Data.WritingOptions.atomic)
            } catch {
                logger.error("Failed to save budget snapshot: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func load() {
        let data: Data
        do {
            data = try Data(contentsOf: saveURL)
        } catch {
            let nsError = error as NSError
            if nsError.domain != NSCocoaErrorDomain || nsError.code != NSFileReadNoSuchFileError {
                logger.error("Failed to read budget snapshot: \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        let snapshot: BudgetSnapshotStore
        do {
            snapshot = try JSONDecoder().decode(BudgetSnapshotStore.self, from: data)
        } catch {
            logger.error("Failed to decode budget snapshot: \(error.localizedDescription, privacy: .public)")
            return
        }

        payFrequency = snapshot.payFrequency
        incomeByMonth = snapshot.incomeByMonth ?? [:]
        needsAllocationsByMonth = snapshot.needsAllocationsByMonth ?? [:]
        wantsAllocationsByMonth = snapshot.wantsAllocationsByMonth ?? [:]
        if incomeByMonth.isEmpty, snapshot.income > 0 {
            incomeByMonth[Self.monthKey(for: Date())] = snapshot.income
        }
        income = incomeByMonth[Self.monthKey(for: Date())] ?? snapshot.income
        needsCategories = snapshot.needsCategories
        wantsCategories = snapshot.wantsCategories
        savingsGoals = snapshot.savingsGoals
        incomes = snapshot.incomes ?? []
        expenses = snapshot.expenses
        savingsEntries = snapshot.savingsEntries ?? []

        if expenses.isEmpty {
            let importedNeeds = needsCategories.compactMap { category -> Expense? in
                guard category.spentAmount > 0 else { return nil }
                return Expense(name: "Imported Spend", amount: category.spentAmount, date: Date(), section: .needs, categoryId: category.id)
            }
            let importedWants = wantsCategories.compactMap { category -> Expense? in
                guard category.spentAmount > 0 else { return nil }
                return Expense(name: "Imported Spend", amount: category.spentAmount, date: Date(), section: .wants, categoryId: category.id)
            }
            if !importedNeeds.isEmpty || !importedWants.isEmpty {
                expenses = importedNeeds + importedWants
            }
        }

        recalculateSpent()
    }

    func categoryName(for expense: Expense) -> String {
        switch expense.section {
        case .needs:
            return needsCategories.first(where: { $0.id == expense.categoryId })?.name ?? "Needs"
        case .wants:
            return wantsCategories.first(where: { $0.id == expense.categoryId })?.name ?? "Wants"
        }
    }

    func savingsGoalName(for entry: SavingsEntry) -> String {
        savingsGoals.first(where: { $0.id == entry.goalId })?.displayName ?? "Savings"
    }

    func removeExpenses(for categoryId: UUID) {
        expenses.removeAll { $0.categoryId == categoryId }
    }

    func applyMonthlyAllocations(for date: Date) {
        let key = Self.monthKey(for: date)
        let previousKey = Self.monthKey(for: Calendar.current.date(byAdding: .month, value: -1, to: date) ?? date)

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
    }

    func removeAllocation(for categoryId: UUID, section: BudgetSection) {
        switch section {
        case .needs:
            for key in Array(needsAllocationsByMonth.keys) {
                needsAllocationsByMonth[key]?[categoryId] = nil
            }
        case .wants:
            for key in Array(wantsAllocationsByMonth.keys) {
                wantsAllocationsByMonth[key]?[categoryId] = nil
            }
        }
    }

    func addSavingsEntry(_ entry: SavingsEntry) {
        savingsEntries.append(entry)
        adjustSavingsGoalBalance(for: entry.goalId, delta: entry.amount)
    }

    func updateSavingsEntry(_ updatedEntry: SavingsEntry) {
        guard let index = savingsEntries.firstIndex(where: { $0.id == updatedEntry.id }) else { return }
        let previousEntry = savingsEntries[index]
        savingsEntries[index] = updatedEntry

        if previousEntry.goalId == updatedEntry.goalId {
            adjustSavingsGoalBalance(for: updatedEntry.goalId, delta: updatedEntry.amount - previousEntry.amount)
        } else {
            adjustSavingsGoalBalance(for: previousEntry.goalId, delta: -previousEntry.amount)
            adjustSavingsGoalBalance(for: updatedEntry.goalId, delta: updatedEntry.amount)
        }
    }

    func deleteSavingsEntry(id: UUID) {
        guard let index = savingsEntries.firstIndex(where: { $0.id == id }) else { return }
        let removedEntry = savingsEntries.remove(at: index)
        adjustSavingsGoalBalance(for: removedEntry.goalId, delta: -removedEntry.amount)
    }

    func removeSavingsGoal(id: UUID) {
        savingsGoals.removeAll { $0.id == id }
        savingsEntries.removeAll { $0.goalId == id }
    }

    func income(for date: Date) -> Double {
        incomeByMonth[Self.monthKey(for: date)] ?? 0
    }

    func setIncome(_ value: Double, for date: Date) {
        incomeByMonth[Self.monthKey(for: date)] = value
    }

    static func monthKey(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    private func recalculateSpent() {
        guard !expenses.isEmpty else {
            for index in needsCategories.indices {
                needsCategories[index].spentAmount = 0
            }
            for index in wantsCategories.indices {
                wantsCategories[index].spentAmount = 0
            }
            return
        }

        var needsTotals: [UUID: Double] = [:]
        var wantsTotals: [UUID: Double] = [:]

        for expense in expenses {
            switch expense.section {
            case .needs:
                needsTotals[expense.categoryId, default: 0] += expense.amount
            case .wants:
                wantsTotals[expense.categoryId, default: 0] += expense.amount
            }
        }

        for index in needsCategories.indices {
            let id = needsCategories[index].id
            needsCategories[index].spentAmount = needsTotals[id, default: 0]
        }

        for index in wantsCategories.indices {
            let id = wantsCategories[index].id
            wantsCategories[index].spentAmount = wantsTotals[id, default: 0]
        }
    }

    private func adjustSavingsGoalBalance(for goalId: UUID, delta: Double) {
        guard let index = savingsGoals.firstIndex(where: { $0.id == goalId }) else { return }
        let updatedAmount = savingsGoals[index].currentAmount + delta
        savingsGoals[index].currentAmount = max(updatedAmount, 0)
    }
}
