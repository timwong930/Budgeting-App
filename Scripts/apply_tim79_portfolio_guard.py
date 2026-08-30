from pathlib import Path

path = Path("Budgeting App/Models.swift")
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
'''                    PortfolioTransaction(
                        date: transaction.date,
                        type: .manualAdjustment,
                        amount: -marginPaydown,
                        notes: "Cash contribution applied to margin balance"
                    )
''',
'''                    PortfolioTransaction(
                        date: transaction.date,
                        type: .manualAdjustment,
                        amount: -marginPaydown,
                        notes: "Cash contribution applied to margin balance",
                        portfolioAccountId: transaction.portfolioAccountId
                    )
''', "margin paydown account ref")

replace_once(
'''                PortfolioTransaction(
                    date: transaction.date,
                    type: .manualAdjustment,
                    amount: marginDraw,
                    notes: "Auto margin draw for \\(transaction.ticker ?? "investment") buy"
                )
''',
'''                PortfolioTransaction(
                    date: transaction.date,
                    type: .manualAdjustment,
                    amount: marginDraw,
                    notes: "Auto margin draw for \\(transaction.ticker ?? "investment") buy",
                    portfolioAccountId: transaction.portfolioAccountId
                )
''', "margin draw account ref")

replace_once(
'''    func synchronizeLegacyMarginStateFromLedger() {
        let legacyMarginUsed = max(portfolioSnapshot.marginUsed, 0)
        if portfolioTransactions.isEmpty, legacyMarginUsed > 0 {
            portfolioTransactions.append(
                PortfolioTransaction(
                    type: .manualAdjustment,
                    amount: legacyMarginUsed,
                    notes: "Imported existing margin balance"
                )
            )
        }

        let legacyTransactions = portfolioTransactions.filter { !isPlaidAuthoritativePortfolioAccount($0.portfolioAccountId) }
        let derivedHoldings = holdingsFromTransactions
        if !derivedHoldings.isEmpty || !legacyTransactions.isEmpty {
            holdings = derivedHoldings
            portfolioSnapshot.marginUsed = max(marginUsedFromLedger, 0)
        }

        sweepCashAgainstMarginIfNeeded()

        portfolioSnapshot.freeMarginLimit = marginSettings.interestFreeMarginLimit
        portfolioSnapshot.marginInterestRate = marginSettings.marginInterestRate
    }

    private func sweepCashAgainstMarginIfNeeded() {
''',
'''    func synchronizeLegacyMarginStateFromLedger() {
        let manualPortfolioAccounts = portfolioAccounts.filter { !isPlaidAuthoritativePortfolioAccount($0.id) }
        var legacyTransactions = portfolioTransactions.filter { !isPlaidAuthoritativePortfolioAccount($0.portfolioAccountId) }
        let legacyMarginUsed = max(portfolioSnapshot.marginUsed, 0)
        if legacyTransactions.isEmpty,
           legacyMarginUsed > 0,
           let manualPortfolioAccount = manualPortfolioAccounts.first {
            portfolioTransactions.append(
                PortfolioTransaction(
                    type: .manualAdjustment,
                    amount: legacyMarginUsed,
                    notes: "Imported existing margin balance",
                    portfolioAccountId: manualPortfolioAccount.id
                )
            )
            legacyTransactions = portfolioTransactions.filter { !isPlaidAuthoritativePortfolioAccount($0.portfolioAccountId) }
        }

        let derivedHoldings = holdingsFromTransactions
        if !derivedHoldings.isEmpty || !legacyTransactions.isEmpty {
            holdings = derivedHoldings
            portfolioSnapshot.marginUsed = max(marginUsedFromLedger, 0)
        }

        if let manualPortfolioAccount = manualPortfolioAccounts.first {
            sweepCashAgainstMarginIfNeeded(portfolioAccountId: manualPortfolioAccount.id)
        }

        portfolioSnapshot.freeMarginLimit = marginSettings.interestFreeMarginLimit
        portfolioSnapshot.marginInterestRate = marginSettings.marginInterestRate
    }

    private func sweepCashAgainstMarginIfNeeded(portfolioAccountId: UUID) {
''', "manual portfolio synchronization guard")

replace_once(
'''        portfolioTransactions.append(
            PortfolioTransaction(
                type: .manualAdjustment,
                amount: -roundedSweep,
                notes: "Cash balance swept to pay down margin"
            )
        )
''',
'''        portfolioTransactions.append(
            PortfolioTransaction(
                type: .manualAdjustment,
                amount: -roundedSweep,
                notes: "Cash balance swept to pay down margin",
                portfolioAccountId: portfolioAccountId
            )
        )
''', "sweep account ref")

path.write_text(text)
if 'sweepCashAgainstMarginIfNeeded()' in text:
    raise RuntimeError('unguarded legacy sweep call remains')
print('TIM-79 portfolio guard checks passed')
