#!/usr/bin/env python3
"""Apply TIM-118 Budget Hub workspace routing to ContentView.swift.

This is intentionally an exact guarded replacement because ContentView.swift is a very
large legacy file. The script refuses to write if the expected source block has changed.
"""

from pathlib import Path
import sys

PATH = Path("Budgeting App/ContentView.swift")

OLD = r'''    private var budgetPlanSubmenu: some View {
        budgetSubmenuPage(title: "Plan", subtitle: "Assign this month's income before you spend it.", systemImage: "slider.horizontal.3") {
            MonthlyPlanWorkspaceView(
                budget: budget,
                selectedMonth: $selectedMonth,
                onAddNeeds: { showingAddNeedsCategory = true },
                onAddWants: { showingAddWantsCategory = true },
                onAddSavings: { showingAddSavingsGoal = true },
                onEditCategory: { editingCategory = $0 },
                onEditSavingsGoal: { editingSavingsGoal = $0 }
            )
            if budget.income > 0 && budget.needsCategories.isEmpty && budget.wantsCategories.isEmpty && budget.savingsGoals.isEmpty {
                nextStepSection
            }
            incomeSection
            needsSection
            wantsSection
            savingsSection
        }
        .onAppear {
            incomeExpanded = true
            needsExpanded = true
            wantsExpanded = true
            savingsExpanded = true
            budget.applyMonthlyAllocations(for: selectedMonth)
        }
    }

    private var budgetActivitySubmenu: some View {
        budgetSubmenuPage(title: "Activity", subtitle: "Monthly movement and logged cash flow.", systemImage: "list.bullet.rectangle.portrait") {
            logMonthHeaderSelector
            recurringChargesSection
            logTrendsSection
            logTransactionsSection
        }
        .onAppear {
            recurringChargesExpanded = true
            logTrendsExpanded = true
            logTransactionsExpanded = true
        }
    }

    private var budgetAccountsSubmenu: some View {
        budgetSubmenuPage(title: "Accounts", subtitle: "Balances that feed your budget snapshot.", systemImage: "creditcard.and.123") {
            accountBalancesSection
        }
        .onAppear {
            accountBalancesExpanded = true
        }
    }

    private var budgetReportsSubmenu: some View {
        budgetSubmenuPage(title: "Reports", subtitle: "Summaries and allocation readouts.", systemImage: "chart.pie") {
            summarySection
            categorySummarySection
            budgetBreakdownSection
        }
        .onAppear {
            summaryExpanded = true
            categorySummaryExpanded = true
            budgetBreakdownExpanded = true
        }
    }
'''

NEW = r'''    private var budgetPlanSubmenu: some View {
        budgetSubmenuPage(
            title: "Plan",
            subtitle: "Fund the month first. Add detail only when it helps.",
            systemImage: "slider.horizontal.3"
        ) {
            MonthlyPlanWorkspaceView(
                budget: budget,
                selectedMonth: $selectedMonth,
                onAddNeeds: { showingAddNeedsCategory = true },
                onAddWants: { showingAddWantsCategory = true },
                onAddSavings: { showingAddSavingsGoal = true },
                onEditCategory: { editingCategory = $0 },
                onEditSavingsGoal: { editingSavingsGoal = $0 }
            )
        }
        .onAppear {
            budget.applyMonthlyAllocations(for: selectedMonth)
        }
    }

    private var budgetActivitySubmenu: some View {
        budgetSubmenuPage(
            title: "Activity",
            subtitle: "See what moved, then drill into what changed.",
            systemImage: "list.bullet.rectangle.portrait"
        ) {
            BudgetActivityWorkspaceView(
                budget: budget,
                selectedMonth: $selectedMonth,
                onAddExpense: startAddExpense,
                onAddIncome: startAddIncome,
                onAddSavings: {
                    if let goal = budget.savingsGoals.first {
                        savingsEntryDraft = SavingsEntryDraft(goalId: goal.id)
                    } else {
                        showingAddSavingsGoal = true
                    }
                },
                onEditExpense: { editingExpense = $0 },
                onEditIncome: { editingIncome = $0 },
                onEditSavings: { editingSavingsEntry = $0 },
                onEditRecurring: { editingRecurringPayment = $0 }
            )
        }
    }

    private var budgetAccountsSubmenu: some View {
        budgetSubmenuPage(
            title: "Accounts",
            subtitle: "Know where your money is and what needs attention.",
            systemImage: "creditcard.and.123"
        ) {
            BudgetAccountsWorkspaceView(
                budget: budget,
                onTransfer: { showingAddCashTransfer = true },
                onManageBanks: { showingBankAccounts = true },
                onManageCredit: { showingCreditAccounts = true }
            )
        }
    }

    private var budgetReportsSubmenu: some View {
        budgetSubmenuPage(
            title: "Reports",
            subtitle: "Understand the month without turning reports into another editor.",
            systemImage: "chart.pie"
        ) {
            BudgetReportsWorkspaceView(
                budget: budget,
                selectedMonth: $selectedMonth
            )
        }
    }
'''


def main() -> int:
    if not PATH.exists():
        print(f"error: {PATH} was not found; run from the repository root", file=sys.stderr)
        return 2

    text = PATH.read_text()

    if NEW in text:
        print("TIM-118 Budget Hub workspaces are already wired into ContentView.swift")
        return 0

    count = text.count(OLD)
    if count != 1:
        print(
            f"error: expected exactly one legacy Budget Hub submenu block, found {count}; refusing to modify ContentView.swift",
            file=sys.stderr,
        )
        return 3

    updated = text.replace(OLD, NEW, 1)
    PATH.write_text(updated)
    print("Applied TIM-118 Budget Hub workspace routing to ContentView.swift")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
