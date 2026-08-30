from pathlib import Path

path = Path('Budgeting App/MarginViews.swift')
source = path.read_text()

source = source.replace(
    '@State private var type: PortfolioTransactionType = .contribution',
    '@State private var type: PortfolioTransactionType = .manualAdjustment',
    1,
)

old_can_save = '''        case .contribution:\n            let hasFundingAccount = !fundingBankAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty\n            return transactionAmount > 0 && hasFundingAccount\n'''
new_can_save = '''        case .contribution:\n            return transactionAmount > 0\n'''
if old_can_save not in source:
    raise SystemExit('contribution canSave block not found')
source = source.replace(old_can_save, new_can_save, 1)

old_portfolio_section = '''                Section("Portfolio") {\n                    Picker("Account", selection: $portfolioAccountId) {\n                        ForEach(budget.activePortfolioAccounts) { account in\n                            Text(account.name).tag(Optional(account.id))\n                        }\n                    }\n                    if budget.activePortfolioAccounts.isEmpty {\n                        Text("Add a portfolio account before recording investment activity.")\n                            .font(.caption)\n                            .foregroundStyle(.secondary)\n                    }\n                }\n'''
new_portfolio_section = '''                Section("Manual Backup") {\n                    Picker("Portfolio Account", selection: $portfolioAccountId) {\n                        ForEach(budget.activePortfolioAccounts) { account in\n                            Text(portfolioAccountLabel(for: account)).tag(Optional(account.id))\n                        }\n                    }\n                    if budget.activePortfolioAccounts.isEmpty {\n                        Text("Connect Plaid or add a portfolio account before recording manual activity.")\n                            .font(.caption)\n                            .foregroundStyle(.secondary)\n                    } else if let portfolioAccountId, budget.portfolioAccountIsPlaidAuthoritative(portfolioAccountId) {\n                        Text("Plaid is the primary source for this account. Use manual transactions only to backfill or correct activity Plaid misses; synced balances remain authoritative.")\n                            .font(.caption)\n                            .foregroundStyle(.secondary)\n                    } else {\n                        Text("Manual transactions are a backup for activity that is not available from Plaid.")\n                            .font(.caption)\n                            .foregroundStyle(.secondary)\n                    }\n                }\n'''
if old_portfolio_section not in source:
    raise SystemExit('AddTransaction portfolio section not found')
source = source.replace(old_portfolio_section, new_portfolio_section, 1)

old_funding = '''                    if type == .contribution {\n                        Picker("From Account", selection: $fundingBankAccount) {\n                            ForEach(bankAccountOptions, id: \\.self) { accountName in\n                                Text(accountName).tag(accountName)\n                            }\n                        }\n                        if budget.bankAccounts.isEmpty {\n                            Text("Add a bank account before recording a portfolio contribution.")\n                                .font(.caption)\n                                .foregroundStyle(.secondary)\n                        } else if let selectedAccount {\n                            LabeledContent("Available", value: selectedAccount.balance.formatted(.currency(code: "USD")))\n                        }\n                    }\n'''
new_funding = '''                    if type == .contribution {\n                        if budget.bankAccounts.isEmpty {\n                            Text("Funding account is optional for a manual backup contribution.")\n                                .font(.caption)\n                                .foregroundStyle(.secondary)\n                        } else {\n                            Picker("From Account (optional)", selection: $fundingBankAccount) {\n                                Text("Not linked").tag("")\n                                ForEach(bankAccountOptions, id: \\.self) { accountName in\n                                    Text(accountName).tag(accountName)\n                                }\n                            }\n                            if let selectedAccount {\n                                LabeledContent("Available", value: selectedAccount.balance.formatted(.currency(code: "USD")))\n                            }\n                        }\n                    }\n'''
if old_funding not in source:
    raise SystemExit('funding block not found')
source = source.replace(old_funding, new_funding, 1)

source = source.replace('.navigationTitle("Add Transaction")', '.navigationTitle("Manual Transaction")', 1)

transaction_helper_anchor = '''    private var selectedAccount: BankAccount? {\n'''
transaction_helper = '''    private func portfolioAccountLabel(for account: PortfolioAccount) -> String {\n        let matches = budget.activePortfolioAccounts.filter { $0.name == account.name }\n        guard matches.count > 1, let index = matches.firstIndex(where: { $0.id == account.id }) else {\n            return account.name\n        }\n        return "\\(account.name) \\(index + 1)"\n    }\n\n'''
if transaction_helper_anchor not in source:
    raise SystemExit('transaction helper anchor not found')
source = source.replace(transaction_helper_anchor, transaction_helper + transaction_helper_anchor, 1)

old_investment_section = '''                Section("Portfolio") {\n                    Picker("Account", selection: $portfolioAccountId) {\n                        ForEach(budget.activePortfolioAccounts) { account in\n                            Text(account.name).tag(Optional(account.id))\n                        }\n                    }\n                    if budget.activePortfolioAccounts.isEmpty {\n                        Text("Add a portfolio account before recording an investment.")\n                            .font(.caption)\n                            .foregroundStyle(.secondary)\n                    }\n                }\n'''
new_investment_section = '''                Section("Manual Backup") {\n                    Picker("Portfolio Account", selection: $portfolioAccountId) {\n                        ForEach(budget.activePortfolioAccounts) { account in\n                            Text(portfolioAccountLabel(for: account)).tag(Optional(account.id))\n                        }\n                    }\n                    if budget.activePortfolioAccounts.isEmpty {\n                        Text("Connect Plaid or add a portfolio account before recording a manual investment.")\n                            .font(.caption)\n                            .foregroundStyle(.secondary)\n                    } else if let portfolioAccountId, budget.portfolioAccountIsPlaidAuthoritative(portfolioAccountId) {\n                        Text("Plaid remains the primary source for this account. Use manual investments only when a position is missing or needs temporary backfill; the next Plaid sync may replace synced position data.")\n                            .font(.caption)\n                            .foregroundStyle(.secondary)\n                    } else {\n                        Text("Manual investments are intended as a fallback when Plaid data is unavailable.")\n                            .font(.caption)\n                            .foregroundStyle(.secondary)\n                    }\n                }\n'''
if old_investment_section not in source:
    raise SystemExit('AddInvestment portfolio section not found')
source = source.replace(old_investment_section, new_investment_section, 1)
source = source.replace('.navigationTitle("Add Investment")', '.navigationTitle("Manual Investment")', 1)

investment_helper_anchor = '''    private func applyExistingHoldingDefaults() {\n'''
investment_helper = '''    private func portfolioAccountLabel(for account: PortfolioAccount) -> String {\n        let matches = budget.activePortfolioAccounts.filter { $0.name == account.name }\n        guard matches.count > 1, let index = matches.firstIndex(where: { $0.id == account.id }) else {\n            return account.name\n        }\n        return "\\(account.name) \\(index + 1)"\n    }\n\n'''
if investment_helper_anchor not in source:
    raise SystemExit('investment helper anchor not found')
source = source.replace(investment_helper_anchor, investment_helper + investment_helper_anchor, 1)

path.write_text(source)
