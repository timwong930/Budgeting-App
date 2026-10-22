# Momo's Money — Financial reliability and UX audit (TIM-191 / TIM-89)

**Date:** 2026-10-19  
**Stack:** `main` → draft PR #22 (`tim-191-plaid-transfer-classification`) → this branch.  
**Scope:** Source-level review of transaction reconciliation, Plaid sync/review UI, account ledger, budgeting/portfolio entry points, persistence, and existing test infrastructure. Not a completed device-wide UX audit.

## Ranked findings

| Severity | Finding | Evidence / status |
| --- | --- | --- |
| P0 | An incremental Plaid delivery containing only one side of a previously auto-verified pair could create an extra unpaired transfer without removing the pair. | `PlaidTransactionReconciliation.swift` reconciled only the current payload's sides. **Mitigated on this branch:** retain prior pair when partner is omitted, not removed. Full Xcode/device verification remains outstanding. |
| P0 | Withdrawals were historically misclassified as transfers, or legitimate pairs rejected. | TIM-191 draft PR #22 includes stricter matching and manual review. **Still unmerged and not device-tested**; this branch stacks on it rather than duplicating the logic. |
| P0 validation gap | The custom `@main` regression collection is not the suite executed by the isolated `Budgeting AppTests` Xcode target, whose source is presently a single smoke test. | `Budgeting AppTests/CuanMarketModelsTests.swift`, `BudgetingAppTests.xcodeproj/project.pbxproj`, `Budgeting AppTests/BudgetingAppSmokeTests.swift`. Regression execution must be explicitly established before merge; static assertions are not execution. |
| P1 | Review reminders could be removed by swipe without an undo action or a clear explanation of what dismissal means. | **Improved on this branch:** in-view undo, explicit reminder/transaction distinction. Undo lasts while the settings view remains open. |
| P1 | A linked institution with no last-successful-sync timestamp displayed no freshness warning; older syncs were not called out. | **Improved on this branch:** missing/older-than-24-hour timestamp shows explanatory copy. The 24-hour threshold is a UX caution, **not** a guarantee that a bank is current or stale. |
| P1 | Some automatic home-screen sync invocations suppress thrown errors with `try?`, which could hide failure from users. | `ContentView.swift`. **Unchanged:** requires coordinated app-wide sync status UX and regression tests. |
| P1 | Expired connections, partial failures, account discrepancies, and balance provenance have not been fully validated against real institutions. | Plaid client/coordinator/status screens are present, but simulator and real-item workflows were not exercised. **Open QA.** |
| P2 | The app's main SwiftUI view remains a very large file with coupled screens and state. | `ContentView.swift` exceeds 11,000 lines on this branch. **Do not rewrite simply for aesthetics;** modularize only with bounded regression coverage. |

## Implemented changes on this branch

1. **Partial-sync pair safety.** A Plaid pair with exactly one member in an incremental delivery is preserved without emitting a new single transfer or duplicate income/expense. If Plaid explicitly removes its counterpart, the pair may be invalidated and the surviving side reclassified/reviewed. User-confirmed pairs also honor explicit removals.
2. **Synthetic tests added.** Coverage for one-sided repeat deliveries, full replay after a partial delivery, authoritative counterpart removal, and a user-confirmed pair whose partner is removed. Pre-existing transfer tests remain in place. These cases are **source-added, not Xcode-executed**.
3. **Plaid settings feedback.** Exposes missing/old sync timestamps with cautious text rather than implying freshness. A dismissed review item can be restored from that view without touching the underlying transaction; a review's swipe text now explains classification is unchanged.

## Unchanged trust boundaries

- No live Plaid calls, real bank transfers, Supabase production writes, backend migrations, real user finance records, or account credentials used.
- No financial-history migration or existing manual classification overwrite.
- Do not infer a missing balance is $0 or fabricate bank entries. The linked bank is authoritative for its reported current/available balance; locally calculated totals are not the same thing.
- The underlying storage remains the existing local JSON/app-group/iCloud model. No migration or backend rewrite performed.

## Acceptance and manual QA matrix (must execute on a Mac before merge)

- [ ] Build `MomosMoney.xcworkspace` app and `Budgeting AppTests` scheme, then run on at least one installed iPhone simulator.
- [ ] Establish that `CuanMarketModelsTests.swift` scenarios actually run, or migrate them to the isolated XCTest harness before claiming regression coverage.
- [ ] Two real connected depository accounts: matching two-sided transfer appears **once**, not in income/spending.
- [ ] Receive an incremental delivery with only one known pair member: the existing pair remains **once**.
- [ ] Replay both members: no duplicates; explicitly remove one: linked pair no longer claims the removed bank side.
- [ ] Unrelated same-dollar ACH/payroll/ATM/Zelle events stay separate; ambiguous equal-dollar events require review.
- [ ] User-confirmed transfers and user-confirmed withdrawals survive repeat sync; removed/posted transactions behave correctly.
- [ ] Credit-card payments, edited categories/notes, empty/partial holdings, disconnect/reconnect, and per-account budget totals are verified separately.
- [ ] Force sync failures and stale connection timestamps. Confirm no fabricated $0 values and actions remain understandable.
- [ ] Dismiss and undo review. VoiceOver, Dynamic Type, both color schemes, and small/large iPhone layouts checked.
- [ ] Capture **sanitized** simulator before/after screenshots; never include account IDs, Plaid tokens, or transaction details from live accounts.

## Validation boundaries

- Xcode and iOS Simulator are not available in this execution environment; no app build, actual XCTest run, real Plaid validation, or screenshots are claimed.
- Earlier structural checks passed for the original narrow partial-sync fix. The October 19 follow-up has additional source inspection and checks; **no Xcode build, simulator execution, or actual custom regression suite run has occurred**. A previously noted standalone guard sanity exercise does not validate the expanded app logic.
- Keep both stacked PRs as drafts and do not merge until device/Plaid acceptance for TIM-191 and the partial-sync cases is complete.


## TIM-193 — Payment classification and in-app correction follow-up (October 19)

**User-reported blocking issues:** transfers do not link to the right accounts; cash withdrawals and credit-card payments are misclassified; correction in the app is difficult.

### Additional confirmed code-level defects (severity: P0)

1. **No cross-delivery matching.** An incoming Plaid delta only compared against other transactions in that same payload. The opposite entry may already be persisted from a different bank sync, so genuine bank transfers or card payments failed to pair.
2. **Credit cards inaccessible from manual review.** Review candidates were limited to depository accounts, blocking checking-to-card matching even when a real credit-side row existed.
3. **Misidentified payments.** Broad `autopay` and Plaid `LOAN_PAYMENT` detection could classify purchases or bank loans as transfers; a coincidental card credit could match a non-card debit.
4. **ATM classification.** ATM cash withdrawals were imported into generic categories rather than the dedicated Cash Withdrawals category. This assumes no separate physical-cash wallet tracking; classification remains editable.
5. **Unknown card credits counted as income.** A credit-card-side `ACH CREDIT` without payment wording could fall through as ordinary income. Ambiguous card credits must be explicitly reviewed, not assumed to be wages or a confirmed payment.
6. **No safe way to undo a wrong pair.** Account ledger editing previously routed Plaid pairs to the generic manual CashTransfer editor without restoration of both original sides.

### Additional implementation committed on this draft branch

- Save exact Plaid transaction legs and their category on newly imported Plaid single/pair movements, keeping optional JSON fields backward-compatible.
- Search previously saved unmatched transaction legs across multiple Plaid sync deliveries. Auto-pair only uniquely corroborated opposite account movements, respecting exact original account IDs, rejected matches, and user confirmations.
- Validate card-payment direction and require bank-side card-payment memo or specific issuer evidence. Generic bank loans, merchant autopays, payroll and cash withdrawals are not proof of a card payment.
- Quarantine ambiguous incoming credit-card credits for review. Clearly named refunds remain distinct from card payments under existing refund handling; refund-versus-income budgeting semantics need further testing.
- Assign ATM cash withdrawals to `Cash Withdrawals` and migrate only existing machine-assigned `Plaid Needs` ATM categories, preserving user-edited classifications.
- Offer bank-to-bank and checking-to-credit-card manual matching from observed Plaid rows; add safe Undo Incorrect Match in Plaid Settings and bank/card account transaction sheets.
- Preserve rejected source-pair relationships after undo, even across future syncs. Undo requires exact stored original source legs; the app refuses to recreate unavailable historical data.
- Add synthetic source-level regression scenarios: bank/card separate syncs, automatic card pairing, manual generic-ACH review, undo/replay, ATM categories, loan/autopay false positives, ambiguous card credits and Codable compatibility.

### High-priority acceptance / limitations

- [ ] Execute all model regression cases, not just the isolated XCTest smoke test; compile the workspace on macOS and exercise both iOS simulator and physical device.
- [ ] Full-history Plaid refresh path required to repair **legacy pre-snapshot matched pairs**. Source details were not previously saved, so the new Undo button correctly refuses unsafe reconstruction for those old entries.
- [ ] User edits and merchant/category notes are not fully proven to survive all automatic pairing/undo paths; regression coverage should be expanded before production adoption.
- [ ] Unknown credit-card credits require manual review; where a genuine refund is unclear from the source description, the app does not infer one without user evidence.
- [ ] Confirm true bank/card transfers exclude income and expenses, and confirm payment/withdrawal classifications against sanitized real Plaid data.
- [ ] Run disconnected, partially synced, pending-to-posted, and restarted-app QA, including making and undoing a manual decision.
- [ ] Confirm no PII/tokens in logs or screenshots. No real financial transactions were initiated by this patch.

**Deployment status:** PR #22 and stacked PR #23 remain drafts. `main` and the installed production app are **not** updated by these changes.

## Design reference

- [Apple Human Interface Guidelines — Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)
- [Apple Human Interface Guidelines — Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles)
- [Apple Human Interface Guidelines — Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
