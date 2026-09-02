import Foundation

extension BudgetModel {
    /// Finalizes complete Plaid investment snapshots after the normal sync engine runs.
    ///
    /// The backend only includes an account ID here when `/investments/holdings/get`
    /// completed successfully for that account. This lets an empty holdings array mean
    /// "the account now has zero positions" without treating a failed/unsupported
    /// holdings request as an authoritative empty snapshot.
    func finalizePlaidHoldingSnapshots(_ payload: PlaidSyncPayload) {
        guard let snapshotAccountIds = payload.holdingSnapshotAccountIds else { return }
        let completeAccountIds = Set(snapshotAccountIds)
        guard !completeAccountIds.isEmpty else { return }

        let accountIdsWithHoldingRows = Set(payload.holdings.map(\.accountId))
        let zeroHoldingAccountIds = completeAccountIds.subtracting(accountIdsWithHoldingRows)
        guard !zeroHoldingAccountIds.isEmpty else { return }

        holdings.removeAll { holding in
            guard let accountId = holding.plaidMetadata?.accountId else {
                // Manual positions and legacy/manual holdings are never owned by Plaid.
                return false
            }
            return zeroHoldingAccountIds.contains(accountId)
        }

        // Investment account cash/margin was already refreshed from the successful
        // account snapshot in applyPlaidSync. Rebuild only the aggregate totals after
        // removing stale Plaid-owned positions.
        synchronizeAggregatePortfolioBalances()
        let holdingsValue = holdings.reduce(0) { total, holding in
            let ticker = holding.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let price = cachedQuotes[ticker]?.price ?? holding.currentPrice
            return total + holding.shares * price
        }
        portfolioSnapshot.portfolioValue = roundedPlaidSnapshotCurrency(
            holdingsValue + portfolioSnapshot.cashBalance
        )
    }

    private func roundedPlaidSnapshotCurrency(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
