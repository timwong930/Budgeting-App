import Foundation

extension BudgetModel {
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
