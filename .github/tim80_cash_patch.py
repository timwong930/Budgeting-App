from pathlib import Path

engine_path = Path('Budgeting App/PlaidSyncEngine.swift')
source = engine_path.read_text()

old_account = '''        guard account.type == .investment else { return }
        let cashBalance = roundedCurrency(account.availableBalance ?? 0)
        if let index = portfolioAccounts.firstIndex(where: { $0.financialAccountId == financialAccountId }) {
            portfolioAccounts[index].name = account.name
            portfolioAccounts[index].cashBalance = cashBalance
            portfolioAccounts[index].isActive = true
        } else {
            portfolioAccounts.append(
                PortfolioAccount(
                    financialAccountId: financialAccountId,
                    name: account.name,
                    cashBalance: cashBalance
                )
            )
        }
'''
new_account = '''        guard account.type == .investment else { return }
        let availableBalance = roundedCurrency(account.availableBalance ?? 0)
        let cashBalance = roundedCurrency(max(availableBalance, 0))
        let marginBalance = roundedCurrency(max(-availableBalance, 0))
        if let index = portfolioAccounts.firstIndex(where: { $0.financialAccountId == financialAccountId }) {
            portfolioAccounts[index].name = account.name
            portfolioAccounts[index].cashBalance = cashBalance
            portfolioAccounts[index].marginBalance = marginBalance
            portfolioAccounts[index].isActive = true
        } else {
            portfolioAccounts.append(
                PortfolioAccount(
                    financialAccountId: financialAccountId,
                    name: account.name,
                    cashBalance: cashBalance,
                    marginBalance: marginBalance
                )
            )
        }
'''
if old_account not in source:
    raise SystemExit('investment account balance block not found')
source = source.replace(old_account, new_account, 1)

old_holdings_start = '''    func applyPlaidHoldings(_ syncedHoldings: [PlaidSyncedHolding], syncedAt: Date) {
        let displayableHoldings = syncedHoldings.filter(isDisplayablePlaidHolding)
        let syncedExternalAccountIds = Set(displayableHoldings.map(\\.accountId))
'''
new_holdings_start = '''    func applyPlaidHoldings(_ syncedHoldings: [PlaidSyncedHolding], syncedAt: Date) {
        let syncedExternalAccountIds = Set(syncedHoldings.map(\\.accountId))
        applyPlaidCashHoldings(syncedHoldings)
        let displayableHoldings = syncedHoldings.filter(isDisplayablePlaidHolding)
'''
if old_holdings_start not in source:
    raise SystemExit('applyPlaidHoldings start not found')
source = source.replace(old_holdings_start, new_holdings_start, 1)

old_display = '''    func isDisplayablePlaidHolding(_ holding: PlaidSyncedHolding) -> Bool {
        guard let ticker = normalizedTicker(holding.ticker) else { return false }
        let securityType = holding.securityType?.lowercased() ?? ""
        if securityType.contains("option") || securityType.contains("derivative") {
            return false
        }
        return !isOptionContractTicker(ticker)
    }
'''
new_display = '''    func isPlaidCashHolding(_ holding: PlaidSyncedHolding) -> Bool {
        let ticker = normalizedTicker(holding.ticker)
        let securityType = holding.securityType?.lowercased() ?? ""
        return ticker == "CUR:USD" || securityType.contains("cash")
    }

    func plaidCashAmount(for holding: PlaidSyncedHolding) -> Double {
        if let institutionValue = holding.institutionValue {
            return institutionValue
        }
        if let institutionPrice = holding.institutionPrice {
            return holding.quantity * institutionPrice
        }
        return holding.quantity
    }

    func applyPlaidCashHoldings(_ syncedHoldings: [PlaidSyncedHolding]) {
        let groupedCashHoldings = Dictionary(grouping: syncedHoldings.filter(isPlaidCashHolding)) { $0.accountId }
        for (externalAccountId, cashHoldings) in groupedCashHoldings {
            guard let portfolioAccountId = portfolioAccountId(forPlaidExternalAccountId: externalAccountId),
                  let index = portfolioAccounts.firstIndex(where: { $0.id == portfolioAccountId }) else {
                continue
            }

            let netCash = roundedCurrency(cashHoldings.reduce(0) { $0 + plaidCashAmount(for: $1) })
            portfolioAccounts[index].cashBalance = roundedCurrency(max(netCash, 0))
            portfolioAccounts[index].marginBalance = roundedCurrency(max(-netCash, 0))
        }
    }

    func isDisplayablePlaidHolding(_ holding: PlaidSyncedHolding) -> Bool {
        if isPlaidCashHolding(holding) {
            return false
        }
        guard let ticker = normalizedTicker(holding.ticker) else { return false }
        let securityType = holding.securityType?.lowercased() ?? ""
        if securityType.contains("option") || securityType.contains("derivative") {
            return false
        }
        return !isOptionContractTicker(ticker)
    }
'''
if old_display not in source:
    raise SystemExit('displayable holding helper not found')
source = source.replace(old_display, new_display, 1)
engine_path.write_text(source)

test_path = Path('Budgeting AppTests/CuanMarketModelsTests.swift')
tests = test_path.read_text()
call_anchor = '''        testPlaidOptionHoldingsDoNotImportAsStockTickers()
        testPlaidDuplicateTickerHoldingsStayAccountScoped()
'''
call_replacement = '''        testPlaidOptionHoldingsDoNotImportAsStockTickers()
        testPlaidCashHoldingFeedsCashAndMarginBalances()
        testPlaidDuplicateTickerHoldingsStayAccountScoped()
'''
if call_anchor not in tests:
    raise SystemExit('test call anchor not found')
tests = tests.replace(call_anchor, call_replacement, 1)

function_anchor = '''    private static func testPlaidDuplicateTickerHoldingsStayAccountScoped() {
'''
new_test = '''    private static func testPlaidCashHoldingFeedsCashAndMarginBalances() {
        let budget = BudgetModel()

        _ = budget.applyPlaidSync(
            PlaidSyncPayload(
                accounts: [
                    PlaidSyncedAccount(id: "inv-cash", itemId: "item-1", name: "Cash Brokerage", type: .investment, subtype: "brokerage", currentBalance: 485.50, availableBalance: 999, creditLimit: nil, institutionName: "Broker"),
                    PlaidSyncedAccount(id: "inv-margin", itemId: "item-1", name: "Margin Brokerage", type: .investment, subtype: "brokerage", currentBalance: 285, availableBalance: -999, creditLimit: nil, institutionName: "Broker")
                ],
                transactions: [],
                creditLiabilities: [],
                holdings: [
                    PlaidSyncedHolding(accountId: "inv-cash", itemId: "item-1", securityId: "sec-aapl", ticker: "AAPL", name: "Apple", quantity: 2, costBasis: 300, institutionPrice: 180, institutionValue: 360, priceAsOf: nil, securityType: "equity"),
                    PlaidSyncedHolding(accountId: "inv-cash", itemId: "item-1", securityId: "cash-usd-1", ticker: "CUR:USD", name: "US Dollar", quantity: 125.50, costBasis: nil, institutionPrice: 1, institutionValue: 125.50, priceAsOf: nil, securityType: "cash"),
                    PlaidSyncedHolding(accountId: "inv-margin", itemId: "item-1", securityId: "sec-msft", ticker: "MSFT", name: "Microsoft", quantity: 1, costBasis: 300, institutionPrice: 360, institutionValue: 360, priceAsOf: nil, securityType: "equity"),
                    PlaidSyncedHolding(accountId: "inv-margin", itemId: "item-1", securityId: "cash-usd-2", ticker: "CUR:USD", name: "US Dollar", quantity: -75, costBasis: nil, institutionPrice: 1, institutionValue: -75, priceAsOf: nil, securityType: "cash")
                ],
                investmentTransactions: [],
                connectionStatuses: []
            )
        )

        let cashAccount = budget.portfolioAccounts.first { $0.name == "Cash Brokerage" }
        let marginAccount = budget.portfolioAccounts.first { $0.name == "Margin Brokerage" }
        assert(cashAccount?.cashBalance == 125.50, "Expected CUR:USD positive value to become brokerage cash balance")
        assert(cashAccount?.marginBalance == 0, "Expected positive CUR:USD cash not to create margin")
        assert(marginAccount?.cashBalance == 0, "Expected negative CUR:USD value not to remain as negative cash")
        assert(marginAccount?.marginBalance == 75, "Expected negative CUR:USD value to become margin used")
        assert(!budget.holdings.contains(where: { $0.ticker == "CUR:USD" }), "Expected CUR:USD to be excluded from holdings")
        assert(!budget.watchlistTickers.contains("CUR:USD"), "Expected CUR:USD to be excluded from watchlist")
        assert(budget.portfolioSnapshot.cashBalance == 125.50, "Expected All Portfolios cash to aggregate positive cash balances")
        assert(budget.portfolioSnapshot.marginUsed == 75, "Expected All Portfolios margin to aggregate negative cash balances")
    }

'''
if function_anchor not in tests:
    raise SystemExit('test function anchor not found')
tests = tests.replace(function_anchor, new_test + function_anchor, 1)
test_path.write_text(tests)
