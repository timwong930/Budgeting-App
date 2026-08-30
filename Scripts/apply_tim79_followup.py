from pathlib import Path

MODELS = Path("Budgeting App/Models.swift")
TESTS = Path("Budgeting AppTests/CuanMarketModelsTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


models = MODELS.read_text()

# Plaid-authoritative portfolio rows must not participate in the legacy manual ledger.
models = replace_once(models,
'''    var marginUsedFromLedger: Double {
        portfolioTransactions.reduce(0) { partial, tx in
''',
'''    var marginUsedFromLedger: Double {
        portfolioTransactions
            .filter { !isPlaidAuthoritativePortfolioAccount($0.portfolioAccountId) }
            .reduce(0) { partial, tx in
''', "margin ledger filter")

models = replace_once(models,
'''        let ordered = portfolioTransactions.sorted { $0.date < $1.date }
''',
'''        let ordered = portfolioTransactions
            .filter { !isPlaidAuthoritativePortfolioAccount($0.portfolioAccountId) }
            .sorted { $0.date < $1.date }
''', "holding ledger filter")

models = replace_once(models,
'''                nextExDividendDate: holdings.first(where: { $0.ticker.uppercased() == ticker })?.nextExDividendDate,
                nextPayDate: holdings.first(where: { $0.ticker.uppercased() == ticker })?.nextPayDate
''',
'''                nextExDividendDate: holdings.first(where: { $0.ticker.uppercased() == ticker })?.nextExDividendDate,
                nextPayDate: holdings.first(where: { $0.ticker.uppercased() == ticker })?.nextPayDate,
                portfolioAccountId: resolvePortfolioAccountId(metadata: nil)
''', "derived holding account ref")

models = replace_once(models,
'''        portfolioTransactions.append(transaction)
        if affectsBalances {
            applyCashImpact(for: transaction)
        }
        roundPortfolioCashBalance()
        synchronizeLegacyMarginStateFromLedger()
        recordPortfolioValueHistory()
    }

    func updatePortfolioTransaction(_ updatedTransaction: PortfolioTransaction) {
        guard let index = portfolioTransactions.firstIndex(where: { $0.id == updatedTransaction.id }) else { return }
        let previousTransaction = portfolioTransactions[index]
        reverseEditableCashImpact(for: previousTransaction)
        portfolioTransactions[index] = updatedTransaction
        applyEditableCashImpact(for: updatedTransaction)
        roundPortfolioCashBalance()
        synchronizeLegacyMarginStateFromLedger()
        recordPortfolioValueHistory()
    }

    func deletePortfolioTransaction(id: UUID) {
        guard let index = portfolioTransactions.firstIndex(where: { $0.id == id }) else { return }
        let removedTransaction = portfolioTransactions.remove(at: index)
        reverseEditableCashImpact(for: removedTransaction)
        roundPortfolioCashBalance()
        synchronizeLegacyMarginStateFromLedger()
        recordPortfolioValueHistory()
    }
''',
'''        if transaction.portfolioAccountId == nil {
            transaction.portfolioAccountId = resolvePortfolioAccountId(metadata: transaction.plaidMetadata)
        }
        if transaction.fundingBankAccountId == nil, let fundingName = transaction.fundingBankAccount {
            transaction.fundingBankAccountId = resolveFinancialAccountId(legacyName: fundingName, allowedKinds: [.depository])
        }
        portfolioTransactions.append(transaction)
        let isPlaidAuthoritative = isPlaidAuthoritativePortfolioAccount(transaction.portfolioAccountId)
        if affectsBalances && !isPlaidAuthoritative {
            applyCashImpact(for: transaction)
        }
        roundPortfolioCashBalance()
        if !isPlaidAuthoritative {
            synchronizeLegacyMarginStateFromLedger()
            recordPortfolioValueHistory()
        }
    }

    func updatePortfolioTransaction(_ updatedTransaction: PortfolioTransaction) {
        guard let index = portfolioTransactions.firstIndex(where: { $0.id == updatedTransaction.id }) else { return }
        let previousTransaction = portfolioTransactions[index]
        let previousIsPlaid = isPlaidAuthoritativePortfolioAccount(previousTransaction.portfolioAccountId)
        if !previousIsPlaid {
            reverseEditableCashImpact(for: previousTransaction)
        }

        var resolvedTransaction = updatedTransaction
        if resolvedTransaction.portfolioAccountId == nil {
            resolvedTransaction.portfolioAccountId = resolvePortfolioAccountId(metadata: resolvedTransaction.plaidMetadata)
        }
        if resolvedTransaction.fundingBankAccountId == nil, let fundingName = resolvedTransaction.fundingBankAccount {
            resolvedTransaction.fundingBankAccountId = resolveFinancialAccountId(legacyName: fundingName, allowedKinds: [.depository])
        }
        portfolioTransactions[index] = resolvedTransaction

        let updatedIsPlaid = isPlaidAuthoritativePortfolioAccount(resolvedTransaction.portfolioAccountId)
        if !updatedIsPlaid {
            applyEditableCashImpact(for: resolvedTransaction)
        }
        roundPortfolioCashBalance()
        if !previousIsPlaid || !updatedIsPlaid {
            synchronizeLegacyMarginStateFromLedger()
            recordPortfolioValueHistory()
        }
    }

    func deletePortfolioTransaction(id: UUID) {
        guard let index = portfolioTransactions.firstIndex(where: { $0.id == id }) else { return }
        let removedTransaction = portfolioTransactions.remove(at: index)
        let isPlaidAuthoritative = isPlaidAuthoritativePortfolioAccount(removedTransaction.portfolioAccountId)
        if !isPlaidAuthoritative {
            reverseEditableCashImpact(for: removedTransaction)
        }
        roundPortfolioCashBalance()
        if !isPlaidAuthoritative {
            synchronizeLegacyMarginStateFromLedger()
            recordPortfolioValueHistory()
        }
    }
''', "portfolio mutation UUID/Plaid guard")

models = replace_once(models,
'''        case .contribution:
            applyBankAccountDelta(named: transaction.fundingBankAccount ?? "", delta: -amount)
''',
'''        case .contribution:
            applyBankAccountDelta(
                accountId: transaction.fundingBankAccountId,
                legacyName: transaction.fundingBankAccount ?? "",
                delta: -amount
            )
''', "portfolio contribution debit")

models = replace_once(models,
'''        case .contribution:
            applyBankAccountDelta(named: transaction.fundingBankAccount ?? "", delta: amount)
''',
'''        case .contribution:
            applyBankAccountDelta(
                accountId: transaction.fundingBankAccountId,
                legacyName: transaction.fundingBankAccount ?? "",
                delta: amount
            )
''', "portfolio contribution reversal")

models = replace_once(models,
'''        let derivedHoldings = holdingsFromTransactions
        if !derivedHoldings.isEmpty || !portfolioTransactions.isEmpty {
            holdings = derivedHoldings
            portfolioSnapshot.marginUsed = max(marginUsedFromLedger, 0)
        }
''',
'''        let legacyTransactions = portfolioTransactions.filter { !isPlaidAuthoritativePortfolioAccount($0.portfolioAccountId) }
        let derivedHoldings = holdingsFromTransactions
        if !derivedHoldings.isEmpty || !legacyTransactions.isEmpty {
            holdings = derivedHoldings
            portfolioSnapshot.marginUsed = max(marginUsedFromLedger, 0)
        }
''', "legacy synchronization filter")

# Credit-card balances and payment targets use the stable UUID first, with name fallback only for legacy rows.
models = replace_once(models,
'''        let normalizedName = normalizedAccountName(account.name)
        guard !normalizedName.isEmpty else { return 0 }
        return expenses.reduce(account.startingBalance) { partial, expense in
            if let paidCard = creditCardPaymentTarget(for: expense),
               paidCard.caseInsensitiveCompare(account.name) == .orderedSame {
                return partial - expense.amount
            }
            let paymentAccount = normalizedAccountName(expense.paymentAccount)
            guard paymentAccount == normalizedName else { return partial }
            return partial + expense.amount
        }
''',
'''        let normalizedName = normalizedAccountName(account.name)
        guard !normalizedName.isEmpty else { return 0 }
        let stableAccountId = financialAccountId(for: account)
        return expenses.reduce(account.startingBalance) { partial, expense in
            if let targetId = expense.creditCardPaymentTargetId {
                if targetId == stableAccountId {
                    return partial - expense.amount
                }
            } else if let paidCard = creditCardPaymentTarget(for: expense),
                      paidCard.caseInsensitiveCompare(account.name) == .orderedSame {
                return partial - expense.amount
            }

            if let paymentAccountId = expense.paymentAccountId {
                guard paymentAccountId == stableAccountId else { return partial }
            } else {
                let paymentAccount = normalizedAccountName(expense.paymentAccount)
                guard paymentAccount == normalizedName else { return partial }
            }
            return partial + expense.amount
        }
''', "credit balance UUID lookup")

models = replace_once(models,
'''    func creditCardPaymentTarget(for expense: Expense) -> String? {
        if let target = expense.creditCardPaymentTarget?.trimmingCharacters(in: .whitespacesAndNewlines),
''',
'''    func creditCardPaymentTarget(for expense: Expense) -> String? {
        if let targetId = expense.creditCardPaymentTargetId,
           let account = financialAccounts.first(where: { $0.id == targetId }) {
            return account.name
        }
        if let target = expense.creditCardPaymentTarget?.trimmingCharacters(in: .whitespacesAndNewlines),
''', "credit target display lookup")

# Helpers for credit UUID matching and Plaid portfolio authority.
models = replace_once(models,
'''    private func normalizedAccountName(_ name: String) -> String {
''',
'''    private func financialAccountId(for creditAccount: CreditAccount) -> UUID? {
        if let externalId = creditAccount.plaidMetadata?.accountId,
           let financialAccount = financialAccounts.first(where: { $0.externalAccountId == externalId && $0.kind == .credit }) {
            return financialAccount.id
        }
        if financialAccounts.contains(where: { $0.id == creditAccount.id && $0.kind == .credit }) {
            return creditAccount.id
        }
        let normalized = normalizedAccountName(creditAccount.name)
        let matches = financialAccounts.filter { $0.kind == .credit && normalizedAccountName($0.name) == normalized }
        return matches.count == 1 ? matches[0].id : nil
    }

    private func isPlaidAuthoritativePortfolioAccount(_ portfolioAccountId: UUID?) -> Bool {
        guard let portfolioAccountId,
              let portfolioAccount = portfolioAccounts.first(where: { $0.id == portfolioAccountId }),
              let financialAccountId = portfolioAccount.financialAccountId,
              let financialAccount = financialAccounts.first(where: { $0.id == financialAccountId }) else {
            return false
        }
        return financialAccount.source == .plaid
    }

    private func normalizedAccountName(_ name: String) -> String {
''', "account identity helpers")

MODELS.write_text(models)

# Regression tests: legacy-name migration across every referenced record, plus credit rename behavior.
tests = TESTS.read_text()
tests = replace_once(tests,
'''        testLegacyAccountsMigrateToStableAccountDomain()
        testStableAccountUUIDSurvivesRename()
        testManualLedgerDoesNotMutatePlaidBalance()
''',
'''        testLegacyAccountsMigrateToStableAccountDomain()
        testLegacyLedgerReferencesMigrateToUUIDs()
        testStableAccountUUIDSurvivesRename()
        testStableCreditUUIDSurvivesRename()
        testManualLedgerDoesNotMutatePlaidBalance()
''', "register follow-up tests")

new_tests = r'''

    private static func testLegacyLedgerReferencesMigrateToUUIDs() {
        let checkingId = UUID()
        let savingsId = UUID()
        let creditId = UUID()
        let investmentFinancialId = UUID()
        let portfolioId = UUID()
        let categoryId = UUID()
        let budget = BudgetModel()
        budget.financialAccounts = [
            FinancialAccount(id: checkingId, name: "Checking", kind: .depository),
            FinancialAccount(id: savingsId, name: "Savings", kind: .depository),
            FinancialAccount(id: creditId, name: "Card", kind: .credit),
            FinancialAccount(id: investmentFinancialId, name: "Brokerage", kind: .investment)
        ]
        budget.bankAccounts = [
            BankAccount(id: checkingId, name: "Checking", balance: 500),
            BankAccount(id: savingsId, name: "Savings", balance: 100)
        ]
        budget.creditAccounts = [CreditAccount(id: creditId, name: "Card", dueDay: 15)]
        budget.portfolioAccounts = [PortfolioAccount(id: portfolioId, financialAccountId: investmentFinancialId, name: "Brokerage")]
        budget.incomes = [IncomeEntry(name: "Paycheck", amount: 100, bankName: "Checking")]
        budget.expenses = [Expense(name: "Groceries", amount: 25, section: .needs, categoryId: categoryId, paymentAccount: "Checking")]
        budget.cashTransfers = [CashTransfer(name: "Move", amount: 20, fromAccountName: "Checking", toAccountName: "Savings")]
        budget.portfolioTransactions = [PortfolioTransaction(type: .contribution, amount: 50, fundingBankAccount: "Checking")]
        budget.holdings = [PortfolioHolding(ticker: "AAPL", shares: 1, averageCost: 100, currentPrice: 180)]

        budget.migrateLegacyAccountsIfNeeded()

        assert(budget.incomes[0].bankAccountId == checkingId, "Expected legacy income bank name to migrate to UUID")
        assert(budget.expenses[0].paymentAccountId == checkingId, "Expected legacy expense payment account to migrate to UUID")
        assert(budget.cashTransfers[0].fromAccountId == checkingId, "Expected transfer source to migrate to UUID")
        assert(budget.cashTransfers[0].toAccountId == savingsId, "Expected transfer destination to migrate to UUID")
        assert(budget.portfolioTransactions[0].portfolioAccountId == portfolioId, "Expected portfolio transaction to link to stable portfolio UUID")
        assert(budget.portfolioTransactions[0].fundingBankAccountId == checkingId, "Expected portfolio funding bank to migrate to UUID")
        assert(budget.holdings[0].portfolioAccountId == portfolioId, "Expected holding to link to stable portfolio UUID")
    }

    private static func testStableCreditUUIDSurvivesRename() {
        let cardId = UUID()
        let categoryId = UUID()
        let budget = BudgetModel()
        budget.financialAccounts = [FinancialAccount(id: cardId, name: "Card", kind: .credit)]
        budget.creditAccounts = [CreditAccount(id: cardId, name: "Card", dueDay: 15, startingBalance: 100)]
        budget.expenses = [
            Expense(name: "Purchase", amount: 25, section: .needs, categoryId: categoryId, paymentAccount: "Card", paymentAccountId: cardId)
        ]
        assert(budget.creditAccountActualBalance(budget.creditAccounts[0]) == 125, "Expected expense to count against card by UUID")

        budget.creditAccounts[0].name = "Travel Card"
        budget.financialAccounts[0].name = "Travel Card"
        assert(budget.creditAccountActualBalance(budget.creditAccounts[0]) == 125, "Expected card rename not to break UUID-linked expense")
    }
'''
marker = "\n    private static func testStableAccountUUIDSurvivesRename() {"
if marker not in tests:
    raise RuntimeError("test insertion marker missing")
tests = tests.replace(marker, new_tests + marker, 1)

# Existing legacy JSON test should explicitly verify UUID fields default to nil.
tests = replace_once(tests,
'''        assert(expense.plaidMetadata == nil, "Expected legacy expense JSON without Plaid metadata to decode")
''',
'''        assert(expense.plaidMetadata == nil, "Expected legacy expense JSON without Plaid metadata to decode")
        assert(expense.paymentAccountId == nil, "Expected legacy expense without account UUID to remain readable")
        assert(expense.creditCardPaymentTargetId == nil, "Expected legacy credit-card UUID to default to nil")
''', "legacy expense UUID assertions")
TESTS.write_text(tests)

final_models = MODELS.read_text()
if "applyBankAccountDelta(named:" in final_models:
    raise RuntimeError("legacy name-only bank balance mutation helper remains")
for token in [
    "financialAccountId(for creditAccount:",
    "isPlaidAuthoritativePortfolioAccount",
    ".filter { !isPlaidAuthoritativePortfolioAccount($0.portfolioAccountId) }",
    "portfolioAccountId: resolvePortfolioAccountId(metadata: nil)",
]:
    if token not in final_models:
        raise RuntimeError(f"missing follow-up token: {token}")
print("TIM-79 follow-up checks passed")
