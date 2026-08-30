from pathlib import Path

engine_path = Path('Budgeting App/PlaidSyncEngine.swift')
source = engine_path.read_text()
old = '        watchlistTickers.removeAll { isOptionContractTicker($0) }\n'
new = '''        watchlistTickers.removeAll { ticker in
            normalizedTicker(ticker) == "CUR:USD" || isOptionContractTicker(ticker)
        }
'''
if old not in source:
    raise SystemExit('watchlist cleanup anchor not found')
engine_path.write_text(source.replace(old, new, 1))

test_path = Path('Budgeting AppTests/CuanMarketModelsTests.swift')
tests = test_path.read_text()
old_setup = '''    private static func testPlaidCashHoldingFeedsCashAndMarginBalances() {
        let budget = BudgetModel()

        _ = budget.applyPlaidSync(
'''
new_setup = '''    private static func testPlaidCashHoldingFeedsCashAndMarginBalances() {
        let budget = BudgetModel()
        budget.watchlistTickers = ["CUR:USD", "AAPL"]

        _ = budget.applyPlaidSync(
'''
if old_setup not in tests:
    raise SystemExit('cash test setup anchor not found')
test_path.write_text(tests.replace(old_setup, new_setup, 1))
