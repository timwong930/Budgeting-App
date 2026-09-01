from pathlib import Path

path = Path('Budgeting App/PlaidSyncEngine.swift')
text = path.read_text()

old = '''        for account in payload.accounts {
            accountNamesById[account.id] = account.name
            accountTypesById[account.id] = account.type
            upsertPlaidFinancialAccount(account, syncedAt: now)
            switch account.type {
            case .depository:
                upsertPlaidBankAccount(account, syncedAt: now)
                result.updatedAccounts += 1
            case .credit:
                let liability = payload.creditLiabilities.first { $0.accountId == account.id }
                upsertPlaidCreditAccount(account, liability: liability, syncedAt: now)
'''
new = '''        for account in payload.accounts {
            let displayName = localDisplayName(for: account) ?? account.name
            accountNamesById[account.id] = displayName
            accountTypesById[account.id] = account.type
            upsertPlaidFinancialAccount(account, displayName: displayName, syncedAt: now)
            switch account.type {
            case .depository:
                upsertPlaidBankAccount(account, displayName: displayName, syncedAt: now)
                result.updatedAccounts += 1
            case .credit:
                let liability = payload.creditLiabilities.first { $0.accountId == account.id }
                upsertPlaidCreditAccount(account, displayName: displayName, liability: liability, syncedAt: now)
'''
if text.count(old) != 1:
    raise SystemExit(f'account loop anchor count: {text.count(old)}')
text = text.replace(old, new, 1)

old = '''private extension BudgetModel {
    func upsertPlaidFinancialAccount(_ account: PlaidSyncedAccount, syncedAt: Date) {
'''
new = '''private extension BudgetModel {
    func localDisplayName(for account: PlaidSyncedAccount) -> String? {
        let candidate: String?
        switch account.type {
        case .depository:
            candidate = bankAccounts.first(where: { $0.plaidMetadata?.accountId == account.id })?.name
                ?? financialAccounts.first(where: { $0.externalAccountId == account.id })?.name
        case .credit:
            candidate = creditAccounts.first(where: { $0.plaidMetadata?.accountId == account.id })?.name
                ?? financialAccounts.first(where: { $0.externalAccountId == account.id })?.name
        case .investment:
            if let financialAccount = financialAccounts.first(where: { $0.externalAccountId == account.id }) {
                candidate = portfolioAccounts.first(where: { $0.financialAccountId == financialAccount.id })?.name
                    ?? financialAccount.name
            } else {
                candidate = nil
            }
        case .loan, .other:
            candidate = financialAccounts.first(where: { $0.externalAccountId == account.id })?.name
        }

        guard let candidate else { return nil }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : candidate
    }

    func upsertPlaidFinancialAccount(_ account: PlaidSyncedAccount, displayName: String, syncedAt: Date) {
'''
if text.count(old) != 1:
    raise SystemExit(f'financial upsert anchor count: {text.count(old)}')
text = text.replace(old, new, 1)

replacements = [
    ('            financialAccounts[index].name = account.name\n', '            financialAccounts[index].name = displayName\n', 1),
    ('                name: account.name,\n                institutionName: account.institutionName,\n                kind: kind,\n', '                name: displayName,\n                institutionName: account.institutionName,\n                kind: kind,\n', 1),
    ('    func upsertPlaidBankAccount(_ account: PlaidSyncedAccount, syncedAt: Date) {\n', '    func upsertPlaidBankAccount(_ account: PlaidSyncedAccount, displayName: String, syncedAt: Date) {\n', 1),
    ('            bankAccounts[index].name = account.name\n', '            bankAccounts[index].name = displayName\n', 1),
    ('                BankAccount(\n                    name: account.name,\n', '                BankAccount(\n                    name: displayName,\n', 1),
    ('    func upsertPlaidCreditAccount(_ account: PlaidSyncedAccount, liability: PlaidSyncedCreditLiability?, syncedAt: Date) {\n', '    func upsertPlaidCreditAccount(_ account: PlaidSyncedAccount, displayName: String, liability: PlaidSyncedCreditLiability?, syncedAt: Date) {\n', 1),
    ('            creditAccounts[index].name = account.name\n', '            creditAccounts[index].name = displayName\n', 1),
    ('                CreditAccount(\n                    name: account.name,\n', '                CreditAccount(\n                    name: displayName,\n', 1),
]
for old, new, expected in replacements:
    if text.count(old) < expected:
        raise SystemExit(f'missing replacement anchor: {old[:70]!r}')
    text = text.replace(old, new, expected)

path.write_text(text)
