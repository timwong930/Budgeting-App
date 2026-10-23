# TIM-198 — Impeccable review of Budget, Transactions & Transfer Matching

Date: 2026-10-22  
Design mode: **Operate · native SwiftUI iOS**  
Branch: `tim-191-tim-89-partial-sync-reliability`  
Draft PR: [#23](https://github.com/timwong930/Budgeting-App/pull/23) (stacked on draft #22, not on `main`)  
Linear: [TIM-198](https://linear.app/tim415/issue/TIM-198)

## Direction

Preserve Momo's Money's existing financial identity and native SF Symbols / semantic platform colors. A budget is a decision surface, not a decorative dashboard. The first task is **understand what moved**, the second is **confirm which accounts**, the third is **correct and recover**. Clear signed amounts, named banks, and undo matter more than additional cards.

Impeccable's iOS, Operate, layout, clarity, and craft-floor guidance was read and applied. The context launcher could not execute: no local project checkout or installed launcher executable was available. No visual simulator pass was possible.

## Source audit, ranked by severity

| Priority | Confirmed problem | Effect | Implemented |
| --- | --- | --- | --- |
| P0 | Calendar created an imported internal bucket credit as `isIncome = true`, `isTransfer = false` | Green positive income event despite budget rules excluding the credit from income | Shared transfer classification flags, teal neutral transfer event, Transfers filter |
| P0 | Review controls only said “Match with Account Name” and generic confirmation | Couldn't determine the exact source/destination; accidental financial misclassification risk | Reusable full two-sided account review sheet plus manual-confirmation identity gate |
| P1 | Account Activity, account ledger and transaction editor all used different match confirmations | Users couldn't predict what tapping a match would do | One reusable candidate row and confirmation view |
| P1 | Expense editing presented multiple overlapping switches/pickers | Large, error-prone form, especially in iPhone sheet | One native Transaction type picker; sections for Transaction / Classification / Notes |
| P1 | Plaid-linked account source displayed as disabled dropdown | Looked editable but was not; unclear institution identity | Read-only recorded-account detail |
| P1 | Confirmed two-sided bucket credit showed as an additional calendar line | Same money movement appeared twice | Shared reciprocal Plaid-pair suppression, preserving original records |
| P2 | Long imported merchant description was used as editor navigation title | Title truncation, Save/Cancel crowding | Short “Edit transaction” / “Edit income” navigation titles |

## Implemented user journeys

### Budget → Activity → Review transactions
1. Review pending items by recorded account and date.
2. Open a **Possible match** row. It shows a withdrawal account and receiving account separately, bank institution/type, amounts, and dates.
3. A native review sheet states this is only a **suggestion**, shows **From** and **To** account identities plus both original descriptions, amounts and dates.
4. Only then can the user choose **Confirm these accounts**; Cancel is always available. A failed match leaves an actionable refresh message.
5. For a pair that can't be distinguished visually (two accounts with identical name/institution/type), confirmation is disabled. No fake last-four/account mask is manufactured from a Plaid opaque ID.
6. Manual decisions continue through the existing source-preserving Plaid reconciliation and Undo flows.

### Transactions → Edit transaction
The Classification screen uses a single **Transaction type** choice: Expense, Account transfer, Credit card payment, Internal bucket transfer, or Duplicate. Only applicable form fields appear. The Plaid-authoritative source account is displayed, not edited. When a real counterpart is available, the same two-sided review sheet opens.

### Calendar · month, week and day
- A corrected bank or bucket transfer is a neutral teal transfer item with an arrow symbol, **not** an income item or green plus sign.
- Transfers respond to the **Transfers** filter even if their underlying source remains an `IncomeEntry` or `Expense`; the Income filter doesn't own those events.
- Confirmed debit/credit bucket pairs appear once in calendar and Budget Activity. Unpaired bucket movements still appear with transfer styling, never as financial income/spending.
- Monthly income/spending summaries continue to exclude reclassified movements. Existing cache updates are triggered when incomes, expenses or transfers change.

## Shared model invariants and safety

- `BudgetModel.isTransferMovement` has explicit expense and income cases.
- `BudgetModel.isPairedBucketCredit` requires reciprocal original Plaid transaction IDs before collapsing the receiving side from user timelines.
- `canClearlyIdentifyPlaidMatch` blocks manual link confirmation when any involved active account has an indistinguishable visible name, institution and type; linked account IDs themselves remain stable.
- The transfer review sheet reads observed sources; it does not infer a bank balance or create financial activity.
- Existing duplicate income corrections, card payments and source-backed match Undo are preserved.

## Static validation completed

**27 of 27 focused structural checks passed.** They cover calendar flags/filter ordering, duplicate/paired-bucket suppression, reusable three-entry-point review sheets, account identity gating, exact source descriptions and amounts, native form type picker, read-only Plaid source account, and synthetic regression registrations.

Source regression cases added:
- `testInternalBucketCalendarSemantics`: income/spending exclusion, correct transfer semantics, reciprocal pair suppression and unpaired transfer visibility.
- `testPlaidMatchingRequiresDistinctAccountLabels`: blocks two same-named Example Bank checking accounts, permits explicit confirmation once account names differ.

**These are source assertions and test implementations, not executed Swift/XCTest results.** The financial-model test suite is not fully wired into the isolated XCTest smoke target.

## Release blockers

- [ ] Full Xcode project build and financial regression suite execution.
- [ ] iPhone and iPad simulator screenshots, including dark/light modes and enlarged Dynamic Type.
- [ ] VoiceOver navigation order, 44-point tap area for every candidate/control and keyboard behavior.
- [ ] Verify all 3 matching entry points against genuine Plaid histories on a physical iPhone; confirm correct checking/savings/card directions with institutions and multiple cards.
- [ ] Verify calendar month/week/day, date-crossing bucket pairs, toggling Transfers vs Income, and recalculating calendar income/net flow.
- [ ] Verify repeated Plaid sync, offline/retry, older matches without source snapshots, undo, and no fabricated balances.
- [ ] Confirm account name uniqueness or wire institution-provided safe masked account numbers through the data pipeline before allowing identical display names.
- [ ] Capture sanitized before/after screenshots; never expose customer amounts, tokens or identifying bank data.
- [ ] Keep draft PR #22/#23 unmerged until review and approval.

**Not accomplished:** a full-screen iOS visual build/QA pass, executable tests, simulator screenshots, or production release.
