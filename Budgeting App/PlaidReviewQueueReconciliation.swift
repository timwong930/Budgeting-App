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
