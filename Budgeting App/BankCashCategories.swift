import SwiftUI
import Combine

struct BankCashCategory: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let accountKey: String
    var name: String
    var allocatedAmount: Double
    var targetAmount: Double
    let createdAt: Date

    init(
        id: UUID = UUID(),
        accountKey: String,
        name: String,
        allocatedAmount: Double = 0,
        targetAmount: Double = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountKey = accountKey
        self.name = name
        self.allocatedAmount = max(allocatedAmount, 0)
        self.targetAmount = max(targetAmount, 0)
        self.createdAt = createdAt
    }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(max(allocatedAmount / targetAmount, 0), 1)
    }
}

@MainActor
final class BankCashCategoryStore: ObservableObject {
    @Published private(set) var categories: [BankCashCategory] = []

    private let defaults: UserDefaults
    private let storageKey = "bankCashCategories.v1"

    init() {
        defaults = UserDefaults(suiteName: BudgetModel.appGroupIdentifier) ?? .standard
        load()
    }

    func categories(for accountKey: String) -> [BankCashCategory] {
        categories
            .filter { $0.accountKey == accountKey }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.createdAt < $1.createdAt
            }
    }

    func totalAllocated(for accountKey: String, excluding excludedId: UUID? = nil) -> Double {
        categories
            .filter { $0.accountKey == accountKey && $0.id != excludedId }
            .reduce(0) { $0 + $1.allocatedAmount }
    }

    func upsert(_ category: BankCashCategory) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
        persist()
    }

    func delete(id: UUID) {
        categories.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([BankCashCategory].self, from: data) else {
            categories = []
            return
        }
        categories = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct BankCashCategoriesSection: View {
    @ObservedObject var store: BankCashCategoryStore
    let accountKey: String
    let accountBalance: Double
    let onAdd: () -> Void
    let onEdit: (BankCashCategory) -> Void

    private var categories: [BankCashCategory] {
        store.categories(for: accountKey)
    }

    private var totalAllocated: Double {
        store.totalAllocated(for: accountKey)
    }

    private var unallocated: Double {
        accountBalance - totalAllocated
    }

    var body: some View {
        Section {
            if categories.isEmpty {
                Button(action: onAdd) {
                    Label("Create a cash category", systemImage: "plus.circle")
                }
            } else {
                ForEach(categories) { category in
                    Button {
                        onEdit(category)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if category.targetAmount > 0 {
                                        Text("Target \(category.targetAmount, format: .currency(code: "USD"))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Momo's Money category")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(category.allocatedAmount, format: .currency(code: "USD"))
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }

                            if category.targetAmount > 0 {
                                ProgressView(value: category.progress)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Label(unallocated >= 0 ? "Unallocated" : "Overallocated", systemImage: unallocated >= 0 ? "circle.dashed" : "exclamationmark.triangle.fill")
                    .foregroundStyle(unallocated >= 0 ? Color.primary : Color.red)
                Spacer()
                Text(unallocated, format: .currency(code: "USD"))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(unallocated >= 0 ? Color.primary : Color.red)
            }

            if unallocated < -0.005 {
                Text("Your Plaid balance is now lower than the money assigned to categories. Reduce one or more category balances to resolve the over-allocation.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            HStack {
                Text("Cash Categories")
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add cash category")
            }
        } footer: {
            Text("These categories are stored in Momo's Money. Wealthfront does not expose its native Cash Category names or balances through Plaid, so the bank balance above remains the source of truth.")
        }
    }
}

struct BankCashCategoryEditorView: View {
    @ObservedObject var store: BankCashCategoryStore
    let accountKey: String
    let accountName: String
    let accountBalance: Double
    let existingCategory: BankCashCategory?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var allocatedAmount: Double
    @State private var targetAmount: Double

    init(
        store: BankCashCategoryStore,
        accountKey: String,
        accountName: String,
        accountBalance: Double,
        existingCategory: BankCashCategory? = nil
    ) {
        self.store = store
        self.accountKey = accountKey
        self.accountName = accountName
        self.accountBalance = accountBalance
        self.existingCategory = existingCategory
        _name = State(initialValue: existingCategory?.name ?? "")
        _allocatedAmount = State(initialValue: existingCategory?.allocatedAmount ?? 0)
        _targetAmount = State(initialValue: existingCategory?.targetAmount ?? 0)
    }

    private var otherAllocated: Double {
        store.totalAllocated(for: accountKey, excluding: existingCategory?.id)
    }

    private var maximumAllocation: Double {
        max(accountBalance - otherAllocated, 0)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            allocatedAmount >= 0 &&
            allocatedAmount <= maximumAllocation + 0.005 &&
            targetAmount >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Name", text: $name)
                    TextField("Allocated", value: $allocatedAmount, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                    TextField("Target (optional)", value: $targetAmount, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                }

                Section("Account") {
                    LabeledContent("Bank account", value: accountName)
                    LabeledContent("Account balance") {
                        Text(accountBalance, format: .currency(code: "USD"))
                    }
                    LabeledContent("Available to assign") {
                        Text(maximumAllocation, format: .currency(code: "USD"))
                    }
                }

                if allocatedAmount > maximumAllocation + 0.005 {
                    Section {
                        Text("This category would make your category allocations exceed the bank account balance.")
                            .foregroundStyle(.red)
                    }
                }

                if existingCategory != nil {
                    Section {
                        Button("Delete Category", role: .destructive) {
                            if let existingCategory {
                                store.delete(id: existingCategory.id)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingCategory == nil ? "New Cash Category" : "Edit Cash Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let category = BankCashCategory(
                            id: existingCategory?.id ?? UUID(),
                            accountKey: accountKey,
                            name: trimmedName,
                            allocatedAmount: (allocatedAmount * 100).rounded() / 100,
                            targetAmount: (targetAmount * 100).rounded() / 100,
                            createdAt: existingCategory?.createdAt ?? Date()
                        )
                        store.upsert(category)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
