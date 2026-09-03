# TIM-118 — Budget Hub workspace redesign

## Mental model

Budget Hub should answer four different questions instead of rendering four variations of the same card stack:

- **Plan — Where should this month’s money go?**
- **Activity — What changed this month?**
- **Accounts — Where is my money and what needs attention?**
- **Reports — How am I doing?**

The top-level destination should answer its question quickly. Secondary screens should provide detail only when the user deliberately drills in.

## Plan

Plan is the monthly allocation workspace.

- Expected monthly income uses the existing pay-frequency model.
- Needs / Wants / Savings are authoritative parent buckets using the existing 50 / 20 / 30 rule.
- Subcategories and savings goals are optional breakdowns rather than prerequisites.
- Uncategorized money remains planned inside its parent bucket.
- Subcategories that exceed the parent target show an allocation error instead of silently increasing the budget.
- The default UI is one compact Plan card with expandable parent buckets.
- Category and savings-goal editing appears only after expansion.

## Activity

Activity answers what moved this month before showing charts.

### Main workspace
- Month selector.
- Net movement hero.
- Inflow / spending / savings metrics.
- Expense / income / savings quick actions.
- Recent activity preview.

### Drill-downs
- **Transactions** — full selected-month ledger with direct editing.
- **Recurring** — active repeating income and expenses, monthly totals, direct editing.
- **Trends** — daily spending and income charts plus average/peak spending context.

## Accounts

Accounts summarizes financial position and surfaces attention items before presenting account lists.

### Main workspace
- Net financial position.
- Cash / credit debt / investment net metrics.
- Transfer / Banks / Cards quick actions.
- Attention area for card utilization and Plaid review items.

### Drill-downs
- **Banks** — available cash and individual balances, with a direct Manage action.
- **Credit** — total card debt, overall utilization, individual utilization/available credit.
- **Credit card detail** — balance, available credit, utilization, statement close, due day, purchases and payments.
- **Investments** — net investment value, margin exposure, portfolio cash and holdings.

## Reports

Reports is read-oriented. Editing belongs in Plan or Activity.

### Main workspace
- Selected month.
- Remaining after spending and savings.
- Income / spent / saved metrics.
- Savings rate.
- Largest category insight.

### Drill-downs
- **Category performance** — planned vs actual by Needs/Wants category.
- **50 / 20 / 30** — parent targets vs actual spending/saving.
- **Month comparison** — spending, income, and savings compared with the previous month.

## Interaction rules

- Keep the selected month consistent across Plan, Activity, and Reports.
- Put one clear action or answer near the top of each destination.
- Prefer compact summary rows over nested card grids.
- Reveal detail progressively instead of expanding everything by default.
- Keep editing in Plan / Activity / account-management screens; Reports remains analytical.
- Preserve BudgetModel, Plaid reconciliation, persistence, Cuan/Glass styling, and accessibility conventions.

## Implementation status

Implemented on `tim-118-budget-hub-workspaces`:

- `MonthlyPlanWorkspace.swift` — Plan UX and parent-bucket logic.
- `BudgetHubWorkspaces.swift` — Activity, Accounts, Reports and all new drill-down views.
- `scripts/apply-tim-118-budget-hub-workspaces.py` — exact guarded replacement for the legacy Budget Hub destination block in `ContentView.swift`.
- `docs/TIM-118-contentview-workspace-integration.patch` — reviewable integration diff.

The project uses a filesystem-synchronized Xcode group, so `BudgetHubWorkspaces.swift` is automatically included. The final `ContentView.swift` route replacement is deliberately guarded: the legacy file is roughly 12,000 lines and the GitHub write interface available in this session only supports whole-file replacement rather than a small patch operation.

## Verification

After applying the guarded ContentView integration, build in Xcode and test:

1. Budget Hub → Plan: no duplicated legacy sections below the new Plan workspace.
2. Activity: quick actions, recent items, Transactions, Recurring and Trends navigation/edit flows.
3. Accounts: summary values, attention states, Banks, Credit, card detail and Investments.
4. Reports: month selector, category performance, 50/20/30 and previous-month comparison.
5. Switch months and confirm Activity/Reports reflect the selected month.
6. Test empty-data states and small-screen layout.
7. Confirm existing Plaid/manual account management and transaction editor sheets still work.
