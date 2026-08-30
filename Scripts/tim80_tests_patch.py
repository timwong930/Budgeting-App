from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "Budgeting AppTests/CuanMarketModelsTests.swift"
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
'''        testPlaidDuplicateTickerHoldingsAggregateWithoutCrash()
''',
'''        testPlaidDuplicateTickerHoldingsStayAccountScoped()
        testManualSameTickerHoldingsStayAccountScoped()
        testPortfolioCashAndMarginStayAccountScoped()
''',
"test calls"
)

once(
'''        let holding = budget.holdings.first
        assert(holding?.ticker == "AAPL", "Expected Plaid ticker to be normalized")
''',
'''        let holding = budget.holdings.first { $0.plaidMetadata?.accountId == "inv-1" }
        assert(holding?.ticker == "AAPL", "Expected Plaid ticker to be normalized")
''',
"Plaid metadata test account lookup"
)

replacement = r'''    private static func testPlaidDuplicateTickerHoldingsStayAccountScoped() {
        let budget = BudgetModel()

        _ = budget.applyPlaidSync(
            PlaidSyncPayload(
                accounts: [
                    PlaidSyncedAccount(id: "inv-1", itemId: "item-1", name: "Brokerage A", type: .investment, subtype: "brokerage", currentBalance: 180, availableBalance: 0, creditLimit: nil, institutionName: "Broker A"),
                    PlaidSyncedAccount(id: "inv-2", itemId: "item-2", name: "Brokerage B", type: .investment, subtype: "brokerage", currentBalance: 362, availableBalance: 0, creditLimit: nil, institutionName: "Broker B")
                ],
                transactions: [],
                creditLiabilities: [],
                holdings: [
                    PlaidSyncedHolding(accountId: "inv-1", itemId: "item-1", securityId: "sec-aapl-1", ticker: "AAPL", name: "Apple", quantity: 1, costBasis: 100, institutionPrice: 180, institutionValue: 180, priceAsOf: nil, securityType: "equity"),
                    PlaidSyncedHolding(accountId: "inv-2", itemId: "item-2", securityId: "sec-aapl-2", ticker: "AAPL", name: "Apple", quantity: 2, costBasis: 260, institutionPrice: 181, institutionValue: 362, priceAsOf: nil, securityType: "equity")
                ],
                investmentTransactions: [],
                connectionStatuses: []
            )
        )

        let aaplHoldings = budget.holdings.filter { $0.ticker == "AAPL" }
        assert(aaplHoldings.count == 2, "Expected same ticker to remain as two brokerage-scoped positions")
        assert(Set(aaplHoldings.compactMap(\.portfolioAccountId)).count == 2, "Expected each Plaid holding to retain a different portfolio account ID")
        assert(aaplHoldings.map(\.shares).sorted() == [1, 2], "Expected brokerage quantities to remain independent")

        let aggregate = budget.consolidatedHoldings.first { $0.ticker == "AAPL" }
        assert(aggregate?.shares == 3, "Expected All Portfolios to sum same-ticker shares")
        assert(abs((aggregate?.averageCost ?? 0) - 120) < 0.001, "Expected All Portfolios average cost to be share weighted")
        assert(aggregate?.portfolioAccountId == nil, "Expected All Portfolios holding to be derived rather than tied to one brokerage")
    }

    private static func testManualSameTickerHoldingsStayAccountScoped() {
        let accountA = PortfolioAccount(name: "Brokerage A", cashBalance: 1_000)
        let accountB = PortfolioAccount(name: "Brokerage B", cashBalance: 1_000)
        let budget = BudgetModel()
        budget.portfolioAccounts = [accountA, accountB]
        budget.portfolioTransactions = []
        budget.holdings = []
        budget.portfolioSnapshot.cashBalance = 0
        budget.portfolioSnapshot.marginUsed = 0

        budget.addPortfolioTransaction(
            PortfolioTransaction(type: .buy, ticker: "AAPL", shares: 2, pricePerShare: 100, amount: 200, portfolioAccountId: accountA.id)
        )
        budget.addPortfolioTransaction(
            PortfolioTransaction(type: .buy, ticker: "AAPL", shares: 3, pricePerShare: 150, amount: 450, portfolioAccountId: accountB.id)
        )

        let positions = budget.holdings.filter { $0.ticker == "AAPL" }
        assert(positions.count == 2, "Expected manual same-ticker buys to produce two account-scoped holdings")
        let holdingA = positions.first { $0.portfolioAccountId == accountA.id }
        let holdingB = positions.first { $0.portfolioAccountId == accountB.id }
        assert(holdingA?.shares == 2 && holdingA?.averageCost == 100, "Expected Brokerage A quantity and cost basis to stay isolated")
        assert(holdingB?.shares == 3 && holdingB?.averageCost == 150, "Expected Brokerage B quantity and cost basis to stay isolated")

        let aggregate = budget.consolidatedHoldings.first { $0.ticker == "AAPL" }
        assert(aggregate?.shares == 5, "Expected All Portfolios to sum manual same-ticker shares")
        assert(abs((aggregate?.averageCost ?? 0) - 130) < 0.001, "Expected aggregate manual cost basis to be weighted correctly")
    }

    private static func testPortfolioCashAndMarginStayAccountScoped() {
        let accountA = PortfolioAccount(name: "Brokerage A", cashBalance: 100)
        let accountB = PortfolioAccount(name: "Brokerage B", cashBalance: 25)
        let budget = BudgetModel()
        budget.portfolioAccounts = [accountA, accountB]
        budget.portfolioTransactions = []
        budget.holdings = []
        budget.portfolioSnapshot.cashBalance = 0
        budget.portfolioSnapshot.marginUsed = 0

        budget.addPortfolioTransaction(
            PortfolioTransaction(type: .buy, ticker: "MSFT", shares: 1, pricePerShare: 200, amount: 200, portfolioAccountId: accountA.id)
        )
        budget.addPortfolioTransaction(
            PortfolioTransaction(type: .buy, ticker: "NVDA", shares: 1, pricePerShare: 75, amount: 75, portfolioAccountId: accountB.id)
        )

        let refreshedA = budget.portfolioAccounts.first { $0.id == accountA.id }
        let refreshedB = budget.portfolioAccounts.first { $0.id == accountB.id }
        assert(refreshedA?.cashBalance == 0 && refreshedA?.marginBalance == 100, "Expected Brokerage A cash and margin to update independently")
        assert(refreshedB?.cashBalance == 0 && refreshedB?.marginBalance == 50, "Expected Brokerage B cash and margin to update independently")
        assert(budget.portfolioSnapshot.cashBalance == 0, "Expected All Portfolios cash to equal account cash total")
        assert(budget.portfolioSnapshot.marginUsed == 150, "Expected All Portfolios margin to equal account margin total")
    }

'''
between(
"    private static func testPlaidDuplicateTickerHoldingsAggregateWithoutCrash() {",
"    private static func testFinancialAccountCodableRoundTrip() {",
replacement,
"replace duplicate ticker regression and add account isolation tests"
)

PATH.write_text(text)
