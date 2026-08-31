import SwiftUI

enum AccountLedgerEntryKind: String, Sendable, Equatable {
    case expense
    case income
    case purchase
    case refund
    case payment
    case transferIn
    case transferOut

    var title: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .purchase: return "Purchase"
        case .refund: return "Refund / Credit"
        case .payment: return "Payment"
        case .transferIn: return "Transfer In"
        case .transferOut: return "Transfer Out"
        }
    }

    var systemImage: String {
        switch self {
        case .expense, .purchase: return "arrow.up.right"
        case .income, .refund: return "arrow.down.left"
        case .payment: return "creditcard"
        case .transferIn: return "arrow.down.left.circle"
        case .transferOut: return "arrow.up.right.circle"
        }
    }
}

struct AccountLedgerEntry: Identifiable, Sendable, Equatable {
    let id: String
    var date: Date
    var title: String
    var detail: String
    var signedAmount: Double
    var kind: AccountLedgerEntryKind
    var isPending: Bool
    var sourceLabel: String
    var plaidStatus: PlaidImportStatus?
    var matchConfidence: Double?
}

extension BudgetModel {
    func bankLedgerEntries(for account: BankAccount) -> [AccountLedgerEntry] {
        let accountId = ledgerFinancialAccountId(
            localId: account.id,
            name: account.name,
            metadata: account.plaidMetadata,
            kind: .depository
        )
        let normalizedName = ledgerNormalizedAccountName(account.name)
        var entries: [AccountLedgerEntry] = []

        for expense in expenses where ledgerExpenseUsesAccount(expense, accountId: accountId, normalizedName: normalizedName) {
            let isCardPayment = creditCardPaymentTarget(for: expense) != nil
            entries.append(
                AccountLedgerEntry(
                    id: "expense|\(expense.id.uuidString)",
                    date: expense.date,
                    title: expense.name,
                    detail: isCardPayment ? "Credit card payment" : ledgerExpenseDetail(expense),
                    signedAmount: -abs(expense.amount),
                    kind: isCardPayment ? .payment : .expense,
                    isPending: ledgerIsPending(expense.plaidMetadata, note: expense.note),
                    sourceLabel: expense.plaidMetadata == nil ? "Manual" : "Plaid",
                    plaidStatus: expense.plaidMetadata?.status,
                    matchConfidence: expense.plaidMetadata?.matchConfidence
                )
            )
        }

        for income in incomes where ledgerIncomeUsesAccount(income, accountId: accountId, normalizedName: normalizedName) {
            entries.append(
                AccountLedgerEntry(
                    id: "income|\(income.id.uuidString)",
                    date: income.date,
                    title: income.name,
                    detail: "Deposit / income",
                    signedAmount: abs(income.amount),
                    kind: .income,
                    isPending: income.plaidMetadata?.isPending == true,
                    sourceLabel: income.plaidMetadata == nil ? "Manual" : "Plaid",
                    plaidStatus: income.plaidMetadata?.status,
                    matchConfidence: income.plaidMetadata?.matchConfidence
                )
            )
        }

        for transfer in cashTransfers {
            let isFrom = ledgerTransferSideMatches(
                id: transfer.fromAccountId,
                name: transfer.fromAccountName,
                accountId: accountId,
                normalizedName: normalizedName
            )
            let isTo = ledgerTransferSideMatches(
                id: transfer.toAccountId,
                name: transfer.toAccountName,
                accountId: accountId,
                normalizedName: normalizedName
            )
            guard isFrom || isTo else { continue }

            let isPlaidPair = transfer.note.hasPrefix("[PLAID_PAIR:")
            let otherName = isFrom ? transfer.toAccountName : transfer.fromAccountName
            let otherKind = isFrom ? ledgerFinancialAccountKind(id: transfer.toAccountId) : ledgerFinancialAccountKind(id: transfer.fromAccountId)
            let isCardPayment = otherKind == .credit
            let kind: AccountLedgerEntryKind = isCardPayment ? .payment : (isFrom ? .transferOut : .transferIn)

            entries.append(
                AccountLedgerEntry(
                    id: "transfer|\(transfer.id.uuidString)|\(isFrom ? "out" : "in")",
                    date: transfer.date,
                    title: transfer.name,
                    detail: isCardPayment ? "Credit card payment • \(otherName)" : "\(isFrom ? "To" : "From") \(otherName)",
                    signedAmount: isFrom ? -abs(transfer.amount) : abs(transfer.amount),
                    kind: kind,
                    isPending: false,
                    sourceLabel: isPlaidPair ? "Plaid" : "Manual",
                    plaidStatus: isPlaidPair ? .reconciled : nil,
                    matchConfidence: nil
                )
            )
        }

        return ledgerSorted(entries)
    }

    func creditLedgerEntries(for account: CreditAccount) -> [AccountLedgerEntry] {
        let accountId = ledgerFinancialAccountId(
            localId: account.id,
            name: account.name,
            metadata: account.plaidMetadata,
            kind: .credit
        )
        let normalizedName = ledgerNormalizedAccountName(account.name)
        var entries: [AccountLedgerEntry] = []

        for expense in expenses {
            if ledgerCreditPaymentTargetsAccount(expense, accountId: accountId, normalizedName: normalizedName) {
                entries.append(
                    AccountLedgerEntry(
                        id: "payment|\(expense.id.uuidString)",
                        date: expense.date,
                        title: expense.name,
                        detail: "Payment to \(account.name)",
                        signedAmount: abs(expense.amount),
                        kind: .payment,
                        isPending: ledgerIsPending(expense.plaidMetadata, note: expense.note),
                        sourceLabel: expense.plaidMetadata == nil ? "Manual" : "Plaid",
                        plaidStatus: expense.plaidMetadata?.status,
                        matchConfidence: expense.plaidMetadata?.matchConfidence
                    )
                )
                continue
            }

            guard ledgerExpenseUsesAccount(expense, accountId: accountId, normalizedName: normalizedName) else { continue }
            entries.append(
                AccountLedgerEntry(
                    id: "purchase|\(expense.id.uuidString)",
                    date: expense.date,
                    title: expense.name,
                    detail: ledgerExpenseDetail(expense),
                    signedAmount: -abs(expense.amount),
                    kind: .purchase,
                    isPending: ledgerIsPending(expense.plaidMetadata, note: expense.note),
                    sourceLabel: expense.plaidMetadata == nil ? "Manual" : "Plaid",
                    plaidStatus: expense.plaidMetadata?.status,
                    matchConfidence: expense.plaidMetadata?.matchConfidence
                )
            )
        }

        for income in incomes where ledgerIncomeUsesAccount(income, accountId: accountId, normalizedName: normalizedName) {
            entries.append(
                AccountLedgerEntry(
                    id: "refund|\(income.id.uuidString)",
                    date: income.date,
                    title: income.name,
                    detail: "Refund / statement credit",
                    signedAmount: abs(income.amount),
                    kind: .refund,
                    isPending: income.plaidMetadata?.isPending == true,
                    sourceLabel: income.plaidMetadata == nil ? "Manual" : "Plaid",
                    plaidStatus: income.plaidMetadata?.status,
                    matchConfidence: income.plaidMetadata?.matchConfidence
                )
            )
        }

        for transfer in cashTransfers {
            let isFrom = ledgerTransferSideMatches(
                id: transfer.fromAccountId,
                name: transfer.fromAccountName,
                accountId: accountId,
                normalizedName: normalizedName
            )
            let isTo = ledgerTransferSideMatches(
                id: transfer.toAccountId,
                name: transfer.toAccountName,
                accountId: accountId,
                normalizedName: normalizedName
            )
            guard isFrom || isTo else { continue }

            let isPlaidPair = transfer.note.hasPrefix("[PLAID_PAIR:")
            let otherName = isFrom ? transfer.toAccountName : transfer.fromAccountName
            entries.append(
                AccountLedgerEntry(
                    id: "card-transfer|\(transfer.id.uuidString)|\(isFrom ? "out" : "in")",
                    date: transfer.date,
                    title: transfer.name,
                    detail: "Payment • \(otherName)",
                    signedAmount: isTo ? abs(transfer.amount) : -abs(transfer.amount),
                    kind: .payment,
                    isPending: false,
                    sourceLabel: isPlaidPair ? "Plaid" : "Manual",
                    plaidStatus: isPlaidPair ? .reconciled : nil,
                    matchConfidence: nil
                )
            )
        }

        return ledgerSorted(entries)
    }

    func ledgerFinancialAccountId(for account: BankAccount) -> UUID? {
        ledgerFinancialAccountId(localId: account.id, name: account.name, metadata: account.plaidMetadata, kind: .depository)
    }

    func ledgerFinancialAccountId(for account: CreditAccount) -> UUID? {
        ledgerFinancialAccountId(localId: account.id, name: account.name, metadata: account.plaidMetadata, kind: .credit)
    }

    private func ledgerFinancialAccountId(
        localId: UUID,
        name: String,
        metadata: PlaidSourceMetadata?,
        kind: FinancialAccountKind
    ) -> UUID? {
        if let externalAccountId = metadata?.accountId,
           let match = financialAccounts.first(where: { $0.kind == kind && $0.externalAccountId == externalAccountId }) {
            return match.id
        }
        if financialAccounts.contains(where: { $0.id == localId && $0.kind == kind }) {
            return localId
        }
        let normalizedName = ledgerNormalizedAccountName(name)
        guard !normalizedName.isEmpty else { return nil }
        let matches = financialAccounts.filter { $0.kind == kind && ledgerNormalizedAccountName($0.name) == normalizedName }
        return matches.count == 1 ? matches[0].id : nil
    }

    private func ledgerExpenseUsesAccount(_ expense: Expense, accountId: UUID?, normalizedName: String) -> Bool {
        if let accountId, let expenseAccountId = expense.paymentAccountId {
            return expenseAccountId == accountId
        }
        if expense.paymentAccountId != nil, accountId == nil {
            return false
        }
        return ledgerNormalizedAccountName(expense.paymentAccount) == normalizedName
    }

    private func ledgerIncomeUsesAccount(_ income: IncomeEntry, accountId: UUID?, normalizedName: String) -> Bool {
        if let accountId, let incomeAccountId = income.bankAccountId {
            return incomeAccountId == accountId
        }
        if income.bankAccountId != nil, accountId == nil {
            return false
        }
        return ledgerNormalizedAccountName(income.bankName) == normalizedName
    }

    private func ledgerCreditPaymentTargetsAccount(_ expense: Expense, accountId: UUID?, normalizedName: String) -> Bool {
        if let accountId, let targetId = expense.creditCardPaymentTargetId {
            return targetId == accountId
        }
        if expense.creditCardPaymentTargetId != nil, accountId == nil {
            return false
        }
        guard let target = creditCardPaymentTarget(for: expense) else { return false }
        return ledgerNormalizedAccountName(target) == normalizedName
    }

    private func ledgerTransferSideMatches(id: UUID?, name: String, accountId: UUID?, normalizedName: String) -> Bool {
        if let accountId, let id {
            return id == accountId
        }
        if id != nil, accountId == nil {
            return false
        }
        return ledgerNormalizedAccountName(name) == normalizedName
    }

    private func ledgerFinancialAccountKind(id: UUID?) -> FinancialAccountKind? {
        guard let id else { return nil }
        return financialAccounts.first(where: { $0.id == id })?.kind
    }

    private func ledgerExpenseDetail(_ expense: Expense) -> String {
        let note = expense.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty, note != "Plaid pending transaction" {
            return note
        }
        return expense.section.title
    }

    private func ledgerIsPending(_ metadata: PlaidSourceMetadata?, note: String) -> Bool {
        metadata?.isPending == true || note == "Plaid pending transaction"
    }

    private func ledgerNormalizedAccountName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func ledgerSorted(_ entries: [AccountLedgerEntry]) -> [AccountLedgerEntry] {
        entries.sorted {
            if $0.date == $1.date { return $0.id > $1.id }
            return $0.date > $1.date
        }
    }
}

struct BankAccountLedgerView: View {
    @Binding var account: BankAccount
    @ObservedObject var budget: BudgetModel

    private var entries: [AccountLedgerEntry] {
        budget.bankLedgerEntries(for: account)
    }

    private var institutionName: String? {
        guard let accountId = budget.ledgerFinancialAccountId(for: account) else { return account.plaidMetadata?.institutionName }
        return budget.financialAccounts.first(where: { $0.id == accountId })?.institutionName ?? account.plaidMetadata?.institutionName
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(account.balance, format: .currency(code: "USD"))
                        .font(.title2.weight(.semibold))
                    Text("Current balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let institutionName, !institutionName.isEmpty {
                        Text(institutionName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            AccountLedgerSection(entries: entries)
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Edit") {
                    EditBankAccountView(account: $account)
                }
            }
        }
    }
}

struct CreditAccountLedgerView: View {
    @Binding var account: CreditAccount
    @ObservedObject var budget: BudgetModel

    private var entries: [AccountLedgerEntry] {
        budget.creditLedgerEntries(for: account)
    }

    private var actualBalance: Double {
        budget.creditAccountActualBalance(account)
    }

    private var utilization: Double {
        guard account.creditLimit > 0 else { return 0 }
        return max(0, actualBalance / account.creditLimit)
    }

    private var institutionName: String? {
        guard let accountId = budget.ledgerFinancialAccountId(for: account) else { return account.plaidMetadata?.institutionName }
        return budget.financialAccounts.first(where: { $0.id == accountId })?.institutionName ?? account.plaidMetadata?.institutionName
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(actualBalance, format: .currency(code: "USD"))
                        .font(.title2.weight(.semibold))
                    Text("Current balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if account.creditLimit > 0 {
                        ProgressView(value: min(utilization, 1))
                        HStack {
                            Text("\(utilization * 100, specifier: "%.1f")% utilization")
                            Spacer()
                            Text(account.creditLimit, format: .currency(code: "USD"))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 16) {
                        Label("Closes \(account.closingDay)", systemImage: "calendar")
                        Label("Due \(account.dueDay)", systemImage: "calendar.badge.clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let institutionName, !institutionName.isEmpty {
                        Text(institutionName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            AccountLedgerSection(entries: entries)
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Edit") {
                    EditCreditAccountView(account: $account)
                }
            }
        }
    }
}

private struct AccountLedgerSection: View {
    let entries: [AccountLedgerEntry]

    var body: some View {
        Section("Transactions") {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Activity linked to this account will appear here.")
                )
            } else {
                ForEach(entries) { entry in
                    AccountLedgerRow(entry: entry)
                }
            }
        }
    }
}

private struct AccountLedgerRow: View {
    let entry: AccountLedgerEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind.systemImage)
                .frame(width: 24)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    if entry.isPending {
                        Text("Pending")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                    Text("•")
                    Text(entry.kind.title)
                    Text("•")
                    Text(entry.sourceLabel)
                    if entry.plaidStatus == .reconciled {
                        Text("• Reconciled")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(entry.signedAmount, format: .currency(code: "USD").sign(strategy: .always()))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(entry.signedAmount > 0 ? .green : .primary)
        }
        .padding(.vertical, 2)
    }
}
