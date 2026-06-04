# Budgeting App Updates

## 2026-06-02 - TradingView Charts (OpenStock-inspired)

### Watchlist, holdings snapshots, and portfolio charts
- Added `TradingViewCharts.swift` with free TradingView embed widgets (advanced chart, symbol info, technical analysis, market quotes watchlist) via `WKWebView`, matching [OpenStock](https://github.com/Open-Dev-Society/OpenStock) patterns
- `TickerPriceHistoryChart` accepts an optional `symbol` and prefers TradingView when set; falls back to Swift Charts using your Finnhub/Alpaca/Alpha Vantage data offline
- Home watchlist shows a live TradingView market-quotes board; ticker detail sheets include candle/baseline/area style picker, symbol info, technical analysis, and provider-data fallback
- Portfolio holding quote snapshots use compact TradingView mini charts; holding detail adds a **Full TradingView Chart** screen
- Watchlist settings includes a live quotes preview; symbol formatting supports international exchange suffixes (e.g. `.TW`, `.L`, `.TO`)

## 2026-06-02 - Ticker Price History Charts

### Improved snapshot and watchlist price charts
- Added `TickerPricePoint` model and `fetchCompositeRecentPriceHistory` so charts use real trading dates from Finnhub/Alpaca/Alpha Vantage
- New shared `TickerPriceHistoryChart` zooms the Y-axis to the actual price range instead of wasting vertical space
- X-axis now shows date labels; caption shows session count, span (~weeks/months), and date range
- Detailed ticker snapshot chart shows period % change and supports drag-to-inspect price/date
- Watchlist expanded preview and margin quote snapshots use the same improved compact chart

### Chart clipping and indicator fixes
- Fixed green area bleed by clipping plot area, anchoring fill to chart baseline, and using monotone interpolation
- Moved `TickerPriceHistoryChart` into `ContentView.swift` to resolve Xcode scope errors
- Centralized SMA/EMA/RSI/MACD in `TickerIndicators` with bar-aligned MACD and live price included in indicator inputs

## 2025-01-16 - Build Fix

### Fixed Compilation Errors (`Models.swift`)
- Added `import Combine` to fix `ObservableObject` and `@Published` property wrapper errors
- BudgetModel now properly conforms to ObservableObject protocol

## 2025-01-16 - Initial App Creation

### Created Data Models (`Models.swift`)
- `PayFrequency` enum: Weekly, Bi-Weekly, Monthly, Annually with multipliers for income calculations
- `Category` struct: Tracks name, allocated amount, and spent amount for needs/wants categories
- `SavingsGoal` struct: Tracks savings goals with target amount, current amount, and account name
- `BudgetModel` class: Observable object managing all budget data with 50/30/20 rule calculations
  - Calculates monthly/annual income from pay frequency
  - Tracks needs (50%), savings (30%), and wants (20%) budgets
  - Provides remaining budget calculations

### Created Main UI (`ContentView.swift`)
- **Income Section**: Input field for income amount and pay frequency picker
- **Budget Breakdown**: Visual bars showing 50/30/20 allocation with progress indicators
- **Needs Categories**: Add/edit/delete needs categories with spent amount tracking
- **Wants Categories**: Add/edit/delete wants categories with spent amount tracking
- **Savings Goals**: Add/edit/delete savings goals with progress tracking and account names
- **Summary Section**: Shows total spending across categories and remaining budget
- Supporting views for adding/editing categories and savings goals
- Real-time calculations for remaining budgets and spending tracking

### Features Implemented
- ✅ 50/30/20 rule budgeting (50% needs, 30% savings, 20% wants)
- ✅ Income input with pay frequency selection
- ✅ Category management for needs and wants
- ✅ Savings goals with account tracking
- ✅ Expense tracking (spent amounts)
- ✅ Remaining budget calculations
- ✅ Visual progress indicators
- ✅ One-page scrollable UI with clean UX
