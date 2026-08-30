from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "Budgeting App/PlaidSyncEngine.swift"
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
'''        if plaidInvestmentCash > 0 {
            portfolioSnapshot.cashBalance = roundedCurrency(plaidInvestmentCash)
        }
''',
'''        if plaidInvestmentCash > 0, portfolioAccounts.isEmpty {
            portfolioSnapshot.cashBalance = roundedCurrency(plaidInvestmentCash)
        } else {
            synchronizeAggregatePortfolioBalances()
        }
''',
"aggregate Plaid cash"
)

once(
'''        migrateLegacyAccountsIfNeeded()
        return result
''',
'''        migrateLegacyAccountsIfNeeded()
        synchronizeLegacyMarginStateFromLedger()
        return result
''',
"sync account-scoped ledger after Plaid"
)

replacement = r'''    func applyPlaidHoldings(_ syncedHoldings: [PlaidSyncedHolding], syncedAt: Date) {
        let displayableHoldings = syncedHoldings.filter(isDisplayablePlaidHolding)
        let syncedExternalAccountIds = Set(displayableHoldings.map(\.accountId))
        let preservedHoldings = holdings.filter { holding in
            guard let metadata = holding.plaidMetadata else { return true }
            return !syncedExternalAccountIds.contains(metadata.accountId)
        }

        let groupedPlaidHoldings = Dictionary(grouping: displayableHoldings) { holding in
            let securityIdentity = holding.securityId ?? normalizedTicker(holding.ticker) ?? holding.name
            return "\(holding.accountId)|\(securityIdentity)"
        }

        watchlistTickers.removeAll { isOptionContractTicker($0) }

        let importedHoldings: [PortfolioHolding] = groupedPlaidHoldings.compactMap { _, plaidHoldings in
            guard let first = plaidHoldings.first,
                  let ticker = normalizedTicker(first.ticker) else { return nil }

            let portfolioAccountId = portfolioAccountId(forPlaidExternalAccountId: first.accountId)
            let existing = holdings.first { holding in
                guard holding.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == ticker else { return false }
                if let securityId = first.securityId,
                   holding.plaidMetadata?.securityId == securityId,
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

'''
between(
"    func applyPlaidHoldings(_ syncedHoldings: [PlaidSyncedHolding], syncedAt: Date) {",
"    func makeIncome(from transaction: PlaidSyncedTransaction",
replacement,
"Plaid account + security holdings"
)

once(
'''            notes: transaction.name,
            plaidMetadata: PlaidSourceMetadata(
''',
'''            notes: transaction.name,
            portfolioAccountId: portfolioAccountId(forPlaidExternalAccountId: transaction.accountId),
            plaidMetadata: PlaidSourceMetadata(
''',
"Plaid investment transaction account linkage"
)

PATH.write_text(text)
