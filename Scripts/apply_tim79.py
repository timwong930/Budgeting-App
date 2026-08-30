from pathlib import Path

MODELS = Path("Budgeting App/Models.swift")
PLAID = Path("Budgeting App/PlaidSyncEngine.swift")
TESTS = Path("Budgeting AppTests/CuanMarketModelsTests.swift")
TASKS = Path("TASKS.md")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


models = MODELS.read_text()

# Expense stable refs.
models = replace_once(models,
"""    var paymentAccount: String
    var note: String
    var creditCardPaymentTarget: String?
    var plaidMetadata: PlaidSourceMetadata?
""",
"""    var paymentAccount: String
    var paymentAccountId: UUID?
    var note: String
    var creditCardPaymentTarget: String?
    var creditCardPaymentTargetId: UUID?
    var plaidMetadata: PlaidSourceMetadata?
""", "expense properties")
models = replace_once(models,
"""        paymentAccount: String = "",
        note: String = "",
        creditCardPaymentTarget: String? = nil,
        plaidMetadata: PlaidSourceMetadata? = nil
""",
"""        paymentAccount: String = "",
        paymentAccountId: UUID? = nil,
        note: String = "",
        creditCardPaymentTarget: String? = nil,
        creditCardPaymentTargetId: UUID? = nil,
        plaidMetadata: PlaidSourceMetadata? = nil
""", "expense init parameters")
models = replace_once(models,
"""        self.paymentAccount = paymentAccount
        self.note = note
        self.creditCardPaymentTarget = creditCardPaymentTarget
        self.plaidMetadata = plaidMetadata
""",
"""        self.paymentAccount = paymentAccount
        self.paymentAccountId = paymentAccountId
        self.note = note
        self.creditCardPaymentTarget = creditCardPaymentTarget
        self.creditCardPaymentTargetId = creditCardPaymentTargetId
        self.plaidMetadata = plaidMetadata
""", "expense init assignments")
models = replace_once(models,
"""        case paymentAccount
        case note
        case creditCardPaymentTarget
        case plaidMetadata
""",
"""        case paymentAccount
        case paymentAccountId
        case note
        case creditCardPaymentTarget
        case creditCardPaymentTargetId
        case plaidMetadata
""", "expense coding keys")
models = replace_once(models,
"""        paymentAccount = try container.decodeIfPresent(String.self, forKey: .paymentAccount) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        creditCardPaymentTarget = try container.decodeIfPresent(String.self, forKey: .creditCardPaymentTarget)
        plaidMetadata = try container.decodeIfPresent(PlaidSourceMetadata.self, forKey: .plaidMetadata)
""",
"""        paymentAccount = try container.decodeIfPresent(String.self, forKey: .paymentAccount) ?? ""
        paymentAccountId = try container.decodeIfPresent(UUID.self, forKey: .paymentAccountId)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        creditCardPaymentTarget = try container.decodeIfPresent(String.self, forKey: .creditCardPaymentTarget)
        creditCardPaymentTargetId = try container.decodeIfPresent(UUID.self, forKey: .creditCardPaymentTargetId)
        plaidMetadata = try container.decodeIfPresent(PlaidSourceMetadata.self, forKey: .plaidMetadata)
""", "expense decode")

# Cash transfer stable refs.
models = replace_once(models,
"""    var fromAccountName: String
    var toAccountName: String
    var note: String
""",
"""    var fromAccountName: String
    var toAccountName: String
    var fromAccountId: UUID?
    var toAccountId: UUID?
    var note: String
""", "transfer properties")
models = replace_once(models,
"""        fromAccountName: String,
        toAccountName: String,
        note: String = ""
""",
"""        fromAccountName: String,
        toAccountName: String,
        fromAccountId: UUID? = nil,
        toAccountId: UUID? = nil,
        note: String = ""
""", "transfer init")
models = replace_once(models,
"""        self.fromAccountName = fromAccountName
        self.toAccountName = toAccountName
        self.note = note
""",
"""        self.fromAccountName = fromAccountName
        self.toAccountName = toAccountName
        self.fromAccountId = fromAccountId
        self.toAccountId = toAccountId
        self.note = note
""", "transfer assignments")

# Income stable ref.
models = replace_once(models,
"""    var bankName: String
    var plaidMetadata: PlaidSourceMetadata?

    init(id: UUID = UUID(), name: String, amount: Double, date: Date = Date(), bankName: String = "", plaidMetadata: PlaidSourceMetadata? = nil) {
""",
"""    var bankName: String
    var bankAccountId: UUID?
    var plaidMetadata: PlaidSourceMetadata?

    init(id: UUID = UUID(), name: String, amount: Double, date: Date = Date(), bankName: String = "", bankAccountId: UUID? = nil, plaidMetadata: PlaidSourceMetadata? = nil) {
""", "income properties/init")
models = replace_once(models,
"""        self.bankName = bankName
        self.plaidMetadata = plaidMetadata
""",
"""        self.bankName = bankName
        self.bankAccountId = bankAccountId
        self.plaidMetadata = plaidMetadata
""", "income assignment")
models = replace_once(models,
"""        case bankName
        case plaidMetadata
""",
"""        case bankName
        case bankAccountId
        case plaidMetadata
""", "income coding keys")
models = replace_once(models,
"""        bankName = try container.decodeIfPresent(String.self, forKey: .bankName) ?? ""
        plaidMetadata = try container.decodeIfPresent(PlaidSourceMetadata.self, forKey: .plaidMetadata)
""",
"""        bankName = try container.decodeIfPresent(String.self, forKey: .bankName) ?? ""
        bankAccountId = try container.decodeIfPresent(UUID.self, forKey: .bankAccountId)
        plaidMetadata = try container.decodeIfPresent(PlaidSourceMetadata.self, forKey: .plaidMetadata)
""", "income decode")
models = replace_once(models,
"""        try container.encode(bankName, forKey: .bankName)
        try container.encodeIfPresent(plaidMetadata, forKey: .plaidMetadata)
""",
"""        try container.encode(bankName, forKey: .bankName)
        try container.encodeIfPresent(bankAccountId, forKey: .bankAccountId)
        try container.encodeIfPresent(plaidMetadata, forKey: .plaidMetadata)
""", "income encode")

# Portfolio transaction stable refs.
models = replace_once(models,
"""    var notes: String?
    var fundingBankAccount: String?
    var plaidMetadata: PlaidSourceMetadata?
""",
"""    var notes: String?
    var portfolioAccountId: UUID?
    var fundingBankAccount: String?
    var fundingBankAccountId: UUID?
    var plaidMetadata: PlaidSourceMetadata?
""", "portfolio transaction properties")
models = replace_once(models,
"""        amount: Double,
        notes: String? = nil,
        fundingBankAccount: String? = nil,
        plaidMetadata: PlaidSourceMetadata? = nil
""",
"""        amount: Double,
        notes: String? = nil,
        portfolioAccountId: UUID? = nil,
        fundingBankAccount: String? = nil,
        fundingBankAccountId: UUID? = nil,
        plaidMetadata: PlaidSourceMetadata? = nil
""", "portfolio transaction init")
models = replace_once(models,
"""        self.amount = amount
        self.notes = notes
        self.fundingBankAccount = fundingBankAccount
        self.plaidMetadata = plaidMetadata
""",
"""        self.amount = amount
        self.notes = notes
        self.portfolioAccountId = portfolioAccountId
        self.fundingBankAccount = fundingBankAccount
        self.fundingBankAccountId = fundingBankAccountId
        self.plaidMetadata = plaidMetadata
""", "portfolio transaction assignment")
models = replace_once(models,
"""        case amount
        case notes
        case fundingBankAccount
        case plaidMetadata
""",
"""        case amount
        case notes
        case portfolioAccountId
        case fundingBankAccount
        case fundingBankAccountId
        case plaidMetadata
""", "portfolio transaction coding keys")
models = replace_once(models,
"""        amount = try container.decode(Double.self, forKey: .amount)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        fundingBankAccount = try container.decodeIfPresent(String.self, forKey: .fundingBankAccount)
        plaidMetadata = try container.decodeIfPresent(PlaidSourceMetadata.self, forKey: .plaidMetadata)
""",
"""        amount = try container.decode(Double.self, forKey: .amount)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        portfolioAccountId = try container.decodeIfPresent(UUID.self, forKey: .portfolioAccountId)
        fundingBankAccount = try container.decodeIfPresent(String.self, forKey: .fundingBankAccount)
        fundingBankAccountId = try container.decodeIfPresent(UUID.self, forKey: .fundingBankAccountId)
        plaidMetadata = try container.decodeIfPresent(PlaidSourceMetadata.self, forKey: .plaidMetadata)
""", "portfolio transaction decode")
models = replace_once(models,
"""        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(fundingBankAccount, forKey: .fundingBankAccount)
        try container.encodeIfPresent(plaidMetadata, forKey: .plaidMetadata)
""",
"""        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(portfolioAccountId, forKey: .portfolioAccountId)
        try container.encodeIfPresent(fundingBankAccount, forKey: .fundingBankAccount)
        try container.encodeIfPresent(fundingBankAccountId, forKey: .fundingBankAccountId)
        try container.encodeIfPresent(plaidMetadata, forKey: .plaidMetadata)
""", "portfolio transaction encode")

# Holding stable ref.
models = replace_once(models,
"""    var nextExDividendDate: Date?
    var nextPayDate: Date?
    var plaidMetadata: PlaidSourceMetadata?
""",
"""    var nextExDividendDate: Date?
    var nextPayDate: Date?
    var portfolioAccountId: UUID?
    var plaidMetadata: PlaidSourceMetadata?
""", "holding properties")
models = replace_once(models,
"""        notes: String = "",
        nextExDividendDate: Date? = nil,
        nextPayDate: Date? = nil,
        plaidMetadata: PlaidSourceMetadata? = nil
""",
"""        notes: String = "",
        nextExDividendDate: Date? = nil,
        nextPayDate: Date? = nil,
        portfolioAccountId: UUID? = nil,
        plaidMetadata: PlaidSourceMetadata? = nil
""", "holding init")
models = replace_once(models,
"""        self.notes = notes
        self.nextExDividendDate = nextExDividendDate
        self.nextPayDate = nextPayDate
        self.plaidMetadata = plaidMetadata
""",
"""        self.notes = notes
        self.nextExDividendDate = nextExDividendDate
        self.nextPayDate = nextPayDate
        self.portfolioAccountId = portfolioAccountId
        self.plaidMetadata = plaidMetadata
""", "holding assignment")

# Add migration after legacy accounts are created.
needle = """        if hasLegacyPortfolio, portfolioAccounts.isEmpty {
            let plaidMetadata = holdings.compactMap(\\.plaidMetadata).first
            let source: FinancialAccountSource = plaidMetadata == nil ? .manual : .plaid
            let financialAccount = FinancialAccount(
                name: "Main Portfolio",
                kind: .investment,
                source: source,
                externalAccountId: plaidMetadata?.accountId,
                externalItemId: plaidMetadata?.itemId,
                lastSyncedAt: plaidMetadata?.lastSyncedAt
            )
            financialAccounts.append(financialAccount)
            portfolioAccounts.append(
                PortfolioAccount(
                    financialAccountId: financialAccount.id,
                    name: financialAccount.name,
                    cashBalance: portfolioSnapshot.cashBalance,
                    marginBalance: portfolioSnapshot.marginUsed
                )
            )
        }
    }

    private func hasFinancialAccount(id: UUID, metadata: PlaidSourceMetadata?) -> Bool {
"""
replacement = needle.replace("        }\n    }\n\n    private func hasFinancialAccount", "        }\n\n        migrateStableAccountReferencesIfNeeded()\n    }\n\n    private func migrateStableAccountReferencesIfNeeded() {\n        for index in incomes.indices where incomes[index].bankAccountId == nil {\n            incomes[index].bankAccountId = resolveFinancialAccountId(legacyName: incomes[index].bankName, allowedKinds: [.depository], metadata: incomes[index].plaidMetadata)\n        }\n        for index in expenses.indices {\n            if expenses[index].paymentAccountId == nil {\n                expenses[index].paymentAccountId = resolveFinancialAccountId(legacyName: expenses[index].paymentAccount, allowedKinds: [.depository, .credit], metadata: expenses[index].plaidMetadata)\n            }\n            if expenses[index].creditCardPaymentTargetId == nil, let target = creditCardPaymentTarget(for: expenses[index]) {\n                expenses[index].creditCardPaymentTargetId = resolveFinancialAccountId(legacyName: target, allowedKinds: [.credit])\n            }\n        }\n        for index in cashTransfers.indices {\n            if cashTransfers[index].fromAccountId == nil { cashTransfers[index].fromAccountId = resolveFinancialAccountId(legacyName: cashTransfers[index].fromAccountName, allowedKinds: [.depository]) }\n            if cashTransfers[index].toAccountId == nil { cashTransfers[index].toAccountId = resolveFinancialAccountId(legacyName: cashTransfers[index].toAccountName, allowedKinds: [.depository]) }\n        }\n        for index in portfolioTransactions.indices {\n            if portfolioTransactions[index].portfolioAccountId == nil { portfolioTransactions[index].portfolioAccountId = resolvePortfolioAccountId(metadata: portfolioTransactions[index].plaidMetadata) }\n            if portfolioTransactions[index].fundingBankAccountId == nil, let name = portfolioTransactions[index].fundingBankAccount { portfolioTransactions[index].fundingBankAccountId = resolveFinancialAccountId(legacyName: name, allowedKinds: [.depository]) }\n        }\n        for index in holdings.indices where holdings[index].portfolioAccountId == nil {\n            holdings[index].portfolioAccountId = resolvePortfolioAccountId(metadata: holdings[index].plaidMetadata)\n        }\n    }\n\n    private func resolveFinancialAccountId(legacyName: String, allowedKinds: [FinancialAccountKind], metadata: PlaidSourceMetadata? = nil) -> UUID? {\n        if let externalId = metadata?.accountId, let account = financialAccounts.first(where: { $0.externalAccountId == externalId && allowedKinds.contains($0.kind) }) { return account.id }\n        let normalized = normalizedAccountName(legacyName)\n        guard !normalized.isEmpty else { return nil }\n        let matches = financialAccounts.filter { allowedKinds.contains($0.kind) && normalizedAccountName($0.name) == normalized }\n        if matches.count == 1 { return matches[0].id }\n        if matches.count > 1 { return nil }\n        var candidates: [(UUID, String, FinancialAccountKind, PlaidSourceMetadata?)] = []\n        if allowedKinds.contains(.depository) { candidates += bankAccounts.filter { normalizedAccountName($0.name) == normalized }.map { ($0.id, $0.name, .depository, $0.plaidMetadata) } }\n        if allowedKinds.contains(.credit) { candidates += creditAccounts.filter { normalizedAccountName($0.name) == normalized }.map { ($0.id, $0.name, .credit, $0.plaidMetadata) } }\n        guard candidates.count == 1 else { return nil }\n        let candidate = candidates[0]\n        if !financialAccounts.contains(where: { $0.id == candidate.0 }) {\n            financialAccounts.append(FinancialAccount(id: candidate.0, name: candidate.1, institutionName: candidate.3?.institutionName, kind: candidate.2, source: candidate.3 == nil ? .manual : .plaid, externalAccountId: candidate.3?.accountId, externalItemId: candidate.3?.itemId, lastSyncedAt: candidate.3?.lastSyncedAt))\n        }\n        return candidate.0\n    }\n\n    private func resolvePortfolioAccountId(metadata: PlaidSourceMetadata?) -> UUID? {\n        if let externalId = metadata?.accountId, let financial = financialAccounts.first(where: { $0.externalAccountId == externalId }), let portfolio = portfolioAccounts.first(where: { $0.financialAccountId == financial.id }) { return portfolio.id }\n        let active = portfolioAccounts.filter(\\.isActive)\n        return active.count == 1 ? active[0].id : nil\n    }\n\n    private func hasFinancialAccount")
models = replace_once(models, needle, replacement, "migration helpers")

# Resolve refs on ledger writes.
models = replace_once(models,
"""    func addIncomeEntry(_ entry: IncomeEntry) {
        incomes.append(entry)
        applyBalanceImpact(for: entry, multiplier: 1)
    }

    func updateIncomeEntry(_ updatedEntry: IncomeEntry) {
        guard let index = incomes.firstIndex(where: { $0.id == updatedEntry.id }) else { return }
        let previousEntry = incomes[index]
        applyBalanceImpact(for: previousEntry, multiplier: -1)
        incomes[index] = updatedEntry
        applyBalanceImpact(for: updatedEntry, multiplier: 1)
    }
""",
"""    func addIncomeEntry(_ entry: IncomeEntry) {
        var resolved = entry
        if resolved.bankAccountId == nil { resolved.bankAccountId = resolveFinancialAccountId(legacyName: resolved.bankName, allowedKinds: [.depository], metadata: resolved.plaidMetadata) }
        incomes.append(resolved)
        applyBalanceImpact(for: resolved, multiplier: 1)
    }

    func updateIncomeEntry(_ updatedEntry: IncomeEntry) {
        guard let index = incomes.firstIndex(where: { $0.id == updatedEntry.id }) else { return }
        let previousEntry = incomes[index]
        applyBalanceImpact(for: previousEntry, multiplier: -1)
        var resolved = updatedEntry
        if resolved.bankAccountId == nil { resolved.bankAccountId = resolveFinancialAccountId(legacyName: resolved.bankName, allowedKinds: [.depository], metadata: resolved.plaidMetadata) }
        incomes[index] = resolved
        applyBalanceImpact(for: resolved, multiplier: 1)
    }
""", "income mutations")
models = replace_once(models,
"""    func addExpense(_ expense: Expense) {
        expenses.append(expense)
        applyBalanceImpact(for: expense, multiplier: 1)
    }

    func updateExpense(_ updatedExpense: Expense) {
        guard let index = expenses.firstIndex(where: { $0.id == updatedExpense.id }) else { return }
        let previousExpense = expenses[index]
        applyBalanceImpact(for: previousExpense, multiplier: -1)
        expenses[index] = updatedExpense
        applyBalanceImpact(for: updatedExpense, multiplier: 1)
    }
""",
"""    func addExpense(_ expense: Expense) {
        let resolved = resolvingAccountReferences(for: expense)
        expenses.append(resolved)
        applyBalanceImpact(for: resolved, multiplier: 1)
    }

    func updateExpense(_ updatedExpense: Expense) {
        guard let index = expenses.firstIndex(where: { $0.id == updatedExpense.id }) else { return }
        let previousExpense = expenses[index]
        applyBalanceImpact(for: previousExpense, multiplier: -1)
        let resolved = resolvingAccountReferences(for: updatedExpense)
        expenses[index] = resolved
        applyBalanceImpact(for: resolved, multiplier: 1)
    }
""", "expense mutations")
models = replace_once(models,
"""    func addCashTransfer(_ transfer: CashTransfer) {
        guard canApplyCashTransfer(transfer) else { return }
        cashTransfers.append(transfer)
        applyBalanceImpact(for: transfer, multiplier: 1)
    }

    func updateCashTransfer(_ updatedTransfer: CashTransfer) {
        guard canApplyCashTransfer(updatedTransfer),
              let index = cashTransfers.firstIndex(where: { $0.id == updatedTransfer.id }) else { return }
        let previousTransfer = cashTransfers[index]
        applyBalanceImpact(for: previousTransfer, multiplier: -1)
        cashTransfers[index] = updatedTransfer
        applyBalanceImpact(for: updatedTransfer, multiplier: 1)
    }
""",
"""    func addCashTransfer(_ transfer: CashTransfer) {
        let resolved = resolvingAccountReferences(for: transfer)
        guard canApplyCashTransfer(resolved) else { return }
        cashTransfers.append(resolved)
        applyBalanceImpact(for: resolved, multiplier: 1)
    }

    func updateCashTransfer(_ updatedTransfer: CashTransfer) {
        let resolved = resolvingAccountReferences(for: updatedTransfer)
        guard canApplyCashTransfer(resolved), let index = cashTransfers.firstIndex(where: { $0.id == resolved.id }) else { return }
        let previousTransfer = cashTransfers[index]
        applyBalanceImpact(for: previousTransfer, multiplier: -1)
        cashTransfers[index] = resolved
        applyBalanceImpact(for: resolved, multiplier: 1)
    }
""", "transfer mutations")

# UUID-first balance mutation + Plaid authority protection.
models = replace_once(models,
"""    private func applyBalanceImpact(for income: IncomeEntry, multiplier: Double) {
        applyBankAccountDelta(named: income.bankName, delta: income.amount * multiplier)
    }

    private func applyBalanceImpact(for expense: Expense, multiplier: Double) {
        applyBankAccountDelta(named: expense.paymentAccount, delta: -expense.amount * multiplier)
    }

    private func applyBalanceImpact(for transfer: CashTransfer, multiplier: Double) {
        applyBankAccountDelta(named: transfer.fromAccountName, delta: -transfer.amount * multiplier)
        applyBankAccountDelta(named: transfer.toAccountName, delta: transfer.amount * multiplier)
    }

    private func canApplyCashTransfer(_ transfer: CashTransfer) -> Bool {
        let from = normalizedAccountName(transfer.fromAccountName)
        let to = normalizedAccountName(transfer.toAccountName)
        guard transfer.amount > 0, !from.isEmpty, !to.isEmpty, from != to else { return false }
        let availableAccounts = Set(bankAccounts.map { normalizedAccountName($0.name) })
        return availableAccounts.contains(from) && availableAccounts.contains(to)
    }

    private func applyBankAccountDelta(named accountName: String, delta: Double) {
        let normalized = normalizedAccountName(accountName)
        guard !normalized.isEmpty else { return }
        guard let index = bankAccounts.firstIndex(where: { normalizedAccountName($0.name) == normalized }) else { return }
        bankAccounts[index].balance = ((bankAccounts[index].balance + delta) * 100).rounded() / 100
    }
""",
"""    private func resolvingAccountReferences(for expense: Expense) -> Expense {
        var resolved = expense
        if resolved.paymentAccountId == nil { resolved.paymentAccountId = resolveFinancialAccountId(legacyName: resolved.paymentAccount, allowedKinds: [.depository, .credit], metadata: resolved.plaidMetadata) }
        if resolved.creditCardPaymentTargetId == nil, let target = creditCardPaymentTarget(for: resolved) { resolved.creditCardPaymentTargetId = resolveFinancialAccountId(legacyName: target, allowedKinds: [.credit]) }
        return resolved
    }

    private func resolvingAccountReferences(for transfer: CashTransfer) -> CashTransfer {
        var resolved = transfer
        if resolved.fromAccountId == nil { resolved.fromAccountId = resolveFinancialAccountId(legacyName: resolved.fromAccountName, allowedKinds: [.depository]) }
        if resolved.toAccountId == nil { resolved.toAccountId = resolveFinancialAccountId(legacyName: resolved.toAccountName, allowedKinds: [.depository]) }
        return resolved
    }

    private func applyBalanceImpact(for income: IncomeEntry, multiplier: Double) {
        applyBankAccountDelta(accountId: income.bankAccountId, legacyName: income.bankName, delta: income.amount * multiplier)
    }

    private func applyBalanceImpact(for expense: Expense, multiplier: Double) {
        applyBankAccountDelta(accountId: expense.paymentAccountId, legacyName: expense.paymentAccount, delta: -expense.amount * multiplier)
    }

    private func applyBalanceImpact(for transfer: CashTransfer, multiplier: Double) {
        applyBankAccountDelta(accountId: transfer.fromAccountId, legacyName: transfer.fromAccountName, delta: -transfer.amount * multiplier)
        applyBankAccountDelta(accountId: transfer.toAccountId, legacyName: transfer.toAccountName, delta: transfer.amount * multiplier)
    }

    private func canApplyCashTransfer(_ transfer: CashTransfer) -> Bool {
        guard transfer.amount > 0, let from = bankAccountIndex(accountId: transfer.fromAccountId, legacyName: transfer.fromAccountName), let to = bankAccountIndex(accountId: transfer.toAccountId, legacyName: transfer.toAccountName) else { return false }
        return from != to
    }

    private func applyBankAccountDelta(accountId: UUID?, legacyName: String, delta: Double) {
        guard let index = bankAccountIndex(accountId: accountId, legacyName: legacyName) else { return }
        guard bankAccounts[index].plaidMetadata == nil else { return }
        if let accountId, financialAccounts.first(where: { $0.id == accountId })?.source == .plaid { return }
        bankAccounts[index].balance = ((bankAccounts[index].balance + delta) * 100).rounded() / 100
    }

    private func bankAccountIndex(accountId: UUID?, legacyName: String) -> Int? {
        if let accountId {
            if let direct = bankAccounts.firstIndex(where: { $0.id == accountId }) { return direct }
            guard let financial = financialAccounts.first(where: { $0.id == accountId }) else { return nil }
            if let externalId = financial.externalAccountId, let matched = bankAccounts.firstIndex(where: { $0.plaidMetadata?.accountId == externalId }) { return matched }
            let normalized = normalizedAccountName(financial.name)
            let matches = bankAccounts.indices.filter { normalizedAccountName(bankAccounts[$0].name) == normalized }
            return matches.count == 1 ? matches[0] : nil
        }
        let normalized = normalizedAccountName(legacyName)
        guard !normalized.isEmpty else { return nil }
        let matches = bankAccounts.indices.filter { normalizedAccountName(bankAccounts[$0].name) == normalized }
        return matches.count == 1 ? matches[0] : nil
    }
""", "UUID-first balance helpers")

MODELS.write_text(models)

plaid = PLAID.read_text()
plaid = replace_once(plaid,
"""        if !payload.connectionStatuses.isEmpty {
            plaidConnectionStatuses = payload.connectionStatuses
        }

        return result
""",
"""        if !payload.connectionStatuses.isEmpty {
            plaidConnectionStatuses = payload.connectionStatuses
        }

        migrateLegacyAccountsIfNeeded()
        return result
""", "Plaid post-sync migration")
PLAID.write_text(plaid)

tasks = TASKS.read_text()
for old in [
    "- [ ] Replace name-based account references with stable local UUIDs.",
    "- [ ] Add backward-compatible account references to income, expenses, transfers, portfolio transactions, and holdings.",
    "- [ ] Keep display names as presentation fields only.",
    "- [ ] Prevent manual ledger actions from mutating Plaid-authoritative balances.",
]:
    if old not in tasks:
        raise RuntimeError(f"missing task line: {old}")
    tasks = tasks.replace(old, old.replace("[ ]", "[x]"), 1)
TASKS.write_text(tasks)

# Lightweight regression coverage.
tests = TESTS.read_text()
tests = replace_once(tests,
"""        testFinancialAccountCodableRoundTrip()
        testLegacyAccountsMigrateToStableAccountDomain()
        testHoldingsConsolidateToOneRowPerTicker()
""",
"""        testFinancialAccountCodableRoundTrip()
        testLegacyAccountsMigrateToStableAccountDomain()
        testStableAccountUUIDSurvivesRename()
        testManualLedgerDoesNotMutatePlaidBalance()
        testHoldingsConsolidateToOneRowPerTicker()
""", "test registration")
new_tests = r'''

    private static func testStableAccountUUIDSurvivesRename() {
        let checkingId = UUID()
        let savingsId = UUID()
        let transferId = UUID()
        let budget = BudgetModel()
        budget.financialAccounts = [
            FinancialAccount(id: checkingId, name: "Checking", kind: .depository),
            FinancialAccount(id: savingsId, name: "Savings", kind: .depository)
        ]
        budget.bankAccounts = [
            BankAccount(id: checkingId, name: "Checking", balance: 500),
            BankAccount(id: savingsId, name: "Savings", balance: 100)
        ]
        budget.addCashTransfer(CashTransfer(id: transferId, name: "Move", amount: 50, fromAccountName: "Checking", toAccountName: "Savings"))
        assert(budget.cashTransfers[0].fromAccountId == checkingId, "Expected transfer source UUID to persist")
        budget.bankAccounts[0].name = "Primary Checking"
        budget.financialAccounts[0].name = "Primary Checking"
        budget.updateCashTransfer(CashTransfer(id: transferId, name: "Move", amount: 30, fromAccountName: "Checking", toAccountName: "Savings", fromAccountId: checkingId, toAccountId: savingsId))
        assert(budget.bankAccounts.first(where: { $0.id == checkingId })?.balance == 470, "Expected renamed source to remain linked by UUID")
        assert(budget.bankAccounts.first(where: { $0.id == savingsId })?.balance == 130, "Expected destination to remain linked by UUID")
    }

    private static func testManualLedgerDoesNotMutatePlaidBalance() {
        let financialId = UUID()
        let budget = BudgetModel()
        budget.financialAccounts = [FinancialAccount(id: financialId, name: "Plaid Checking", kind: .depository, source: .plaid, externalAccountId: "plaid-checking")]
        budget.bankAccounts = [BankAccount(name: "Plaid Checking", balance: 1000, plaidMetadata: PlaidSourceMetadata(itemId: "item-1", accountId: "plaid-checking"))]
        budget.addIncomeEntry(IncomeEntry(name: "Manual adjustment", amount: 250, bankName: "Plaid Checking", bankAccountId: financialId))
        assert(budget.bankAccounts[0].balance == 1000, "Expected manual ledger actions not to mutate Plaid-authoritative balances")
        assert(budget.incomes.count == 1, "Expected manual ledger row to remain recorded")
    }
'''
marker = "\n    private static func testHoldingsConsolidateToOneRowPerTicker() {"
if marker not in tests:
    raise RuntimeError("test insertion marker missing")
tests = tests.replace(marker, new_tests + marker, 1)
TESTS.write_text(tests)

required = ["paymentAccountId", "bankAccountId", "fromAccountId", "portfolioAccountId", "fundingBankAccountId", "migrateStableAccountReferencesIfNeeded", "applyBankAccountDelta(accountId:"]
for token in required:
    if token not in MODELS.read_text():
        raise RuntimeError(f"missing required token: {token}")
print("TIM-79 patch applied")
