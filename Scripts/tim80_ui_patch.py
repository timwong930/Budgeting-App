from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "Budgeting App/MarginViews.swift"
text = PATH.read_text()

def once(old, new, label):
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 match, found {count}")
    text = text.replace(old, new, 1)

# Add Transaction
once(
'''    @State private var fundingBankAccount = ""
''',
'''    @State private var fundingBankAccount = ""
    @State private var portfolioAccountId: UUID?
''',
"transaction portfolio state"
)
once(
'''    private var canSave: Bool {
        switch type {
''',
'''    private var canSave: Bool {
        guard portfolioAccountId != nil else { return false }
        switch type {
''',
"transaction requires portfolio"
)
once(
'''            Form {
                Section("Position Details") {
''',
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
"transaction account picker"
)
once(
'''                                notes: notes.nilIfBlank,
                                fundingBankAccount: type == .contribution ? fundingBankAccount.nilIfBlank : nil
''',
'''                                notes: notes.nilIfBlank,
                                fundingBankAccount: type == .contribution ? fundingBankAccount.nilIfBlank : nil,
                                portfolioAccountId: portfolioAccountId
''',
"transaction account linkage"
)
once(
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
"transaction default account"
)

# Add Investment
once(
'''    @State private var date = Date()
    @State private var quoteFetchTask: Task<Void, Never>?

    private var cleanTicker: String {
''',
'''    @State private var date = Date()
    @State private var quoteFetchTask: Task<Void, Never>?
    @State private var portfolioAccountId: UUID?

    private var cleanTicker: String {
''',
"investment portfolio state"
)
once(
'''    private var canSave: Bool {
        !cleanTicker.isEmpty && sharesBought > 0 && investmentAmount > 0
    }
''',
'''    private var canSave: Bool {
        portfolioAccountId != nil && !cleanTicker.isEmpty && sharesBought > 0 && investmentAmount > 0
    }
''',
"investment requires portfolio"
)
# Replace second Form/Position Details occurrence by anchoring AddInvestment body
old = '''    var body: some View {
        NavigationStack {
            Form {
                Section("Position Details") {
                    TextField("Ticker", text: $ticker)
'''
new = '''    var body: some View {
        NavigationStack {
            Form {
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
'''
# This pattern should now only occur in AddInvestment (Manual holding has same field later, but nearby body exact may repeat). Find after AddInvestment marker.
idx = text.find("private struct AddInvestmentView")
a = text.find(old, idx)
if a < 0:
    raise RuntimeError("investment account picker: marker not found")
text = text[:a] + text[a:].replace(old, new, 1)

once(
'''                        let existingHolding = budget.holdings.first { $0.ticker.uppercased() == cleanTicker }
''',
'''                        guard let portfolioAccountId else { return }
                        let existingHolding = budget.holdings.first {
                            $0.portfolioAccountId == portfolioAccountId && $0.ticker.uppercased() == cleanTicker
                        }
''',
"investment scoped existing holding"
)
once(
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
"investment scoped save"
)
once(
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
"investment default account"
)
once(
'''    private func applyExistingHoldingDefaults() {
        guard let holding = budget.holdings.first(where: { $0.ticker.uppercased() == cleanTicker }) else { return }
''',
'''    private func applyExistingHoldingDefaults() {
        guard let portfolioAccountId,
              let holding = budget.holdings.first(where: {
                  $0.portfolioAccountId == portfolioAccountId && $0.ticker.uppercased() == cleanTicker
              }) else { return }
''',
"investment scoped defaults"
)

# Manual Holding
manual_marker = text.find("private struct ManualHoldingEntryView")
if manual_marker < 0:
    raise RuntimeError("manual holding marker not found")
manual_tail = text[manual_marker:]
manual_tail = manual_tail.replace(
'''    @State private var quoteFetchTask: Task<Void, Never>?

    var body: some View {
''',
'''    @State private var quoteFetchTask: Task<Void, Never>?
    @State private var portfolioAccountId: UUID?

    var body: some View {
''', 1)
manual_tail = manual_tail.replace(
'''            Form {
                Section("Position Details") {
''',
'''            Form {
                Section("Portfolio") {
                    Picker("Account", selection: $portfolioAccountId) {
                        ForEach(budget.activePortfolioAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    if budget.activePortfolioAccounts.isEmpty {
                        Text("Add a portfolio account before recording a manual holding.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Position Details") {
''', 1)
manual_tail = manual_tail.replace(
'''            .onDisappear {
                quoteFetchTask?.cancel()
            }
''',
'''            .onAppear {
                if portfolioAccountId == nil {
                    portfolioAccountId = budget.activePortfolioAccounts.first?.id
                }
            }
            .onDisappear {
                quoteFetchTask?.cancel()
            }
''', 1)
manual_tail = manual_tail.replace(
'''                        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        guard !cleanTicker.isEmpty, shares > 0 else { return }
''',
'''                        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        guard let portfolioAccountId, !cleanTicker.isEmpty, shares > 0 else { return }
''', 1)
manual_tail = manual_tail.replace(
'''                                amount: shares * averageCost,
                                notes: "Manual holding entry"
''',
'''                                amount: shares * averageCost,
                                notes: "Manual holding entry",
                                portfolioAccountId: portfolioAccountId
''', 1)
manual_tail = manual_tail.replace(
'''                        if let idx = budget.holdings.firstIndex(where: { $0.ticker.uppercased() == cleanTicker }) {
''',
'''                        if let idx = budget.holdings.firstIndex(where: {
                            $0.portfolioAccountId == portfolioAccountId && $0.ticker.uppercased() == cleanTicker
                        }) {
''', 1)
manual_tail = manual_tail.replace(
'''                    .disabled(ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || shares <= 0)
''',
'''                    .disabled(portfolioAccountId == nil || ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || shares <= 0)
''', 1)
text = text[:manual_marker] + manual_tail

# Aggregate cash is derived, not editable.
once(
'''                editableCurrencyRow("Cash Balance", value: $budget.portfolioSnapshot.cashBalance)
''',
'''                metricRow("All Portfolios Cash", budget.portfolioSnapshot.cashBalance)
''',
"derived aggregate cash display"
)

PATH.write_text(text)
