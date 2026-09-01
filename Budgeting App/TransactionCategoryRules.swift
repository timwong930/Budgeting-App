import Foundation

struct PersistentTransactionCategoryRule: Codable, Sendable, Equatable {
    var section: BudgetSection
    var categoryId: UUID
    var updatedAt: Date
}

enum TransactionCategoryRuleStore {
    private static let storageKey = "transactionCategoryRules.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: BudgetModel.appGroupIdentifier) ?? .standard
    }

    static func rule(for name: String) -> PersistentTransactionCategoryRule? {
        let key = normalizedKey(name)
        guard !key.isEmpty else { return nil }
        return load()[key]
    }

    static func remember(
        names: [String],
        section: BudgetSection,
        categoryId: UUID
    ) {
        let keys = Set(names.map(normalizedKey).filter { !$0.isEmpty })
        guard !keys.isEmpty else { return }

        var rules = load()
        let rule = PersistentTransactionCategoryRule(
            section: section,
            categoryId: categoryId,
            updatedAt: Date()
        )
        for key in keys {
            rules[key] = rule
        }
        save(rules)
    }

    static func removeRule(for name: String) {
        let key = normalizedKey(name)
        guard !key.isEmpty else { return }
        var rules = load()
        rules[key] = nil
        save(rules)
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func load() -> [String: PersistentTransactionCategoryRule] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: PersistentTransactionCategoryRule].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func save(_ rules: [String: PersistentTransactionCategoryRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

extension BudgetModel {
    func rememberPersistentCategoryRule(for expense: Expense, aliases: [String] = []) {
        guard expense.plaidMetadata?.transactionId != nil else { return }
        TransactionCategoryRuleStore.remember(
            names: [expense.name] + aliases,
            section: expense.section,
            categoryId: expense.categoryId
        )
    }

    func persistentCategoryAssignment(
        for transaction: PlaidSyncedTransaction
    ) -> (section: BudgetSection, categoryId: UUID)? {
        let displayName = transaction.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? transaction.merchantName!
            : transaction.name
        guard let rule = TransactionCategoryRuleStore.rule(for: displayName) else { return nil }

        switch rule.section {
        case .needs:
            guard needsCategories.contains(where: { $0.id == rule.categoryId }) else {
                TransactionCategoryRuleStore.removeRule(for: displayName)
                return nil
            }
        case .wants:
            guard wantsCategories.contains(where: { $0.id == rule.categoryId }) else {
                TransactionCategoryRuleStore.removeRule(for: displayName)
                return nil
            }
        }
        return (rule.section, rule.categoryId)
    }
}
