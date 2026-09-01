from pathlib import Path

path = Path("Budgeting App/AccountTransactionLedger.swift")
text = path.read_text()

old = '''struct BankAccountLedgerView: View {
    @Binding var account: BankAccount
    @ObservedObject var budget: BudgetModel
    @State private var editingEntry: AccountLedgerEntry?

    private var entries: [AccountLedgerEntry] {
'''
new = '''struct BankAccountLedgerView: View {
    @Binding var account: BankAccount
    @ObservedObject var budget: BudgetModel
    @State private var editingEntry: AccountLedgerEntry?
    @StateObject private var cashCategoryStore = BankCashCategoryStore()
    @State private var showingAddCashCategory = false
    @State private var editingCashCategory: BankCashCategory?

    private var entries: [AccountLedgerEntry] {
'''
if text.count(old) != 1:
    raise SystemExit(f"Bank ledger state anchor count: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''    private var institutionName: String? {
        guard let accountId = budget.ledgerFinancialAccountId(for: account) else { return account.plaidMetadata?.institutionName }
        return budget.financialAccounts.first(where: { $0.id == accountId })?.institutionName ?? account.plaidMetadata?.institutionName
    }

    var body: some View {
'''
new = '''    private var institutionName: String? {
        guard let accountId = budget.ledgerFinancialAccountId(for: account) else { return account.plaidMetadata?.institutionName }
        return budget.financialAccounts.first(where: { $0.id == accountId })?.institutionName ?? account.plaidMetadata?.institutionName
    }

    private var cashCategoryAccountKey: String {
        if let accountId = budget.ledgerFinancialAccountId(for: account) {
            return "financial:\\(accountId.uuidString)"
        }
        if let externalAccountId = account.plaidMetadata?.accountId, !externalAccountId.isEmpty {
            return "plaid:\\(externalAccountId)"
        }
        return "bank:\\(account.id.uuidString)"
    }

    var body: some View {
'''
if text.count(old) < 1:
    raise SystemExit("Bank ledger account-key anchor missing")
text = text.replace(old, new, 1)

old = '''            }

            AccountLedgerSection(entries: entries, onEdit: { editingEntry = $0 })
        }
        .navigationTitle(account.name)
'''
new = '''            }

            BankCashCategoriesSection(
                store: cashCategoryStore,
                accountKey: cashCategoryAccountKey,
                accountBalance: account.balance,
                onAdd: { showingAddCashCategory = true },
                onEdit: { editingCashCategory = $0 }
            )

            AccountLedgerSection(entries: entries, onEdit: { editingEntry = $0 })
        }
        .navigationTitle(account.name)
'''
if text.count(old) < 1:
    raise SystemExit("Bank ledger section anchor missing")
text = text.replace(old, new, 1)

old = '''        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Edit") {
                    EditBankAccountView(account: $account)
                }
            }
        }
    }
}

struct CreditAccountLedgerView: View {
'''
new = '''        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Edit") {
                    EditBankAccountView(account: $account)
                }
            }
        }
        .sheet(isPresented: $showingAddCashCategory) {
            BankCashCategoryEditorView(
                store: cashCategoryStore,
                accountKey: cashCategoryAccountKey,
                accountName: account.name,
                accountBalance: account.balance
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingCashCategory) { category in
            BankCashCategoryEditorView(
                store: cashCategoryStore,
                accountKey: cashCategoryAccountKey,
                accountName: account.name,
                accountBalance: account.balance,
                existingCategory: category
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct CreditAccountLedgerView: View {
'''
if text.count(old) != 1:
    raise SystemExit(f"Bank ledger sheet anchor count: {text.count(old)}")
text = text.replace(old, new, 1)

path.write_text(text)
