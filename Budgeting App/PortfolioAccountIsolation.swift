import Foundation

struct PortfolioPositionKey: Hashable {
    let portfolioAccountId: UUID?
    let securityIdentity: String
}

extension BudgetModel {
    var activePortfolioAccounts: [PortfolioAccount] {
        portfolioAccounts
            .filter(\.isActive)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func holdings(forPortfolioAccountId portfolioAccountId: UUID?) -> [PortfolioHolding] {
        guard let portfolioAccountId else { return consolidatedHoldings }
        return holdings
            .filter { $0.portfolioAccountId == portfolioAccountId }
            .sorted { lhs, rhs in
                let comparison = lhs.ticker.localizedStandardCompare(rhs.ticker)
                if comparison == .orderedSame {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return comparison == .orderedAscending
            }
    }

    func transactions(forPortfolioAccountId portfolioAccountId: UUID?) -> [PortfolioTransaction] {
        guard let portfolioAccountId else { return portfolioTransactions }
        return portfolioTransactions.filter { $0.portfolioAccountId == portfolioAccountId }
    }

    func portfolioAccountName(for portfolioAccountId: UUID?) -> String {
        guard let portfolioAccountId else { return "All Portfolios" }
        return portfolioAccounts.first(where: { $0.id == portfolioAccountId })?.name ?? "Unknown Portfolio"
    }

    func portfolioCashBalance(for portfolioAccountId: UUID?) -> Double {
        guard let portfolioAccountId else {
            return activePortfolioAccounts.reduce(0) { $0 + $1.cashBalance }
        }
        return portfolioAccounts.first(where: { $0.id == portfolioAccountId })?.cashBalance ?? 0
    }

    func portfolioMarginBalance(for portfolioAccountId: UUID?) -> Double {
        guard let portfolioAccountId else {
            return activePortfolioAccounts.reduce(0) { $0 + $1.marginBalance }
        }
        return portfolioAccounts.first(where: { $0.id == portfolioAccountId })?.marginBalance ?? 0
    }

    func portfolioAccountIsPlaidAuthoritative(_ portfolioAccountId: UUID?) -> Bool {
        guard let portfolioAccountId,
              let portfolioAccount = portfolioAccounts.first(where: { $0.id == portfolioAccountId }),
              let financialAccountId = portfolioAccount.financialAccountId,
              let financialAccount = financialAccounts.first(where: { $0.id == financialAccountId }) else {
            return false
        }
        return financialAccount.source == .plaid
    }

    func marginDelta(for transaction: PortfolioTransaction) -> Double {
        switch transaction.type {
        case .billPaidByMargin, .marginInterest, .manualAdjustment:
            return transaction.amount
        case .sell:
            return -transaction.amount
        case .buy, .contribution, .dividend:
            return 0
        }
    }

    func marginUsedFromLedger(for portfolioAccountId: UUID) -> Double {
        portfolioTransactions
            .filter {
                $0.portfolioAccountId == portfolioAccountId &&
                !portfolioAccountIsPlaidAuthoritative($0.portfolioAccountId)
            }
            .reduce(0) { $0 + marginDelta(for: $1) }
    }

    func portfolioAccountId(forPlaidExternalAccountId externalAccountId: String) -> UUID? {
        guard let financialAccountId = financialAccounts.first(where: {
            $0.kind == .investment && $0.externalAccountId == externalAccountId
        })?.id else {
            return nil
        }
        return portfolioAccounts.first(where: { $0.financialAccountId == financialAccountId })?.id
    }

    func synchronizeAggregatePortfolioBalances() {
        guard !portfolioAccounts.isEmpty else { return }
        let activeAccounts = portfolioAccounts.filter(\.isActive)
        portfolioSnapshot.cashBalance = roundedAccountCurrency(activeAccounts.reduce(0) { $0 + $1.cashBalance })
        portfolioSnapshot.marginUsed = roundedAccountCurrency(activeAccounts.reduce(0) { $0 + $1.marginBalance })
    }

    func roundPortfolioAccountBalances() {
        for index in portfolioAccounts.indices {
            portfolioAccounts[index].cashBalance = roundedAccountCurrency(portfolioAccounts[index].cashBalance)
            portfolioAccounts[index].marginBalance = roundedAccountCurrency(portfolioAccounts[index].marginBalance)
        }
        synchronizeAggregatePortfolioBalances()
    }

    private func roundedAccountCurrency(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
