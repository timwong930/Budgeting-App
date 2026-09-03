# TIM-118 — Budget Hub subpage UX

## Why this iteration exists

TIM-95 improved the Budget Hub entry point, but the four subpages still feel too similar. Each one currently opens with the same generic page wrapper and mostly stacks pre-existing expandable sections. That creates navigation depth without creating a stronger reason to visit the destination.

The redesign should make every subpage answer one distinct financial question within the first screenful.

## Information architecture

### Plan — Where should this month's money go?

Primary job: finish the monthly plan before spending happens.

Above the fold:
- Month selector
- Plan status: balanced / money still unassigned / over-planned / missing income
- Expected income
- Assigned amount and assignment progress
- Needs / Wants / Savings planned-vs-actual cards

Main content:
- Editable Needs categories
- Editable Wants categories
- Savings contribution goals

Remove from the Plan destination:
- Duplicate legacy Income section
- Duplicate legacy Needs section
- Duplicate legacy Wants section
- Duplicate legacy Savings section

`MonthlyPlanWorkspaceView` should become the canonical planning surface.

### Activity — What changed this month?

Primary job: understand recent money movement and find transactions that need attention.

Above the fold:
- Inflow
- Outflow
- Net movement
- Transaction count
- One primary action: Log transaction

Then:
1. Recent transactions, newest first
2. Recurring charges / upcoming obligations
3. Trends and range selector

Avoid leading with charts. The first screen should answer what happened before explaining the trend.

### Accounts — Where is my money and what needs attention?

Primary job: understand liquidity, debt, and investment balances.

Above the fold:
- Cash
- Credit-card debt
- Investments
- Net financial position

Attention area:
- Cards with upcoming due dates
- High utilization / balance attention where the data is available
- Accounts that failed or need Plaid reconnect when sync health is available

Then:
- Bank account group
- Credit-card group
- Investment group
- Transfer action

Avoid making the page feel like an extra tap just to see the same account cards that already exist elsewhere.

### Reports — How am I doing?

Primary job: turn historical budget data into an answer, not another set of expandable cards.

Above the fold:
- Budget vs actual for the selected month
- Savings rate
- Remaining / overspent status
- Change versus prior month when enough data exists

Then:
- Category drivers: top categories and largest overages
- Needs / Wants / Savings allocation comparison
- Month-end totals
- Trend details

Reports should be read-oriented. Editing belongs in Plan or Activity.

## Interaction rules

- Keep the selected month consistent when moving between Budget Hub workspaces.
- Put one primary action near the top of each workspace.
- Prefer summary bands and rows over nested GlassCards inside GlassCards.
- Expandable sections should be used only for genuinely secondary detail.
- Keep transaction editing, account management, Plaid behavior, persistence, and calculations unchanged.
- Reuse the existing Cuan / Glass design language and Dynamic Type conventions.

## Implementation slices

### Slice 1 — Plan workspace
- Add plan health/status messaging.
- Make unassigned / over-planned money visually explicit.
- Improve planned-vs-actual cards and category progress.
- Improve savings contribution progress.
- Remove duplicate legacy sections from `budgetPlanSubmenu` once the parent is edited.

### Slice 2 — Activity
- Add month activity hero with inflow, outflow, net movement, and count.
- Move transactions ahead of trends.
- Keep recurring charges as an attention section.

### Slice 3 — Accounts
- Add cash / debt / investments / net summary.
- Add attention rows for due cards and sync health when available.
- Preserve existing account detail sheets.

### Slice 4 — Reports
- Add budget-vs-actual report hero.
- Add month-over-month comparison using existing monthly data.
- Surface top category drivers before the full breakdown.

## Acceptance

- Each workspace has a distinct purpose and first-screen summary.
- Plan no longer duplicates the legacy planning sections after the monthly workspace.
- Activity prioritizes recent movement over charts.
- Accounts surfaces financial position and attention items, not only account lists.
- Reports provides comparative insight, not only a stack of existing summaries.
- No intended model, persistence, Plaid sync, or calculation changes.
