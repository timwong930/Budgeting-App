# Budgeting App

A native iOS budgeting and portfolio-management app built with SwiftUI.

## Features

### Home Dashboard
- Net worth chart with interactive range selector (1D–All)
- Watchlist with live TradingView market-quotes board; sort/filter by gainers/losers
- Ticker detail sheets with TradingView advanced charts (candlestick/bar/line/area/baseline), technical analysis, and fundamental data; native fallback via Alpha Vantage / Finnhub / Alpaca
- Ticker search and watchlist alert configuration (price thresholds, percent move)
- Auto-refresh with background `BGTaskScheduler` support

### Calendar
- Monthly calendar with transaction event markers
- Day detail sheet with expense, recurring payment, credit card due date, and income entries
- Mark recurring payments as paid inline
- Calendar entry editor and credit-account quick actions

### Budget Hub
- Monthly income with pay frequency (Weekly / Bi-Weekly / Monthly / Annually)
- 50/30/20 rule: Needs (50%), Savings (30%), Wants (20%) with progress bars
- Category and savings-goal management
- Expense, income, and savings-entry logging with credit card payment target support
- Trend charts (spending vs income) with drag-to-inspect
- Submenus: Plan, Activity (recurring charges / trends), Accounts (bank / credit / portfolio), Reports
- Bank and credit account management (closing day, due day, limit, balance)

### Margin / Portfolio Tab
- Portfolio net worth with interactive chart (gross/net, range selector 1D–All)
- Holdings list (card or table view) sortable by ticker, value, income, yield, P&L, shares, price; filterable by asset type
- Dividend forecast (weekly / monthly / projected annual)
- Margin tracking: interest-free limit, paid margin, utilization, personal cap, interest calculations
- Income vs Costs analysis with coverage ratio
- Stress tests (20%/35%/50% drawdown)
- Ledger history and add-transaction flow (contribution, buy, sell, dividend, bill, margin interest, adjustment)

### Widgets (3 systemSmall/systemMedium)
- **Budget Summary** — remaining budget, income, allocation bars, quick-add deep links
- **Portfolio Snapshot** — portfolio value, cash, margin, top holdings
- **Watchlist** — ticker prices (up to 5 on medium)

### Notifications
- Scheduled: daily budget snapshot (8 AM + 6 PM), portfolio snapshot (11:30 AM + 3:30 PM), payment reminders (day before due)
- Live: watchlist price alerts (with 15 min cooldown), portfolio updates (net worth change >= $10)
- Rich notification content extension with charts and metric pills

### Siri / Shortcuts (10 App Intents)
- Portfolio summary, net worth, position lookup, stock quote, watchlist prices, budget status
- Add portfolio transaction, expense, watchlist ticker, ticker notes

## Tech Stack

- Swift / SwiftUI / Combine
- `WKWebView` TradingView integration (advanced charts, market quotes, technical analysis, fundamentals)
- Alpha Vantage, Finnhub, Alpaca (composable fallback)
- `BGTaskScheduler` background refresh
- `App Intents` framework (iOS 26.0+)
- WidgetKit + Notification Content Extension

## Project Structure

- `Budgeting App/` — app source code
- `Budgeting App.xcodeproj/` — Xcode project configuration
- `BudgetingWidgets/` — widget extension
- `BudgetNotificationContentExtension/` — rich notification UI
- `Budgeting AppTests/` — unit test target
- `build/` — build artifacts

## Getting Started

1. Open `Budgeting App.xcodeproj` in Xcode.
2. Select the `Budgeting App` scheme.
3. Choose an iOS Simulator target.
4. Build and run.

## Notes

- Data is persisted as JSON to the app documents directory, shared app group container (for widgets), and optional iCloud. Auto-saves on change with 200 ms debounce.
- Deep link scheme: `momosmoney://` (open ticker, tab, or quick-add actions).
- Market data uses Alpha Vantage → Finnhub → Alpaca fallback chain (Alpaca requires credentials).
- Requires a TradingView chart API key for embedded web charts.
- This repository targets local development/debug workflows.
