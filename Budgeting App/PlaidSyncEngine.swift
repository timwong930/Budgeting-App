import Foundation

extension BudgetModel {
    @discardableResult
    func applyPlaidSync(_ payload: PlaidSyncPayload) -> PlaidSyncResult {
        let now = Date()
        var result = PlaidSyncResult()
        var accountNamesById: [String: String] = [:]
        var accountTypesById: [String: PlaidAccountType] = [:]
        var plaidInvestmentValue = 0.0
        var plaidInvestmentCash = 0.0

        for account in payload.accounts {
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
                result.updatedAccounts += 1
            case .investment:
                plaidInvestmentValue += account.currentBalance ?? 0
                plaidInvestmentCash += account.availableBalance ?? 0
            case .loan, .other:
                continue
            }
        }

        for transaction in payload.transactions {
            if transaction.removed {
                result.removedTransactions += removePlaidTransaction(id: transaction.id)
                continue
            }
            let importResult = upsertPlaidTransaction(
                transaction,
                accountName: accountNamesById[transaction.accountId] ?? "",
                accountType: accountTypesById[transaction.accountId] ?? .other,
                syncedAt: now
            )
            switch importResult {
            case .imported:
                result.importedTransactions += 1
            case .reconciled:
                result.reconciledTransactions += 1
            case .needsReview:
                result.reviewItems += 1
            }
        }

        if !payload.holdings.isEmpty {
            applyPlaidHoldings(payload.holdings, syncedAt: now)
            result.updatedHoldings = payload.holdings.count
        } else if plaidInvestmentValue > 0 {
            portfolioSnapshot.portfolioValue = roundedCurrency(plaidInvestmentValue)
        }
        if plaidInvestmentCash > 0, portfolioAccounts.isEmpty {
            portfolioSnapshot.cashBalance = roundedCurrency(plaidInvestmentCash)
        } else {
            synchronizeAggregatePortfolioBalances()
        }

        for transaction in payload.investmentTransactions {
            guard !portfolioTransactions.contains(where: { $0.plaidMetadata?.investmentTransactionId == transaction.id }) else { continue }
            portfolioTransactions.append(makePortfolioTransaction(from: transaction, syncedAt: now))
            result.importedInvestmentTransactions += 1
        }

        if !payload.connectionStatuses.isEmpty {
            plaidConnectionStatuses = payload.connectionStatuses
        }

        migrateLegacyAccountsIfNeeded()
        synchronizeLegacyMarginStateFromLedger()
        return result
    }
}

private enum PlaidTransactionImportResult {
    case imported
    case reconciled
    case needsReview
}

private extension BudgetModel {
    func upsertPlaidFinancialAccount(_ account: PlaidSyncedAccount, syncedAt: Date) {
        let kind: FinancialAccountKind
        switch account.type {
        case .depository: kind = .depository
        case .credit: kind = .credit
        case .investment: kind = .investment
        case .loan: kind = .loan
        case .other: kind = .other
        }

        let financialAccountId: UUID
        if let index = financialAccounts.firstIndex(where: { $0.externalAccountId == account.id }) {
            financialAccounts[index].name = account.name
            financialAccounts[index].institutionName = account.institutionName
            financialAccounts[index].kind = kind
            financialAccounts[index].source = .plaid
            financialAccounts[index].externalItemId = account.itemId
            financialAccounts[index].isActive = true
            financialAccounts[index].lastSyncedAt = syncedAt
            financialAccountId = financialAccounts[index].id
        } else {
            let financialAccount = FinancialAccount(
                name: account.name,
                institutionName: account.institutionName,
                kind: kind,
                source: .plaid,
                externalAccountId: account.id,
                externalItemId: account.itemId,
                lastSyncedAt: syncedAt
            )
            financialAccounts.append(financialAccount)
            financialAccountId = financialAccount.id
        }

        guard account.type == .investment else { return }
        let cashBalance = roundedCurrency(account.availableBalance ?? 0)
        if let index = portfolioAccounts.firstIndex(where: { $0.financialAccountId == financialAccountId }) {
            portfolioAccounts[index].name = account.name
            portfolioAccounts[index].cashBalance = cashBalance
            portfolioAccounts[index].isActive = true
        } else {
            portfolioAccounts.append(
                PortfolioAccount(
                    financialAccountId: financialAccountId,
                    name: account.name,
                    cashBalance: cashBalance
                )
            )
        }
    }

    func upsertPlaidBankAccount(_ account: PlaidSyncedAccount, syncedAt: Date) {
        let metadata = PlaidSourceMetadata(
            itemId: account.itemId,
            accountId: account.id,
            institutionName: account.institutionName,
            lastSyncedAt: syncedAt
        )
        let balance = roundedCurrency(account.currentBalance ?? account.availableBalance ?? 0)
        if let index = bankAccounts.firstIndex(where: { $0.plaidMetadata?.accountId == account.id || normalized($0.name) == normalized(account.name) }) {
            bankAccounts[index].name = account.name
            bankAccounts[index].balance = balance
            bankAccounts[index].plaidMetadata = metadata
            if bankAccounts[index].note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let institutionName = account.institutionName {
                bankAccounts[index].note = "Synced from \(institutionName)"
            }
        } else {
            bankAccounts.append(
                BankAccount(
                    name: account.name,
                    balance: balance,
                    note: account.institutionName.map { "Synced from \($0)" } ?? "",
                    plaidMetadata: metadata
                )
            )
        }
    }

    func upsertPlaidCreditAccount(_ account: PlaidSyncedAccount, liability: PlaidSyncedCreditLiability?, syncedAt: Date) {
        let metadata = PlaidSourceMetadata(
            itemId: account.itemId,
            accountId: account.id,
            institutionName: account.institutionName,
            lastSyncedAt: syncedAt
        )
        let dueDay = liability?.nextPaymentDueDate.map { Calendar.current.component(.day, from: $0) } ?? 1
        let noteParts = [
            account.institutionName.map { "Synced from \($0)" },
            liability?.aprPercentage.map { "APR \($0)%" }
        ].compactMap { $0 }
        if let index = creditAccounts.firstIndex(where: { $0.plaidMetadata?.accountId == account.id || normalized($0.name) == normalized(account.name) }) {
            creditAccounts[index].name = account.name
            creditAccounts[index].startingBalance = roundedCurrency(account.currentBalance ?? creditAccounts[index].startingBalance)
            creditAccounts[index].expectedAmount = roundedCurrency(liability?.minimumPaymentAmount ?? creditAccounts[index].expectedAmount)
            creditAccounts[index].creditLimit = max(account.creditLimit ?? creditAccounts[index].creditLimit, 0)
            creditAccounts[index].dueDay = min(max(dueDay, 1), 31)
            creditAccounts[index].isActive = true
            creditAccounts[index].plaidMetadata = metadata
            if !noteParts.isEmpty {
                creditAccounts[index].note = noteParts.joined(separator: "\n")
            }
        } else {
            creditAccounts.append(
                CreditAccount(
                    name: account.name,
                    closingDay: 1,
                    dueDay: dueDay,
                    startingBalance: roundedCurrency(account.currentBalance ?? 0),
                    expectedAmount: roundedCurrency(liability?.minimumPaymentAmount ?? 0),
                    creditLimit: max(account.creditLimit ?? 0, 0),
                    isActive: true,
                    note: noteParts.joined(separator: "\n"),
                    plaidMetadata: metadata
                )
            )
        }
    }

    func upsertPlaidTransaction(_ transaction: PlaidSyncedTransaction, accountName: String, accountType: PlaidAccountType, syncedAt: Date) -> PlaidTransactionImportResult {
        if let expenseIndex = expenses.firstIndex(where: { $0.plaidMetadata?.transactionId == transaction.id }) {
            if transaction.amount >= 0 {
                expenses[expenseIndex] = makeExpense(from: transaction, accountName: accountName, existingId: expenses[expenseIndex].id, syncedAt: syncedAt)
            }
            return .imported
        }
        if let incomeIndex = incomes.firstIndex(where: { $0.plaidMetadata?.transactionId == transaction.id }) {
            if transaction.amount < 0 {
                incomes[incomeIndex] = makeIncome(from: transaction, accountName: accountName, existingId: incomes[incomeIndex].id, syncedAt: syncedAt)
            }
            return .imported
        }

        if transaction.amount < 0 {
            let income = makeIncome(from: transaction, accountName: accountName, syncedAt: syncedAt)
            if let duplicateIndex = matchingIncomeIndex(for: income) {
                incomes[duplicateIndex].plaidMetadata = income.plaidMetadata
                return .reconciled
            }
            incomes.append(income)
            return .imported
        }

        let expense = makeExpense(from: transaction, accountName: accountName, syncedAt: syncedAt)
        if let duplicateIndex = matchingExpenseIndex(for: expense) {
            expenses[duplicateIndex].plaidMetadata = expense.plaidMetadata
            if expenses[duplicateIndex].paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                expenses[duplicateIndex].paymentAccount = accountName
            }
            return .reconciled
        }

        if transaction.category == nil {
            plaidReviewItems.append(
                PlaidReviewItem(
                    title: transaction.merchantName ?? transaction.name,
                    detail: "Plaid transaction needs category review.",
                    amount: transaction.amount,
                    date: transaction.date,
                    sourceId: transaction.id
                )
            )
            expenses.append(expense)
            return .needsReview
        }

        if accountType == .credit, isLikelyCreditCardPayment(transaction) {
            expenses.append(
                Expense(
                    id: expense.id,
                    name: expense.name,
                    amount: expense.amount,
                    date: expense.date,
                    section: expense.section,
                    categoryId: expense.categoryId,
                    paymentAccount: expense.paymentAccount,
                    note: expense.note,
                    creditCardPaymentTarget: accountName,
                    plaidMetadata: expense.plaidMetadata
                )
            )
        } else {
            expenses.append(expense)
        }
        return .imported
    }

    func removePlaidTransaction(id: String) -> Int {
        let oldExpenseCount = expenses.count
        expenses.removeAll { $0.plaidMetadata?.transactionId == id }
        let oldIncomeCount = incomes.count
        incomes.removeAll { $0.plaidMetadata?.transactionId == id }
        return (oldExpenseCount - expenses.count) + (oldIncomeCount - incomes.count)
    }

    func applyPlaidHoldings(_ syncedHoldings: [PlaidSyncedHolding], syncedAt: Date) {
        let displayableHoldings = syncedHoldings.filter(isDisplayablePlaidHolding)
        let syncedExternalAccountIds = Set(displayableHoldings.map(\.accountId))
        let preservedHoldings = holdings.filter { holding in
            guard let metadata = holding.plaidMetadata else { return true }
            return !syncedExternalAccountIds.contains(metadata.accountId)
        }

        let groupedPlaidHoldings = Dictionary(grouping: displayableHoldings) { holding in
            let normalizedSecurityId = holding.securityId.trimmingCharacters(in: .whitespacesAndNewlines)
            let securityIdentity = normalizedSecurityId.isEmpty
                ? (normalizedTicker(holding.ticker) ?? holding.name ?? "UNKNOWN")
                : normalizedSecurityId
            return "\(holding.accountId)|\(securityIdentity)"
        }

        watchlistTickers.removeAll { isOptionContractTicker($0) }

        let importedHoldings: [PortfolioHolding] = groupedPlaidHoldings.compactMap { _, plaidHoldings in
            guard let first = plaidHoldings.first,
                  let ticker = normalizedTicker(first.ticker) else { return nil }

            let portfolioAccountId = resolvePortfolioAccountId(forPlaidExternalAccountId: first.accountId)
            let existing = holdings.first { holding in
                guard holding.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == ticker else { return false }
                let securityId = first.securityId
                if holding.plaidMetadata?.securityId == securityId,
                   holding.plaidMetadata?.accountId == first.accountId {
                    return true
                }
                return holding.portfolioAccountId == portfolioAccountId
            } ?? holdings.first {
                $0.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == ticker
            }

            let totalQuantity = plaidHoldings.reduce(0) { $0 + $1.quantity }
            let totalCostBasis = plaidHoldings.reduce(0) { partial, holding in
                partial + (holding.costBasis ?? ((existing?.averageCost ?? 0) * holding.quantity))
            }
            let institutionValue = plaidHoldings.compactMap(\.institutionValue).reduce(0, +)
            let fallbackPrice = plaidHoldings.compactMap(\.institutionPrice).first { $0 > 0 }
                ?? existing?.currentPrice
                ?? 0
            let price = totalQuantity > 0 && institutionValue > 0
                ? institutionValue / totalQuantity
                : fallbackPrice
            let averageCost = totalQuantity > 0 ? totalCostBasis / totalQuantity : 0

            if price > 0 {
                cachedQuotes[ticker] = CachedQuote(ticker: ticker, price: price, updatedAt: syncedAt)
            }
            if !watchlistTickers.contains(where: { normalizedTicker($0) == ticker }) {
                watchlistTickers.append(ticker)
            }

            return PortfolioHolding(
                ticker: ticker,
                shares: totalQuantity,
                averageCost: averageCost,
                currentPrice: price,
                annualDividendPerShare: existing?.annualDividendPerShare ?? 0,
                dividendFrequency: existing?.dividendFrequency ?? .quarterly,
                assetType: existing?.assetType ?? .dividendStock,
                dividendReliability: existing?.dividendReliability ?? .medium,
                notes: existing?.notes ?? "",
                nextExDividendDate: existing?.nextExDividendDate,
                nextPayDate: existing?.nextPayDate,
                portfolioAccountId: portfolioAccountId,
                plaidMetadata: PlaidSourceMetadata(
                    itemId: first.itemId,
                    accountId: first.accountId,
                    securityId: first.securityId,
                    lastSyncedAt: syncedAt
                )
            )
        }

        holdings = (preservedHoldings + importedHoldings).sorted { lhs, rhs in
            let comparison = lhs.ticker.localizedStandardCompare(rhs.ticker)
            if comparison == .orderedSame {
                return portfolioAccountName(for: lhs.portfolioAccountId)
                    .localizedStandardCompare(portfolioAccountName(for: rhs.portfolioAccountId)) == .orderedAscending
            }
            return comparison == .orderedAscending
        }

        let holdingsValue = holdings.reduce(0) { total, holding in
            let price = cachedQuotes[holding.ticker.uppercased()]?.price ?? holding.currentPrice
            return total + holding.shares * price
        }
        synchronizeAggregatePortfolioBalances()
        portfolioSnapshot.portfolioValue = roundedCurrency(holdingsValue + portfolioSnapshot.cashBalance)
    }

    func makeIncome(from transaction: PlaidSyncedTransaction, accountName: String, existingId: UUID = UUID(), syncedAt: Date) -> IncomeEntry {
        IncomeEntry(
            id: existingId,
            name: transaction.merchantName ?? transaction.name,
            amount: roundedCurrency(abs(transaction.amount)),
            date: transaction.date,
            bankName: accountName,
            plaidMetadata: metadata(for: transaction, syncedAt: syncedAt)
        )
    }

    func makeExpense(from transaction: PlaidSyncedTransaction, accountName: String, existingId: UUID = UUID(), syncedAt: Date) -> Expense {
        let mapped = mappedBudgetCategory(for: transaction.category)
        return Expense(
            id: existingId,
            name: transaction.merchantName ?? transaction.name,
            amount: roundedCurrency(abs(transaction.amount)),
            date: transaction.date,
            section: mapped.section,
            categoryId: mapped.categoryId,
            paymentAccount: accountName,
            note: transaction.pending ? "Plaid pending transaction" : "",
            plaidMetadata: metadata(for: transaction, syncedAt: syncedAt)
        )
    }

    func makePortfolioTransaction(from transaction: PlaidSyncedInvestmentTransaction, syncedAt: Date) -> PortfolioTransaction {
        let type = portfolioTransactionType(for: transaction)
        return PortfolioTransaction(
            date: transaction.date,
            type: type,
            ticker: normalizedTicker(transaction.ticker),
            shares: transaction.quantity,
            pricePerShare: transaction.price,
            amount: roundedCurrency(abs(transaction.amount)),
            notes: transaction.name,
            portfolioAccountId: resolvePortfolioAccountId(forPlaidExternalAccountId: transaction.accountId),
            plaidMetadata: PlaidSourceMetadata(
                itemId: transaction.itemId,
                accountId: transaction.accountId,
                investmentTransactionId: transaction.id,
                securityId: transaction.securityId,
                lastSyncedAt: syncedAt
            )
        )
    }

    func metadata(for transaction: PlaidSyncedTransaction, syncedAt: Date) -> PlaidSourceMetadata {
        PlaidSourceMetadata(
            itemId: transaction.itemId,
            accountId: transaction.accountId,
            transactionId: transaction.id,
            lastSyncedAt: syncedAt,
            status: .imported,
            matchConfidence: nil
        )
    }

    func matchingExpenseIndex(for expense: Expense) -> Int? {
        expenses.firstIndex { existing in
            existing.plaidMetadata?.transactionId == nil &&
            abs(existing.amount - expense.amount) < 0.01 &&
            Calendar.current.isDate(existing.date, inSameDayAs: expense.date) &&
            namesLikelyMatch(existing.name, expense.name)
        }
    }

    func matchingIncomeIndex(for income: IncomeEntry) -> Int? {
        incomes.firstIndex { existing in
            existing.plaidMetadata?.transactionId == nil &&
            abs(existing.amount - income.amount) < 0.01 &&
            Calendar.current.isDate(existing.date, inSameDayAs: income.date) &&
            namesLikelyMatch(existing.name, income.name)
        }
    }

    func mappedBudgetCategory(for plaidCategory: String?) -> (section: BudgetSection, categoryId: UUID) {
        let category = (plaidCategory ?? "").lowercased()
        let section: BudgetSection
        if category.contains("travel") || category.contains("entertainment") || category.contains("recreation") || category.contains("shops") {
            section = .wants
        } else {
            section = .needs
        }
        switch section {
        case .needs:
            if let match = needsCategories.first(where: { category.contains($0.name.lowercased()) || $0.name.localizedCaseInsensitiveContains("plaid") }) {
                return (.needs, match.id)
            }
            let newCategory = Category(name: "Plaid Needs", allocatedAmount: 0)
            needsCategories.append(newCategory)
            return (.needs, newCategory.id)
        case .wants:
            if let match = wantsCategories.first(where: { category.contains($0.name.lowercased()) || $0.name.localizedCaseInsensitiveContains("plaid") }) {
                return (.wants, match.id)
            }
            let newCategory = Category(name: "Plaid Wants", allocatedAmount: 0)
            wantsCategories.append(newCategory)
            return (.wants, newCategory.id)
        }
    }

    func portfolioTransactionType(for transaction: PlaidSyncedInvestmentTransaction) -> PortfolioTransactionType {
        let raw = "\(transaction.type) \(transaction.subtype ?? "")".lowercased()
        if raw.contains("buy") { return .buy }
        if raw.contains("sell") { return .sell }
        if raw.contains("dividend") { return .dividend }
        if raw.contains("interest") { return .marginInterest }
        if raw.contains("deposit") || raw.contains("contribution") { return .contribution }
        return transaction.amount < 0 ? .buy : .sell
    }

    func isLikelyCreditCardPayment(_ transaction: PlaidSyncedTransaction) -> Bool {
        let text = "\(transaction.name) \(transaction.merchantName ?? "") \(transaction.category ?? "")".lowercased()
        return text.contains("payment") || text.contains("credit card")
    }

    func namesLikelyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.contains(right) || right.contains(left)
    }

    func normalizedTicker(_ value: String?) -> String? {
        let ticker = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return ticker.isEmpty ? nil : ticker
    }

    func isDisplayablePlaidHolding(_ holding: PlaidSyncedHolding) -> Bool {
        guard let ticker = normalizedTicker(holding.ticker) else { return false }
        let securityType = holding.securityType?.lowercased() ?? ""
        if securityType.contains("option") || securityType.contains("derivative") {
            return false
        }
        return !isOptionContractTicker(ticker)
    }

    func isOptionContractTicker(_ ticker: String) -> Bool {
        let value = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = #"^[A-Z]{1,6}\d{6}[CP]\d{8}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    func resolvePortfolioAccountId(forPlaidExternalAccountId externalAccountId: String) -> UUID? {
    guard let financialAccountId = financialAccounts.first(where: { $0.externalAccountId == externalAccountId })?.id else {
        return nil
    }
    return portfolioAccounts.first(where: { $0.financialAccountId == financialAccountId })?.id
}

func portfolioAccountName(for id: UUID?) -> String {
    guard let id,
          let account = portfolioAccounts.first(where: { $0.id == id }) else {
        return "Unassigned"
    }
    let trimmedName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedName.isEmpty ? "Investment Account" : trimmedName
}

func synchronizeAggregatePortfolioBalances() {
    let activeAccounts = portfolioAccounts.filter(\.isActive)
    portfolioSnapshot.cashBalance = roundedCurrency(
        activeAccounts.reduce(0) { $0 + $1.cashBalance }
    )
    portfolioSnapshot.marginUsed = roundedCurrency(
        activeAccounts.reduce(0) { $0 + $1.marginBalance }
    )
}

    func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
    }

    func roundedCurrency(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
