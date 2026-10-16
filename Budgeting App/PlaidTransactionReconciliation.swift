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
            // A previously auto-created single transfer may now be correctly
            // recognized as an ordinary withdrawal, expense, or deposit.
            _ = removePlaidSingleTransfers(sourceIds: [transaction.id])
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
            // Plaid removals must also remove linked, auto-generated pairs.
            _ = removePlaidPairedTransfers(sourceIds: [transaction.id])
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
        var confirmedPairMarkers: Set<String> = []
        let activeById = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })

        // Preserve user-approved matches through later syncs. If both sides
        // change into incompatible transactions, re-evaluate them normally.
        for transfer in cashTransfers where transfer.note.contains("[USER_CONFIRMED]") {
            guard let ids = plaidPairTransactionIds(from: transfer.note) else { continue }
            let present = ids.compactMap { activeById[$0] }
            let stillValid = present.count < 2 || (
                present[0].accountId != present[1].accountId &&
                present[0].amount * present[1].amount < 0 &&
                abs(abs(present[0].amount) - abs(present[1].amount)) < 0.01 &&
                dayDistance(present[0].date, present[1].date) <= 3
            )
            guard stillValid else { continue }
            confirmedPairMarkers.insert(plaidTransferSourceMarker(outflowId: ids[0], inflowId: ids[1]))
            result.handledTransactionIds.formUnion(ids)
        }

        for (index, transaction) in transactions.enumerated() {
            guard !result.handledTransactionIds.contains(transaction.id) else { continue }
            let type = accountTypesById[transaction.accountId] ?? .other
            let keptAsTransaction = expenses.contains {
                $0.plaidMetadata?.transactionId == transaction.id &&
                $0.plaidMetadata?.userConfirmedNotTransfer == true
            } || incomes.contains {
                $0.plaidMetadata?.transactionId == transaction.id &&
                $0.plaidMetadata?.userConfirmedNotTransfer == true
            }
            guard !keptAsTransaction,
                  isStrongTransferOrPayment(transaction, accountType: type) else { continue }

            // An equal amount and nearby date are not sufficient proof of an
            // account-to-account transfer. Both directions must have exactly
            // one eligible counterpart; otherwise, keep the account unassigned.
            let candidates = eligibleTransferCounterpartIndices(
                for: transaction,
                at: index,
                in: transactions,
                accountTypesById: accountTypesById
            )
            var confirmedCandidate: PlaidSyncedTransaction?
            if candidates.count == 1 {
                let candidateIndex = candidates[0]
                let reverseCandidates = eligibleTransferCounterpartIndices(
                    for: transactions[candidateIndex],
                    at: candidateIndex,
                    in: transactions,
                    accountTypesById: accountTypesById
                )
                if reverseCandidates == [index] &&
                    !result.handledTransactionIds.contains(transactions[candidateIndex].id) {
                    confirmedCandidate = transactions[candidateIndex]
                }
            }

            if let confirmedCandidate {
                let outflow = transaction.amount > 0 ? transaction : confirmedCandidate
                let inflow = transaction.amount < 0 ? transaction : confirmedCandidate

                // Remove legacy sign-first rows before creating a verified pair.
                _ = removeReconciledPlaidTransaction(id: transaction.id)
                _ = removeReconciledPlaidTransaction(id: confirmedCandidate.id)

                upsertPlaidTransfer(
                    outflow: outflow,
                    inflow: inflow,
                    accountNamesById: accountNamesById,
                    accountTypesById: accountTypesById
                )
                confirmedPairMarkers.insert(
                    plaidTransferSourceMarker(outflowId: outflow.id, inflowId: inflow.id)
                )
                result.handledTransactionIds.insert(transaction.id)
                result.handledTransactionIds.insert(confirmedCandidate.id)
                result.reconciledTransactions += 2
            } else {
                // A *named* transfer may leave the connected-account set, but we
                // never invent a destination bank account or count it as income.
                _ = removeReconciledPlaidTransaction(id: transaction.id)
                upsertUnpairedPlaidTransfer(
                    transaction,
                    accountName: accountNamesById[transaction.accountId] ?? "Plaid account",
                    accountType: type
                )
                let added = upsertPlaidReviewItem(
                    sourceId: transaction.id,
                    title: transactionDisplayName(transaction),
                    detail: "Transfer/payment is unpaired or has multiple possible matches. Verify the destination before classifying it as a bank transfer.",
                    amount: transaction.amount,
                    date: transaction.date
                )
                result.handledTransactionIds.insert(transaction.id)
                if added { result.reviewItemsAdded += 1 }
            }
        }

        // When both transaction sides are in this delivery, discard older Plaid
        // pairs that fail the new matching rules. Do not touch manual transfers
        // or pairs whose other side was omitted by a partial delivery.
        _ = removeStalePlaidTransferPairs(
            presentTransactionIds: Set(transactions.map(\.id)),
            confirmedPairMarkers: confirmedPairMarkers
        )
        return result
    }

    func eligibleTransferCounterpartIndices(
        for transaction: PlaidSyncedTransaction,
        at index: Int,
        in transactions: [PlaidSyncedTransaction],
        accountTypesById: [String: PlaidAccountType]
    ) -> [Int] {
        let type = accountTypesById[transaction.accountId] ?? .other
        return transactions.indices.filter { candidateIndex in
            let candidate = transactions[candidateIndex]
            guard candidateIndex != index,
                  candidate.accountId != transaction.accountId,
                  transaction.amount * candidate.amount < 0,
                  abs(abs(transaction.amount) - abs(candidate.amount)) < 0.01,
                  dayDistance(transaction.date, candidate.date) <= 3 else { return false }
            return canPairTransfer(
                transaction,
                accountType: type,
                with: candidate,
                candidateAccountType: accountTypesById[candidate.accountId] ?? .other
            )
        }
    }

    func canPairTransfer(
        _ lhs: PlaidSyncedTransaction,
        accountType lhsType: PlaidAccountType,
        with rhs: PlaidSyncedTransaction,
        candidateAccountType rhsType: PlaidAccountType
    ) -> Bool {
        let bothDepository = lhsType == .depository && rhsType == .depository
        if bothDepository {
            // One side may read "TRANSFER TO SAVINGS" and the other "ACH CREDIT".
            // Plaid's transfer category corroborates the latter but cannot
            // independently turn an ordinary withdrawal into a transfer.
            guard !isObviousNonTransfer(lhs), !isObviousNonTransfer(rhs) else { return false }
            let left = isLikelyBankTransfer(lhs)
            let right = isLikelyBankTransfer(rhs)
            return (left && right) ||
                (left && isTransferCategory(rhs)) ||
                (right && isTransferCategory(lhs))
        }

        let depositoryAndCredit =
            (lhsType == .depository && rhsType == .credit) ||
            (lhsType == .credit && rhsType == .depository)
        if depositoryAndCredit {
            let credit = lhsType == .credit ? lhs : rhs
            let bank = lhsType == .depository ? lhs : rhs
            let bankDescription = transactionDescriptionText(bank)
            // A random bank withdrawal must not become a card payment just
            // because a card has an equal, opposite-signed transaction.
            return isLikelyCreditCardPaymentForReconciliation(credit) &&
                (isLikelyCreditCardPaymentForReconciliation(bank) ||
                 bankDescription.contains("payment") ||
                 bankDescription.contains("autopay") ||
                 bankDescription.contains("credit card"))
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

    func isTransferCategory(_ transaction: PlaidSyncedTransaction) -> Bool {
        (transaction.category ?? "").lowercased().contains("transfer")
    }

    func isObviousNonTransfer(_ transaction: PlaidSyncedTransaction) -> Bool {
        let name = transactionDescriptionText(transaction)
        let exclusions = ["atm", "cash withdrawal", "payroll", "paycheck", "salary",
                          "zelle", "venmo", "cash app", "merchant", "purchase",
                          "refund", "bill pay"]
        return exclusions.contains { name.contains($0) }
    }

    func isLikelyBankTransfer(_ transaction: PlaidSyncedTransaction) -> Bool {
        // Plaid's broad TRANSFER category, ACH debit/credit, and Zelle do NOT
        // prove a movement between the user's own linked bank accounts.
        // Require an explicit transfer word in the bank's description.
        let description = transactionDescriptionText(transaction)
        return description.range(
            of: #"\b(transfer|xfer|xfr)\b"#,
            options: .regularExpression
        ) != nil
    }

    func transactionDescriptionText(_ transaction: PlaidSyncedTransaction) -> String {
        "\(transaction.name) \(transaction.merchantName ?? "")".lowercased()
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
        _ = removePlaidSingleTransfers(sourceIds: [outflow.id, inflow.id])

        // Only the same Plaid source IDs may update an existing pair.
        // Matching by amount/date/accounts collapses distinct transfers.
        let existingIndex = cashTransfers.firstIndex {
            $0.note.contains(sourceMarker)
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

    func upsertUnpairedPlaidTransfer(
        _ transaction: PlaidSyncedTransaction,
        accountName: String,
        accountType: PlaidAccountType
    ) {
        if let pendingTransactionId = transaction.pendingTransactionId {
            _ = removePlaidSingleTransfers(sourceIds: [pendingTransactionId])
        }

        let sourceMarker = plaidSingleTransferSourceMarker(transaction.id)
        let currentAccountId = stableFinancialAccountId(forPlaidAccountId: transaction.accountId)
        let isOutflow = transaction.amount > 0
        let amount = roundedReconciliationCurrency(abs(transaction.amount))
        let externalName = "External account"
        let pendingMarker = transaction.pending ? " [PENDING]" : ""
        let isCardPayment = accountType == .credit && isLikelyCreditCardPaymentForReconciliation(transaction)
        let title = isCardPayment ? "Credit card payment" : transactionDisplayName(transaction)
        let note = "\(sourceMarker)\(pendingMarker) Unpaired Plaid transfer/payment"

        if let existingIndex = cashTransfers.firstIndex(where: { $0.note.contains(sourceMarker) }) {
            cashTransfers[existingIndex].name = title
            cashTransfers[existingIndex].amount = amount
            cashTransfers[existingIndex].date = transaction.date
            cashTransfers[existingIndex].fromAccountName = isOutflow ? accountName : externalName
            cashTransfers[existingIndex].toAccountName = isOutflow ? externalName : accountName
            cashTransfers[existingIndex].fromAccountId = isOutflow ? currentAccountId : nil
            cashTransfers[existingIndex].toAccountId = isOutflow ? nil : currentAccountId
            cashTransfers[existingIndex].note = note
            return
        }

        cashTransfers.append(
            CashTransfer(
                name: title,
                amount: amount,
                date: transaction.date,
                fromAccountName: isOutflow ? accountName : externalName,
                toAccountName: isOutflow ? externalName : accountName,
                fromAccountId: isOutflow ? currentAccountId : nil,
                toAccountId: isOutflow ? nil : currentAccountId,
                note: note
            )
        )
    }

    func plaidPairTransactionIds(from note: String) -> [String]? {
        let prefix = "[PLAID_PAIR:"
        guard note.hasPrefix(prefix),
              let closingBracket = note.firstIndex(of: "]") else { return nil }
        let start = note.index(note.startIndex, offsetBy: prefix.count)
        let ids = note[start..<closingBracket].split(separator: "|").map(String.init)
        return ids.count == 2 ? ids : nil
    }

    @discardableResult
    func removeStalePlaidTransferPairs(
        presentTransactionIds: Set<String>,
        confirmedPairMarkers: Set<String>
    ) -> Int {
        let previousCount = cashTransfers.count
        cashTransfers.removeAll { transfer in
            guard let ids = plaidPairTransactionIds(from: transfer.note),
                  ids.allSatisfy({ presentTransactionIds.contains($0) }) else {
                return false
            }
            let marker = plaidTransferSourceMarker(outflowId: ids[0], inflowId: ids[1])
            return !confirmedPairMarkers.contains(marker)
        }
        return previousCount - cashTransfers.count
    }

    @discardableResult
    func removePlaidPairedTransfers(sourceIds: [String]) -> Int {
        let removedIds = Set(sourceIds)
        let previousCount = cashTransfers.count
        cashTransfers.removeAll { transfer in
            guard let ids = plaidPairTransactionIds(from: transfer.note) else { return false }
            return ids.contains(where: { removedIds.contains($0) })
        }
        return previousCount - cashTransfers.count
    }

    func plaidSingleTransferSourceMarker(_ transactionId: String) -> String {
        "[PLAID_SINGLE:\(transactionId)]"
    }

    @discardableResult
    func removePlaidSingleTransfers(sourceIds: [String]) -> Int {
        let markers = sourceIds.map(plaidSingleTransferSourceMarker)
        let oldCount = cashTransfers.count
        cashTransfers.removeAll { transfer in
            markers.contains { transfer.note.contains($0) }
        }
        return oldCount - cashTransfers.count
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

        let hasManualCategory = persistentCategoryAssignment(for: transaction) != nil
        let categoryNeedsReview = transaction.category == nil && !hasManualCategory
        let ambiguousPlaidTransferCategory =
            (transaction.category ?? "").lowercased().contains("transfer") &&
            !isLikelyBankTransfer(transaction) && !hasManualCategory
        if categoryNeedsReview || ambiguousPlaidTransferCategory {
            let added = upsertPlaidReviewItem(
                sourceId: transaction.id,
                title: expense.name,
                detail: ambiguousPlaidTransferCategory
                    ? "Plaid labels this a transfer, but no receiving bank transaction was confirmed. It is currently recorded as a withdrawal/expense; review whether it belongs to an external account."
                    : "Plaid transaction needs category review.",
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
        updated.plaidMetadata?.userConfirmedNotTransfer = existing.plaidMetadata?.userConfirmedNotTransfer
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
        updated.plaidMetadata?.userConfirmedNotTransfer = existing.plaidMetadata?.userConfirmedNotTransfer
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
        let mapped = persistentCategoryAssignment(for: transaction) ?? mappedReconciliationCategory(for: transaction.category)
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
        let mapped = persistentCategoryAssignment(for: transaction) ?? mappedReconciliationCategory(for: transaction.category)
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
        let removedSingleTransfers = removePlaidSingleTransfers(sourceIds: [id])
        clearPlaidReviewItems(sourceIds: [id])
        return (oldExpenseCount - expenses.count) + (oldIncomeCount - incomes.count) + removedSingleTransfers
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
