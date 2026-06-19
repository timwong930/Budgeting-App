# Budgeting App — AGENTS.md

## Build & Run

- Open `Budgeting App.xcodeproj` in Xcode, select `Budgeting App` scheme, run on iOS Simulator.
- No SPM dependencies, npm, or CLI build commands. Everything is Xcode-managed.
- No CI, no lint, no typecheck, no formatter config in the repo.

## Tests

- One test file: `Budgeting AppTests/CuanMarketModelsTests.swift`. Uses a custom `@main` struct (not XCTest), run via Xcode scheme or by executing the test target.
- To add tests, follow the `@main` pattern in the test file.

## Architecture

- Entrypoint: `Budgeting_AppApp.swift` (line 11). Uses `BudgetAppDelegate` (UIApplicationDelegateAdaptor) and `BudgetBackgroundRefreshCoordinator`.
- Main view: `ContentView.swift` (~5000+ lines, monolith). All 4 tabs (Home, Calendar, Budget Hub, Margin) are inline in this file.
- State: `BudgetModel` (ObservableObject) in `Models.swift:1237`. Persists all data as JSON to documents directory, shared app group container, and optional iCloud. Auto-saves on change with 200 ms debounce.
- `TickerPriceHistoryChart` is defined inside `ContentView.swift` (not a separate file). Do not extract it — Xcode scope errors were previously fixed by keeping it inline.
- `import FoundationModels` in `Models.swift:14` — this is a project-local module within the Xcode target (no SPM package).

## Deep Links

- Custom URL scheme: `momosmoney://`
- Supported actions in `Budgeting_AppApp.swift:37-41`: ticker, tab, addIncome, addExpense.

## Market Data

- Fallback chain: Alpha Vantage → Finnhub → Alpaca (Alpaca requires credentials).
- Providers configured via `MarketDataSettings` in `Models.swift:765`.
- TradingView charts embedded via `WKWebView` in `TradingViewCharts.swift`. Requires a TradingView chart API key.
- Symbol formatting supports international exchange suffixes (`.TW`, `.L`, `.TO`, etc.) — `TradingViewCharts.swift:7-17`.

## Project Targets

- `Budgeting App/` — main app source
- `BudgetingWidgets/` — WidgetKit extension (3 widgets)
- `BudgetNotificationContentExtension/` — rich notification UI extension
- `Budgeting AppTests/` — test target

## Persistence

- App group ID: `group.Timothy-Wong.Budgeting-App` (entitlements + `Models.swift:1238`)
- iCloud container: `iCloud.$(CFBundleIdentifier)` with CloudDocuments service
- Display name: "Momo's Money!" (`Budgeting App-Info.plist:12`)
- Background refresh identifier: `Timothy-Wong.Budgeting-App.background-refresh`

## Notables

- The app requires iOS 26.0+ for App Intents (`ShortcutsIntents.swift:6`).
- No `.gitignore` exists — build artifacts in `build/` and `.DerivedData/` are not excluded.
- `CuanTheme` (`CuanTheme.swift`) provides the design system: cards, buttons, pills, sparklines, segmented controls.
- Budget follows 50/30/20 rule: Needs 50%, Savings 30%, Wants 20%.
