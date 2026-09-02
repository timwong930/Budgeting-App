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

        if let rule = TransactionCategoryRuleStore.rule(for: displayName) {
            switch rule.section {
            case .needs:
                if needsCategories.contains(where: { $0.id == rule.categoryId }) {
                    return (rule.section, rule.categoryId)
                }
            case .wants:
                if wantsCategories.contains(where: { $0.id == rule.categoryId }) {
                    return (rule.section, rule.categoryId)
                }
            }
            TransactionCategoryRuleStore.removeRule(for: displayName)
        }

        return uncategorizedCategoryAssignment(for: transaction)
    }

    private func uncategorizedCategoryAssignment(
        for transaction: PlaidSyncedTransaction
    ) -> (section: BudgetSection, categoryId: UUID) {
        let plaidCategory = (transaction.category ?? "").lowercased()
        let section: BudgetSection = (
            plaidCategory.contains("travel") ||
            plaidCategory.contains("entertainment") ||
            plaidCategory.contains("recreation") ||
            plaidCategory.contains("shops")
        ) ? .wants : .needs

        switch section {
        case .needs:
            if let existing = needsCategories.first(where: { $0.name.caseInsensitiveCompare("Uncategorized") == .orderedSame }) {
                return (.needs, existing.id)
            }
            if let legacyIndex = needsCategories.firstIndex(where: { $0.name.caseInsensitiveCompare("Plaid Needs") == .orderedSame }) {
                needsCategories[legacyIndex].name = "Uncategorized"
                return (.needs, needsCategories[legacyIndex].id)
            }
            let category = Category(name: "Uncategorized", allocatedAmount: 0)
            needsCategories.append(category)
            return (.needs, category.id)

        case .wants:
            if let existing = wantsCategories.first(where: { $0.name.caseInsensitiveCompare("Uncategorized") == .orderedSame }) {
                return (.wants, existing.id)
            }
            if let legacyIndex = wantsCategories.firstIndex(where: { $0.name.caseInsensitiveCompare("Plaid Wants") == .orderedSame }) {
                wantsCategories[legacyIndex].name = "Uncategorized"
                return (.wants, wantsCategories[legacyIndex].id)
            }
            let category = Category(name: "Uncategorized", allocatedAmount: 0)
            wantsCategories.append(category)
            return (.wants, category.id)
        }
    }
}
