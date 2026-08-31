import Foundation

extension BudgetModel {
    /// Relinks an existing pending row to Plaid's posted transaction ID before the
    /// reconciliation pass. This lets the normal exact-ID path preserve local edits
    /// while updating amount/date/direction from the posted transaction.
    func preparePlaidPendingTransactionReplacements(_ payload: PlaidSyncPayload) {
        for transaction in payload.transactions where !transaction.removed && !transaction.pending {
            if let pendingTransactionId = transaction.pendingTransactionId,
               !pendingTransactionId.isEmpty,
               relinkPendingPlaidRow(from: pendingTransactionId, to: transaction.id) {
                continue
            }

            // Backward-compatible fallback for backends/older persisted rows that do
            // not yet carry Plaid's pending_transaction_id.
            relinkSingleHeuristicPendingRow(to: transaction)
        }
    }
}

private extension BudgetModel {
    @discardableResult
    func relinkPendingPlaidRow(from pendingTransactionId: String, to postedTransactionId: String) -> Bool {
        if let index = expenses.firstIndex(where: { $0.plaidMetadata?.transactionId == pendingTransactionId }) {
            expenses[index].plaidMetadata?.transactionId = postedTransactionId
            return true
        }
        if let index = incomes.firstIndex(where: { $0.plaidMetadata?.transactionId == pendingTransactionId }) {
            incomes[index].plaidMetadata?.transactionId = postedTransactionId
            return true
        }
        return false
    }

    func relinkSingleHeuristicPendingRow(to transaction: PlaidSyncedTransaction) {
        let expenseMatches = expenses.indices.filter { index in
            let expense = expenses[index]
            guard pendingMetadataMatches(
                expense.plaidMetadata,
                legacyPendingMarker: expense.note == "Plaid pending transaction",
                transaction: transaction
            ),
            abs(expense.amount - abs(transaction.amount)) < 0.01,
            pendingDayDistance(expense.date, transaction.date) <= 3 else {
                return false
            }
            return pendingNamesLikelyMatch(expense.name, transaction.merchantName ?? transaction.name)
        }

        let incomeMatches = incomes.indices.filter { index in
            let income = incomes[index]
            guard pendingMetadataMatches(
                income.plaidMetadata,
                legacyPendingMarker: false,
                transaction: transaction
            ),
            abs(income.amount - abs(transaction.amount)) < 0.01,
            pendingDayDistance(income.date, transaction.date) <= 3 else {
                return false
            }
            return pendingNamesLikelyMatch(income.name, transaction.merchantName ?? transaction.name)
        }

        guard expenseMatches.count + incomeMatches.count == 1 else { return }
        if let index = expenseMatches.first {
            expenses[index].plaidMetadata?.transactionId = transaction.id
        } else if let index = incomeMatches.first {
            incomes[index].plaidMetadata?.transactionId = transaction.id
        }
    }

    func pendingMetadataMatches(
        _ metadata: PlaidSourceMetadata?,
        legacyPendingMarker: Bool,
        transaction: PlaidSyncedTransaction
    ) -> Bool {
        guard let metadata,
              metadata.transactionId != nil,
              metadata.transactionId != transaction.id,
              metadata.accountId == transaction.accountId else {
            return false
        }
        return metadata.isPending == true || legacyPendingMarker
    }

    func pendingNamesLikelyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedPendingText(lhs)
        let right = normalizedPendingText(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.contains(right) || right.contains(left)
    }

    func normalizedPendingText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
    }

    func pendingDayDistance(_ lhs: Date, _ rhs: Date) -> Int {
        let calendar = Calendar.current
        let left = calendar.startOfDay(for: lhs)
        let right = calendar.startOfDay(for: rhs)
        return abs(calendar.dateComponents([.day], from: left, to: right).day ?? Int.max)
    }
}
