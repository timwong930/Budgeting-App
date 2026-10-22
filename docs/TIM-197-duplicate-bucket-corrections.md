# TIM-197 — Duplicate income and internal bucket transfer corrections

**Date:** 2026-10-22  
**Linear:** [TIM-197](https://linear.app/tim415/issue/TIM-197/reversible-duplicate-income-corrections-and-same-account-bucket)  
**Source branch:** `tim-191-tim-89-partial-sync-reliability`  
**Stacked draft PR:** [#23](https://github.com/timwong930/Budgeting-App/pull/23), based on unfinished #22. No main merge or production deployment.

## Confirmed source-level findings

1. **P0 — Duplicate income behavior:** The Plaid reconciler handled pending-to-posted replacement for expenses, not income. When the posted income received a different Plaid ID, it could leave two entries. Ambiguous manual-to-Plaid matches could also surface twice, without an easy reversible correction.
2. **P0 — Bucket accounting:** Income and spending models offered no persisted way to classify movements within the *same* connected bank account as internal bucket reallocations. Equal-value opposing Plaid entries are not proof of a transfer without the user's confirmation.
3. **P1 — No duplicate recovery:** Ordinary income/expense editors offered deletion, which loses audit history; users had no **Mark as Duplicate** or **Restore** workflow.
4. **P1 — Inconsistent totals:** Account ledgers, monthly income totals, account balance calculations and reports needed consistent exclusion of duplicates/internal bucket movements, rather than hiding only one view.

## Implemented in draft #23

- Optional Codable `TransactionCorrection` (`duplicate`, `bucketTransfer`) on income and expense with optional bucket names, original paired Plaid transaction IDs and prior correction state for restoration. Existing data can decode without these fields.
- Both expense and income editors have explicit classification choices. Duplicates require confirmation, do not delete original bank data, are hidden from ordinary activity and amounts, and can be restored under **Budget → Activity → Review transactions → Hidden duplicates**.
- Retain Plaid IDs/source account on edited records. On resync, user corrections persist; existing Plaid entries are updated rather than re-created.
- Conservative pending-income → posted-income reconciliation: only same source account, same amount, date within three days, and explicit Plaid pending ID or one uniquely name-matching pending entry. Ambiguous cases are **not** automatically merged.
- Optional bucket From/To descriptions. A single unpaired bank entry can be marked internal without manufacturing its other side.
- Actual opposite-signed Plaid legs in the **same connected account** with equal magnitudes and close dates can be explicitly linked as one internal bucket movement. The source rows remain stored and can be reclassified. A same-dollar coincidence cannot auto-pair itself.
- The Budget Activity list displays **one** internal bucket transfer for an explicitly linked debit/credit pair and displays unpaired bucket entries with neutral transfer styling. Balance and budget reporting excludes their income/expense effects; authentic Plaid bank balances remain unchanged.
- Duplicate records are not offered as potential cross-account transfer matches; correcting bucket entries cannot create a bank-to-bank transfer.
- Hidden duplicate restores retain prior transfer/card categorization and previously selected bucket classification when applicable. Previously paired bucket metadata is unlinked when a side is reclassified, to avoid phantom reciprocal links.
- Balance impact of manually created (non-Plaid) corrected records is reversed exactly once on exclusion and restored exactly once on undo.
- Synthetic regression-source scenarios: duplicate income replay and restore; pending/posting payroll ID replacement; local manual deposit/expense balance adjustments; explicit same-bank bucket pairing; no automatic pairing from amount alone; Codable roundtrips and prior bucket correction restore.

## Safety invariants

- **Never delete** a bank-synced transaction merely because a user marked it duplicate.
- **Never treat a bucket allocation as true income/spending** or invent a second bank account/balance movement.
- **Never auto-link same-dollar bucket entries** merely because amount/date match; require explicit confirmation and exact account identity.
- **Never overwrite a user correction on subsequent Plaid replay**.
- **Never unhide duplicate entries without a user restore action**.
- Don't infer that a bank institution's bucket labels are available from Plaid's normal transaction feed; labels may need manual entry.

## Validation and QA checklist — NOT YET EXECUTED

- [ ] Build full iOS app in Xcode and verify new SwiftUI editors compile with Dynamic Type and appearance modes.
- [ ] Run `CuanMarketModelsTests` financial scenarios through an actual automated target; isolated XCTest currently includes only smoke coverage.
- [ ] Import a Plaid pending payroll, post it under a new ID, ensure **one** income; verify distinct real paychecks remain separate.
- [ ] Mark one duplicate income; assert only one income counts in monthly Activity and Reports; repeat Plaid sync and restart app; restore duplicate and verify the original ID remains.
- [ ] Mark imported duplicate expense; verify no spending/double counting, no real-bank balance changes and normal recovery.
- [ ] For a bucket movement, test one-sided and real two-sided entries in the same Plaid account, plus same-dollar transactions from another account (must not match).
- [ ] Confirm bucket debit/credit displays once in Budget Activity and does not affect income/spending or reported account balance.
- [ ] Test changes to one side of a formerly paired bucket movement and ensure stale counterpart references clear.
- [ ] Confirm manual bank-account entries correctly reverse and restore local balance impacts.
- [ ] Exercise offline, sync failure, pending removals, different app restarts, account renames, disabled destinations, and historical records.
- [ ] Capture sanitized iPhone before/after images only; do not expose transaction IDs, account details or Plaid credentials.

**Current evidence:** 20/20 source structural consistency checks pass. **Not actual Swift/XCTest execution**. Neither PR #22 nor #23 should merge without successful Mac/device testing and explicit approval.
