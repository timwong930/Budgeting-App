import Foundation

private enum PlaidReconciledImportResult {
    case imported
    case reconciled
    case needsReview
}

private struct PlaidManualMatch {
    let index: Int
    let confidence: Double
    let ambiguous: Bool
}

private struct PlaidTransferReconciliationResult {
    var handledTransactionIds: Set<String> = []
    var reconciledTransactions = 0
    var reviewItemsAdded = 0
}

extension BudgetModel {
    /// Applies the non-transaction portions of the existing Plaid sync, then reconciles
    /// transaction deltas with account-aware, idempotent rules.
    @discardableResult
    func applyPlaidSyncReconciled(_ payload: PlaidSyncPayload) -> PlaidSyncResult {
        var nonTransactionPayload = payload
        nonTransactionPayload.transactions = []
        var result = applyPlaidSync(nonTransactionPayload)

        let syncedAt = Date()
        var accountNamesById: [String: String] = [:]
        var accountTypesById: [String: PlaidAccountType] = [:]
        // A connection can omit unchanged accounts from an incremental update.
        for account in financialAccounts {
            guard let id = account.externalAccountId else { continue }
            accountNamesById[id] = account.name
            switch account.kind {
            case .depository: accountTypesById[id] = .depository
            case .credit: accountTypesById[id] = .credit
            default: break
            }
        }
        for account in payload.accounts {
            accountNamesById[account.id] = account.name
            accountTypesById[account.id] = account.type
        }

        let activeTransactions = payload.transactions.filter { !$0.removed }
        let removedSourceIds = Set(payload.transactions.filter { $0.removed }.map(\.id))
        let transferResult = reconcilePlaidTransfers(
            activeTransactions,
            accountNamesById: accountNamesById,
            accountTypesById: accountTypesById,
            removedSourceIds: removedSourceIds
        )
        result.reconciledTransactions += transferResult.reconciledTransactions
        result.reviewItems += transferResult.reviewItemsAdded

        for transaction in activeTransactions where !transferResult.handledTransactionIds.contains(transaction.id) {
            // A previously auto-created single transfer may now be correctly
            // recognized as an ordinary withdrawal, expense, or deposit.
            _ = removePlaidSingleTransfers(sourceIds: [transaction.id])
            let importResult = reconcilePlaidTransaction(
                transaction,
                accountName: accountNamesById[transaction.accountId] ?? "",
                syncedAt: syncedAt
            )
            switch importResult {
            case .imported:
                result.importedTransactions += 1
            case .reconciled:
                result.reconciledTransactions += 1
            case .needsReview:
                result.reviewItems += 1
            }
        }

        // Process removals after additions/modifications so a posted transaction can
        // replace a pending row before Plaid removes the old pending transaction ID.
        for transaction in payload.transactions where transaction.removed {
            result.removedTransactions += removeReconciledPlaidTransaction(id: transaction.id)
            // Plaid removals must also remove linked, auto-generated pairs.
            _ = removePlaidPairedTransfers(sourceIds: [transaction.id])
        }

        synchronizeLegacyMarginStateFromLedger()
        return result
    }
}

private extension BudgetModel {
    // MARK: - Transfer and card-payment classification

    func reconcilePlaidTransfers(
        _ transactions: [PlaidSyncedTransaction],
        accountNamesById: [String: String],
        accountTypesById: [String: PlaidAccountType],
        removedSourceIds: Set<String>
    ) -> PlaidTransferReconciliationResult {
        var result = PlaidTransferReconciliationResult()
        var confirmedPairMarkers: Set<String> = []
        let activeById = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        // Plaid sends deltas, not complete history. Revisit unmatched observed
        // legs from earlier deliveries when searching for this batch's partner.
        let candidates = transactions + storedPlaidTransferCandidates(
            excluding: Set(transactions.map(\.id)).union(removedSourceIds)
        )

        // Plaid sync is incremental: a previously verified pair may have only
        // one side in this delivery. Do not create an additional unpaired
        // transfer while its partner is absent. Defer changes to that pair
        // until both sides arrive, or until Plaid explicitly removes a side.
        // A removal is authoritative and must not be held by this safeguard.
        for transfer in cashTransfers {
            guard !transfer.note.contains("[USER_CONFIRMED]"),
                  let ids = plaidPairTransactionIds(from: transfer.note),
                  ids.filter({ activeById[$0] != nil }).count == 1,
                  !ids.contains(where: { removedSourceIds.contains($0) }) else {
                continue
            }
            result.handledTransactionIds.formUnion(ids)
        }

        // Preserve user-approved matches through later syncs. If both sides
        // change into incompatible transactions, re-evaluate them normally.
        for transfer in cashTransfers where transfer.note.contains("[USER_CONFIRMED]") {
            guard let ids = plaidPairTransactionIds(from: transfer.note),
                  !ids.contains(where: { removedSourceIds.contains($0) }) else { continue }
            let present = ids.compactMap { activeById[$0] }
            let stillValid = present.count < 2 || (
                present[0].accountId != present[1].accountId &&
                present[0].amount * present[1].amount < 0 &&
                abs(abs(present[0].amount) - abs(present[1].amount)) < 0.01 &&
                dayDistance(present[0].date, present[1].date) <= 3
            )
            guard stillValid else { continue }
            confirmedPairMarkers.insert(plaidTransferSourceMarker(outflowId: ids[0], inflowId: ids[1]))
            result.handledTransactionIds.formUnion(ids)
        }

        for (index, transaction) in transactions.enumerated() {
            guard !result.handledTransactionIds.contains(transaction.id) else { continue }
            let type = accountTypesById[transaction.accountId] ?? .other
            let keptAsTransaction = expenses.contains {
                $0.plaidMetadata?.transactionId == transaction.id &&
                ($0.plaidMetadata?.userConfirmedNotTransfer == true ||
                 $0.userClassifiedTransfer == true ||
                 $0.transferDestinationAccountId != nil ||
                 $0.creditCardPaymentTargetId != nil ||
                 $0.creditCardPaymentTarget != nil)
            } || incomes.contains {
                $0.plaidMetadata?.transactionId == transaction.id &&
                $0.plaidMetadata?.userConfirmedNotTransfer == true
            }
            guard !keptAsTransaction else { continue }

            // A generic ACH credit may be the *new* side of an explicitly
            // named transfer already stored from a prior sync. It must be
            // eligible to trigger matching, even without transfer wording.
            let candidateIndices = eligibleTransferCounterpartIndices(
                for: transaction,
                at: index,
                in: candidates,
                accountTypesById: accountTypesById
            ).filter { !isRejectedPlaidPair(transaction.id, candidates[$0].id) }
            // Unidentified credits on a credit account are not wages or
            // deposits. Hold them for review rather than inflate income.
            let ambiguousCardCredit = type == .credit && transaction.amount < 0 &&
                !isRecognizableCardRefund(transaction)
            guard isStrongTransferOrPayment(transaction, accountType: type) ||
                    !candidateIndices.isEmpty || ambiguousCardCredit else { continue }

            // Amount + date alone never creates a verified pair; candidate
            // eligibility and unique reverse matching are still required.
            var confirmedCandidate: PlaidSyncedTransaction?
            if candidateIndices.count == 1 {
                let candidateIndex = candidateIndices[0]
                let reverseCandidates = eligibleTransferCounterpartIndices(
                    for: candidates[candidateIndex],
                    at: candidateIndex,
                    in: candidates,
                    accountTypesById: accountTypesById
                ).filter { !isRejectedPlaidPair(candidates[candidateIndex].id, candidates[$0].id) }
                if reverseCandidates == [index] &&
                    !result.handledTransactionIds.contains(candidates[candidateIndex].id) {
                    confirmedCandidate = candidates[candidateIndex]
                }
            }

            if let confirmedCandidate {
                let outflow = transaction.amount > 0 ? transaction : confirmedCandidate
                let inflow = transaction.amount < 0 ? transaction : confirmedCandidate

                // Preserve the user's chosen label/note before replacing the
                // single-side expense with a verified, two-sided Plaid pair.
                let sourceIds = Set([outflow.id, inflow.id])
                let userAnnotatedMovement = expenses.first(where: {
                    sourceIds.contains($0.plaidMetadata?.transactionId ?? "") &&
                    (isUserClassifiedTransfer($0) || isCreditCardPayment($0))
                })
                _ = removeReconciledPlaidTransaction(id: transaction.id)
                _ = removeReconciledPlaidTransaction(id: confirmedCandidate.id)

                upsertPlaidTransfer(
                    outflow: outflow,
                    inflow: inflow,
                    accountNamesById: accountNamesById,
                    accountTypesById: accountTypesById,
                    userTitle: userAnnotatedMovement?.name,
                    userNote: userAnnotatedMovement?.note
                )
                confirmedPairMarkers.insert(
                    plaidTransferSourceMarker(outflowId: outflow.id, inflowId: inflow.id)
                )
                result.handledTransactionIds.insert(transaction.id)
                result.handledTransactionIds.insert(confirmedCandidate.id)
                result.reconciledTransactions += 2
            } else {
                // Keep a user's rejected-counterpart decision even when the
                // new bank sync updates the same source ID.
                let rejectedIds = cashTransfers.first(where: {
                    $0.note.hasPrefix("[PLAID_SINGLE:\(transaction.id)]")
                })?.plaidRejectedCounterpartIds ??
                    expenses.first(where: { $0.plaidMetadata?.transactionId == transaction.id })?
                        .plaidMetadata?.rejectedCounterpartIds ??
                    incomes.first(where: { $0.plaidMetadata?.transactionId == transaction.id })?
                        .plaidMetadata?.rejectedCounterpartIds
                _ = removeReconciledPlaidTransaction(id: transaction.id)
                upsertUnpairedPlaidTransfer(
                    transaction,
                    accountName: accountNamesById[transaction.accountId] ?? "Plaid account",
                    accountType: type,
                    rejectedCounterpartIds: rejectedIds
                )
                let added = upsertPlaidReviewItem(
                    sourceId: transaction.id,
                    title: transactionDisplayName(transaction),
                    detail: "Transfer/payment is unpaired or has multiple possible matches. Verify the destination before classifying it as a bank transfer.",
                    amount: transaction.amount,
                    date: transaction.date
                )
                result.handledTransactionIds.insert(transaction.id)
                if added { result.reviewItemsAdded += 1 }
            }
        }

        // When both transaction sides are in this delivery, discard older Plaid
        // pairs that fail the new matching rules. Do not touch manual transfers
        // or pairs whose other side was omitted by a partial delivery.
        _ = removeStalePlaidTransferPairs(
            presentTransactionIds: Set(transactions.map(\.id)),
            confirmedPairMarkers: confirmedPairMarkers
        )
        return result
    }


    /// Durable matching pool: Plaid sync calls often contain only one Item's
    /// changes. Persisted unmatched legs are genuine bank observations; we
    /// never invent an opposite transaction from an account balance.
    func storedPlaidTransferCandidates(excluding excludedIds: Set<String>) -> [PlaidSyncedTransaction] {
        let pairedIds = Set(cashTransfers.compactMap { transfer -> [String]? in
            guard transfer.note.hasPrefix("[PLAID_PAIR:") else { return nil }
            return plaidPairTransactionIds(from: transfer.note)
        }.flatMap { $0 })
        var unique: [String: PlaidSyncedTransaction] = [:]

        func add(_ transaction: PlaidSyncedTransaction) {
            guard !excludedIds.contains(transaction.id), !pairedIds.contains(transaction.id),
                  unique[transaction.id] == nil,
                  financialAccounts.contains(where: {
                      $0.externalAccountId == transaction.accountId &&
                      ($0.kind == .depository || $0.kind == .credit)
                  }) else { return }
            unique[transaction.id] = transaction
        }

        for transfer in cashTransfers where transfer.note.hasPrefix("[PLAID_SINGLE:") {
            if let originals = transfer.plaidSourceTransactions {
                originals.forEach(add)
            } else if let closing = transfer.note.firstIndex(of: "]"),
                      let accountId = transfer.fromAccountId ?? transfer.toAccountId,
                      let account = financialAccounts.first(where: {
                          $0.id == accountId && $0.externalAccountId != nil
                      }), let externalId = account.externalAccountId {
                let start = transfer.note.index(transfer.note.startIndex, offsetBy: "[PLAID_SINGLE:".count)
                add(PlaidSyncedTransaction(
                    id: String(transfer.note[start..<closing]), accountId: externalId,
                    itemId: account.externalItemId ?? "", name: transfer.name,
                    merchantName: nil,
                    amount: transfer.fromAccountId != nil ? transfer.amount : -transfer.amount,
                    date: transfer.date, pending: transfer.note.contains("[PENDING]"),
                    category: nil, removed: false
                ))
            }
        }
        for expense in expenses {
            guard let metadata = expense.plaidMetadata,
                  let id = metadata.transactionId,
                  let accountId = metadata.accountId,
                  metadata.userConfirmedNotTransfer != true else { continue }
            add(PlaidSyncedTransaction(
                id: id, accountId: accountId, itemId: metadata.itemId,
                name: expense.name, merchantName: nil, amount: abs(expense.amount),
                date: expense.date, pending: metadata.isPending ?? false,
                category: metadata.originalCategory, removed: false
            ))
        }
        for income in incomes {
            guard let metadata = income.plaidMetadata,
                  let id = metadata.transactionId,
                  let accountId = metadata.accountId,
                  metadata.userConfirmedNotTransfer != true else { continue }
            add(PlaidSyncedTransaction(
                id: id, accountId: accountId, itemId: metadata.itemId,
                name: income.name, merchantName: nil, amount: -abs(income.amount),
                date: income.date, pending: metadata.isPending ?? false,
                category: metadata.originalCategory, removed: false
            ))
        }
        return unique.values.sorted { $0.id < $1.id }
    }

    func isRejectedPlaidPair(_ lhs: String, _ rhs: String) -> Bool {
        let lhsRejections = expenses.first(where: { $0.plaidMetadata?.transactionId == lhs })?
            .plaidMetadata?.rejectedCounterpartIds ??
            incomes.first(where: { $0.plaidMetadata?.transactionId == lhs })?
                .plaidMetadata?.rejectedCounterpartIds ?? []
        let rhsRejections = expenses.first(where: { $0.plaidMetadata?.transactionId == rhs })?
            .plaidMetadata?.rejectedCounterpartIds ??
            incomes.first(where: { $0.plaidMetadata?.transactionId == rhs })?
                .plaidMetadata?.rejectedCounterpartIds ?? []
        let lhsTransfer = cashTransfers.first(where: { $0.note.hasPrefix("[PLAID_SINGLE:\(lhs)]") })?
            .plaidRejectedCounterpartIds ?? []
        let rhsTransfer = cashTransfers.first(where: { $0.note.hasPrefix("[PLAID_SINGLE:\(rhs)]") })?
            .plaidRejectedCounterpartIds ?? []
        return lhsRejections.contains(rhs) || rhsRejections.contains(lhs) ||
            lhsTransfer.contains(rhs) || rhsTransfer.contains(lhs)
    }

    func eligibleTransferCounterpartIndices(
        for transaction: PlaidSyncedTransaction,
        at index: Int,
        in transactions: [PlaidSyncedTransaction],
        accountTypesById: [String: PlaidAccountType]
    ) -> [Int] {
        let type = accountTypesById[transaction.accountId] ?? .other
        return transactions.indices.filter { candidateIndex in
            let candidate = transactions[candidateIndex]
            guard candidateIndex != index,
                  candidate.accountId != transaction.accountId,
                  transaction.amount * candidate.amount < 0,
                  abs(abs(transaction.amount) - abs(candidate.amount)) < 0.01,
                  dayDistance(transaction.date, candidate.date) <= 3 else { return false }
            return canPairTransfer(
                transaction,
                accountType: type,
                with: candidate,
                candidateAccountType: accountTypesById[candidate.accountId] ?? .other
            )
        }
    }

    func declaredTransferDestinationAllows(sourceId: String, candidateAccountId: String) -> Bool {
        guard let expense = expenses.first(where: { $0.plaidMetadata?.transactionId == sourceId }) else {
            return true
        }
        let destinationId = expense.transferDestinationAccountId ?? expense.creditCardPaymentTargetId
        guard let destinationId else { return true }
        return financialAccounts.contains(where: {
            $0.id == destinationId && $0.externalAccountId == candidateAccountId
        })
    }

    func userSelectedAccountDestination(sourceId: String, targetExternalAccountId: String, kind: FinancialAccountKind) -> Bool {
        guard let expense = expenses.first(where: { $0.plaidMetadata?.transactionId == sourceId }) else { return false }
        let selectedId: UUID?
        if kind == .credit {
            selectedId = expense.creditCardPaymentTargetId
        } else {
            selectedId = expense.userClassifiedTransfer == true ? expense.transferDestinationAccountId : nil
        }
        guard let selectedId else { return false }
        return financialAccounts.contains(where: {
            $0.id == selectedId && $0.externalAccountId == targetExternalAccountId && $0.kind == kind
        })
    }

    func canPairTransfer(
        _ lhs: PlaidSyncedTransaction,
        accountType lhsType: PlaidAccountType,
        with rhs: PlaidSyncedTransaction,
        candidateAccountType rhsType: PlaidAccountType
    ) -> Bool {
        // A manual destination is a user decision, not just a hint. Never
        // silently pair that debit with a different observed account.
        guard declaredTransferDestinationAllows(sourceId: lhs.id, candidateAccountId: rhs.accountId),
              declaredTransferDestinationAllows(sourceId: rhs.id, candidateAccountId: lhs.accountId)
        else { return false }
        let bothDepository = lhsType == .depository && rhsType == .depository
        if bothDepository {
            // One side may read "TRANSFER TO SAVINGS" and the other "ACH CREDIT".
            // Plaid's transfer category corroborates the latter but cannot
            // independently turn an ordinary withdrawal into a transfer.
            guard !isObviousNonTransfer(lhs), !isObviousNonTransfer(rhs) else { return false }
            let left = isLikelyBankTransfer(lhs)
            let right = isLikelyBankTransfer(rhs)
            let explicitlySelected =
                (userSelectedAccountDestination(sourceId: lhs.id, targetExternalAccountId: rhs.accountId, kind: .depository) &&
                 isTransferCategory(rhs)) ||
                (userSelectedAccountDestination(sourceId: rhs.id, targetExternalAccountId: lhs.accountId, kind: .depository) &&
                 isTransferCategory(lhs))
            return explicitlySelected ||
                (left && right) ||
                (left && isTransferCategory(rhs)) ||
                (right && isTransferCategory(lhs))
        }

        let depositoryAndCredit =
            (lhsType == .depository && rhsType == .credit) ||
            (lhsType == .credit && rhsType == .depository)
        if depositoryAndCredit {
            let credit = lhsType == .credit ? lhs : rhs
            let bank = lhsType == .depository ? lhs : rhs
            // Card payments leave checking and enter credit accounts.
            // Similar-sized purchases or refunds are not card payments.
            guard credit.amount < 0, bank.amount > 0,
                  !isRecognizableCardRefund(credit) else { return false }
            let bankDescription = transactionDescriptionText(bank)
            // Loan payments, ordinary bill payments and merchant autopay can
            // coincide with a card credit by amount/date. A card transaction
            // alone does NOT verify that the bank debit paid this card.
            let explicitCardMemo = [
                "credit card", "card payment", "cardmember", "epay", "pymt"
            ].contains { bankDescription.contains($0) }
            let knownIssuer = financialAccounts.first(where: {
                $0.externalAccountId == credit.accountId
            })?.institutionName?.lowercased() ?? ""
            let mentionsIssuer = knownIssuer.count >= 5 &&
                !["bank", "credit union", "unknown", "financial institution"].contains(knownIssuer) &&
                bankDescription.contains(knownIssuer) &&
                (bankDescription.contains("payment") || bankDescription.contains("autopay"))
            let selectedCard = userSelectedAccountDestination(
                sourceId: bank.id, targetExternalAccountId: credit.accountId, kind: .credit
            )
            return (selectedCard &&
                (isTransferCategory(credit) || isLikelyCreditCardPaymentForReconciliation(credit))) ||
                (isLikelyCreditCardPaymentForReconciliation(credit) &&
                 (explicitCardMemo || mentionsIssuer))
        }
        return false
    }

    func isStrongTransferOrPayment(_ transaction: PlaidSyncedTransaction, accountType: PlaidAccountType) -> Bool {
        // Positive credit-account amounts are purchases, not payments. Generic
        // words such as "autopay" must never hide card spending on their own.
        if accountType == .credit {
            return transaction.amount < 0 && !isRecognizableCardRefund(transaction) &&
                isLikelyCreditCardPaymentForReconciliation(transaction)
        }
        if isLikelyBankTransfer(transaction) {
            return true
        }

        // LOAN_PAYMENT also describes mortgages and other ordinary bank
        // withdrawals. Do not exclude those from spending without card evidence.
        let text = transactionSearchText(transaction)
        return text.contains("credit card payment") ||
            text.contains("card payment") ||
            text.contains("payment thank you") ||
            text.contains("epay") ||
            text.contains("pymt")
    }

    func isTransferCategory(_ transaction: PlaidSyncedTransaction) -> Bool {
        (transaction.category ?? "").lowercased().contains("transfer")
    }

    func isObviousNonTransfer(_ transaction: PlaidSyncedTransaction) -> Bool {
        let name = transactionDescriptionText(transaction)
        let exclusions = ["atm", "cash withdrawal", "cash wdl", "cash wd", "payroll", "paycheck", "salary",
                          "zelle", "venmo", "cash app", "merchant", "purchase",
                          "refund", "bill pay"]
        return exclusions.contains { name.contains($0) }
    }

    func isLikelyBankTransfer(_ transaction: PlaidSyncedTransaction) -> Bool {
        // Plaid's broad TRANSFER category, ACH debit/credit, and Zelle do NOT
        // prove a movement between the user's own linked bank accounts.
        // Require an explicit transfer word in the bank's description.
        let description = transactionDescriptionText(transaction)
        return description.range(
            of: #"\b(transfer|xfer|xfr|tfr|trf|trsf|trnsfr)\b"#,
            options: .regularExpression
        ) != nil
    }

    func transactionDescriptionText(_ transaction: PlaidSyncedTransaction) -> String {
        "\(transaction.name) \(transaction.merchantName ?? "")".lowercased()
    }

    func isRecognizableCardRefund(_ transaction: PlaidSyncedTransaction) -> Bool {
        let description = transactionDescriptionText(transaction)
        return ["refund", "return", "reversal", "cashback", "cash back",
                "statement credit", "reward credit", "adjustment credit"].contains {
            description.contains($0)
        }
    }

    func isLikelyCreditCardPaymentForReconciliation(_ transaction: PlaidSyncedTransaction) -> Bool {
        let category = (transaction.category ?? "").lowercased()
        let text = transactionSearchText(transaction)
        return category.contains("loan_payment") ||
            category.contains("loan payment") ||
            text.contains("credit card payment") ||
            text.contains("card payment") ||
            text.contains("payment thank you") ||
            text.contains("payment received") ||
            text.contains("online payment") ||
            text.contains("automatic payment") ||
            text.contains("epay") ||
            text.contains("pymt") ||
            text.contains("autopay")
    }

    func upsertPlaidTransfer(
        outflow: PlaidSyncedTransaction,
        inflow: PlaidSyncedTransaction,
        accountNamesById: [String: String],
        accountTypesById: [String: PlaidAccountType],
        userTitle: String? = nil,
        userNote: String? = nil
    ) {
        let fromName = accountNamesById[outflow.accountId] ??
            financialAccounts.first(where: { $0.externalAccountId == outflow.accountId })?.name ?? "Plaid account"
        let toName = accountNamesById[inflow.accountId] ??
            financialAccounts.first(where: { $0.externalAccountId == inflow.accountId })?.name ?? "Plaid account"
        let fromId = stableFinancialAccountId(forPlaidAccountId: outflow.accountId)
        let toId = stableFinancialAccountId(forPlaidAccountId: inflow.accountId)
        let amount = roundedReconciliationCurrency(abs(outflow.amount))
        let date = max(outflow.date, inflow.date)
        let isCardPayment = accountTypesById[inflow.accountId] == .credit || accountTypesById[outflow.accountId] == .credit
        let sourceMarker = plaidTransferSourceMarker(outflowId: outflow.id, inflowId: inflow.id)
        let cleanedTitle = userTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNote = userNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let transferNote = "\(sourceMarker) Synced from Plaid transaction pair" +
            ((cleanedNote?.isEmpty == false) ? " · \(cleanedNote!)" : "")
        _ = removePlaidSingleTransfers(sourceIds: [outflow.id, inflow.id])

        // Only the same Plaid source IDs may update an existing pair.
        // Matching by amount/date/accounts collapses distinct transfers.
        let existingIndex = cashTransfers.firstIndex {
            $0.note.contains(sourceMarker)
        }

        if let existingIndex {
            cashTransfers[existingIndex].amount = amount
            cashTransfers[existingIndex].date = date
            cashTransfers[existingIndex].fromAccountName = fromName
            cashTransfers[existingIndex].toAccountName = toName
            cashTransfers[existingIndex].fromAccountId = fromId
            cashTransfers[existingIndex].toAccountId = toId
            cashTransfers[existingIndex].note = transferNote
            if let cleanedTitle, !cleanedTitle.isEmpty {
                cashTransfers[existingIndex].name = cleanedTitle
            }
            cashTransfers[existingIndex].plaidSourceTransactions = [outflow, inflow]
            return
        }

        cashTransfers.append(
            CashTransfer(
                name: (cleanedTitle?.isEmpty == false) ?
                    cleanedTitle! : (isCardPayment ? "Credit card payment" : "Account transfer"),
                amount: amount,
                date: date,
                fromAccountName: fromName,
                toAccountName: toName,
                fromAccountId: fromId,
                toAccountId: toId,
                note: transferNote,
                plaidSourceTransactions: [outflow, inflow]
            )
        )
    }

    func upsertUnpairedPlaidTransfer(
        _ transaction: PlaidSyncedTransaction,
        accountName: String,
        accountType: PlaidAccountType,
        rejectedCounterpartIds: [String]? = nil
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
            cashTransfers[existingIndex].plaidSourceTransactions = [transaction]
            if let rejectedCounterpartIds {
                cashTransfers[existingIndex].plaidRejectedCounterpartIds = rejectedCounterpartIds
            }
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
                note: note,
                plaidSourceTransactions: [transaction],
                plaidRejectedCounterpartIds: rejectedCounterpartIds
            )
        )
    }

    func plaidPairTransactionIds(from note: String) -> [String]? {
        let prefix = "[PLAID_PAIR:"
        guard note.hasPrefix(prefix),
              let closingBracket = note.firstIndex(of: "]") else { return nil }
        let start = note.index(note.startIndex, offsetBy: prefix.count)
        let ids = note[start..<closingBracket].split(separator: "|").map(String.init)
        return ids.count == 2 ? ids : nil
    }

    @discardableResult
    func removeStalePlaidTransferPairs(
        presentTransactionIds: Set<String>,
        confirmedPairMarkers: Set<String>
    ) -> Int {
        let previousCount = cashTransfers.count
        cashTransfers.removeAll { transfer in
            guard let ids = plaidPairTransactionIds(from: transfer.note),
                  ids.allSatisfy({ presentTransactionIds.contains($0) }) else {
                return false
            }
            let marker = plaidTransferSourceMarker(outflowId: ids[0], inflowId: ids[1])
            return !confirmedPairMarkers.contains(marker)
        }
        return previousCount - cashTransfers.count
    }

    @discardableResult
    func removePlaidPairedTransfers(sourceIds: [String]) -> Int {
        let removedIds = Set(sourceIds)
        let previousCount = cashTransfers.count
        cashTransfers.removeAll { transfer in
            guard let ids = plaidPairTransactionIds(from: transfer.note) else { return false }
            return ids.contains(where: { removedIds.contains($0) })
        }
        return previousCount - cashTransfers.count
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

    func plaidTransferSourceMarker(outflowId: String, inflowId: String) -> String {
        let ids = [outflowId, inflowId].sorted()
        return "[PLAID_PAIR:\(ids.joined(separator: "|"))]"
    }

    // MARK: - Transaction reconciliation

    func reconcilePlaidTransaction(
        _ transaction: PlaidSyncedTransaction,
        accountName: String,
        syncedAt: Date
    ) -> PlaidReconciledImportResult {
        if let expenseIndex = expenses.firstIndex(where: { $0.plaidMetadata?.transactionId == transaction.id }) {
            if transaction.amount >= 0 {
                expenses[expenseIndex] = mergedPlaidExpense(
                    expenses[expenseIndex],
                    with: transaction,
                    accountName: accountName,
                    syncedAt: syncedAt
                )
            } else {
                let existing = expenses.remove(at: expenseIndex)
                incomes.append(incomeFromDirectionChange(existing, transaction: transaction, accountName: accountName, syncedAt: syncedAt))
            }
            clearPlaidReviewItems(sourceIds: [transaction.id])
            return .reconciled
        }

        if let incomeIndex = incomes.firstIndex(where: { $0.plaidMetadata?.transactionId == transaction.id }) {
            if transaction.amount < 0 {
                incomes[incomeIndex] = mergedPlaidIncome(
                    incomes[incomeIndex],
                    with: transaction,
                    accountName: accountName,
                    syncedAt: syncedAt
                )
            } else {
                let existing = incomes.remove(at: incomeIndex)
                expenses.append(expenseFromDirectionChange(existing, transaction: transaction, accountName: accountName, syncedAt: syncedAt))
            }
            clearPlaidReviewItems(sourceIds: [transaction.id])
            return .reconciled
        }

        if let pendingIndex = pendingExpenseReplacementIndex(for: transaction), transaction.amount >= 0 {
            let oldSourceId = expenses[pendingIndex].plaidMetadata?.transactionId
            expenses[pendingIndex] = mergedPlaidExpense(
                expenses[pendingIndex],
                with: transaction,
                accountName: accountName,
                syncedAt: syncedAt
            )
            clearPlaidReviewItems(sourceIds: [transaction.id, oldSourceId].compactMap { $0 })
            return .reconciled
        }

        if transaction.amount < 0 {
            let income = makeReconciledIncome(from: transaction, accountName: accountName, syncedAt: syncedAt)
            if let match = bestManualIncomeMatch(for: income) {
                if match.ambiguous {
                    let added = upsertPlaidReviewItem(
                        sourceId: transaction.id,
                        title: income.name,
                        detail: "Multiple manual income entries could match this Plaid transaction. Review the duplicate before merging.",
                        amount: transaction.amount,
                        date: transaction.date
                    )
                    incomes.append(income)
                    return added ? .needsReview : .imported
                }
                var existing = incomes[match.index]
                existing.plaidMetadata = reconciliationMetadata(
                    for: transaction,
                    syncedAt: syncedAt,
                    status: .reconciled,
                    matchConfidence: match.confidence
                )
                if existing.bankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing.bankName = accountName
                }
                if existing.bankAccountId == nil {
                    existing.bankAccountId = stableFinancialAccountId(forPlaidAccountId: transaction.accountId)
                }
                incomes[match.index] = existing
                clearPlaidReviewItems(sourceIds: [transaction.id])
                return .reconciled
            }
            incomes.append(income)
            clearPlaidReviewItems(sourceIds: [transaction.id])
            return .imported
        }

        let expense = makeReconciledExpense(from: transaction, accountName: accountName, syncedAt: syncedAt)
        if let match = bestManualExpenseMatch(for: expense) {
            if match.ambiguous {
                let added = upsertPlaidReviewItem(
                    sourceId: transaction.id,
                    title: expense.name,
                    detail: "Multiple manual expenses could match this Plaid transaction. Review the duplicate before merging.",
                    amount: transaction.amount,
                    date: transaction.date
                )
                expenses.append(expense)
                return added ? .needsReview : .imported
            }
            var existing = expenses[match.index]
            existing.plaidMetadata = reconciliationMetadata(
                for: transaction,
                syncedAt: syncedAt,
                status: .reconciled,
                matchConfidence: match.confidence
            )
            if existing.paymentAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.paymentAccount = accountName
            }
            if existing.paymentAccountId == nil {
                existing.paymentAccountId = stableFinancialAccountId(forPlaidAccountId: transaction.accountId)
            }
            expenses[match.index] = existing
            clearPlaidReviewItems(sourceIds: [transaction.id])
            return .reconciled
        }

        let hasManualCategory = persistentCategoryAssignment(for: transaction) != nil
        let categoryNeedsReview = transaction.category == nil && !hasManualCategory
        let ambiguousPlaidTransferCategory =
            (transaction.category ?? "").lowercased().contains("transfer") &&
            !isLikelyBankTransfer(transaction) && !isPlaidCashWithdrawal(transaction) && !hasManualCategory
        if categoryNeedsReview || ambiguousPlaidTransferCategory {
            let added = upsertPlaidReviewItem(
                sourceId: transaction.id,
                title: expense.name,
                detail: ambiguousPlaidTransferCategory
                    ? "Plaid labels this a transfer, but no receiving bank transaction was confirmed. It is currently recorded as a withdrawal/expense; review whether it belongs to an external account."
                    : "Plaid transaction needs category review.",
                amount: transaction.amount,
                date: transaction.date
            )
            expenses.append(expense)
            return added ? .needsReview : .imported
        }

        expenses.append(expense)
        clearPlaidReviewItems(sourceIds: [transaction.id])
        return .imported
    }

    func pendingExpenseReplacementIndex(for transaction: PlaidSyncedTransaction) -> Int? {
        guard !transaction.pending else { return nil }
        return expenses.firstIndex { existing in
            let wasPending = existing.plaidMetadata?.isPending == true || existing.note == "Plaid pending transaction"
            guard wasPending,
                  existing.plaidMetadata?.transactionId != nil,
                  existing.plaidMetadata?.transactionId != transaction.id,
                  existing.plaidMetadata?.accountId == transaction.accountId,
                  abs(existing.amount - abs(transaction.amount)) < 0.01,
                  dayDistance(existing.date, transaction.date) <= 3 else {
                return false
            }
            return namesLikelyMatchForReconciliation(existing.name, transactionDisplayName(transaction))
        }
    }

    func mergedPlaidExpense(
        _ existing: Expense,
        with transaction: PlaidSyncedTransaction,
        accountName: String,
        syncedAt: Date
    ) -> Expense {
        var updated = existing
        updated.amount = roundedReconciliationCurrency(abs(transaction.amount))
        updated.date = transaction.date
        // Only migrate the generic Plaid fallback, never a user-selected category.
        if isPlaidCashWithdrawal(transaction), updated.section == .needs,
           needsCategories.contains(where: { $0.id == updated.categoryId && $0.name == "Plaid Needs" }) {
            updated.categoryId = plaidCashWithdrawalCategory().categoryId
        }
        updated.paymentAccount = accountName
        updated.paymentAccountId = stableFinancialAccountId(forPlaidAccountId: transaction.accountId)

        // Only replace the machine-owned pending marker. Any user note/category/name
        // remains untouched across Plaid modifications.
        if existing.note == "Plaid pending transaction" {
            updated.note = transaction.pending ? "Plaid pending transaction" : ""
        }

        updated.plaidMetadata = reconciliationMetadata(
            for: transaction,
            syncedAt: syncedAt,
            status: existing.plaidMetadata?.status ?? .imported,
            matchConfidence: existing.plaidMetadata?.matchConfidence,
            importedAt: existing.plaidMetadata?.importedAt
        )
        updated.plaidMetadata?.userConfirmedNotTransfer = existing.plaidMetadata?.userConfirmedNotTransfer
        updated.plaidMetadata?.rejectedCounterpartIds = existing.plaidMetadata?.rejectedCounterpartIds
        updated.plaidMetadata?.originalCategory = transaction.category ?? existing.plaidMetadata?.originalCategory
        return updated
    }

    func mergedPlaidIncome(
        _ existing: IncomeEntry,
        with transaction: PlaidSyncedTransaction,
        accountName: String,
        syncedAt: Date
    ) -> IncomeEntry {
        var updated = existing
        updated.amount = roundedReconciliationCurrency(abs(transaction.amount))
        updated.date = transaction.date
        updated.bankName = accountName
        updated.bankAccountId = stableFinancialAccountId(forPlaidAccountId: transaction.accountId)
        updated.plaidMetadata = reconciliationMetadata(
            for: transaction,
            syncedAt: syncedAt,
            status: existing.plaidMetadata?.status ?? .imported,
            matchConfidence: existing.plaidMetadata?.matchConfidence,
            importedAt: existing.plaidMetadata?.importedAt
        )
        updated.plaidMetadata?.userConfirmedNotTransfer = existing.plaidMetadata?.userConfirmedNotTransfer
        updated.plaidMetadata?.rejectedCounterpartIds = existing.plaidMetadata?.rejectedCounterpartIds
        updated.plaidMetadata?.originalCategory = transaction.category ?? existing.plaidMetadata?.originalCategory
        return updated
    }

    func incomeFromDirectionChange(
        _ existing: Expense,
        transaction: PlaidSyncedTransaction,
        accountName: String,
        syncedAt: Date
    ) -> IncomeEntry {
        IncomeEntry(
            id: existing.id,
            name: existing.name,
            amount: roundedReconciliationCurrency(abs(transaction.amount)),
            date: transaction.date,
            bankName: accountName,
            bankAccountId: stableFinancialAccountId(forPlaidAccountId: transaction.accountId),
            plaidMetadata: reconciliationMetadata(
                for: transaction,
                syncedAt: syncedAt,
                status: existing.plaidMetadata?.status ?? .imported,
                matchConfidence: existing.plaidMetadata?.matchConfidence,
                importedAt: existing.plaidMetadata?.importedAt
            )
        )
    }

    func expenseFromDirectionChange(
        _ existing: IncomeEntry,
        transaction: PlaidSyncedTransaction,
        accountName: String,
        syncedAt: Date
    ) -> Expense {
        let mapped = persistentCategoryAssignment(for: transaction) ?? mappedReconciliationCategory(for: transaction.category)
        return Expense(
            id: existing.id,
            name: existing.name,
            amount: roundedReconciliationCurrency(abs(transaction.amount)),
            date: transaction.date,
            section: mapped.section,
            categoryId: mapped.categoryId,
            paymentAccount: accountName,
            paymentAccountId: stableFinancialAccountId(forPlaidAccountId: transaction.accountId),
            note: transaction.pending ? "Plaid pending transaction" : "",
            plaidMetadata: reconciliationMetadata(
                for: transaction,
                syncedAt: syncedAt,
                status: existing.plaidMetadata?.status ?? .imported,
                matchConfidence: existing.plaidMetadata?.matchConfidence,
                importedAt: existing.plaidMetadata?.importedAt
            )
        )
    }

    func makeReconciledIncome(from transaction: PlaidSyncedTransaction, accountName: String, syncedAt: Date) -> IncomeEntry {
        IncomeEntry(
            name: transactionDisplayName(transaction),
            amount: roundedReconciliationCurrency(abs(transaction.amount)),
            date: transaction.date,
            bankName: accountName,
            bankAccountId: stableFinancialAccountId(forPlaidAccountId: transaction.accountId),
            plaidMetadata: reconciliationMetadata(for: transaction, syncedAt: syncedAt)
        )
    }

    func makeReconciledExpense(from transaction: PlaidSyncedTransaction, accountName: String, syncedAt: Date) -> Expense {
        let mapped = persistentCategoryAssignment(for: transaction) ??
            (isPlaidCashWithdrawal(transaction) ? plaidCashWithdrawalCategory() : mappedReconciliationCategory(for: transaction.category))
        return Expense(
            name: transactionDisplayName(transaction),
            amount: roundedReconciliationCurrency(abs(transaction.amount)),
            date: transaction.date,
            section: mapped.section,
            categoryId: mapped.categoryId,
            paymentAccount: accountName,
            paymentAccountId: stableFinancialAccountId(forPlaidAccountId: transaction.accountId),
            note: transaction.pending ? "Plaid pending transaction" : "",
            plaidMetadata: reconciliationMetadata(for: transaction, syncedAt: syncedAt)
        )
    }

    // MARK: - Account-aware manual matching

    func bestManualExpenseMatch(for imported: Expense) -> PlaidManualMatch? {
        let scored = expenses.enumerated().compactMap { index, existing -> (Int, Double)? in
            guard existing.plaidMetadata?.transactionId == nil,
                  abs(existing.amount - imported.amount) < 0.01 else { return nil }
            guard let score = manualExpenseMatchScore(existing: existing, imported: imported) else { return nil }
            return (index, score)
        }.sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 >= 0.65 else { return nil }
        let ambiguous = scored.dropFirst().first.map { best.1 - $0.1 < 0.08 } ?? false
        return PlaidManualMatch(index: best.0, confidence: min(best.1, 1), ambiguous: ambiguous)
    }

    func manualExpenseMatchScore(existing: Expense, imported: Expense) -> Double? {
        var score = 0.30 // exact amount is required by the caller
        let dayGap = dayDistance(existing.date, imported.date)
        if dayGap == 0 {
            score += 0.25
        } else if dayGap <= 2 {
            score += 0.12
        } else {
            return nil
        }

        if let existingId = existing.paymentAccountId, let importedId = imported.paymentAccountId {
            guard existingId == importedId else { return nil }
            score += 0.30
        } else {
            let existingAccount = normalizedReconciliationText(existing.paymentAccount)
            let importedAccount = normalizedReconciliationText(imported.paymentAccount)
            if !existingAccount.isEmpty, !importedAccount.isEmpty {
                guard existingAccount == importedAccount else { return nil }
                score += 0.20
            }
        }

        guard namesLikelyMatchForReconciliation(existing.name, imported.name) else { return nil }
        score += 0.20
        return score
    }

    func bestManualIncomeMatch(for imported: IncomeEntry) -> PlaidManualMatch? {
        let scored = incomes.enumerated().compactMap { index, existing -> (Int, Double)? in
            guard existing.plaidMetadata?.transactionId == nil,
                  abs(existing.amount - imported.amount) < 0.01 else { return nil }
            guard let score = manualIncomeMatchScore(existing: existing, imported: imported) else { return nil }
            return (index, score)
        }.sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 >= 0.65 else { return nil }
        let ambiguous = scored.dropFirst().first.map { best.1 - $0.1 < 0.08 } ?? false
        return PlaidManualMatch(index: best.0, confidence: min(best.1, 1), ambiguous: ambiguous)
    }

    func manualIncomeMatchScore(existing: IncomeEntry, imported: IncomeEntry) -> Double? {
        var score = 0.30
        let dayGap = dayDistance(existing.date, imported.date)
        if dayGap == 0 {
            score += 0.25
        } else if dayGap <= 2 {
            score += 0.12
        } else {
            return nil
        }

        if let existingId = existing.bankAccountId, let importedId = imported.bankAccountId {
            guard existingId == importedId else { return nil }
            score += 0.30
        } else {
            let existingAccount = normalizedReconciliationText(existing.bankName)
            let importedAccount = normalizedReconciliationText(imported.bankName)
            if !existingAccount.isEmpty, !importedAccount.isEmpty {
                guard existingAccount == importedAccount else { return nil }
                score += 0.20
            }
        }

        guard namesLikelyMatchForReconciliation(existing.name, imported.name) else { return nil }
        score += 0.20
        return score
    }

    // MARK: - Review + metadata helpers

    @discardableResult
    func upsertPlaidReviewItem(
        sourceId: String,
        title: String,
        detail: String,
        amount: Double?,
        date: Date?
    ) -> Bool {
        if let index = plaidReviewItems.firstIndex(where: { $0.sourceId == sourceId }) {
            plaidReviewItems[index].title = title
            plaidReviewItems[index].detail = detail
            plaidReviewItems[index].amount = amount
            plaidReviewItems[index].date = date
            return false
        }
        plaidReviewItems.append(
            PlaidReviewItem(
                title: title,
                detail: detail,
                amount: amount,
                date: date,
                sourceId: sourceId
            )
        )
        return true
    }

    func clearPlaidReviewItems(sourceIds: [String]) {
        let ids = Set(sourceIds)
        plaidReviewItems.removeAll { ids.contains($0.sourceId) }
    }

    func removeReconciledPlaidTransaction(id: String) -> Int {
        let oldExpenseCount = expenses.count
        expenses.removeAll { $0.plaidMetadata?.transactionId == id }
        let oldIncomeCount = incomes.count
        incomes.removeAll { $0.plaidMetadata?.transactionId == id }
        let removedSingleTransfers = removePlaidSingleTransfers(sourceIds: [id])
        clearPlaidReviewItems(sourceIds: [id])
        return (oldExpenseCount - expenses.count) + (oldIncomeCount - incomes.count) + removedSingleTransfers
    }

    func reconciliationMetadata(
        for transaction: PlaidSyncedTransaction,
        syncedAt: Date,
        status: PlaidImportStatus = .imported,
        matchConfidence: Double? = nil,
        importedAt: Date? = nil
    ) -> PlaidSourceMetadata {
        var metadata = PlaidSourceMetadata(
            itemId: transaction.itemId,
            accountId: transaction.accountId,
            transactionId: transaction.id,
            importedAt: importedAt ?? syncedAt,
            lastSyncedAt: syncedAt,
            status: status,
            matchConfidence: matchConfidence,
            isPending: transaction.pending
        )
        metadata.originalCategory = transaction.category
        return metadata
    }

    func stableFinancialAccountId(forPlaidAccountId accountId: String) -> UUID? {
        financialAccounts.first { $0.externalAccountId == accountId }?.id
    }

    func isPlaidCashWithdrawal(_ transaction: PlaidSyncedTransaction) -> Bool {
        guard transaction.amount > 0 else { return false }
        let desc = transactionDescriptionText(transaction)
        guard !desc.contains("surcharge"), !desc.contains(" fee") else { return false }
        return ["atm", "cash withdrawal", "cash wdl", "cash wd"].contains { desc.contains($0) }
    }

    func plaidCashWithdrawalCategory() -> (section: BudgetSection, categoryId: UUID) {
        if let existing = needsCategories.first(where: { $0.name == "Cash Withdrawals" }) {
            return (.needs, existing.id)
        }
        let created = Category(name: "Cash Withdrawals", allocatedAmount: 0)
        needsCategories.append(created)
        return (.needs, created.id)
    }

    func mappedReconciliationCategory(for plaidCategory: String?) -> (section: BudgetSection, categoryId: UUID) {
        let category = (plaidCategory ?? "").lowercased()
        let section: BudgetSection = (
            category.contains("travel") ||
            category.contains("entertainment") ||
            category.contains("recreation") ||
            category.contains("shops")
        ) ? .wants : .needs

        switch section {
        case .needs:
            if let match = needsCategories.first(where: { category.contains($0.name.lowercased()) || $0.name.localizedCaseInsensitiveContains("plaid") }) {
                return (.needs, match.id)
            }
            let newCategory = Category(name: "Plaid Needs", allocatedAmount: 0)
            needsCategories.append(newCategory)
            return (.needs, newCategory.id)
        case .wants:
            if let match = wantsCategories.first(where: { category.contains($0.name.lowercased()) || $0.name.localizedCaseInsensitiveContains("plaid") }) {
                return (.wants, match.id)
            }
            let newCategory = Category(name: "Plaid Wants", allocatedAmount: 0)
            wantsCategories.append(newCategory)
            return (.wants, newCategory.id)
        }
    }

    // MARK: - Comparison helpers

    func transactionDisplayName(_ transaction: PlaidSyncedTransaction) -> String {
        transaction.merchantName ?? transaction.name
    }

    func transactionSearchText(_ transaction: PlaidSyncedTransaction) -> String {
        "\(transaction.name) \(transaction.merchantName ?? "") \(transaction.category ?? "")".lowercased()
    }

    func namesLikelyMatchForReconciliation(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedReconciliationText(lhs)
        let right = normalizedReconciliationText(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.contains(right) || right.contains(left)
    }

    func normalizedReconciliationText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
    }

    func dayDistance(_ lhs: Date, _ rhs: Date) -> Int {
        let calendar = Calendar.current
        let left = calendar.startOfDay(for: lhs)
        let right = calendar.startOfDay(for: rhs)
        return abs(calendar.dateComponents([.day], from: left, to: right).day ?? Int.max)
    }

    func roundedReconciliationCurrency(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
