from pathlib import Path

path = Path("Budgeting App/ContentView.swift")
text = path.read_text()

needle = "                budgetHubSnapshotSection\n"
if needle not in text:
    raise SystemExit("budget snapshot anchor not found")
if "                budgetQuickActionsSection\n" not in text:
    text = text.replace(needle, needle + "                budgetQuickActionsSection\n", 1)

anchor = "    private var budgetSubmenusSection: some View {\n"
insert = '''    private var budgetQuickActionsSection: some View {
        GlassCard(padding: 10) {
            HStack(spacing: 8) {
                budgetQuickAction(title: "Expense", systemImage: "minus.circle.fill", tint: .red) {
                    startAddExpense()
                }
                budgetQuickAction(title: "Income", systemImage: "plus.circle.fill", tint: .green) {
                    startAddIncome()
                }
                budgetQuickAction(title: "Savings", systemImage: "banknote.fill", tint: .mint) {
                    if let goal = budget.savingsGoals.first {
                        savingsEntryDraft = SavingsEntryDraft(goalId: goal.id)
                    } else {
                        showingAddSavingsGoal = true
                    }
                }
                budgetQuickAction(title: "Transfer", systemImage: "arrow.left.arrow.right", tint: .cyan) {
                    showingAddCashTransfer = true
                }
            }
        }
    }

    private func budgetQuickAction(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

'''
if "private var budgetQuickActionsSection" not in text:
    if anchor not in text:
        raise SystemExit("budget submenu anchor not found")
    text = text.replace(anchor, insert + anchor, 1)

path.write_text(text)
