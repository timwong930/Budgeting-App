from pathlib import Path

engine_path = Path('Budgeting App/PlaidSyncEngine.swift')
engine = engine_path.read_text()

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
if old not in engine:
    raise SystemExit('applyPlaidSync account loop anchor not found')
engine = engine.replace(old, new, 1)

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
if old not in engine:
    raise SystemExit('private extension anchor not found')
engine = engine.replace(old, new, 1)

engine = engine.replace('            financialAccounts[index].name = account.name\n', '            financialAccounts[index].name = displayName\n', 1)
engine = engine.replace('''                name: account.name,
                institutionName: account.institutionName,
                kind: kind,
''', '''                name: displayName,
                institutionName: account.institutionName,
                kind: kind,
''', 1)
engine = engine.replace('    func upsertPlaidBankAccount(_ account: PlaidSyncedAccount, syncedAt: Date) {\n', '    func upsertPlaidBankAccount(_ account: PlaidSyncedAccount, displayName: String, syncedAt: Date) {\n', 1)
engine = engine.replace('            bankAccounts[index].name = account.name\n', '            bankAccounts[index].name = displayName\n', 1)
engine = engine.replace('''                BankAccount(
                    name: account.name,
''', '''                BankAccount(
                    name: displayName,
''', 1)
engine = engine.replace('    func upsertPlaidCreditAccount(_ account: PlaidSyncedAccount, liability: PlaidSyncedCreditLiability?, syncedAt: Date) {\n', '    func upsertPlaidCreditAccount(_ account: PlaidSyncedAccount, displayName: String, liability: PlaidSyncedCreditLiability?, syncedAt: Date) {\n', 1)
engine = engine.replace('            creditAccounts[index].name = account.name\n', '            creditAccounts[index].name = displayName\n', 1)
engine = engine.replace('''                CreditAccount(
                    name: account.name,
''', '''                CreditAccount(
                    name: displayName,
''', 1)
engine_path.write_text(engine)

tests_path = Path('Budgeting AppTests/CuanMarketModelsTests.swift')
tests = tests_path.read_text()
call_anchor = '        testPlaidCreditAccountUpdateUsesLiabilityFields()\n'
if call_anchor not in tests:
    raise SystemExit('test call anchor not found')
tests = tests.replace(call_anchor, call_anchor + '        testPlaidSyncPreservesUserRenamedAccountDisplayNames()\n', 1)

fn_anchor = '    private static func testPlaidHoldingsSnapshotPreservesTickerMetadata() {\n'
if fn_anchor not in tests:
    raise SystemExit('test function anchor not found')
new_test = '''    private static func testPlaidSyncPreservesUserRenamedAccountDisplayNames() {
        let budget = BudgetModel()
        let initialPayload = PlaidSyncPayload(
            accounts: [
                PlaidSyncedAccount(id: "bank-rename", itemId: "item-bank", name: "Plaid Checking", type: .depository, subtype: "checking", currentBalance: 1_000, availableBalance: 900, creditLimit: nil, institutionName: "Example Bank"),
                PlaidSyncedAccount(id: "card-rename", itemId: "item-card", name: "Plaid Credit", type: .credit, subtype: "credit card", currentBalance: 250, availableBalance: nil, creditLimit: 5_000, institutionName: "Example Card Bank")
            ],
            transactions: [],
            creditLiabilities: [
                PlaidSyncedCreditLiability(accountId: "card-rename", itemId: "item-card", minimumPaymentAmount: 30, nextPaymentDueDate: Date(timeIntervalSince1970: 1_780_500_000), lastStatementBalance: 200, lastStatementIssueDate: nil, aprPercentage: 20)
            ],
            holdings: [],
            investmentTransactions: [],
            connectionStatuses: []
        )
        _ = budget.applyPlaidSync(initialPayload)

        guard let bankIndex = budget.bankAccounts.firstIndex(where: { $0.plaidMetadata?.accountId == "bank-rename" }),
              let cardIndex = budget.creditAccounts.firstIndex(where: { $0.plaidMetadata?.accountId == "card-rename" }) else {
            assertionFailure("Expected Plaid accounts to exist before rename")
            return
        }

        budget.bankAccounts[bankIndex].name = "Emergency Cash"
        budget.creditAccounts[cardIndex].name = "Daily Card"

        let refreshedPayload = PlaidSyncPayload(
            accounts: [
                PlaidSyncedAccount(id: "bank-rename", itemId: "item-bank", name: "Plaid Checking", type: .depository, subtype: "checking", currentBalance: 1_250, availableBalance: 1_100, creditLimit: nil, institutionName: "Example Bank"),
                PlaidSyncedAccount(id: "card-rename", itemId: "item-card", name: "Plaid Credit", type: .credit, subtype: "credit card", currentBalance: 300, availableBalance: nil, creditLimit: 6_000, institutionName: "Example Card Bank")
            ],
            transactions: [],
            creditLiabilities: [
                PlaidSyncedCreditLiability(accountId: "card-rename", itemId: "item-card", minimumPaymentAmount: 40, nextPaymentDueDate: Date(timeIntervalSince1970: 1_781_000_000), lastStatementBalance: 275, lastStatementIssueDate: nil, aprPercentage: 20)
            ],
            holdings: [],
            investmentTransactions: [],
            connectionStatuses: []
        )
        _ = budget.applyPlaidSync(refreshedPayload)

        assert(budget.bankAccounts[bankIndex].name == "Emergency Cash", "Expected Plaid sync to preserve user-renamed bank display name")
        assert(budget.creditAccounts[cardIndex].name == "Daily Card", "Expected Plaid sync to preserve user-renamed credit-card display name")
        assert(budget.bankAccounts[bankIndex].balance == 1_250, "Expected Plaid bank balance to keep refreshing after rename")
        assert(budget.creditAccounts[cardIndex].startingBalance == 300, "Expected Plaid credit balance to keep refreshing after rename")
        assert(budget.creditAccounts[cardIndex].creditLimit == 6_000, "Expected Plaid credit limit to keep refreshing after rename")
        assert(budget.bankAccounts.filter { $0.plaidMetadata?.accountId == "bank-rename" }.count == 1, "Expected renamed bank account to stay deduplicated by Plaid account ID")
        assert(budget.creditAccounts.filter { $0.plaidMetadata?.accountId == "card-rename" }.count == 1, "Expected renamed credit account to stay deduplicated by Plaid account ID")
        assert(budget.financialAccounts.first(where: { $0.externalAccountId == "bank-rename" })?.name == "Emergency Cash", "Expected canonical bank account display name to follow the local rename")
        assert(budget.financialAccounts.first(where: { $0.externalAccountId == "card-rename" })?.name == "Daily Card", "Expected canonical credit account display name to follow the local rename")
    }

'''
tests = tests.replace(fn_anchor, new_test + fn_anchor, 1)
tests_path.write_text(tests)
