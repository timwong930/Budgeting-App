import Foundation

extension BudgetModel {
    /// Review dismissal changes only the notification list. The imported
    /// expense, income, transfer, and original Plaid source data are untouched.
    @discardableResult
    func dismissPlaidReviewReminder(id: UUID) -> PlaidReviewItem? {
        guard let index = plaidReviewItems.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let dismissed = plaidReviewItems.remove(at: index)
        saveNow()
        return dismissed
    }

    /// Restore reminders dismissed during the current review session. Source
    /// IDs, rather than generated review UUIDs, ensure no duplicate reminders.
    func restoreDismissedPlaidReviewReminders(_ reminders: [PlaidReviewItem]) {
        var restored = false
        for reminder in reminders where !plaidReviewItems.contains(where: {
            $0.sourceId == reminder.sourceId
        }) {
            // A match may have been confirmed after the reminder was
            // dismissed. Undoing dismissal cannot resurrect stale advice for
            // a Plaid transaction that is already part of a confirmed pair.
            let nowLinked = cashTransfers.contains { transfer in
                plaidPairTransactionIds(from: transfer.note)?.contains(reminder.sourceId) == true
            }
            guard !nowLinked else { continue }
            plaidReviewItems.append(reminder)
            restored = true
        }
        if restored { saveNow() }
    }

    /// Restoring a duplicate changes the app's classification, not bank history.
    @discardableResult
    func restoreDuplicateIncome(id: UUID) -> Bool {
        guard let entry = incomes.first(where: { $0.id == id && $0.reviewCorrection == .duplicate }) else {
            return false
        }
        var restored = entry
        restored.reviewCorrection = restored.correctionBeforeDuplicate
        restored.correctionBeforeDuplicate = nil
        restored.bucketCounterpartSourceId = nil
        updateIncomeEntry(restored)
        saveNow()
        return true
    }

    @discardableResult
    func restoreDuplicateExpense(id: UUID) -> Bool {
        guard let entry = expenses.first(where: { $0.id == id && $0.reviewCorrection == .duplicate }) else {
            return false
        }
        var restored = entry
        restored.reviewCorrection = restored.correctionBeforeDuplicate
        restored.correctionBeforeDuplicate = nil
        restored.bucketCounterpartSourceId = nil
        updateExpense(restored)
        saveNow()
        return true
    }

    /// Bucket reallocations have two signs but the same Plaid account. They
    /// must never be modeled as a bank-to-bank transfer or a new bank balance.
    func bucketTransferIncomeCandidates(for expense: Expense) -> [IncomeEntry] {
        guard expense.reviewCorrection != .duplicate,
              let metadata = expense.plaidMetadata,
              let sourceID = metadata.transactionId,
              let externalAccountID = metadata.accountId,
              metadata.isPending != true else { return [] }
        return incomes.filter { income in
            guard income.reviewCorrection != .duplicate,
                  income.bucketCounterpartSourceId == nil,
                  let incomeID = income.plaidMetadata?.transactionId,
                  incomeID != sourceID,
                  income.plaidMetadata?.accountId == externalAccountID,
                  income.plaidMetadata?.isPending != true,
                  abs(income.amount - expense.amount) < 0.01 else { return false }
            let days = abs(Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: expense.date),
                to: Calendar.current.startOfDay(for: income.date)
            ).day ?? 999)
            return days <= 3
        }.sorted { $0.date > $1.date }
    }

    /// User confirmation is required: same amount/date alone does not prove a
    /// bucket pair, even within one Plaid account.
    @discardableResult
    func confirmInternalBucketTransfer(expenseID: UUID, incomeID: UUID, fromBucket: String, toBucket: String) -> Bool {
        guard let expenseIndex = expenses.firstIndex(where: { $0.id == expenseID }),
              let incomeIndex = incomes.firstIndex(where: { $0.id == incomeID }),
              let sourceID = expenses[expenseIndex].plaidMetadata?.transactionId,
              let counterpartID = incomes[incomeIndex].plaidMetadata?.transactionId,
              expenses[expenseIndex].bucketCounterpartSourceId == nil,
              bucketTransferIncomeCandidates(for: expenses[expenseIndex]).contains(where: { $0.id == incomeID })
        else { return false }

        var outgoing = expenses[expenseIndex]
        outgoing.reviewCorrection = .bucketTransfer
        outgoing.bucketFromName = fromBucket.trimmingCharacters(in: .whitespacesAndNewlines)
        outgoing.bucketToName = toBucket.trimmingCharacters(in: .whitespacesAndNewlines)
        outgoing.bucketCounterpartSourceId = counterpartID

        var incoming = incomes[incomeIndex]
        incoming.reviewCorrection = .bucketTransfer
        incoming.bucketFromName = outgoing.bucketFromName
        incoming.bucketToName = outgoing.bucketToName
        incoming.bucketCounterpartSourceId = sourceID

        updateExpense(outgoing)
        updateIncomeEntry(incoming)
        plaidReviewItems.removeAll {
            $0.sourceId == sourceID || $0.sourceId == counterpartID
        }
        saveNow()
        return true
    }

    /// Restoring one side must not leave a phantom link on the opposite side.
    func clearBucketCounterpartLink(sourceID: String, counterpartID: String?) {
        guard let counterpartID else { return }
        if let index = expenses.firstIndex(where: {
            $0.plaidMetadata?.transactionId == counterpartID &&
            $0.bucketCounterpartSourceId == sourceID
        }) {
            expenses[index].bucketCounterpartSourceId = nil
        }
        if let index = incomes.firstIndex(where: {
            $0.plaidMetadata?.transactionId == counterpartID &&
            $0.bucketCounterpartSourceId == sourceID
        }) {
            incomes[index].bucketCounterpartSourceId = nil
        }
    }

    /// Replayed Plaid deltas must not silently clear an unresolved review item merely
    /// because the Plaid-owned row already exists locally. Preserve prior review state
    /// until the user removes it or the source transaction is genuinely replaced/removed.
    @discardableResult
    func restoreUnresolvedPlaidReviews(
        _ previousReviews: [PlaidReviewItem],
        payload: PlaidSyncPayload
    ) -> Int {
        let activeSourceIds = Set(
            payload.transactions
                .filter { !$0.removed }
                .map(\.id)
        )
        var restored = 0

        for review in previousReviews {
            guard activeSourceIds.contains(review.sourceId),
                  !plaidReviewItems.contains(where: { $0.sourceId == review.sourceId }),
                  plaidTransactionRowExists(sourceId: review.sourceId) else {
                continue
            }
            plaidReviewItems.append(review)
            restored += 1
        }

        return restored
    }
}

private extension BudgetModel {
    func plaidTransactionRowExists(sourceId: String) -> Bool {
        expenses.contains { $0.plaidMetadata?.transactionId == sourceId } ||
        incomes.contains { $0.plaidMetadata?.transactionId == sourceId }
    }
}
