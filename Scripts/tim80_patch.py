from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "Budgeting App/Models.swift"
text = PATH.read_text()

def once(old, new, label):
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 match, found {count}")
    text = text.replace(old, new, 1)

def between(start, end, replacement, label):
    global text
    a = text.find(start)
    b = text.find(end, a + 1) if a >= 0 else -1
    if a < 0 or b < 0:
        raise RuntimeError(f"{label}: markers not found")
    text = text[:a] + replacement + text[b:]

once(
'''            combined.plaidMetadata = tickerHoldings.first(where: { $0.plaidMetadata != nil })?.plaidMetadata
                ?? combined.plaidMetadata
            return combined
''',
'''            combined.plaidMetadata = nil
            combined.portfolioAccountId = nil
            return combined
''',
"derived All Portfolios identity"
)

once(
'''    var marginUsedFromLedger: Double {
        portfolioTransactions
            .filter { !isPlaidAuthoritativePortfolioAccount($0.portfolioAccountId) }
            .reduce(0) { partial, tx in
            switch tx.type {
            case .billPaidByMargin:
                return partial + tx.amount
            case .marginInterest:
                return partial + tx.amount
            case .sell:
                return partial - tx.amount
            case .manualAdjustment:
                return partial + tx.amount
            case .buy, .contribution, .dividend:
                return partial
            }
        }
    }
''',
'''    var marginUsedFromLedger: Double {
        portfolioTransactions
            .filter { !portfolioAccountIsPlaidAuthoritative($0.portfolioAccountId) }
            .reduce(0) { $0 + marginDelta(for: $1) }
    }
''',
"account-aware aggregate margin ledger"
)

holdings = r'''    var holdingsFromTransactions: [PortfolioHolding] {
        var buckets: [PortfolioPositionKey: (shares: Double, cost: Double)] = [:]
        let ordered = portfolioTransactions
            .filter { !portfolioAccountIsPlaidAuthoritative($0.portfolioAccountId) }
            .sorted { $0.date < $1.date }

        for tx in ordered {
            let ticker = tx.ticker?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            let key = PortfolioPositionKey(
                portfolioAccountId: tx.portfolioAccountId,
                securityIdentity: ticker
            )

            switch tx.type {
            case .buy:
                guard !ticker.isEmpty else { continue }
                let shares = max(tx.shares ?? 0, 0)
                guard shares > 0 else { continue }
                var item = buckets[key, default: (0, 0)]
                item.shares += shares
                item.cost += max(tx.amount, 0)
                buckets[key] = item
            case .sell:
                guard !ticker.isEmpty else { continue }
                let sharesToSell = max(tx.shares ?? 0, 0)
                guard sharesToSell > 0, var item = buckets[key], item.shares > 0 else { continue }
                let average = item.cost / item.shares
                let sold = min(sharesToSell, item.shares)
                item.shares -= sold
                item.cost = max(item.cost - average * sold, 0)
                buckets[key] = item
            default:
                continue
            }
        }

        return buckets.compactMap { key, bucket in
            guard bucket.shares > 0 else { return nil }
            let ticker = key.securityIdentity
            let existing = holdings.first {
                $0.portfolioAccountId == key.portfolioAccountId &&
                $0.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == ticker
            } ?? holdings.first {
                $0.plaidMetadata == nil &&
                $0.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == ticker
            }
            let quote = cachedQuotes[ticker]?.price ?? existing?.currentPrice ?? 0

            return PortfolioHolding(
                ticker: ticker,
                shares: bucket.shares,
                averageCost: bucket.cost / bucket.shares,
                currentPrice: quote,
                annualDividendPerShare: existing?.annualDividendPerShare ?? 0,
                dividendFrequency: existing?.dividendFrequency ?? .quarterly,
                assetType: existing?.assetType ?? .dividendStock,
                dividendReliability: existing?.dividendReliability ?? .medium,
                notes: existing?.notes ?? "",
                nextExDividendDate: existing?.nextExDividendDate,
                nextPayDate: existing?.nextPayDate,
                portfolioAccountId: key.portfolioAccountId
            )
        }
        .sorted {
            let comparison = $0.ticker.localizedStandardCompare($1.ticker)
            if comparison == .orderedSame {
                return portfolioAccountName(for: $0.portfolioAccountId)
                    .localizedStandardCompare(portfolioAccountName(for: $1.portfolioAccountId)) == .orderedAscending
            }
            return comparison == .orderedAscending
        }
    }

'''
between(
"    var holdingsFromTransactions: [PortfolioHolding] {",
"    func addPortfolioTransaction(",
holdings,
"account + security holding buckets"
)

once(
'''        fundingSource: InvestmentFundingSource
    ) {
''',
'''        fundingSource: InvestmentFundingSource,
        portfolioAccountId: UUID? = nil
    ) {
''',
"add investment account parameter"
)
once(
'''                amount: dollarsInvested,
                notes: fundingSource == .newContribution ? "Funding: New Contribution" : "Funding: Cash/Margin"
''',
'''                amount: dollarsInvested,
                notes: fundingSource == .newContribution ? "Funding: New Contribution" : "Funding: Cash/Margin",
                portfolioAccountId: portfolioAccountId
''',
"add investment account linkage"
)

cash = r'''    private func applyCashImpact(for transaction: PortfolioTransaction) {
        let amount = transaction.amount
        guard amount != 0 else { return }
        let resolvedAccountId = transaction.portfolioAccountId ?? (activePortfolioAccounts.count == 1 ? activePortfolioAccounts[0].id : nil)
        guard let resolvedAccountId,
              let accountIndex = portfolioAccounts.firstIndex(where: { $0.id == resolvedAccountId }),
              !portfolioAccountIsPlaidAuthoritative(resolvedAccountId) else { return }

        switch transaction.type {
        case .contribution:
            applyBankAccountDelta(
                accountId: transaction.fundingBankAccountId,
                legacyName: transaction.fundingBankAccount ?? "",
                delta: -amount
            )
            let marginPaydown = min(max(portfolioAccounts[accountIndex].marginBalance, 0), max(amount, 0))
            if marginPaydown > 0 {
                portfolioTransactions.append(
                    PortfolioTransaction(
                        date: transaction.date,
                        type: .manualAdjustment,
                        amount: -marginPaydown,
                        notes: "Cash contribution applied to margin balance",
                        portfolioAccountId: resolvedAccountId
                    )
                )
            }
            portfolioAccounts[accountIndex].cashBalance += max(amount - marginPaydown, 0)
        case .dividend:
            portfolioAccounts[accountIndex].cashBalance += amount
        case .buy:
            let cashUsed = min(max(portfolioAccounts[accountIndex].cashBalance, 0), max(amount, 0))
            portfolioAccounts[accountIndex].cashBalance = max(portfolioAccounts[accountIndex].cashBalance - cashUsed, 0)
            let marginDraw = max(amount - cashUsed, 0)
            if marginDraw > 0 {
                portfolioTransactions.append(
                    PortfolioTransaction(
                        date: transaction.date,
                        type: .manualAdjustment,
                        amount: marginDraw,
                        notes: "Auto margin draw for \(transaction.ticker ?? "investment") buy",
                        portfolioAccountId: resolvedAccountId
                    )
                )
            }
        case .sell:
            let marginPaydown = min(max(portfolioAccounts[accountIndex].marginBalance, 0), max(amount, 0))
            portfolioAccounts[accountIndex].cashBalance += max(amount - marginPaydown, 0)
        case .billPaidByMargin, .marginInterest, .manualAdjustment:
            break
        }
        roundPortfolioCashBalance()
    }

    private func reverseCashImpact(for transaction: PortfolioTransaction) {
        let amount = transaction.amount
        guard amount != 0 else { return }
        let resolvedAccountId = transaction.portfolioAccountId ?? (activePortfolioAccounts.count == 1 ? activePortfolioAccounts[0].id : nil)
        guard let resolvedAccountId,
              let accountIndex = portfolioAccounts.firstIndex(where: { $0.id == resolvedAccountId }),
              !portfolioAccountIsPlaidAuthoritative(resolvedAccountId) else { return }

        switch transaction.type {
        case .contribution:
            applyBankAccountDelta(
                accountId: transaction.fundingBankAccountId,
                legacyName: transaction.fundingBankAccount ?? "",
                delta: amount
            )
            portfolioAccounts[accountIndex].cashBalance -= amount
        case .dividend:
            portfolioAccounts[accountIndex].cashBalance -= amount
        case .buy:
            portfolioAccounts[accountIndex].cashBalance += max(amount, 0)
        case .sell:
            portfolioAccounts[accountIndex].cashBalance -= amount
        case .billPaidByMargin, .marginInterest, .manualAdjustment:
            break
        }
        portfolioAccounts[accountIndex].cashBalance = max(portfolioAccounts[accountIndex].cashBalance, 0)
        roundPortfolioCashBalance()
    }

    private func roundPortfolioCashBalance() {
        roundPortfolioAccountBalances()
    }

'''
between(
"    private func applyCashImpact(for transaction: PortfolioTransaction) {",
"    private func applyEditableCashImpact(for transaction: PortfolioTransaction) {",
cash,
"account scoped cash impact"
)

sync = r'''    func synchronizeLegacyMarginStateFromLedger() {
        let manualPortfolioAccounts = portfolioAccounts.filter { !portfolioAccountIsPlaidAuthoritative($0.id) }

        for account in manualPortfolioAccounts {
            let accountTransactions = portfolioTransactions.filter { $0.portfolioAccountId == account.id }
            if accountTransactions.isEmpty, account.marginBalance > 0 {
                portfolioTransactions.append(
                    PortfolioTransaction(
                        type: .manualAdjustment,
                        amount: account.marginBalance,
                        notes: "Imported existing margin balance",
                        portfolioAccountId: account.id
                    )
                )
            }
        }

        let manualTransactions = portfolioTransactions.filter { !portfolioAccountIsPlaidAuthoritative($0.portfolioAccountId) }
        let derivedHoldings = holdingsFromTransactions
        if !derivedHoldings.isEmpty || !manualTransactions.isEmpty {
            let derivedKeys = Set(derivedHoldings.map {
                PortfolioPositionKey(
                    portfolioAccountId: $0.portfolioAccountId,
                    securityIdentity: $0.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                )
            })
            let preservedHoldings = holdings.filter { holding in
                if portfolioAccountIsPlaidAuthoritative(holding.portfolioAccountId) { return true }
                let key = PortfolioPositionKey(
                    portfolioAccountId: holding.portfolioAccountId,
                    securityIdentity: holding.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                )
                return !derivedKeys.contains(key)
            }
            holdings = (preservedHoldings + derivedHoldings).sorted {
                let comparison = $0.ticker.localizedStandardCompare($1.ticker)
                if comparison == .orderedSame {
                    return portfolioAccountName(for: $0.portfolioAccountId)
                        .localizedStandardCompare(portfolioAccountName(for: $1.portfolioAccountId)) == .orderedAscending
                }
                return comparison == .orderedAscending
            }
        }

        for account in manualPortfolioAccounts {
            guard let index = portfolioAccounts.firstIndex(where: { $0.id == account.id }) else { continue }
            portfolioAccounts[index].marginBalance = max(marginUsedFromLedger(for: account.id), 0)
        }

        for account in manualPortfolioAccounts {
            sweepCashAgainstMarginIfNeeded(portfolioAccountId: account.id)
        }

        for account in manualPortfolioAccounts {
            guard let index = portfolioAccounts.firstIndex(where: { $0.id == account.id }) else { continue }
            portfolioAccounts[index].marginBalance = max(marginUsedFromLedger(for: account.id), 0)
        }

        roundPortfolioAccountBalances()
        portfolioSnapshot.freeMarginLimit = marginSettings.interestFreeMarginLimit
        portfolioSnapshot.marginInterestRate = marginSettings.marginInterestRate
    }

    private func sweepCashAgainstMarginIfNeeded(portfolioAccountId: UUID) {
        guard let accountIndex = portfolioAccounts.firstIndex(where: { $0.id == portfolioAccountId }) else { return }
        let availableCash = max(portfolioAccounts[accountIndex].cashBalance, 0)
        let currentMargin = max(portfolioAccounts[accountIndex].marginBalance, 0)
        let sweepAmount = min(availableCash, currentMargin)
        guard sweepAmount > 0 else { return }

        let roundedSweep = (sweepAmount * 100).rounded() / 100
        guard roundedSweep > 0 else { return }

        portfolioTransactions.append(
            PortfolioTransaction(
                type: .manualAdjustment,
                amount: -roundedSweep,
                notes: "Cash balance swept to pay down margin",
                portfolioAccountId: portfolioAccountId
            )
        )
        portfolioAccounts[accountIndex].cashBalance = max(availableCash - roundedSweep, 0)
        portfolioAccounts[accountIndex].marginBalance = max(currentMargin - roundedSweep, 0)
        roundPortfolioAccountBalances()
    }

'''
between(
"    func synchronizeLegacyMarginStateFromLedger() {",
"    private func recordPortfolioValueHistory() {",
sync,
"account scoped margin synchronization"
)

PATH.write_text(text)
