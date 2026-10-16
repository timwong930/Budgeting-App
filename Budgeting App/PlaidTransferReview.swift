import Foundation

/// A linked-bank transaction awaiting a human decision. Positive amounts are
/// money leaving the account (the same convention used by Plaid transactions).
struct PlaidTransferReviewLeg: Identifiable {
    let id: String
    let title: String
    let accountName: String
    let accountId: UUID
    let signedAmount: Double
    let date: Date
}

extension BudgetModel {
    func plaidTransferReviewLeg(sourceId: String) -> PlaidTransferReviewLeg? {
        if let transfer = cashTransfers.first(where: {
            $0.note.hasPrefix("[PLAID_SINGLE:\(sourceId)]")
        }) {
            guard let accountId = transfer.fromAccountId ?? transfer.toAccountId else { return nil }
            let isOutflow = transfer.fromAccountId != nil
            return PlaidTransferReviewLeg(
                id: sourceId,
                title: transfer.name,
                accountName: isOutflow ? transfer.fromAccountName : transfer.toAccountName,
                accountId: accountId,
                signedAmount: isOutflow ? transfer.amount : -transfer.amount,
                date: transfer.date
            )
        }
        if let expense = expenses.first(where: { $0.plaidMetadata?.transactionId == sourceId }),
           let plaidAccountId = expense.plaidMetadata?.accountId,
           let account = financialAccounts.first(where: { $0.externalAccountId == plaidAccountId }) {
            return PlaidTransferReviewLeg(
                id: sourceId,
                title: expense.name,
                accountName: account.name,
                accountId: account.id,
                signedAmount: expense.amount,
                date: expense.date
            )
        }
        if let income = incomes.first(where: { $0.plaidMetadata?.transactionId == sourceId }),
           let plaidAccountId = income.plaidMetadata?.accountId,
           let account = financialAccounts.first(where: { $0.externalAccountId == plaidAccountId }) {
            return PlaidTransferReviewLeg(
                id: sourceId,
                title: income.name,
                accountName: account.name,
                accountId: account.id,
                signedAmount: -income.amount,
                date: income.date
            )
        }
        return nil
    }

    /// Suggest only observed transactions from another connected depository
    /// account. Never offer an arbitrary destination bank without a Plaid row.
    func plaidTransferReviewCandidates(sourceId: String) -> [PlaidTransferReviewLeg] {
        guard let source = plaidTransferReviewLeg(sourceId: sourceId),
              financialAccounts.contains(where: { $0.id == source.accountId && $0.kind == .depository })
        else { return [] }

        var sourceIds = Set(
            expenses.compactMap { $0.plaidMetadata?.transactionId } +
            incomes.compactMap { $0.plaidMetadata?.transactionId }
        )
        for transfer in cashTransfers where transfer.note.hasPrefix("[PLAID_SINGLE:") {
            if let closing = transfer.note.firstIndex(of: "]") {
                let start = transfer.note.index(transfer.note.startIndex, offsetBy: "[PLAID_SINGLE:".count)
                sourceIds.insert(String(transfer.note[start..<closing]))
            }
        }

        return sourceIds.compactMap { candidateId -> PlaidTransferReviewLeg? in
            guard candidateId != sourceId,
                  let candidate = plaidTransferReviewLeg(sourceId: candidateId),
                  candidate.accountId != source.accountId,
                  source.signedAmount * candidate.signedAmount < 0,
                  abs(abs(source.signedAmount) - abs(candidate.signedAmount)) < 0.01,
                  abs(Calendar.current.dateComponents([.day],
                      from: Calendar.current.startOfDay(for: source.date),
                      to: Calendar.current.startOfDay(for: candidate.date)).day ?? Int.max) <= 3,
                  financialAccounts.contains(where: {
                      $0.id == candidate.accountId && $0.kind == .depository
                  }),
                  !cashTransfers.contains(where: {
                      $0.note.hasPrefix("[PLAID_PAIR:") &&
                      $0.note.contains(candidateId)
                  }),
                  !["payroll", "paycheck", "salary", "atm", "cash withdrawal",
                    "zelle", "venmo", "refund"].contains(where: {
                      candidate.title.localizedCaseInsensitiveContains($0)
                  })
            else { return nil }
            return candidate
        }.sorted {
            abs($0.date.timeIntervalSince(source.date)) < abs($1.date.timeIntervalSince(source.date))
        }
    }

    /// On-demand review mode for transactions that neither bank labeled as a
    /// transfer. Nothing here is automatically reconciled.
    func plaidPotentialTransferReviews() -> [PlaidTransferReviewLeg] {
        var ids = Set(expenses.compactMap { $0.plaidMetadata?.transactionId })
        for transfer in cashTransfers where transfer.note.hasPrefix("[PLAID_SINGLE:") {
            if let end = transfer.note.firstIndex(of: "]") {
                let start = transfer.note.index(transfer.note.startIndex, offsetBy: "[PLAID_SINGLE:".count)
                ids.insert(String(transfer.note[start..<end]))
            }
        }
        let outflows = ids.compactMap { plaidTransferReviewLeg(sourceId: $0) }
            .filter { $0.signedAmount > 0 }
            .filter { leg in
                // Suppress obvious purchases, cash withdrawals, and person-to-
                // person payments from the suggestions; they remain expenses.
                !["atm", "cash withdrawal", "payroll", "paycheck", "zelle",
                  "venmo", "cash app", "merchant", "purchase", "refund"].contains {
                    leg.title.localizedCaseInsensitiveContains($0)
                }
            }
            .sorted { $0.date > $1.date }
        return Array(outflows.prefix(100).filter {
            !plaidTransferReviewCandidates(sourceId: $0.id).isEmpty
        }.prefix(25))
    }

    /// Explicit review choices survive repeated Plaid sync through the
    /// PLAID_PAIR marker plus USER_CONFIRMED tag.
    @discardableResult
    func confirmPlaidTransferReview(sourceId: String, counterpartId: String) -> Bool {
        guard let source = plaidTransferReviewLeg(sourceId: sourceId),
              let candidate = plaidTransferReviewCandidates(sourceId: sourceId)
                  .first(where: { $0.id == counterpartId }) else { return false }

        let outflow = source.signedAmount > 0 ? source : candidate
        let inflow = source.signedAmount < 0 ? source : candidate
        let ids = [outflow.id, inflow.id].sorted()
        let marker = "[PLAID_PAIR:\(ids.joined(separator: "|"))]"

        // Replaying an accepted decision should never create another pair.
        guard !cashTransfers.contains(where: { $0.note.contains(marker) }) else { return false }
        let sourceIds = Set(ids)
        cashTransfers.removeAll { transfer in
            sourceIds.contains { transfer.note.hasPrefix("[PLAID_SINGLE:\($0)]") }
        }
        expenses.removeAll { sourceIds.contains($0.plaidMetadata?.transactionId ?? "") }
        incomes.removeAll { sourceIds.contains($0.plaidMetadata?.transactionId ?? "") }
        cashTransfers.append(
            CashTransfer(
                name: "Reviewed bank transfer",
                amount: abs(outflow.signedAmount),
                date: max(outflow.date, inflow.date),
                fromAccountName: outflow.accountName,
                toAccountName: inflow.accountName,
                fromAccountId: outflow.accountId,
                toAccountId: inflow.accountId,
                note: "\(marker) [USER_CONFIRMED] Linked after manual review"
            )
        )
        plaidReviewItems.removeAll { sourceIds.contains($0.sourceId) }
        saveNow()
        return true
    }

    /// A bank withdrawal should remain an expense even if Plaid labels it as
    /// TRANSFER_OUT or the description contains "transfer".
    @discardableResult
    func keepPlaidWithdrawalAsExpense(sourceId: String) -> Bool {
        guard let source = plaidTransferReviewLeg(sourceId: sourceId),
              source.signedAmount > 0 else { return false }

        if let index = expenses.firstIndex(where: { $0.plaidMetadata?.transactionId == sourceId }) {
            expenses[index].plaidMetadata?.userConfirmedNotTransfer = true
        } else {
            guard let account = financialAccounts.first(where: { $0.id == source.accountId }),
                  let externalAccountId = account.externalAccountId,
                  let itemId = account.externalItemId else { return false }
            let categoryId: UUID
            if let existing = needsCategories.first {
                categoryId = existing.id
            } else {
                let category = Category(name: "Plaid Needs", allocatedAmount: 0)
                needsCategories.append(category)
                categoryId = category.id
            }
            var metadata = PlaidSourceMetadata(
                itemId: itemId,
                accountId: externalAccountId,
                transactionId: sourceId,
                status: .reconciled
            )
            metadata.userConfirmedNotTransfer = true
            expenses.append(
                Expense(
                    name: source.title,
                    amount: source.signedAmount,
                    date: source.date,
                    section: .needs,
                    categoryId: categoryId,
                    paymentAccount: source.accountName,
                    paymentAccountId: source.accountId,
                    plaidMetadata: metadata
                )
            )
            cashTransfers.removeAll { $0.note.hasPrefix("[PLAID_SINGLE:\(sourceId)]") }
        }
        plaidReviewItems.removeAll { $0.sourceId == sourceId }
        saveNow()
        return true
    }
}
