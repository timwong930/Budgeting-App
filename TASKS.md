# Budgeting App Improvement Tasks

Tasks are ordered by dependency. Complete and verify one task before starting the next.

## 1. Account-domain foundation

- [x] Add stable `FinancialAccount` identities for manual and Plaid bank, credit, investment, loan, and other accounts.
- [x] Add stable `PortfolioAccount` identities so each brokerage keeps its own cash, margin, positions, and activity.
- [x] Persist the new account collections without breaking existing `budget.json` snapshots.
- [x] Migrate existing bank accounts, credit accounts, and legacy single-portfolio data.
- [x] Add migration and Codable tests. (App scheme builds; the test target is not currently exposed by the Xcode project/scheme.)

## 2. Stable account references

- [ ] Replace name-based account relationships with local account UUIDs.
- [ ] Add backward-compatible references to income, expenses, transfers, portfolio transactions, and holdings.
- [ ] Keep display names as presentation data rather than identity.
- [ ] Prevent manual ledger operations from mutating Plaid-authoritative balances.

## 3. Multi-account portfolio model

- [ ] Store positions by portfolio account and security identity, not ticker alone.
- [ ] Preserve separate lots, quantities, cost bases, cash, and margin for each brokerage.
- [ ] Add a computed “All Portfolios” aggregate without destroying account-level records.
- [ ] Add portfolio-account selection to manual investment and transaction screens.

## 4. Plaid holdings synchronization

- [ ] Apply holdings as complete snapshots per successfully synced investment account.
- [ ] Correctly clear zero holdings and zero cash balances.
- [ ] Preserve data for accounts whose Plaid Item failed during a partial sync.
- [ ] Keep manual positions separate from Plaid-owned positions.
- [ ] Stop quote refresh and the legacy margin ledger from rebuilding Plaid holdings.

## 5. Transaction reconciliation

- [ ] Classify transfers and credit-card payments before income/expense sign handling.
- [ ] Model pending-to-posted transaction replacement.
- [ ] Make manual/Plaid matching account-aware, scored, and reviewable.
- [ ] Preserve user category, notes, and other overrides across Plaid modifications.
- [ ] Prevent duplicate review items and handle expense/income direction changes.

## 6. Durable backend sync

- [ ] Prevent cursor advancement from losing deltas before the client persists them.
- [ ] Add idempotent delivery/acknowledgment or server-side normalized transaction storage.
- [x] Paginate all investment transactions beyond 500 records.
- [ ] Return per-Item success/failure and snapshot completeness metadata.
- [ ] Reconcile local data when an Item or account is disconnected.

## 7. Authentication and ownership

- [ ] Replace the shared app sync key as the user identity.
- [ ] Associate Plaid Items and accounts with an authenticated owner.
- [ ] Replace the hard-coded Plaid `client_user_id` with a stable per-user ID.
- [ ] Add database ownership constraints/policies and verify Plaid webhooks.

## 8. Sync UX and operations

- [x] Preserve real institution display names and backfill stored `ins_…` identifiers.
- [x] Add throttled foreground and background Plaid sync while retaining manual sync.
- [x] Restore investment app-to-app OAuth return handling for Robinhood-style Link flows.
- [ ] Show per-account sync health, last success, stale data, and actionable errors.
- [ ] Add reconnect/update-mode support for `ITEM_LOGIN_REQUIRED`.
- [ ] Add review actions rather than delete-only review queue behavior.
- [ ] Add safe disconnect choices: retain as manual/archive or remove imported data.

## 9. Test coverage

- [ ] Cover empty holdings/cash, partial failures, repeated sync, disconnect, and cursor replay.
- [ ] Cover two brokerages holding the same ticker.
- [ ] Cover manual and Plaid positions sharing a ticker.
- [ ] Cover transfers, card payments, pending transactions, and ambiguous matches.
- [ ] Cover migrations from every legacy account/portfolio shape.

## 10. Repository hygiene

- [ ] Add a `.gitignore` for `build/`, `.DerivedData/`, Supabase temporary state, and local secrets.
- [ ] Decide whether Vercel or Supabase is the canonical Plaid backend and remove implementation drift.
- [ ] Establish a clean source baseline before committing the integration work.
