from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "Budgeting App/MarginViews.swift"
text = PATH.read_text()

def patch_segment(start_marker, end_marker, changes, label):
    global text
    start = text.find(start_marker)
    end = text.find(end_marker, start + 1)
    if start < 0 or end < 0:
        raise RuntimeError(f"{label}: segment markers not found")
    segment = text[start:end]
    for old, new, change_label in changes:
        count = segment.count(old)
        if count != 1:
            raise RuntimeError(f"{label}/{change_label}: expected 1 match, found {count}")
        segment = segment.replace(old, new, 1)
    text = text[:start] + segment + text[end:]

patch_segment(
    "private struct AddTransactionView: View {",
    "private struct AddInvestmentView: View {",
    [
        (
            '    @State private var fundingBankAccount = ""\n',
            '    @State private var fundingBankAccount = ""\n    @State private var portfolioAccountId: UUID?\n',
            "state"
        ),
        (
            '    private var canSave: Bool {\n        switch type {\n',
            '    private var canSave: Bool {\n        guard portfolioAccountId != nil else { return false }\n        switch type {\n',
            "validation"
        ),
        (
            '            Form {\n                Section("Position Details") {\n',
            '''            Form {
                Section("Portfolio") {
                    Picker("Account", selection: $portfolioAccountId) {
                        ForEach(budget.activePortfolioAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    if budget.activePortfolioAccounts.isEmpty {
                        Text("Add a portfolio account before recording investment activity.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Position Details") {
''',
            "picker"
        ),
        (
            '                                notes: notes.nilIfBlank,\n                                fundingBankAccount: type == .contribution ? fundingBankAccount.nilIfBlank : nil\n',
            '                                notes: notes.nilIfBlank,\n                                fundingBankAccount: type == .contribution ? fundingBankAccount.nilIfBlank : nil,\n                                portfolioAccountId: portfolioAccountId\n',
            "linkage"
        ),
        (
            '''            .onAppear {
                if fundingBankAccount.isEmpty {
                    fundingBankAccount = budget.bankAccounts.first?.name ?? ""
                }
            }
''',
            '''            .onAppear {
                if portfolioAccountId == nil {
                    portfolioAccountId = budget.activePortfolioAccounts.first?.id
                }
                if fundingBankAccount.isEmpty {
                    fundingBankAccount = budget.bankAccounts.first?.name ?? ""
                }
            }
''',
            "default"
        )
    ],
    "AddTransactionView"
)

patch_segment(
    "private struct AddInvestmentView: View {",
    "private struct ElectricBillTrackerView: View {",
    [
        (
            '    @State private var quoteFetchTask: Task<Void, Never>?\n',
            '    @State private var quoteFetchTask: Task<Void, Never>?\n    @State private var portfolioAccountId: UUID?\n',
            "state"
        ),
        (
            '    private var canSave: Bool {\n        !cleanTicker.isEmpty && sharesBought > 0 && investmentAmount > 0\n    }\n',
            '    private var canSave: Bool {\n        portfolioAccountId != nil && !cleanTicker.isEmpty && sharesBought > 0 && investmentAmount > 0\n    }\n',
            "validation"
        ),
        (
            '''            Form {
                Section("Position Details") {
                    TextField("Ticker", text: $ticker)
''',
            '''            Form {
                Section("Portfolio") {
                    Picker("Account", selection: $portfolioAccountId) {
                        ForEach(budget.activePortfolioAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    if budget.activePortfolioAccounts.isEmpty {
                        Text("Add a portfolio account before recording an investment.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Position Details") {
                    TextField("Ticker", text: $ticker)
''',
            "picker"
        ),
        (
            '                        let existingHolding = budget.holdings.first { $0.ticker.uppercased() == cleanTicker }\n',
            '''                        guard let portfolioAccountId else { return }
                        let existingHolding = budget.holdings.first {
                            $0.portfolioAccountId == portfolioAccountId && $0.ticker.uppercased() == cleanTicker
                        }
''',
            "existing position"
        ),
        (
            '''                            date: date,
                            fundingSource: .cash
                        )
                        if let idx = budget.holdings.firstIndex(where: { $0.ticker.uppercased() == cleanTicker }) {
''',
            '''                            date: date,
                            fundingSource: .cash,
                            portfolioAccountId: portfolioAccountId
                        )
                        if let idx = budget.holdings.firstIndex(where: {
                            $0.portfolioAccountId == portfolioAccountId && $0.ticker.uppercased() == cleanTicker
                        }) {
''',
            "save linkage"
        ),
        (
            '''            .onDisappear {
                quoteFetchTask?.cancel()
            }
            .toolbar {
''',
            '''            .onAppear {
                if portfolioAccountId == nil {
                    portfolioAccountId = budget.activePortfolioAccounts.first?.id
                }
            }
            .onDisappear {
                quoteFetchTask?.cancel()
            }
            .toolbar {
''',
            "default"
        ),
        (
            '    private func applyExistingHoldingDefaults() {\n        guard let holding = budget.holdings.first(where: { $0.ticker.uppercased() == cleanTicker }) else { return }\n',
            '''    private func applyExistingHoldingDefaults() {
        guard let portfolioAccountId,
              let holding = budget.holdings.first(where: {
                  $0.portfolioAccountId == portfolioAccountId && $0.ticker.uppercased() == cleanTicker
              }) else { return }
''',
            "scoped defaults"
        )
    ],
    "AddInvestmentView"
)

old_cash = '                editableCurrencyRow("Cash Balance", value: $budget.portfolioSnapshot.cashBalance)\n'
if text.count(old_cash) != 1:
    raise RuntimeError(f"aggregate cash: expected 1 match, found {text.count(old_cash)}")
text = text.replace(old_cash, '                metricRow("All Portfolios Cash", budget.portfolioSnapshot.cashBalance)\n', 1)

PATH.write_text(text)
