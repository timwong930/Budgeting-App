import Foundation

private enum PlaidReconciledImportResult {
    case imported
    case reconciled
    case needsReview
}

private struct PlaidManualMatch {
    let index: Int
    let confidence: Double
    let ambiguous: Bool
}

private struct PlaidTransferReconciliationResult {
    var handledTransactionIds: Set<String> = []
    var reconciledTransactions = 0
    var reviewItemsAdded = 0
}

extension BudgetModel {
    /// Applies the non-transaction portions of the existing Plaid sync, then reconciles
    /// transaction deltas with account-aware, idempotent rules.
    @discardableResult
    func applyPlaidSyncReconciled(_ payload: PlaidSyncPayload) -> PlaidSyncResult {
        var nonTransactionPayload = payload
        nonTransactionPayload.transactions = []
        var result = applyPlaidSync(nonTransactionPayload)

        let syncedAt = Date()
        var accountNamesById: [String: String] = [:]
        var accountTypesById: [String: PlaidAccountType] = [:]
        for account in payload.accounts {
            accountNamesById[account.id] = account.name
            accountTypesById[account.id] = account.type
        }

        let activeTransactions = payload.transactions.filter { !$0.removed }
        let transferResult = reconcilePlaidTransfers(
            activeTransactions,
            accountNamesById: accountNamesById,
            accountTypesById: accountTypesById
        )
        result.reconciledTransactions += transferResult.reconciledTransactions
        result.reviewItems += transferResult.reviewItemsAdded

        for transaction in activeTransactions where !transferResult.handledTransactionIds.contains(transaction.id) {
            let importResult = reconcilePlaidTransaction(
                transaction,
                accountName: accountNamesById[transaction.accountId] ?? "",
                syncedAt: syncedAt
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

        // Process removals after additions/modifications so a posted transaction can
        // replace a pending row before Plaid removes the old pending transaction ID.
        for transaction in payload.transactions where transaction.removed {
            result.removedTransactions += removeReconciledPlaidTransaction(id: transaction.id)
        }

        synchronizeLegacyMarginStateFromLedger()
        return result
    }
}

private extension BudgetModel {
    // MARK: - Transfer and card-payment classification

    func reconcilePlaidTransfers(
        _ transactions: [PlaidSyncedTransaction],
        accountNamesById: [String: String],
        accountTypesById: [String: PlaidAccountType]
    ) -> PlaidTransferReconciliationResult {
        var result = PlaidTransferReconciliationResult()

        for (index, transaction) in transactions.enumerated() {
            guard !result.handledTransactionIds.contains(transaction.id) else { continue }
            let type = accountTypesById[transaction.accountId] ?? .other
            guard isStrongTransferOrPayment(transaction, accountType: type) else { continue }

            var bestMatch: (transaction: PlaidSyncedTransaction, score: Double)?
            for candidateIndex in transactions.indices where candidateIndex != index {
                let candidate = transactions[candidateIndex]
                guard !result.handledTransactionIds.contains(candidate.id),
                      candidate.accountId != transaction.accountId,
                      transaction.amount * candidate.amount < 0,
                      abs(abs(transaction.amount) - abs(candidate.amount)) < 0.01,
                      dayDistance(transaction.date, candidate.date) <= 3 else {
                    continue
                }

                let candidateType = accountTypesById[candidate.accountId] ?? .other
                guard canPairTransfer(
                    transaction,
                    accountType: type,
                    with: candidate,
                    candidateAccountType: candidateType
                ) else { continue }

                var score = 0.55
                if Calendar.current.isDate(transaction.date, inSameDayAs: candidate.date) { score += 0.20 }
                if namesLikelyMatchForReconciliation(transactionDisplayName(transaction), transactionDisplayName(candidate)) { score += 0.10 }
                if isLikelyCreditCardPaymentForReconciliation(transaction) || isLikelyCreditCardPaymentForReconciliation(candidate) { score += 0.15 }

                if bestMatch == nil || score > bestMatch!.score {
                    bestMatch = (candidate, score)
                }
            }

            if let bestMatch {
                let outflow = transaction.amount > 0 ? transaction : bestMatch.transaction
                let inflow = transaction.amount < 0 ? transaction : bestMatch.transaction

                // Clean up rows imported by the pre-TIM-82 sign-first behavior before
                // recording the pair in the transfer ledger.
                _ = removeReconciledPlaidTransaction(id: transaction.id)
                _ = removeReconciledPlaidTransaction(id: bestMatch.transaction.id)

                upsertPlaidTransfer(
                    outflow: outflow,
                    inflow: inflow,
                    accountNamesById: accountNamesById,
                    accountTypesById: accountTypesById
                )
                result.handledTransactionIds.insert(transaction.id)
                result.handledTransactionIds.insert(bestMatch.transaction.id)
                result.reconciledTransactions += 2
            } else {
                // Do not let a known transfer/payment remain counted as ordinary income
                // or spending just because the matching account-side delta is absent.
                _ = removeReconciledPlaidTransaction(id: transaction.id)
                let added = upsertPlaidReviewItem(
                    sourceId: transaction.id,
                    title: transactionDisplayName(transaction),
                    detail: "Plaid transfer/payment could not be paired to another synced account. Review before counting it as income or spending.",
                    amount: transaction.amount,
                    date: transaction.date
                )
                result.handledTransactionIds.insert(transaction.id)
                if added { result.reviewItemsAdded += 1 }
            }
        }

        return result
    }

    func canPairTransfer(
        _ lhs: PlaidSyncedTransaction,
        accountType lhsType: PlaidAccountType,
        with rhs: PlaidSyncedTransaction,
        candidateAccountType rhsType: PlaidAccountType
    ) -> Bool {
        let bothDepository = lhsType == .depository && rhsType == .depository
        if bothDepository {
            return isLikelyBankTransfer(lhs) || isLikelyBankTransfer(rhs)
        }

        let depositoryAndCredit =
            (lhsType == .depository && rhsType == .credit) ||
            (lhsType == .credit && rhsType == .depository)
        if depositoryAndCredit {
            return isLikelyCreditCardPaymentForReconciliation(lhs) ||
                isLikelyCreditCardPaymentForReconciliation(rhs) ||
                isLikelyBankTransfer(lhs) ||
                isLikelyBankTransfer(rhs)
        }
        return false
    }

    func isStrongTransferOrPayment(_ transaction: PlaidSyncedTransaction, accountType: PlaidAccountType) -> Bool {
        if isLikelyBankTransfer(transaction) {
            return true
        }
        if accountType == .credit {
            return isLikelyCreditCardPaymentForReconciliation(transaction)
        }

        // On depository accounts require explicit card-payment language. This avoids
        // treating ordinary merchant autopay charges as credit-card transfers.
        let category = (transaction.category ?? "").lowercased()
        let text = transactionSearchText(transaction)
        return category.contains("loan_payment") ||
            category.contains("loan payment") ||
            text.contains("credit card payment") ||
            text.contains("card payment") ||
            text.contains("payment thank you")
    }

    func isLikelyBankTransfer(_ transaction: PlaidSyncedTransaction) -> Bool {
        let category = (transaction.category ?? "").lowercased()
        let text = transactionSearchText(transaction)
        return category.contains("transfer") ||
            text.contains("transfer") ||
            text.contains("zelle") ||
            text.contains("ach credit") ||
            text.contains("ach debit")
    }

    func isLikelyCreditCardPaymentForReconciliation(_ transaction: PlaidSyncedTransaction) -> Bool {
        let category = (transaction.category ?? "").lowercased()
        let text = transactionSearchText(transaction)
        return category.contains("loan_payment") ||
            category.contains("loan payment") ||
            text.contains("credit card payment") ||
            text.contains("card payment") ||
            text.contains("payment thank you") ||
            text.contains("autopay")
    }

    func upsertPlaidTransfer(
        outflow: PlaidSyncedTransaction,
        inflow: PlaidSyncedTransaction,
        accountNamesById: [String: String],
        accountTypesById: [String: PlaidAccountType]
    ) {
        let fromName = accountNamesById[outflow.accountId] ?? "Plaid account"
        let toName = accountNamesById[inflow.accountId] ?? "Plaid account"
        let fromId = stableFinancialAccountId(forPlaidAccountId: outflow.accountId)
        let toId = stableFinancialAccountId(forPlaidAccountId: inflow.accountId)
        let amount = roundedReconciliationCurrency(abs(outflow.amount))
        let date = max(outflow.date, inflow.date)
        let isCardPayment = accountTypesById[inflow.accountId] == .credit || accountTypesById[outflow.accountId] == .credit
        let sourceMarker = plaidTransferSourceMarker(outflowId: outflow.id, inflowId: inflow.id)

        let existingIndex = cashTransfers.firstIndex { existing in
            if existing.note.contains(sourceMarker) {
                return true
            }

            guard existing.note.hasPrefix("[PLAID_PAIR:"),
                  abs(existing.amount - amount) < 0.01,
                  dayDistance(existing.date, date) <= 3 else { return false }

            if let existingFromId = existing.fromAccountId,
               let existingToId = existing.toAccountId,
               let fromId,
               let toId {
                return existingFromId == fromId && existingToId == toId
            }

            return normalizedReconciliationText(existing.fromAccountName) == normalizedReconciliationText(fromName) &&
                normalizedReconciliationText(existing.toAccountName) == normalizedReconciliationText(toName)
        }

        if let existingIndex {
            cashTransfers[existingIndex].amount = amount
            cashTransfers[existingIndex].date = date
            cashTransfers[existingIndex].fromAccountName = fromName
            cashTransfers[existingIndex].toAccountName = toName
            cashTransfers[existingIndex].fromAccountId = fromId
            cashTransfers[existingIndex].toAccountId = toId
            cashTransfers[existingIndex].note = "\(sourceMarker) Synced from Plaid transaction pair"
            return
        }

        cashTransfers.append(
            CashTransfer(
                name: isCardPayment ? "Credit card payment" : "Account transfer",
                amount: amount,
                date: date,
                fromAccountName: fromName,
                toAccountName: toName,
                fromAccountId: fromId,
                toAccountId: toId,
                note: "\(sourceMarker) Synced from Plaid transaction pair"
            )
        )
    }

    func plaidTransferSourceMarker(outflowId: String, inflowId: String) -> String {
        let ids = [outflowId, inflowId].sorted()
        return "[PLAID_PAIR:\(ids.joined(separator: "|"))]"
    }

    // MARK: - Transaction reconciliation

    func reconcilePlaidTransaction(
        _ transaction: PlaidSyncedTransaction,
        accountName: String,
        syncedAt: Date
    ) -> PlaidReconciledImportResult {
        if let expenseIndex = expenses.firstIndex(where: { $0.plaidMetadata?.transactionId == transaction.id }) {
            if transaction.amount >= 0 {
                expenses[expenseIndex] = mergedPlaidExpense(
                    expenses[expenseIndex],
                    with: transaction,
                    accountName: accountName,
                    syncedAt: syncedAt
                )
            } else {
                let existing = expenses.remove(at: expenseIndex)
                incomes.append(incomeFromDirectionChange(existing, transaction: transaction, accountName: accountName, syncedAt: syncedAt))
            }
            clearPlaidReviewItems(sourceIds: [transaction.id])
            return .reconciled
        }

        if let incomeIndex = incomes.firstIndex(where: { $0.plaidMetadata?.transactionId == transaction.id }) {
            if transaction.amount < 0 {
                incomes[incomeIndex] = mergedPlaidIncome(
                    incomes[incomeIndex],
                    with: transaction,
                    accountName: accountName,
                    syncedAt: syncedAt
                )
            } else {
                let existing = incomes.remove(at: incomeIndex)
                expenses.append(expenseFromDirectionChange(existing, transaction: transaction, accountName: accountName, syncedAt: syncedAt))
            }
            clearPlaidReviewItems(sourceIds: [transaction.id])
            return .reconciled
        }

        if let pendingIndex = pendingExpenseReplacementIndex(for: transaction), transaction.amount >= 0 {
            let oldSourceId = expenses[pendingIndex].plaidMetadata?.transactionId
            expenses[pendingIndex] = mergedPlaidExpense(
                expenses[pendingIndex],
                with: transaction,
                accountName: accountName,
                syncedAt: syncedAt
            )
            clearPlaidReviewItems(sourceIds: [transaction.id, oldSourceId].compactMap { $0 })
            return .reconciled
        }

        if transaction.amount < 0 {
            let income = makeReconciledIncome(from: transaction, accountName: accountName, syncedAt: syncedAt)
            if let match = bestManualIncomeMatch(for: income) {
                if match.ambiguous {
                    let added = upsertPlaidReviewItem(
                        sourceId: transaction.id,
                        title: income.name,
                        detail: "Multiple manual income entries could match this Plaid transaction. Review the duplicate before merging.",
                        amount: transaction.amount,
                        date: transaction.date
                    )
                    incomes.append(income)
                    return added ? .needsReview : .imported
                }
                var existing = incomes[match.index]
                existing.plaidMetadata = reconciliationMetadata(
                    for: transaction,
                    syncedAt: syncedAt,
                    status: .reconciled,
                    matchConfidence: match.confidence
                )
                if existing.bankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing.bankName = accountName
                }
                if existing.bankAccountId == nil {
                    existing.bankAccountId = stableFinancialAccountId(forPlaidAccountId: transaction.accountId)
                }
                incomes[match.index] = existing
                clearPlaidReviewItems(sourceIds: [transaction.id])
                return .reconciled
            }
            incomes.append(income)
            clearPlaidReviewItems(sourceIds: [transaction.id])
            return .imported
        }

        let expense = makeReconciledExpense(from: transaction, accountName: accountName, syncedAt: syncedAt)
        if let match = bestManualExpenseMatch(for: expense) {
            if match.ambiguous {
                let added = upsertPlaidReviewItem(
                    sourceId: transaction.id,
                    title: expense.name,
                    detail: "Multiple manual expenses could match this Plaid transaction. Review the duplicate before merging.",
                    amount: transaction.amount,
                    date: transaction.date
                )
                expenses.append(expense)
                return added ? .needsReview : .imported
            }
            var existing = expenses[match.index]
            existing.plaidMetadata = reconciliationMetadata(
                for: transaction,
                syncedAt: syncedAt,
                status: .reconciled,
                matchConfidence: match.confidence
            )
            if existing.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.paymentAccount = accountName
            }
            if existing.paymentAccountId == nil {
                existing.paymentAccountId = stableFinancialAccountId(forPlaidAccountId: transaction.accountId)
            }
            expenses[match.index] = existing
            clearPlaidReviewItems(sourceIds: [transaction.id])
            return .reconciled
        }

        if transaction.category == nil {
            let added = upsertPlaidReviewItem(
                sourceId: transaction.id,
                title: expense.name,
                detail: "Plaid transaction needs category review.",
                amount: transaction.amount,
                date: transaction.date
            )
            expenses.append(expense)
            return added ? .needsReview : .imported
        }

        expenses.append(expense)
        clearPlaidReviewItems(sourceIds: [transaction.id])
        return .imported
    }

    func pendingExpenseReplacementIndex(for transaction: PlaidSyncedTransaction) -> Int? {
        guard !transaction.pending else { return nil }
        return expenses.firstIndex { existing in
            let wasPending = existing.plaidMetadata?.isPending == true || existing.note == "Plaid pending transaction"
            guard wasPending,
                  existing.plaidMetadata?.transactionId != nil,
                  existing.plaidMetadata?.transactionId != transaction.id,
                  existing.plaidMetadata?.accountId == transaction.accountId,
                  abs(existing.amount - abs(transaction.amount)) < 0.01,
                  dayDistance(existing.date, transaction.date) <= 3 else {
                return false
            }
            return namesLikelyMatchForReconciliation(existing.name, transactionDisplayName(transaction))
        }
    }

    func mergedPlaidExpense(
        _ existing: Expense,
        with transaction: PlaidSyncedTransaction,
        accountName: String,
        syncedAt: Date
    ) -> Expense {
        var updated = existing
        updated.amount = roundedReconciliationCurrency(abs(transaction.amount))
        updated.date = transaction.date
        updated.paymentAccount = accountName
        updated.paymentAccountId = stableFinancialAccountId(forPlaidAccountId: transaction.accountId)

        // Only replace the machine-owned pending marker. Any user note/category/name
        // remains untouched across Plaid modifications.
        if existing.note == "Plaid pending transaction" {
            updated.note = transaction.pending ? "Plaid pending transaction" : ""
        }

        updated.plaidMetadata = reconciliationMetadata(
            for: transaction,
            syncedAt: syncedAt,
            status: existing.plaidMetadata?.status ?? .imported,
            matchConfidence: existing.plaidMetadata?.matchConfidence,
            importedAt: existing.plaidMetadata?.importedAt
        )
        return updated
    }

    func mergedPlaidIncome(
        _ existing: IncomeEntry,
        with transaction: PlaidSyncedTransaction,
        accountName: String,
        syncedAt: Date
    ) -> IncomeEntry {
        var updated = existing
        updated.amount = roundedReconciliationCurrency(abs(transaction.amount))
        updated.date = transaction.date
        updated.bankName = accountName
        updated.bankAccountId = stableFinancialAccountId(forPlaidAccountId: transaction.accountId)
        updated.plaidMetadata = reconciliationMetadata(
            for: transaction,
            syncedAt: syncedAt,
            status: existing.plaidMetadata?.status ?? .imported,
            matchConfidence: existing.plaidMetadata?.matchConfidence,
            importedAt: existing.plaidMetadata?.importedAt
        )
        return updated
    }

    func incomeFromDirectionChange(
        _ existing: Expense,
        transaction: PlaidSyncedTransaction,
        accountName: String,
        syncedAt: Date
    ) -> IncomeEntry {
        IncomeEntry(
            id: existing.id,
            name: existing.name,
            amount: roundedReconciliationCurrency(abs(transaction.amount)),
            date: transaction.date,
            bankName: accountName,
            bankAccountId: stableFinancialAccountId(forPlaidAccountId: transaction.accountId),
            plaidMetadata: reconciliationMetadata(
                for: transaction,
                syncedAt: syncedAt,
                status: existing.plaidMetadata?.status ?? .imported,
                matchConfidence: existing.plaidMetadata?.matchConfidence,
                importedAt: existing.plaidMetadata?.importedAt
            )
        )
    }

    func expenseFromDirectionChange(
        _ existing: IncomeEntry,
        transaction: PlaidSyncedTransaction,
        accountName: String,
        syncedAt: Date
    ) -> Expense {
        let mapped = mappedReconciliationCategory(for: transaction.category)
        return Expense(
            id: existing.id,
            name: existing.name,
            amount: roundedReconciliationCurrency(abs(transaction.amount)),
            date: transaction.date,
            section: mapped.section,
            categoryId: mapped.categoryId,
            paymentAccount: accountName,
            paymentAccountId: stableFinancialAccountId(forPlaidAccountId: transaction.accountId),
            note: transaction.pending ? "Plaid pending transaction" : "",
            plaidMetadata: reconciliationMetadata(
                for: transaction,
                syncedAt: syncedAt,
                status: existing.plaidMetadata?.status ?? .imported,
                matchConfidence: existing.plaidMetadata?.matchConfidence,
                importedAt: existing.plaidMetadata?.importedAt
            )
        )
    }

    func makeReconciledIncome(from transaction: PlaidSyncedTransaction, accountName: String, syncedAt: Date) -> IncomeEntry {
        IncomeEntry(
            name: transactionDisplayName(transaction),
            amount: roundedReconciliationCurrency(abs(transaction.amount)),
            date: transaction.date,
            bankName: accountName,
            bankAccountId: stableFinancialAccountId(forPlaidAccountId: transaction.accountId),
            plaidMetadata: reconciliationMetadata(for: transaction, syncedAt: syncedAt)
        )
    }

    func makeReconciledExpense(from transaction: PlaidSyncedTransaction, accountName: String, syncedAt: Date) -> Expense {
        let mapped = mappedReconciliationCategory(for: transaction.category)
        return Expense(
            name: transactionDisplayName(transaction),
            amount: roundedReconciliationCurrency(abs(transaction.amount)),
            date: transaction.date,
            section: mapped.section,
            categoryId: mapped.categoryId,
            paymentAccount: accountName,
            paymentAccountId: stableFinancialAccountId(forPlaidAccountId: transaction.accountId),
            note: transaction.pending ? "Plaid pending transaction" : "",
            plaidMetadata: reconciliationMetadata(for: transaction, syncedAt: syncedAt)
        )
    }

    // MARK: - Account-aware manual matching

    func bestManualExpenseMatch(for imported: Expense) -> PlaidManualMatch? {
        let scored = expenses.enumerated().compactMap { index, existing -> (Int, Double)? in
            guard existing.plaidMetadata?.transactionId == nil,
                  abs(existing.amount - imported.amount) < 0.01 else { return nil }
            guard let score = manualExpenseMatchScore(existing: existing, imported: imported) else { return nil }
            return (index, score)
        }.sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 >= 0.65 else { return nil }
        let ambiguous = scored.dropFirst().first.map { best.1 - $0.1 < 0.08 } ?? false
        return PlaidManualMatch(index: best.0, confidence: min(best.1, 1), ambiguous: ambiguous)
    }

    func manualExpenseMatchScore(existing: Expense, imported: Expense) -> Double? {
        var score = 0.30 // exact amount is required by the caller
        let dayGap = dayDistance(existing.date, imported.date)
        if dayGap == 0 {
            score += 0.25
        } else if dayGap <= 2 {
            score += 0.12
        } else {
            return nil
        }

        if let existingId = existing.paymentAccountId, let importedId = imported.paymentAccountId {
            guard existingId == importedId else { return nil }
            score += 0.30
        } else {
            let existingAccount = normalizedReconciliationText(existing.paymentAccount)
            let importedAccount = normalizedReconciliationText(imported.paymentAccount)
            if !existingAccount.isEmpty, !importedAccount.isEmpty {
                guard existingAccount == importedAccount else { return nil }
                score += 0.20
            }
        }

        guard namesLikelyMatchForReconciliation(existing.name, imported.name) else { return nil }
        score += 0.20
        return score
    }

    func bestManualIncomeMatch(for imported: IncomeEntry) -> PlaidManualMatch? {
        let scored = incomes.enumerated().compactMap { index, existing -> (Int, Double)? in
            guard existing.plaidMetadata?.transactionId == nil,
                  abs(existing.amount - imported.amount) < 0.01 else { return nil }
            guard let score = manualIncomeMatchScore(existing: existing, imported: imported) else { return nil }
            return (index, score)
        }.sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 >= 0.65 else { return nil }
        let ambiguous = scored.dropFirst().first.map { best.1 - $0.1 < 0.08 } ?? false
        return PlaidManualMatch(index: best.0, confidence: min(best.1, 1), ambiguous: ambiguous)
    }

    func manualIncomeMatchScore(existing: IncomeEntry, imported: IncomeEntry) -> Double? {
        var score = 0.30
        let dayGap = dayDistance(existing.date, imported.date)
        if dayGap == 0 {
            score += 0.25
        } else if dayGap <= 2 {
            score += 0.12
        } else {
            return nil
        }

        if let existingId = existing.bankAccountId, let importedId = imported.bankAccountId {
            guard existingId == importedId else { return nil }
            score += 0.30
        } else {
            let existingAccount = normalizedReconciliationText(existing.bankName)
            let importedAccount = normalizedReconciliationText(imported.bankName)
            if !existingAccount.isEmpty, !importedAccount.isEmpty {
                guard existingAccount == importedAccount else { return nil }
                score += 0.20
            }
        }

        guard namesLikelyMatchForReconciliation(existing.name, imported.name) else { return nil }
        score += 0.20
        return score
    }

    // MARK: - Review + metadata helpers

    @discardableResult
    func upsertPlaidReviewItem(
        sourceId: String,
        title: String,
        detail: String,
        amount: Double?,
        date: Date?
    ) -> Bool {
        if let index = plaidReviewItems.firstIndex(where: { $0.sourceId == sourceId }) {
            plaidReviewItems[index].title = title
            plaidReviewItems[index].detail = detail
            plaidReviewItems[index].amount = amount
            plaidReviewItems[index].date = date
            return false
        }
        plaidReviewItems.append(
            PlaidReviewItem(
                title: title,
                detail: detail,
                amount: amount,
                date: date,
                sourceId: sourceId
            )
        )
        return true
    }

    func clearPlaidReviewItems(sourceIds: [String]) {
        let ids = Set(sourceIds)
        plaidReviewItems.removeAll { ids.contains($0.sourceId) }
    }

    func removeReconciledPlaidTransaction(id: String) -> Int {
        let oldExpenseCount = expenses.count
        expenses.removeAll { $0.plaidMetadata?.transactionId == id }
        let oldIncomeCount = incomes.count
        incomes.removeAll { $0.plaidMetadata?.transactionId == id }
        clearPlaidReviewItems(sourceIds: [id])
        return (oldExpenseCount - expenses.count) + (oldIncomeCount - incomes.count)
    }

    func reconciliationMetadata(
        for transaction: PlaidSyncedTransaction,
        syncedAt: Date,
        status: PlaidImportStatus = .imported,
        matchConfidence: Double? = nil,
        importedAt: Date? = nil
    ) -> PlaidSourceMetadata {
        PlaidSourceMetadata(
            itemId: transaction.itemId,
            accountId: transaction.accountId,
            transactionId: transaction.id,
            importedAt: importedAt ?? syncedAt,
            lastSyncedAt: syncedAt,
            status: status,
            matchConfidence: matchConfidence,
            isPending: transaction.pending
        )
    }

    func stableFinancialAccountId(forPlaidAccountId accountId: String) -> UUID? {
        financialAccounts.first { $0.externalAccountId == accountId }?.id
    }

    func mappedReconciliationCategory(for plaidCategory: String?) -> (section: BudgetSection, categoryId: UUID) {
        let category = (plaidCategory ?? "").lowercased()
        let section: BudgetSection = (
            category.contains("travel") ||
            category.contains("entertainment") ||
            category.contains("recreation") ||
            category.contains("shops")
        ) ? .wants : .needs

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

    // MARK: - Comparison helpers

    func transactionDisplayName(_ transaction: PlaidSyncedTransaction) -> String {
        transaction.merchantName ?? transaction.name
    }

    func transactionSearchText(_ transaction: PlaidSyncedTransaction) -> String {
        "\(transaction.name) \(transaction.merchantName ?? "") \(transaction.category ?? "")".lowercased()
    }

    func namesLikelyMatchForReconciliation(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedReconciliationText(lhs)
        let right = normalizedReconciliationText(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.contains(right) || right.contains(left)
    }

    func normalizedReconciliationText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
    }

    func dayDistance(_ lhs: Date, _ rhs: Date) -> Int {
        let calendar = Calendar.current
        let left = calendar.startOfDay(for: lhs)
        let right = calendar.startOfDay(for: rhs)
        return abs(calendar.dateComponents([.day], from: left, to: right).day ?? Int.max)
    }

    func roundedReconciliationCurrency(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
