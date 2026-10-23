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
           expense.reviewCorrection == nil,
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
           income.reviewCorrection == nil,
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

    /// The current Plaid payload does not expose a last-four identifier in
    /// FinancialAccount. Do not allow a manual confirmation when multiple
    /// accounts would display as the exact same account to the user.
    func plaidAccountLabelIsAmbiguous(_ accountID: UUID) -> Bool {
        guard let account = financialAccounts.first(where: { $0.id == accountID }) else {
            return true
        }
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let institution = (account.institutionName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return financialAccounts.filter {
            $0.isActive && $0.kind == account.kind &&
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(name) == .orderedSame &&
            ($0.institutionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(institution) == .orderedSame
        }.count > 1
    }

    func canClearlyIdentifyPlaidMatch(sourceID: String, counterpartID: String) -> Bool {
        guard let source = plaidTransferReviewLeg(sourceId: sourceID),
              let candidate = plaidTransferReviewLeg(sourceId: counterpartID),
              source.accountId != candidate.accountId else { return false }
        return !plaidAccountLabelIsAmbiguous(source.accountId) &&
            !plaidAccountLabelIsAmbiguous(candidate.accountId)
    }

    private func isConfirmedNonTransfer(sourceId: String) -> Bool {
        expenses.contains {
            $0.plaidMetadata?.transactionId == sourceId &&
            $0.plaidMetadata?.userConfirmedNotTransfer == true
        } || incomes.contains {
            $0.plaidMetadata?.transactionId == sourceId &&
            $0.plaidMetadata?.userConfirmedNotTransfer == true
        }
    }

    /// Suggest only observed transactions from another connected depository
    /// account. Never offer an arbitrary destination bank without a Plaid row.
    func plaidTransferReviewCandidates(sourceId: String) -> [PlaidTransferReviewLeg] {
        guard !isConfirmedNonTransfer(sourceId: sourceId),
              let source = plaidTransferReviewLeg(sourceId: sourceId),
              financialAccounts.contains(where: {
                  $0.id == source.accountId && ($0.kind == .depository || $0.kind == .credit)
              })
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
                  !isConfirmedNonTransfer(sourceId: candidateId),
                  let candidate = plaidTransferReviewLeg(sourceId: candidateId),
                  candidate.accountId != source.accountId,
                  source.signedAmount * candidate.signedAmount < 0,
                  abs(abs(source.signedAmount) - abs(candidate.signedAmount)) < 0.01,
                  abs(Calendar.current.dateComponents([.day],
                      from: Calendar.current.startOfDay(for: source.date),
                      to: Calendar.current.startOfDay(for: candidate.date)).day ?? Int.max) <= 3,
                  financialAccounts.contains(where: {
                      $0.id == candidate.accountId && ($0.kind == .depository || $0.kind == .credit)
                  }),
                  !plaidPairWasRejected(sourceId: sourceId, counterpartId: candidateId),
                  plaidCanReviewPair(source, candidate),
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
        // Card-side payments are credits; offer them for manual matching even
        // when the bank's debit arrives in a different Plaid sync delivery.
        for income in incomes {
            guard let accountId = income.plaidMetadata?.accountId,
                  financialAccounts.contains(where: {
                      $0.externalAccountId == accountId && $0.kind == .credit
                  }),
                  !isLikelyCardRefundTitle(income.name),
                  let id = income.plaidMetadata?.transactionId else { continue }
            ids.insert(id)
        }
        for transfer in cashTransfers where transfer.note.hasPrefix("[PLAID_SINGLE:") {
            if let end = transfer.note.firstIndex(of: "]") {
                let start = transfer.note.index(transfer.note.startIndex, offsetBy: "[PLAID_SINGLE:".count)
                ids.insert(String(transfer.note[start..<end]))
            }
        }
        let outflows = ids.compactMap { plaidTransferReviewLeg(sourceId: $0) }
            .filter { leg in
                if isConfirmedNonTransfer(sourceId: leg.id) { return false }
                if leg.signedAmount > 0 { return true }
                return financialAccounts.contains(where: {
                    $0.id == leg.accountId && $0.kind == .credit
                }) && !isLikelyCardRefundTitle(leg.title)
            }
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
        guard canClearlyIdentifyPlaidMatch(sourceID: sourceId, counterpartID: counterpartId),
              let source = plaidTransferReviewLeg(sourceId: sourceId),
              let candidate = plaidTransferReviewCandidates(sourceId: sourceId)
                  .first(where: { $0.id == counterpartId }) else { return false }

        let outflow = source.signedAmount > 0 ? source : candidate
        let inflow = source.signedAmount < 0 ? source : candidate
        let ids = [outflow.id, inflow.id].sorted()
        let marker = "[PLAID_PAIR:\(ids.joined(separator: "|"))]"

        // Replaying an accepted decision should never create another pair.
        guard !cashTransfers.contains(where: { $0.note.contains(marker) }) else { return false }
        let originals = ids.compactMap { plaidObservedTransaction(sourceId: $0) }
        guard originals.count == 2 else { return false }
        let sourceIds = Set(ids)
        let annotatedExpense = expenses.first(where: {
            sourceIds.contains($0.plaidMetadata?.transactionId ?? "") &&
                (isUserClassifiedTransfer($0) || isCreditCardPayment($0))
        })
        let annotatedName = annotatedExpense?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let annotatedNote = annotatedExpense?.note.trimmingCharacters(in: .whitespacesAndNewlines)
        cashTransfers.removeAll { transfer in
            sourceIds.contains { transfer.note.hasPrefix("[PLAID_SINGLE:\($0)]") }
        }
        expenses.removeAll { sourceIds.contains($0.plaidMetadata?.transactionId ?? "") }
        incomes.removeAll { sourceIds.contains($0.plaidMetadata?.transactionId ?? "") }
        cashTransfers.append(
            CashTransfer(
                name: (annotatedName?.isEmpty == false) ?
                    (annotatedName ?? "Reviewed transfer") :
                    (financialAccounts.contains(where: { $0.id == inflow.accountId && $0.kind == .credit })
                        ? "Reviewed credit card payment" : "Reviewed bank transfer"),
                amount: abs(outflow.signedAmount),
                date: max(outflow.date, inflow.date),
                fromAccountName: outflow.accountName,
                toAccountName: inflow.accountName,
                fromAccountId: outflow.accountId,
                toAccountId: inflow.accountId,
                note: "\(marker) [USER_CONFIRMED] Linked after manual review" +
                    ((annotatedNote?.isEmpty == false) ? " · \(annotatedNote ?? "")" : ""),
                plaidSourceTransactions: originals.count == 2 ? originals : nil
            )
        )
        plaidReviewItems.removeAll { sourceIds.contains($0.sourceId) }
        saveNow()
        return true
    }

    private func isLikelyCardRefundTitle(_ title: String) -> Bool {
        let value = title.lowercased()
        return ["refund", "return", "reversal", "cashback", "cash back",
                "statement credit", "reward credit", "adjustment credit"].contains {
            value.contains($0)
        }
    }

    private func plaidCanReviewPair(_ lhs: PlaidTransferReviewLeg, _ rhs: PlaidTransferReviewLeg) -> Bool {
        guard let lhsAccount = financialAccounts.first(where: { $0.id == lhs.accountId }),
              let rhsAccount = financialAccounts.first(where: { $0.id == rhs.accountId })
        else { return false }
        if lhsAccount.kind == .depository && rhsAccount.kind == .depository {
            return true
        }
        let bank = lhsAccount.kind == .depository ? lhs : rhs
        let credit = lhsAccount.kind == .credit ? lhs : rhs
        return bank.accountId != credit.accountId &&
            financialAccounts.contains(where: { $0.id == bank.accountId && $0.kind == .depository }) &&
            financialAccounts.contains(where: { $0.id == credit.accountId && $0.kind == .credit }) &&
            bank.signedAmount > 0 && credit.signedAmount < 0 &&
            !isLikelyCardRefundTitle(credit.title)
    }

    private func plaidPairWasRejected(sourceId: String, counterpartId: String) -> Bool {
        func rejected(_ source: String, _ other: String) -> Bool {
            let single = cashTransfers.first(where: {
                $0.note.hasPrefix("[PLAID_SINGLE:\(source)]")
            })?.plaidRejectedCounterpartIds ?? []
            let expense = expenses.first(where: { $0.plaidMetadata?.transactionId == source })?
                .plaidMetadata?.rejectedCounterpartIds ?? []
            let income = incomes.first(where: { $0.plaidMetadata?.transactionId == source })?
                .plaidMetadata?.rejectedCounterpartIds ?? []
            return single.contains(other) || expense.contains(other) || income.contains(other)
        }
        return rejected(sourceId, counterpartId) || rejected(counterpartId, sourceId)
    }

    private func plaidObservedTransaction(sourceId: String) -> PlaidSyncedTransaction? {
        if let single = cashTransfers.first(where: {
            $0.note.hasPrefix("[PLAID_SINGLE:\(sourceId)]")
        }), let original = single.plaidSourceTransactions?.first(where: {
            $0.id == sourceId
        }) {
            return original
        }
        if let expense = expenses.first(where: { $0.plaidMetadata?.transactionId == sourceId }),
           let meta = expense.plaidMetadata, let accountId = meta.accountId {
            return PlaidSyncedTransaction(
                id: sourceId, accountId: accountId, itemId: meta.itemId,
                name: expense.name, merchantName: nil, amount: abs(expense.amount),
                date: expense.date, pending: meta.isPending ?? false,
                category: meta.originalCategory, removed: false
            )
        }
        if let income = incomes.first(where: { $0.plaidMetadata?.transactionId == sourceId }),
           let meta = income.plaidMetadata, let accountId = meta.accountId {
            return PlaidSyncedTransaction(
                id: sourceId, accountId: accountId, itemId: meta.itemId,
                name: income.name, merchantName: nil, amount: -abs(income.amount),
                date: income.date, pending: meta.isPending ?? false,
                category: meta.originalCategory, removed: false
            )
        }
        return nil
    }

    /// Undo an incorrect automatically or manually linked pair without
    /// deleting either original financial movement. Never guess missing legs.
    @discardableResult
    func undoPlaidTransferMatch(transferId: UUID) -> Bool {
        guard let index = cashTransfers.firstIndex(where: { $0.id == transferId }),
              let ids = plaidPairIdsForReview(cashTransfers[index].note),
              let originals = cashTransfers[index].plaidSourceTransactions,
              originals.count == 2,
              Set(originals.map(\.id)) == Set(ids),
              originals[0].accountId != originals[1].accountId,
              originals[0].amount * originals[1].amount < 0,
              abs(abs(originals[0].amount) - abs(originals[1].amount)) < 0.01
        else { return false }
        let accounts = originals.compactMap { txn in
            financialAccounts.first(where: { $0.externalAccountId == txn.accountId })
        }
        guard accounts.count == 2,
              !originals.contains(where: { txn in
                  expenses.contains(where: { $0.plaidMetadata?.transactionId == txn.id }) ||
                  incomes.contains(where: { $0.plaidMetadata?.transactionId == txn.id })
              }) else { return false }

        cashTransfers.remove(at: index)
        for txn in originals {
            guard let account = accounts.first(where: { $0.externalAccountId == txn.accountId }),
                  let rejectedId = originals.first(where: { $0.id != txn.id })?.id
            else { continue }
            let outflow = txn.amount > 0
            cashTransfers.append(CashTransfer(
                name: txn.merchantName ?? txn.name,
                amount: abs(txn.amount),
                date: txn.date,
                fromAccountName: outflow ? account.name : "External account",
                toAccountName: outflow ? "External account" : account.name,
                fromAccountId: outflow ? account.id : nil,
                toAccountId: outflow ? nil : account.id,
                note: "[PLAID_SINGLE:\(txn.id)] Needs review after undoing incorrect match",
                plaidSourceTransactions: [txn],
                plaidRejectedCounterpartIds: [rejectedId]
            ))
            if !plaidReviewItems.contains(where: { $0.sourceId == txn.id }) {
                plaidReviewItems.append(PlaidReviewItem(
                    title: txn.merchantName ?? txn.name,
                    detail: "The previous bank/card match was undone. Select a different observed counterpart or keep this as a separate transaction.",
                    amount: txn.amount, date: txn.date, sourceId: txn.id
                ))
            }
        }
        saveNow()
        return true
    }

    private func plaidPairIdsForReview(_ note: String) -> [String]? {
        guard note.hasPrefix("[PLAID_PAIR:"),
              let closing = note.firstIndex(of: "]") else { return nil }
        let start = note.index(note.startIndex, offsetBy: "[PLAID_PAIR:".count)
        let ids = note[start..<closing].split(separator: "|").map(String.init)
        return ids.count == 2 ? ids : nil
    }

    func canUndoPlaidTransferMatch(transferId: UUID) -> Bool {
        guard let transfer = cashTransfers.first(where: { $0.id == transferId }),
              let ids = plaidPairIdsForReview(transfer.note),
              let originals = transfer.plaidSourceTransactions else { return false }
        return originals.count == 2 && Set(ids) == Set(originals.map(\.id))
    }

    /// A bank withdrawal should remain an expense even if Plaid labels it as
    /// TRANSFER_OUT or the description contains "transfer".
    @discardableResult
    func keepPlaidWithdrawalAsExpense(sourceId: String) -> Bool {
        guard let source = plaidTransferReviewLeg(sourceId: sourceId),
              source.signedAmount > 0,
              financialAccounts.contains(where: { $0.id == source.accountId && $0.kind == .depository })
        else { return false }

        if let index = expenses.firstIndex(where: { $0.plaidMetadata?.transactionId == sourceId }) {
            expenses[index].plaidMetadata?.userConfirmedNotTransfer = true
        } else {
            guard let account = financialAccounts.first(where: { $0.id == source.accountId }),
                  let externalAccountId = account.externalAccountId,
                  let itemId = account.externalItemId else { return false }
            let isCashWithdrawal = ["atm", "cash withdrawal", "cash wdl", "cash wd"].contains {
                source.title.localizedCaseInsensitiveContains($0)
            }
            let categoryName = isCashWithdrawal ? "Cash Withdrawals" : "Plaid Needs"
            let categoryId: UUID
            if let existing = needsCategories.first(where: { $0.name == categoryName }) {
                categoryId = existing.id
            } else {
                let category = Category(name: categoryName, allocatedAmount: 0)
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
            metadata.originalCategory = plaidObservedTransaction(sourceId: sourceId)?.category
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
