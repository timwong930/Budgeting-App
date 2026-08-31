from pathlib import Path

reconciliation_path = Path("Budgeting App/PlaidTransactionReconciliation.swift")
text = reconciliation_path.read_text()

old_unpaired = '''            } else {
                // Do not let a known transfer/payment remain counted as ordinary income
                // or spending just because the matching account-side delta is absent.
                _ = removeReconciledPlaidTransaction(id: transaction.id)
                let added = upsertPlaidReviewItem(
                    sourceId: transaction.id,
                    title: transactionDisplayName(transaction),
                    detail: "Plaid transfer/payment could not be paired to another synced account. Review before counting it as income or spending.",
                    amount: transaction.amount,
                    date: transaction.date
                )
                result.handledTransactionIds.insert(transaction.id)
                if added { result.reviewItemsAdded += 1 }
            }'''
new_unpaired = '''            } else {
                // Keep one-sided external transfers visible in the account ledger while
                // keeping them out of budget income/spending until they are reviewed.
                _ = removeReconciledPlaidTransaction(id: transaction.id)
                upsertUnpairedPlaidTransfer(
                    transaction,
                    accountName: accountNamesById[transaction.accountId] ?? "Plaid account",
                    accountType: type
                )
                let added = upsertPlaidReviewItem(
                    sourceId: transaction.id,
                    title: transactionDisplayName(transaction),
                    detail: "Plaid transfer/payment could not be paired to another synced account. It remains visible in the account ledger as an external transfer, but is excluded from income/spending until reviewed.",
                    amount: transaction.amount,
                    date: transaction.date
                )
                result.handledTransactionIds.insert(transaction.id)
                if added { result.reviewItemsAdded += 1 }
            }'''
if text.count(old_unpaired) != 1:
    raise SystemExit(f"Expected one unpaired-transfer block, found {text.count(old_unpaired)}")
text = text.replace(old_unpaired, new_unpaired)

marker_line = '''        let sourceMarker = plaidTransferSourceMarker(outflowId: outflow.id, inflowId: inflow.id)

        let existingIndex = cashTransfers.firstIndex { existing in'''
marker_replacement = '''        let sourceMarker = plaidTransferSourceMarker(outflowId: outflow.id, inflowId: inflow.id)
        _ = removePlaidSingleTransfers(sourceIds: [outflow.id, inflow.id])

        let existingIndex = cashTransfers.firstIndex { existing in'''
if text.count(marker_line) != 1:
    raise SystemExit(f"Expected one paired-transfer marker anchor, found {text.count(marker_line)}")
text = text.replace(marker_line, marker_replacement)

helper_anchor = '''    func plaidTransferSourceMarker(outflowId: String, inflowId: String) -> String {
        let ids = [outflowId, inflowId].sorted()
        return "[PLAID_PAIR:\(ids.joined(separator: "|"))]"
    }
'''
helpers = '''    func upsertUnpairedPlaidTransfer(
        _ transaction: PlaidSyncedTransaction,
        accountName: String,
        accountType: PlaidAccountType
    ) {
        if let pendingTransactionId = transaction.pendingTransactionId {
            _ = removePlaidSingleTransfers(sourceIds: [pendingTransactionId])
        }

        let sourceMarker = plaidSingleTransferSourceMarker(transaction.id)
        let currentAccountId = stableFinancialAccountId(forPlaidAccountId: transaction.accountId)
        let isOutflow = transaction.amount > 0
        let amount = roundedReconciliationCurrency(abs(transaction.amount))
        let externalName = "External account"
        let pendingMarker = transaction.pending ? " [PENDING]" : ""
        let isCardPayment = accountType == .credit && isLikelyCreditCardPaymentForReconciliation(transaction)
        let title = isCardPayment ? "Credit card payment" : transactionDisplayName(transaction)
        let note = "\(sourceMarker)\(pendingMarker) Unpaired Plaid transfer/payment"

        if let existingIndex = cashTransfers.firstIndex(where: { $0.note.contains(sourceMarker) }) {
            cashTransfers[existingIndex].name = title
            cashTransfers[existingIndex].amount = amount
            cashTransfers[existingIndex].date = transaction.date
            cashTransfers[existingIndex].fromAccountName = isOutflow ? accountName : externalName
            cashTransfers[existingIndex].toAccountName = isOutflow ? externalName : accountName
            cashTransfers[existingIndex].fromAccountId = isOutflow ? currentAccountId : nil
            cashTransfers[existingIndex].toAccountId = isOutflow ? nil : currentAccountId
            cashTransfers[existingIndex].note = note
            return
        }

        cashTransfers.append(
            CashTransfer(
                name: title,
                amount: amount,
                date: transaction.date,
                fromAccountName: isOutflow ? accountName : externalName,
                toAccountName: isOutflow ? externalName : accountName,
                fromAccountId: isOutflow ? currentAccountId : nil,
                toAccountId: isOutflow ? nil : currentAccountId,
                note: note
            )
        )
    }

    func plaidSingleTransferSourceMarker(_ transactionId: String) -> String {
        "[PLAID_SINGLE:\(transactionId)]"
    }

    @discardableResult
    func removePlaidSingleTransfers(sourceIds: [String]) -> Int {
        let markers = sourceIds.map(plaidSingleTransferSourceMarker)
        let oldCount = cashTransfers.count
        cashTransfers.removeAll { transfer in
            markers.contains { transfer.note.contains($0) }
        }
        return oldCount - cashTransfers.count
    }

''' + helper_anchor
if text.count(helper_anchor) != 1:
    raise SystemExit(f"Expected one transfer helper anchor, found {text.count(helper_anchor)}")
text = text.replace(helper_anchor, helpers)

old_remove = '''    func removeReconciledPlaidTransaction(id: String) -> Int {
        let oldExpenseCount = expenses.count
        expenses.removeAll { $0.plaidMetadata?.transactionId == id }
        let oldIncomeCount = incomes.count
        incomes.removeAll { $0.plaidMetadata?.transactionId == id }
        clearPlaidReviewItems(sourceIds: [id])
        return (oldExpenseCount - expenses.count) + (oldIncomeCount - incomes.count)
    }'''
new_remove = '''    func removeReconciledPlaidTransaction(id: String) -> Int {
        let oldExpenseCount = expenses.count
        expenses.removeAll { $0.plaidMetadata?.transactionId == id }
        let oldIncomeCount = incomes.count
        incomes.removeAll { $0.plaidMetadata?.transactionId == id }
        let removedSingleTransfers = removePlaidSingleTransfers(sourceIds: [id])
        clearPlaidReviewItems(sourceIds: [id])
        return (oldExpenseCount - expenses.count) + (oldIncomeCount - incomes.count) + removedSingleTransfers
    }'''
if text.count(old_remove) != 1:
    raise SystemExit(f"Expected one removeReconciledPlaidTransaction block, found {text.count(old_remove)}")
reconciliation_path.write_text(text.replace(old_remove, new_remove))

ledger_path = Path("Budgeting App/AccountTransactionLedger.swift")
ledger = ledger_path.read_text()
old_flag = '''            let isPlaidPair = transfer.note.hasPrefix("[PLAID_PAIR:")
            let otherName ='''
new_flag = '''            let isPlaidPair = transfer.note.hasPrefix("[PLAID_PAIR:")
            let isPlaidSingle = transfer.note.hasPrefix("[PLAID_SINGLE:")
            let isPlaidTransfer = isPlaidPair || isPlaidSingle
            let otherName ='''
if ledger.count(old_flag) != 2:
    raise SystemExit(f"Expected two ledger Plaid transfer flag blocks, found {ledger.count(old_flag)}")
ledger = ledger.replace(old_flag, new_flag)

old_metadata = '''                    isPending: false,
                    sourceLabel: isPlaidPair ? "Plaid" : "Manual",
                    plaidStatus: isPlaidPair ? .reconciled : nil,
                    matchConfidence: nil'''
new_metadata = '''                    isPending: isPlaidSingle && transfer.note.contains("[PENDING]"),
                    sourceLabel: isPlaidTransfer ? "Plaid" : "Manual",
                    plaidStatus: isPlaidPair ? .reconciled : (isPlaidSingle ? .needsReview : nil),
                    matchConfidence: nil'''
if ledger.count(old_metadata) != 2:
    raise SystemExit(f"Expected two ledger metadata blocks, found {ledger.count(old_metadata)}")
ledger_path.write_text(ledger.replace(old_metadata, new_metadata))
