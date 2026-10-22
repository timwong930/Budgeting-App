import Foundation

@main
struct CuanMarketModelsTests {
    static func main() {
        testChangeTextIncludesPositiveSign()
        testChangeTextKeepsNegativeSign()
        testSparklineNormalizesValues()
        testSparklineFallsBackForFlatValues()
        testSplashBoardCentersMomosMoney()
        testCashTransferMovesBetweenBankAccounts()
        testCashTransferUpdateAndDeleteReversePreviousBalanceImpact()
        testPlaidMetadataCodableMigrationKeepsLegacyExpenseReadable()
        testPlaidBackendDecoderAcceptsPlaidDateOnlyStrings()
        testPlaidTransactionImportDedupesManualExpense()
        testPlaidWithdrawalsStayExpenses()
        testPlaidBankTransferNeedsVerifiedBothSides()
        testPlaidSeparateSyncBankTransferMatches()
        testPlaidSeparateSyncCardPaymentMatches()
        testPlaidManualCardPaymentCanUndoIncorrectMatch()
        testPlaidCashWithdrawalsGetDedicatedCategory()
        testPlaidCardPurchaseAndBankLoanAreNotPayments()
        testPlaidUndoMetadataCodablePersistence()
        testPlaidUnknownCardCreditRequiresReview()
        testPlaidUserReclassifiedBankTransferSurvivesReplay()
        testPlaidUserReclassifiedCardPaymentSurvivesReplay()
        testPlaidExpenseTransferCodableMigration()
        testPlaidManualDestinationCannotBePairedWithWrongBank()
        testPlaidPartialSyncDoesNotDuplicateVerifiedPair()
        testPlaidPairedSideRemovalBecomesUnpairedReview()
        testPlaidOneSidedTransferDescriptionPairsACHCredit()
        testPlaidManualTransferReviewPersists()
        testPlaidReviewKeepAsWithdrawalPersists()
        testPlaidUnrelatedMatchingAmountDoesNotPair()
        testPlaidAmbiguousTransfersStayUnpaired()
        testPlaidLegacyMispairedTransferIsRemovedOnReplay()
        testPlaidRemovedTransactionClearsPairedTransfer()
        testPlaidCreditAccountUpdateUsesLiabilityFields()
        testPlaidHoldingsSnapshotPreservesTickerMetadata()
        testPlaidWatchlistImportDedupesAndUppercases()
        testPlaidOptionHoldingsDoNotImportAsStockTickers()
        testPlaidCashHoldingFeedsCashAndMarginBalances()
        testPlaidDuplicateTickerHoldingsStayAccountScoped()
        testManualSameTickerHoldingsStayAccountScoped()
        testPortfolioCashAndMarginStayAccountScoped()
        testFinancialAccountCodableRoundTrip()
        testLegacyAccountsMigrateToStableAccountDomain()
        testLegacyLedgerReferencesMigrateToUUIDs()
        testStableAccountUUIDSurvivesRename()
        testStableCreditUUIDSurvivesRename()
        testManualLedgerDoesNotMutatePlaidBalance()
        testHoldingsConsolidateToOneRowPerTicker()
        print("CuanMarketModelsTests passed")
    }

    private static func testChangeTextIncludesPositiveSign() {
        let display = CuanMarketChangeDisplay(change: 2.4, percentChange: 1.25)
        assert(display.priceChangeText == "+$2.40", "Expected positive dollar change to include plus sign")
        assert(display.percentChangeText == "+1.25%", "Expected positive percent change to include plus sign")
        assert(display.direction == .gain, "Expected positive percent change to be a gain")
    }

    private static func testChangeTextKeepsNegativeSign() {
        let display = CuanMarketChangeDisplay(change: -1.27, percentChange: -0.31)
        assert(display.priceChangeText == "-$1.27", "Expected negative dollar change to keep minus sign")
        assert(display.percentChangeText == "-0.31%", "Expected negative percent change to keep minus sign")
        assert(display.direction == .loss, "Expected negative percent change to be a loss")
    }

    private static func testSparklineNormalizesValues() {
        let normalized = CuanSparklineSeries(values: [10, 15, 20]).normalized
        assert(normalized == [0.0, 0.5, 1.0], "Expected min/mid/max normalized series")
    }

    private static func testSparklineFallsBackForFlatValues() {
        let normalized = CuanSparklineSeries(values: [7, 7, 7]).normalized
        assert(normalized == [0.5, 0.5, 0.5], "Expected flat series to center points")
    }

    private static func testSplashBoardCentersMomosMoney() {
        let rows = MomoSplashBoardFormatter.rows(for: ["MOMO'S", "MONEY"], columns: 10, rowCount: 2)
        assert(rows == [
            [" ", " ", "M", "O", "M", "O", "'", "S", " ", " "],
            [" ", " ", "M", "O", "N", "E", "Y", " ", " ", " "]
        ], "Expected Momo's Money splash text to be centered across split-flap rows")
    }

    private static func testCashTransferMovesBetweenBankAccounts() {
        let budget = BudgetModel()
        budget.bankAccounts = [
            BankAccount(name: "Checking", balance: 500),
            BankAccount(name: "Savings", balance: 100)
        ]

        budget.addCashTransfer(
            CashTransfer(
                name: "Emergency fund",
                amount: 125.34,
                fromAccountName: "Checking",
                toAccountName: "Savings"
            )
        )

        assert(budget.bankAccounts.first(where: { $0.name == "Checking" })?.balance == 374.66, "Expected source account balance to decrease by transfer amount")
        assert(budget.bankAccounts.first(where: { $0.name == "Savings" })?.balance == 225.34, "Expected destination account balance to increase by transfer amount")
        assert(budget.cashTransfers.count == 1, "Expected transfer to be recorded separately from income and expenses")
        assert(budget.incomes.isEmpty, "Expected transfer not to count as income")
        assert(budget.expenses.isEmpty, "Expected transfer not to count as an expense")
    }

    private static func testCashTransferUpdateAndDeleteReversePreviousBalanceImpact() {
        let transferId = UUID()
        let budget = BudgetModel()
        budget.bankAccounts = [
            BankAccount(name: "Checking", balance: 500),
            BankAccount(name: "Savings", balance: 100),
            BankAccount(name: "Brokerage Cash", balance: 25)
        ]

        budget.addCashTransfer(
            CashTransfer(
                id: transferId,
                name: "Move cash",
                amount: 50,
                fromAccountName: "Checking",
                toAccountName: "Savings"
            )
        )
        budget.updateCashTransfer(
            CashTransfer(
                id: transferId,
                name: "Move cash",
                amount: 30,
                fromAccountName: "Savings",
                toAccountName: "Brokerage Cash"
            )
        )

        assert(budget.bankAccounts.first(where: { $0.name == "Checking" })?.balance == 500, "Expected old source account to be restored after transfer update")
        assert(budget.bankAccounts.first(where: { $0.name == "Savings" })?.balance == 70, "Expected old destination reversal and new source debit")
        assert(budget.bankAccounts.first(where: { $0.name == "Brokerage Cash" })?.balance == 55, "Expected new destination account to receive updated transfer amount")

        budget.deleteCashTransfer(id: transferId)

        assert(budget.bankAccounts.first(where: { $0.name == "Checking" })?.balance == 500, "Expected unrelated account to stay unchanged after delete")
        assert(budget.bankAccounts.first(where: { $0.name == "Savings" })?.balance == 100, "Expected source account to be restored after delete")
        assert(budget.bankAccounts.first(where: { $0.name == "Brokerage Cash" })?.balance == 25, "Expected destination account to be restored after delete")
        assert(budget.cashTransfers.isEmpty, "Expected deleted transfer to be removed from ledger")
    }

    private static func testPlaidMetadataCodableMigrationKeepsLegacyExpenseReadable() {
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Groceries",
          "amount": 42.75,
          "date": "2026-06-10T12:00:00Z",
          "section": "needs",
          "categoryId": "00000000-0000-0000-0000-000000000002",
          "paymentAccount": "Checking",
          "note": ""
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let expense = try! decoder.decode(Expense.self, from: Data(legacyJSON.utf8))

        assert(expense.plaidMetadata == nil, "Expected legacy expense JSON without Plaid metadata to decode")
        assert(expense.paymentAccountId == nil, "Expected legacy expense without account UUID to remain readable")
        assert(expense.creditCardPaymentTargetId == nil, "Expected legacy credit-card UUID to default to nil")
    }

    private static func testPlaidBackendDecoderAcceptsPlaidDateOnlyStrings() {
        let json = """
        {
          "accounts": [
            {
              "id": "acc-checking",
              "itemId": "item-1",
              "name": "Checking",
              "type": "depository",
              "subtype": "checking",
              "currentBalance": 100.25,
              "availableBalance": 90.25,
              "creditLimit": null,
              "institutionName": "Bank"
            }
          ],
          "transactions": [
            {
              "id": "tx-1",
              "accountId": "acc-checking",
              "itemId": "item-1",
              "name": "Coffee",
              "merchantName": "Coffee Shop",
              "amount": 4.5,
              "date": "2026-06-11",
              "pending": false,
              "category": "Food and Drink",
              "removed": false
            }
          ],
          "creditLiabilities": [
            {
              "accountId": "cc-1",
              "itemId": "item-1",
              "minimumPaymentAmount": 25,
              "nextPaymentDueDate": "2026-07-01",
              "lastStatementBalance": 250,
              "lastStatementIssueDate": "2026-06-01",
              "aprPercentage": 22.9
            }
          ],
          "holdings": [],
          "investmentTransactions": [],
          "connectionStatuses": [
            {
              "itemId": "item-1",
              "institutionName": "Bank",
              "health": "connected",
              "lastSyncedAt": "2026-06-12T06:05:39Z",
              "errorMessage": null
            }
          ]
        }
        """

        let payload = try! JSONDecoder.plaidBackend.decode(PlaidSyncPayload.self, from: Data(json.utf8))

        assert(payload.transactions.count == 1, "Expected Plaid date-only transaction payload to decode")
        assert(payload.creditLiabilities.first?.nextPaymentDueDate != nil, "Expected Plaid liability date-only fields to decode")
        assert(payload.connectionStatuses.first?.lastSyncedAt != nil, "Expected ISO timestamp fields to continue decoding")
    }

    private static func testPlaidTransactionImportDedupesManualExpense() {
        let categoryId = UUID()
        let budget = BudgetModel()
        budget.needsCategories = [Category(id: categoryId, name: "Food", allocatedAmount: 500)]
        budget.bankAccounts = [BankAccount(name: "Checking", balance: 500)]
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        budget.addExpense(
            Expense(
                name: "Whole Foods",
                amount: 23.45,
                date: date,
                section: .needs,
                categoryId: categoryId,
                paymentAccount: "Checking"
            )
        )

        let result = budget.applyPlaidSync(
            PlaidSyncPayload(
                accounts: [PlaidSyncedAccount(id: "acc-checking", itemId: "item-1", name: "Checking", type: .depository, subtype: "checking", currentBalance: 476.55, availableBalance: 476.55, creditLimit: nil, institutionName: "Bank")],
                transactions: [
                    PlaidSyncedTransaction(
                        id: "tx-1",
                        accountId: "acc-checking",
                        itemId: "item-1",
                        name: "Whole Foods Market",
                        merchantName: "Whole Foods",
                        amount: 23.45,
                        date: date,
                        pending: false,
                        category: "Food and Drink",
                        removed: false
                    )
                ],
                creditLiabilities: [],
                holdings: [],
                investmentTransactions: [],
                connectionStatuses: []
            )
        )

        assert(budget.expenses.count == 1, "Expected Plaid import to reconcile duplicate manual expense instead of appending")
        assert(budget.expenses[0].plaidMetadata?.transactionId == "tx-1", "Expected reconciled manual expense to gain Plaid transaction ID")
        assert(result.reconciledTransactions == 1, "Expected import result to report one reconciled transaction")
    }


    private static func testPlaidWithdrawalsStayExpenses() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_780_100_000)
        // Simulate a previously misclassified one-sided Plaid transfer.
        budget.cashTransfers = [
            CashTransfer(name: "ATM CASH WITHDRAWAL", amount: 80, date: date, fromAccountName: "Checking", toAccountName: "External account", note: "[PLAID_SINGLE:withdraw-atm] Unpaired Plaid transfer/payment")
        ]
        let payload = PlaidSyncPayload(
            accounts: [
                PlaidSyncedAccount(id: "withdraw-checking", itemId: "bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 800, availableBalance: 800, creditLimit: nil, institutionName: "Bank")
            ],
            transactions: [
                PlaidSyncedTransaction(id: "withdraw-atm", accountId: "withdraw-checking", itemId: "bank", name: "ATM CASH WITHDRAWAL", merchantName: nil, amount: 80, date: date, pending: false, category: "TRANSFER_OUT", removed: false),
                PlaidSyncedTransaction(id: "withdraw-ach", accountId: "withdraw-checking", itemId: "bank", name: "ACH DEBIT GYM MEMBERSHIP", merchantName: nil, amount: 42, date: date, pending: false, category: "TRANSFER_OUT", removed: false),
                PlaidSyncedTransaction(id: "withdraw-zelle", accountId: "withdraw-checking", itemId: "bank", name: "ZELLE PAYMENT TO FRIEND", merchantName: nil, amount: 35, date: date, pending: false, category: "TRANSFER_OUT", removed: false),
                PlaidSyncedTransaction(id: "withdraw-payroll", accountId: "withdraw-checking", itemId: "bank", name: "ACH CREDIT PAYROLL", merchantName: nil, amount: -1000, date: date, pending: false, category: "TRANSFER_IN", removed: false)
            ],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.isEmpty, "ACH, ATM and Zelle must not automatically become account transfers")
        assert(budget.expenses.count == 3 && budget.incomes.count == 1, "Bank withdrawals should remain outflows and payroll should remain income")

        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.isEmpty && budget.expenses.count == 3 && budget.incomes.count == 1, "Replaying withdrawal transactions must not create duplicates")
    }

    private static func testPlaidBankTransferNeedsVerifiedBothSides() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_780_200_000)
        let checking = PlaidSyncedAccount(id: "pair-check", itemId: "bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank")
        let savings = PlaidSyncedAccount(id: "pair-save", itemId: "bank", name: "Savings", type: .depository, subtype: "savings", currentBalance: 900, availableBalance: 900, creditLimit: nil, institutionName: "Bank")
        let payload = PlaidSyncPayload(
            accounts: [checking, savings],
            transactions: [
                PlaidSyncedTransaction(id: "pair-out", accountId: "pair-check", itemId: "bank", name: "ONLINE TRANSFER TO SAVINGS", merchantName: nil, amount: 200, date: date, pending: false, category: "TRANSFER_OUT", removed: false),
                PlaidSyncedTransaction(id: "pair-in", accountId: "pair-save", itemId: "bank", name: "TRANSFER FROM CHECKING", merchantName: nil, amount: -200, date: date, pending: false, category: "TRANSFER_IN", removed: false)
            ],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.count == 1, "A corroborated two-sided bank transfer should be created exactly once")
        assert(budget.cashTransfers[0].fromAccountName == "Checking" && budget.cashTransfers[0].toAccountName == "Savings", "Verified transfer must preserve bank direction")
        assert(budget.expenses.isEmpty && budget.incomes.isEmpty, "Confirmed transfers should not affect budget income or spending")
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.count == 1, "Repeated sync should not duplicate a confirmed transfer")
    }


    /// Plaid /transactions/sync may deliver modifications from one institution
    /// without replaying the other account's existing transaction.
    private static func testPlaidPartialSyncDoesNotDuplicateVerifiedPair() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_780_235_000)
        let accounts = [
            PlaidSyncedAccount(id: "partial-check", itemId: "partial-bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 650, availableBalance: 650, creditLimit: nil, institutionName: "Bank"),
            PlaidSyncedAccount(id: "partial-save", itemId: "partial-bank", name: "Savings", type: .depository, subtype: "savings", currentBalance: 650, availableBalance: 650, creditLimit: nil, institutionName: "Bank")
        ]
        let out = PlaidSyncedTransaction(id: "partial-out", accountId: "partial-check", itemId: "partial-bank", name: "TRANSFER TO SAVINGS", merchantName: nil, amount: 125, date: date, pending: false, category: "TRANSFER_OUT", removed: false)
        let incoming = PlaidSyncedTransaction(id: "partial-in", accountId: "partial-save", itemId: "partial-bank", name: "TRANSFER FROM CHECKING", merchantName: nil, amount: -125, date: date, pending: false, category: "TRANSFER_IN", removed: false)
        func payload(_ transactions: [PlaidSyncedTransaction]) -> PlaidSyncPayload {
            PlaidSyncPayload(accounts: accounts, transactions: transactions, creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: [])
        }

        _ = budget.applyPlaidSyncReconciled(payload([out, incoming]))
        assert(budget.cashTransfers.count == 1, "Initial two-sided Plaid transfer must create one pair")
        _ = budget.applyPlaidSyncReconciled(payload([out]))
        _ = budget.applyPlaidSyncReconciled(payload([out]))
        assert(budget.cashTransfers.count == 1, "A one-sided incremental replay must not add a second Plaid single transfer")
        assert(budget.cashTransfers[0].note.contains("[PLAID_PAIR:"), "Partial delivery must retain the original verified pair")
        assert(budget.expenses.isEmpty && budget.incomes.isEmpty, "Partial delivery must not double-count a verified transfer as spending or income")

        _ = budget.applyPlaidSyncReconciled(payload([out, incoming]))
        assert(budget.cashTransfers.count == 1 && budget.expenses.isEmpty && budget.incomes.isEmpty, "Full replay must remain idempotent after a partial delivery")
    }

    /// An explicit Plaid removal is authoritative, unlike an omitted
    /// transaction in a partial sync. Do not keep its old verified pair.
    private static func testPlaidPairedSideRemovalBecomesUnpairedReview() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_780_236_000)
        let accounts = [
            PlaidSyncedAccount(id: "removed-check", itemId: "removed-bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 650, availableBalance: 650, creditLimit: nil, institutionName: "Bank"),
            PlaidSyncedAccount(id: "removed-save", itemId: "removed-bank", name: "Savings", type: .depository, subtype: "savings", currentBalance: 650, availableBalance: 650, creditLimit: nil, institutionName: "Bank")
        ]
        let out = PlaidSyncedTransaction(id: "removed-out-2", accountId: "removed-check", itemId: "removed-bank", name: "TRANSFER TO SAVINGS", merchantName: nil, amount: 125, date: date, pending: false, category: "TRANSFER_OUT", removed: false)
        let incoming = PlaidSyncedTransaction(id: "removed-in-2", accountId: "removed-save", itemId: "removed-bank", name: "TRANSFER FROM CHECKING", merchantName: nil, amount: -125, date: date, pending: false, category: "TRANSFER_IN", removed: false)
        let removedIncoming = PlaidSyncedTransaction(id: "removed-in-2", accountId: "removed-save", itemId: "removed-bank", name: "TRANSFER FROM CHECKING", merchantName: nil, amount: -125, date: date, pending: false, category: "TRANSFER_IN", removed: true)

        _ = budget.applyPlaidSyncReconciled(PlaidSyncPayload(accounts: accounts, transactions: [out, incoming], creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []))
        _ = budget.applyPlaidSyncReconciled(PlaidSyncPayload(accounts: accounts, transactions: [out, removedIncoming], creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []))
        assert(budget.cashTransfers.count == 1, "An explicitly removed counterpart must invalidate the verified pair")
        assert(budget.cashTransfers[0].note.contains("[PLAID_SINGLE:removed-out-2]"), "Surviving transfer should be unpaired pending review")
        assert(budget.cashTransfers[0].toAccountId == nil, "Removed counterpart must not leave a phantom receiving account")
        assert(budget.plaidReviewItems.contains(where: { $0.sourceId == "removed-out-2" }), "Surviving unpaired transfer must be reviewable")
    }


    private static func testPlaidSeparateSyncBankTransferMatches() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_781_000_000)
        let accounts = [
            PlaidSyncedAccount(id: "seq-check", itemId: "seq-bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 1000, availableBalance: 1000, creditLimit: nil, institutionName: "Bank"),
            PlaidSyncedAccount(id: "seq-save", itemId: "seq-bank", name: "Savings", type: .depository, subtype: "savings", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank")
        ]
        let debit = PlaidSyncedTransaction(id: "seq-out", accountId: "seq-check", itemId: "seq-bank", name: "ONLINE TRANSFER TO SAVINGS", merchantName: nil, amount: 210, date: date, pending: false, category: "TRANSFER_OUT", removed: false)
        let credit = PlaidSyncedTransaction(id: "seq-in", accountId: "seq-save", itemId: "seq-bank", name: "ACH CREDIT", merchantName: nil, amount: -210, date: date, pending: false, category: "TRANSFER_IN", removed: false)
        func batch(_ records: [PlaidSyncedTransaction]) -> PlaidSyncPayload {
            PlaidSyncPayload(accounts: accounts, transactions: records, creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: [])
        }
        _ = budget.applyPlaidSyncReconciled(batch([debit]))
        assert(budget.cashTransfers.count == 1 && budget.cashTransfers[0].note.hasPrefix("[PLAID_SINGLE:"), "Unmatched first transfer side should remain unpaired, not invent a savings credit")

        _ = budget.applyPlaidSyncReconciled(batch([credit]))
        assert(budget.cashTransfers.count == 1 && budget.cashTransfers[0].note.hasPrefix("[PLAID_PAIR:"), "An ACH receiving leg from a later Plaid batch must match the stored transfer")
        assert(budget.cashTransfers[0].fromAccountName == "Checking" && budget.cashTransfers[0].toAccountName == "Savings", "Cross-batch transfer must link the correct financial accounts")
        assert(budget.expenses.isEmpty && budget.incomes.isEmpty, "Cross-batch transfer must not count as income or spending")
        _ = budget.applyPlaidSyncReconciled(batch([credit]))
        assert(budget.cashTransfers.count == 1 && budget.expenses.isEmpty && budget.incomes.isEmpty, "Repeating a single-side Plaid batch must not create duplicates")
    }

    private static func testPlaidSeparateSyncCardPaymentMatches() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_781_010_000)
        let accounts = [
            PlaidSyncedAccount(id: "card-bank", itemId: "bank-item", name: "Checking", type: .depository, subtype: "checking", currentBalance: 900, availableBalance: 900, creditLimit: nil, institutionName: "Bank"),
            PlaidSyncedAccount(id: "card-credit", itemId: "card-item", name: "Credit Card", type: .credit, subtype: "credit card", currentBalance: 200, availableBalance: 1800, creditLimit: 2000, institutionName: "Bank")
        ]
        let debit = PlaidSyncedTransaction(id: "card-out", accountId: "card-bank", itemId: "bank-item", name: "CREDIT CARD PAYMENT", merchantName: nil, amount: 125, date: date, pending: false, category: "LOAN_PAYMENT", removed: false)
        let credit = PlaidSyncedTransaction(id: "card-in", accountId: "card-credit", itemId: "card-item", name: "AUTOPAY PAYMENT RECEIVED", merchantName: nil, amount: -125, date: date, pending: false, category: "LOAN_PAYMENT", removed: false)
        func batch(_ records: [PlaidSyncedTransaction]) -> PlaidSyncPayload {
            PlaidSyncPayload(accounts: accounts, transactions: records, creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: [])
        }
        _ = budget.applyPlaidSyncReconciled(batch([debit]))
        _ = budget.applyPlaidSyncReconciled(batch([credit]))
        assert(budget.cashTransfers.count == 1 && budget.cashTransfers[0].note.hasPrefix("[PLAID_PAIR:"), "Card payment received later should link to the saved bank debit")
        assert(budget.cashTransfers[0].fromAccountName == "Checking" && budget.cashTransfers[0].toAccountName == "Credit Card", "Checking debit must flow into the correct card")
        assert(budget.expenses.isEmpty && budget.incomes.isEmpty, "Card payment must not count as new spending or income")
        _ = budget.applyPlaidSyncReconciled(batch([debit, credit]))
        assert(budget.cashTransfers.count == 1, "Replay of already-matched card payment must remain idempotent")
    }

    private static func testPlaidManualCardPaymentCanUndoIncorrectMatch() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_781_020_000)
        let accounts = [
            PlaidSyncedAccount(id: "manual-bank-card", itemId: "manual-item", name: "Checking", type: .depository, subtype: "checking", currentBalance: 1000, availableBalance: 1000, creditLimit: nil, institutionName: "Bank"),
            PlaidSyncedAccount(id: "manual-card", itemId: "manual-item", name: "Rewards Card", type: .credit, subtype: "credit card", currentBalance: 150, availableBalance: 1850, creditLimit: 2000, institutionName: "Bank")
        ]
        let bank = PlaidSyncedTransaction(id: "manual-ach-bank", accountId: "manual-bank-card", itemId: "manual-item", name: "ACH DEBIT", merchantName: nil, amount: 96, date: date, pending: false, category: "TRANSFER_OUT", removed: false)
        let card = PlaidSyncedTransaction(id: "manual-ach-card", accountId: "manual-card", itemId: "manual-item", name: "AUTOPAY PAYMENT", merchantName: nil, amount: -96, date: date, pending: false, category: "LOAN_PAYMENT", removed: false)
        let payload = PlaidSyncPayload(accounts: accounts, transactions: [bank, card], creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: [])
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.count == 1 && !budget.cashTransfers[0].note.hasPrefix("[PLAID_PAIR:"), "Generic ACH debit should not auto-link to a card payment without corroborating text")
        assert(budget.plaidTransferReviewCandidates(sourceId: "manual-ach-bank").contains(where: { $0.id == "manual-ach-card" }), "Manual review must offer real credit-card-side matching transactions")
        if let cardId = budget.financialAccounts.first(where: { $0.externalAccountId == "manual-card" })?.id,
           let imported = budget.expenses.first(where: { $0.plaidMetadata?.transactionId == bank.id }) {
            var edited = imported
            edited.creditCardPaymentTargetId = cardId
            edited.creditCardPaymentTarget = "Rewards Card"
            edited.note = "Synthetic payment annotation"
            budget.updateExpense(edited)
        }
        assert(budget.confirmPlaidTransferReview(sourceId: "manual-ach-bank", counterpartId: "manual-ach-card"), "User should be able to confirm a bank debit and credit card payment")
        assert(budget.cashTransfers.count == 1 && budget.canUndoPlaidTransferMatch(transferId: budget.cashTransfers[0].id), "Reviewed pair must retain both original Plaid transactions for undo")
        assert(budget.cashTransfers[0].note.contains("Synthetic payment annotation"), "Linking a classified card payment must preserve the user's note")

        let pairId = budget.cashTransfers[0].id
        assert(budget.undoPlaidTransferMatch(transferId: pairId), "A wrong card payment match must be reversible")
        assert(budget.cashTransfers.count == 2 && budget.cashTransfers.allSatisfy { $0.note.hasPrefix("[PLAID_SINGLE:") }, "Undo must restore both observed legs without destroying data")
        assert(budget.cashTransfers.allSatisfy { $0.plaidRejectedCounterpartIds?.count == 1 }, "Undo must persist pair rejection")
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(!budget.cashTransfers.contains(where: { $0.note.hasPrefix("[PLAID_PAIR:") }), "An undone wrong match must not be recreated on Plaid replay")
        assert(!budget.plaidTransferReviewCandidates(sourceId: "manual-ach-bank").contains(where: { $0.id == "manual-ach-card" }), "Rejected exact counterpart must not be suggested again")
    }

    private static func testPlaidCashWithdrawalsGetDedicatedCategory() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_781_030_000)
        let payload = PlaidSyncPayload(
            accounts: [PlaidSyncedAccount(id: "atm-check", itemId: "atm-item", name: "Checking", type: .depository, subtype: "checking", currentBalance: 700, availableBalance: 700, creditLimit: nil, institutionName: "Bank")],
            transactions: [PlaidSyncedTransaction(id: "atm-40", accountId: "atm-check", itemId: "atm-item", name: "ATM CASH WITHDRAWAL", merchantName: nil, amount: 40, date: date, pending: false, category: "TRANSFER_OUT", removed: false)],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.isEmpty, "ATM cash withdrawals are not transfers to another connected bank")
        assert(budget.expenses.count == 1, "Cash withdrawn without a tracked cash wallet must remain an outflow")
        let category = budget.needsCategories.first(where: { $0.id == budget.expenses[0].categoryId })
        assert(category?.name == "Cash Withdrawals", "A cash withdrawal must not use a generic Plaid Needs category")
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.expenses.count == 1 && budget.cashTransfers.isEmpty, "ATM classification must persist without creating duplicate movements")
    }

    private static func testPlaidCardPurchaseAndBankLoanAreNotPayments() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_781_040_000)
        let payload = PlaidSyncPayload(
            accounts: [
                PlaidSyncedAccount(id: "loan-check", itemId: "loan-bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 900, availableBalance: 900, creditLimit: nil, institutionName: "Bank"),
                PlaidSyncedAccount(id: "autopay-card", itemId: "card-bank", name: "Rewards Card", type: .credit, subtype: "credit card", currentBalance: 300, availableBalance: 1700, creditLimit: 2000, institutionName: "Bank")
            ],
            transactions: [
                PlaidSyncedTransaction(id: "mortgage", accountId: "loan-check", itemId: "loan-bank", name: "MORTGAGE LOAN DEBIT", merchantName: nil, amount: 800, date: date, pending: false, category: "LOAN_PAYMENT", removed: false),
                PlaidSyncedTransaction(id: "merchant-auto", accountId: "autopay-card", itemId: "card-bank", name: "MERCHANT AUTOPAY SUBSCRIPTION", merchantName: nil, amount: 12, date: date, pending: false, category: "SERVICE", removed: false)
            ],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.isEmpty, "A generic bank loan payment and credit-card merchant autopay cannot become account transfers")
        assert(budget.expenses.count == 2, "Loan debit and positive credit purchase must remain spending")
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.expenses.count == 2, "Replayed loan and card purchase must remain two expenses")

        let coincident = BudgetModel()
        let payment = PlaidSyncedTransaction(
            id: "unrelated-card-pay", accountId: "autopay-card", itemId: "card-bank",
            name: "AUTOPAY PAYMENT RECEIVED", merchantName: nil, amount: -800,
            date: date, pending: false, category: "LOAN_PAYMENT", removed: false
        )
        let mortgage = payload.transactions[0]
        _ = coincident.applyPlaidSyncReconciled(
            PlaidSyncPayload(
                accounts: payload.accounts,
                transactions: [mortgage, payment],
                creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
            )
        )
        assert(!coincident.cashTransfers.contains(where: { $0.note.hasPrefix("[PLAID_PAIR:") }),
               "Same-day equal-dollar mortgage and card credit must not be linked automatically")
        assert(coincident.expenses.contains(where: { $0.plaidMetadata?.transactionId == "mortgage" }),
               "Mortgage payment must stay an expense without corroborating bank-side card evidence")
    }

    private static func testPlaidUndoMetadataCodablePersistence() {
        let date = Date(timeIntervalSince1970: 1_781_050_000)
        let source = PlaidSyncedTransaction(id: "persist-1", accountId: "persist-bank", itemId: "persist-item", name: "TRANSFER TO SAVINGS", merchantName: nil, amount: 88, date: date, pending: false, category: "TRANSFER_OUT", removed: false)
        let transfer = CashTransfer(name: "Reviewable movement", amount: 88, date: date, fromAccountName: "Checking", toAccountName: "External account", note: "[PLAID_SINGLE:persist-1]", plaidSourceTransactions: [source], plaidRejectedCounterpartIds: ["rejected-other"])
        let encoded = try! JSONEncoder().encode(transfer)
        let decoded = try! JSONDecoder().decode(CashTransfer.self, from: encoded)
        assert(decoded.plaidSourceTransactions?.first?.id == "persist-1", "Original Plaid source details must survive JSON persistence")
        assert(decoded.plaidRejectedCounterpartIds == ["rejected-other"], "Rejected counterpart choices must survive JSON persistence")

        let legacyJSON = """
        {"id":"00000000-0000-0000-0000-000000000042","name":"Old Transfer","amount":42,"date":781050000,"fromAccountName":"Checking","toAccountName":"Savings","fromAccountId":null,"toAccountId":null,"note":""}
        """
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .secondsSince1970
        let legacy = try! legacyDecoder.decode(CashTransfer.self, from: Data(legacyJSON.utf8))
        assert(legacy.plaidSourceTransactions == nil && legacy.plaidRejectedCounterpartIds == nil, "Older transfer snapshots must still decode without the new optional fields")
    }

    private static func testPlaidUnknownCardCreditRequiresReview() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_781_060_000)
        let accounts = [
            PlaidSyncedAccount(id: "unknown-bank", itemId: "unknown-item", name: "Checking", type: .depository, subtype: "checking", currentBalance: 1000, availableBalance: 1000, creditLimit: nil, institutionName: "Bank"),
            PlaidSyncedAccount(id: "unknown-card", itemId: "unknown-item", name: "Rewards Card", type: .credit, subtype: "credit card", currentBalance: 100, availableBalance: 1900, creditLimit: 2000, institutionName: "Bank")
        ]
        let cardCredit = PlaidSyncedTransaction(id: "unknown-card-credit", accountId: "unknown-card", itemId: "unknown-item", name: "ACH CREDIT", merchantName: nil, amount: -63, date: date, pending: false, category: "TRANSFER_IN", removed: false)
        let bankDebit = PlaidSyncedTransaction(id: "unknown-bank-debit", accountId: "unknown-bank", itemId: "unknown-item", name: "ACH DEBIT", merchantName: nil, amount: 63, date: date, pending: false, category: "TRANSFER_OUT", removed: false)
        func batch(_ transactions: [PlaidSyncedTransaction]) -> PlaidSyncPayload {
            PlaidSyncPayload(accounts: accounts, transactions: transactions, creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: [])
        }
        _ = budget.applyPlaidSyncReconciled(batch([cardCredit]))
        assert(budget.incomes.isEmpty, "An unidentified credit to a credit-card account must not count as income")
        assert(budget.cashTransfers.count == 1 && budget.cashTransfers[0].note.hasPrefix("[PLAID_SINGLE:"), "Unknown card credit should be safely unpaired for review")
        _ = budget.applyPlaidSyncReconciled(batch([bankDebit]))
        assert(!budget.cashTransfers.contains(where: { $0.note.hasPrefix("[PLAID_PAIR:") }), "Generic ACH on both accounts must not auto-link")
        assert(budget.plaidTransferReviewCandidates(sourceId: "unknown-card-credit").contains(where: { $0.id == "unknown-bank-debit" }), "Review must offer actual observed checking debit as a possible card payment")
        assert(budget.confirmPlaidTransferReview(sourceId: "unknown-card-credit", counterpartId: "unknown-bank-debit"), "Manual review can classify a generic card credit as a payment")
        assert(budget.cashTransfers.count == 1 && budget.expenses.isEmpty && budget.incomes.isEmpty, "Confirmed card payment must not inflate spending or income")

        let separate = BudgetModel()
        let refund = PlaidSyncedTransaction(id: "store-refund", accountId: "unknown-card", itemId: "unknown-item", name: "STORE REFUND", merchantName: nil, amount: -15, date: date, pending: false, category: "REFUND", removed: false)
        _ = separate.applyPlaidSyncReconciled(batch([refund]))
        assert(separate.cashTransfers.isEmpty, "An explicitly identified merchant refund is not a card payment")
    }


    /// Synthetic checking-account withdrawal converted into an owned-account transfer.
    /// Classifying the Plaid debit as a transfer does not create a fake credit
    /// on the receiving account, alter Plaid balances, or inflate spending.
    private static func testPlaidUserReclassifiedBankTransferSurvivesReplay() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_782_000_000)
        let source = PlaidSyncedAccount(id: "example-check-abc", itemId: "example-item-a", name: "Example Checking", type: .depository, subtype: "checking", currentBalance: 1400, availableBalance: 1400, creditLimit: nil, institutionName: "Example Bank")
        let target = PlaidSyncedAccount(id: "owned-receiver", itemId: "item-receiver", name: "Example Savings", type: .depository, subtype: "checking", currentBalance: 2200, availableBalance: 2200, creditLimit: nil, institutionName: "Other Bank")
        let original = PlaidSyncedTransaction(id: "synthetic-transfer-137", accountId: source.id, itemId: source.itemId, name: "Monthly Savings Withdrawal", merchantName: nil, amount: 137.42, date: date, pending: false, category: "TRANSFER_OUT", removed: false)
        let payload = PlaidSyncPayload(accounts: [source, target], transactions: [original], creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: [])
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.expenses.count == 1, "Example Bank withdrawal starts as an imported expense before user reclassification")
        let imported = budget.expenses[0]
        guard let destinationId = budget.financialAccounts.first(where: { $0.externalAccountId == target.id })?.id else {
            assertionFailure("Synthetic receiving bank account must exist")
            return
        }
        var revised = imported
        revised.userClassifiedTransfer = true
        revised.transferDestinationAccountId = destinationId
        revised.transferDestinationAccountName = "Example Savings"
        revised.plaidMetadata = nil // Simulates legacy editor recreating Expense without metadata.
        budget.updateExpense(revised)

        assert(budget.expenses.count == 1, "Manual transfer classification must not create a duplicate expense")
        assert(budget.expenses[0].plaidMetadata?.transactionId == original.id, "Plaid original ID must survive editing")
        assert(budget.isExcludedFromSpending(budget.expenses[0]), "User-classified transfer must not count in Needs or Wants")
        assert(budget.cashTransfers.isEmpty, "Transfer conversion must not invent a receiving account deposit")
        assert(budget.bankAccounts.first(where: { $0.name == "Example Savings" })?.balance == 2200, "Destination Plaid balance must not be changed by classification")
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.expenses.count == 1 && budget.cashTransfers.isEmpty, "Resync must preserve user's transfer choice without adding phantom rows")
        assert(budget.expenses[0].transferDestinationAccountId == destinationId, "Destination selection must survive Plaid replay")

        var reverted = budget.expenses[0]
        reverted.userClassifiedTransfer = nil
        reverted.transferDestinationAccountId = nil
        reverted.transferDestinationAccountName = nil
        budget.updateExpense(reverted)
        assert(!budget.isExcludedFromSpending(budget.expenses[0]), "User can undo transfer classification from expense editor")
    }

    /// Synthetic checking-account debit converted into a card payment.
    /// The card-side account transaction is never invented by this manual tag.
    private static func testPlaidUserReclassifiedCardPaymentSurvivesReplay() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_782_010_000)
        let checking = PlaidSyncedAccount(id: "example-check-card", itemId: "example-item-a", name: "Example Checking", type: .depository, subtype: "checking", currentBalance: 1100, availableBalance: 1100, creditLimit: nil, institutionName: "Example Bank")
        let robinhood = PlaidSyncedAccount(id: "rh-card", itemId: "example-item-b", name: "Example Credit Card", type: .credit, subtype: "credit card", currentBalance: 800, availableBalance: 1200, creditLimit: 2000, institutionName: "Example Card Issuer")
        let debit = PlaidSyncedTransaction(id: "synthetic-card-81", accountId: checking.id, itemId: checking.itemId, name: "Example Card Issuer", merchantName: nil, amount: 81.27, date: date, pending: false, category: "TRANSFER_OUT", removed: false)
        let payload = PlaidSyncPayload(accounts: [checking, robinhood], transactions: [debit], creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: [])
        _ = budget.applyPlaidSyncReconciled(payload)
        guard let imported = budget.expenses.first(where: { $0.plaidMetadata?.transactionId == debit.id }),
              let cardId = budget.financialAccounts.first(where: { $0.externalAccountId == robinhood.id })?.id else {
            assertionFailure("Synthetic checking debit and credit card must be imported")
            return
        }
        var revised = imported
        revised.creditCardPaymentTarget = "Example Credit Card"
        revised.creditCardPaymentTargetId = cardId
        revised.plaidMetadata = nil
        budget.updateExpense(revised)
        assert(budget.isCreditCardPayment(budget.expenses[0]), "User-selected Example Card Issuer card payment should not count as spending")
        assert(budget.expenses[0].plaidMetadata?.transactionId == debit.id, "Card-payment edit retains original Plaid transaction ID")
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.expenses.count == 1 && budget.cashTransfers.isEmpty, "Card-payment edit replay must not duplicate checking outflow or fake the card credit")
        assert(budget.isExcludedFromSpending(budget.expenses[0]), "Paid card balance should not double count the purchase as new spending")
    }

    private static func testPlaidExpenseTransferCodableMigration() {
        let destination = UUID()
        let entry = Expense(
            name: "Synthetic owned-account transfer",
            amount: 27,
            section: .needs,
            categoryId: UUID(),
            paymentAccount: "Checking",
            transferDestinationAccountId: destination,
            transferDestinationAccountName: "My Savings",
            userClassifiedTransfer: true
        )
        let encoded = try! JSONEncoder().encode(entry)
        let roundTripped = try! JSONDecoder().decode(Expense.self, from: encoded)
        assert(roundTripped.userClassifiedTransfer == true && roundTripped.transferDestinationAccountId == destination, "Manual transfer classification and destination must survive JSON persistence")

        let legacy = Expense(name: "Legacy bill", amount: 19, section: .needs, categoryId: UUID())
        let decoded = try! JSONDecoder().decode(Expense.self, from: JSONEncoder().encode(legacy))
        assert(decoded.userClassifiedTransfer == nil && decoded.transferDestinationAccountId == nil, "Pre-transfer expenses remain safely readable")
    }


    private static func testPlaidManualDestinationCannotBePairedWithWrongBank() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_782_020_000)
        let checking = PlaidSyncedAccount(id: "chosen-source", itemId: "chosen-item", name: "Checking", type: .depository, subtype: "checking", currentBalance: 900, availableBalance: 900, creditLimit: nil, institutionName: "Bank")
        let savings = PlaidSyncedAccount(id: "chosen-destination", itemId: "chosen-item", name: "Savings", type: .depository, subtype: "savings", currentBalance: 900, availableBalance: 900, creditLimit: nil, institutionName: "Bank")
        let unrelated = PlaidSyncedAccount(id: "wrong-destination", itemId: "chosen-item", name: "Other Bank", type: .depository, subtype: "checking", currentBalance: 900, availableBalance: 900, creditLimit: nil, institutionName: "Bank")
        let outgoing = PlaidSyncedTransaction(id: "chosen-debit", accountId: checking.id, itemId: checking.itemId, name: "Monthly Savings Withdrawal", merchantName: nil, amount: 77, date: date, pending: false, category: "TRANSFER_OUT", removed: false)
        let incoming = PlaidSyncedTransaction(id: "chosen-credit", accountId: savings.id, itemId: savings.itemId, name: "ACH CREDIT", merchantName: nil, amount: -77, date: date, pending: false, category: "TRANSFER_IN", removed: false)
        let distractor = PlaidSyncedTransaction(id: "wrong-credit", accountId: unrelated.id, itemId: unrelated.itemId, name: "ACH CREDIT", merchantName: nil, amount: -77, date: date, pending: false, category: "TRANSFER_IN", removed: false)
        func payload(_ transactions: [PlaidSyncedTransaction]) -> PlaidSyncPayload {
            PlaidSyncPayload(accounts: [checking, savings, unrelated], transactions: transactions, creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: [])
        }
        _ = budget.applyPlaidSyncReconciled(payload([outgoing]))
        guard let original = budget.expenses.first(where: { $0.plaidMetadata?.transactionId == outgoing.id }),
              let chosenId = budget.financialAccounts.first(where: { $0.externalAccountId == savings.id })?.id else {
            assertionFailure("Synthetic source and chosen destination must import")
            return
        }
        var updated = original
        updated.userClassifiedTransfer = true
        updated.transferDestinationAccountId = chosenId
        updated.transferDestinationAccountName = savings.name
        budget.updateExpense(updated)
        _ = budget.applyPlaidSyncReconciled(payload([incoming, distractor]))
        assert(budget.cashTransfers.count == 1 && budget.cashTransfers[0].toAccountId == chosenId,
               "User-chosen Savings must match an observed credit there, not the unrelated same-dollar account")
        assert(!budget.cashTransfers.contains(where: { $0.toAccountName == "Other Bank" }),
               "Wrong destination must not receive the transfer")
        assert(budget.cashTransfers[0].note.hasPrefix("[PLAID_PAIR:"), "A uniquely verified bank credit should become one linked pair")
    }

    private static func testPlaidOneSidedTransferDescriptionPairsACHCredit() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_780_240_000)
        let payload = PlaidSyncPayload(
            accounts: [
                PlaidSyncedAccount(id: "single-check", itemId: "bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank"),
                PlaidSyncedAccount(id: "single-save", itemId: "bank", name: "Savings", type: .depository, subtype: "savings", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank")
            ],
            transactions: [
                PlaidSyncedTransaction(id: "single-out", accountId: "single-check", itemId: "bank", name: "TRANSFER TO SAVINGS", merchantName: nil, amount: 300, date: date, pending: false, category: "TRANSFER_OUT", removed: false),
                PlaidSyncedTransaction(id: "single-in", accountId: "single-save", itemId: "bank", name: "ACH CREDIT", merchantName: nil, amount: -300, date: date, pending: false, category: "TRANSFER_IN", removed: false)
            ],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.count == 1, "A verified bank transfer should match even if the receiving bank calls it ACH CREDIT")
        assert(budget.cashTransfers[0].fromAccountName == "Checking" && budget.cashTransfers[0].toAccountName == "Savings", "Corroborated ACH matching must preserve direction")
        assert(budget.expenses.isEmpty && budget.incomes.isEmpty, "Real bank transfers should not affect spending or income")
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.count == 1, "The one-sided-description case must also be idempotent")
    }

    private static func testPlaidManualTransferReviewPersists() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_780_245_000)
        let payload = PlaidSyncPayload(
            accounts: [
                PlaidSyncedAccount(id: "manual-check", itemId: "bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank"),
                PlaidSyncedAccount(id: "manual-save", itemId: "bank", name: "Savings", type: .depository, subtype: "savings", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank")
            ],
            transactions: [
                PlaidSyncedTransaction(id: "manual-out", accountId: "manual-check", itemId: "bank", name: "ACH DEBIT", merchantName: nil, amount: 150, date: date, pending: false, category: "TRANSFER_OUT", removed: false),
                PlaidSyncedTransaction(id: "manual-in", accountId: "manual-save", itemId: "bank", name: "ACH CREDIT", merchantName: nil, amount: -150, date: date, pending: false, category: "TRANSFER_IN", removed: false)
            ],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.isEmpty, "Two generic ACH labels alone must not auto-link bank accounts")
        assert(budget.plaidPotentialTransferReviews().contains(where: { $0.id == "manual-out" }), "Uncertain but possible matches must appear in review mode")
        assert(budget.plaidTransferReviewCandidates(sourceId: "manual-out").count == 1, "Review mode should show the actual receiving bank transaction")
        assert(budget.confirmPlaidTransferReview(sourceId: "manual-out", counterpartId: "manual-in"), "User confirmation should create a real linked transfer")
        assert(budget.cashTransfers.count == 1 && budget.cashTransfers[0].note.contains("[USER_CONFIRMED]"), "Confirmed transfers must be marked durable")
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.count == 1 && budget.expenses.isEmpty && budget.incomes.isEmpty, "User-reviewed matching must survive replay without duplicates")

        // A subsequent explicit deletion overrides the former manual match:
        // do not retain a phantom receiving account or discard the ACH debit.
        let removedCounterpart = PlaidSyncedTransaction(
            id: "manual-in", accountId: "manual-save", itemId: "bank",
            name: "ACH CREDIT", merchantName: nil, amount: -150,
            date: date, pending: false, category: "TRANSFER_IN", removed: true
        )
        _ = budget.applyPlaidSyncReconciled(
            PlaidSyncPayload(
                accounts: payload.accounts,
                transactions: [payload.transactions[0], removedCounterpart],
                creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
            )
        )
        assert(budget.cashTransfers.isEmpty, "Removed user-confirmed counterpart must invalidate its old pair")
        assert(budget.expenses.count == 1 && budget.incomes.isEmpty, "Surviving ACH debit should be restored as an expense without a phantom credit")
    }

    private static func testPlaidReviewKeepAsWithdrawalPersists() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_780_246_000)
        let payload = PlaidSyncPayload(
            accounts: [
                PlaidSyncedAccount(id: "expense-check", itemId: "bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank")
            ],
            transactions: [
                PlaidSyncedTransaction(id: "expense-out", accountId: "expense-check", itemId: "bank", name: "TRANSFER TO OUTSIDE ACCOUNT", merchantName: nil, amount: 85, date: date, pending: false, category: "TRANSFER_OUT", removed: false)
            ],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.count == 1, "Unpaired explicitly identified transfers start in review")
        assert(budget.keepPlaidWithdrawalAsExpense(sourceId: "expense-out"), "Review should allow a user to keep the actual debit as a withdrawal")
        assert(budget.cashTransfers.isEmpty && budget.expenses.count == 1, "Reviewed withdrawal must not claim any receiving bank")
        assert(budget.expenses[0].plaidMetadata?.userConfirmedNotTransfer == true, "Decision must be saved with Plaid transaction metadata")
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.isEmpty && budget.expenses.count == 1, "The reviewed withdrawal must stay an expense on future sync")
    }

    private static func testPlaidUnrelatedMatchingAmountDoesNotPair() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_780_250_000)
        let payload = PlaidSyncPayload(
            accounts: [
                PlaidSyncedAccount(id: "unrelated-check", itemId: "bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank"),
                PlaidSyncedAccount(id: "unrelated-save", itemId: "bank", name: "Savings", type: .depository, subtype: "savings", currentBalance: 700, availableBalance: 700, creditLimit: nil, institutionName: "Bank")
            ],
            transactions: [
                PlaidSyncedTransaction(id: "unrelated-transfer", accountId: "unrelated-check", itemId: "bank", name: "TRANSFER TO EXTERNAL ACCOUNT", merchantName: nil, amount: 120, date: date, pending: false, category: "TRANSFER_OUT", removed: false),
                PlaidSyncedTransaction(id: "unrelated-paycheck", accountId: "unrelated-save", itemId: "bank", name: "ACH CREDIT PAYROLL", merchantName: nil, amount: -120, date: date, pending: false, category: "TRANSFER_IN", removed: false)
            ],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.incomes.count == 1 && budget.cashTransfers.count == 1, "A same-amount paycheck must not become the other side of a transfer")
        assert(budget.cashTransfers[0].toAccountId == nil, "Unpaired transfer must not point to an unrelated linked savings account")
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.incomes.count == 1 && budget.cashTransfers.count == 1, "Repeated sync must not introduce a false account match")
    }

    private static func testPlaidAmbiguousTransfersStayUnpaired() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_780_300_000)
        let accounts = [
            PlaidSyncedAccount(id: "amb-a", itemId: "bank", name: "Checking A", type: .depository, subtype: "checking", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank"),
            PlaidSyncedAccount(id: "amb-b", itemId: "bank", name: "Checking B", type: .depository, subtype: "checking", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank"),
            PlaidSyncedAccount(id: "amb-save", itemId: "bank", name: "Savings", type: .depository, subtype: "savings", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank")
        ]
        let payload = PlaidSyncPayload(
            accounts: accounts,
            transactions: [
                PlaidSyncedTransaction(id: "amb-out-a", accountId: "amb-a", itemId: "bank", name: "TRANSFER", merchantName: nil, amount: 175, date: date, pending: false, category: "TRANSFER_OUT", removed: false),
                PlaidSyncedTransaction(id: "amb-out-b", accountId: "amb-b", itemId: "bank", name: "TRANSFER", merchantName: nil, amount: 175, date: date, pending: false, category: "TRANSFER_OUT", removed: false),
                PlaidSyncedTransaction(id: "amb-in", accountId: "amb-save", itemId: "bank", name: "TRANSFER", merchantName: nil, amount: -175, date: date, pending: false, category: "TRANSFER_IN", removed: false)
            ],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.count == 3, "Ambiguous sides should remain three independently reviewable movements")
        assert(budget.cashTransfers.allSatisfy { $0.fromAccountId == nil || $0.toAccountId == nil }, "An ambiguous match must not claim another linked bank account")
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.count == 3, "Ambiguity must not disappear after replay or pairing order changes")
    }

    private static func testPlaidLegacyMispairedTransferIsRemovedOnReplay() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_780_400_000)
        budget.cashTransfers = [
            CashTransfer(name: "Bad Plaid match", amount: 90, date: date, fromAccountName: "Checking", toAccountName: "Savings", note: "[PLAID_PAIR:legacy-ach|legacy-income] Synced from Plaid transaction pair"),
            CashTransfer(name: "Manual transfer", amount: 10, date: date, fromAccountName: "Checking", toAccountName: "Savings", note: "Created by user")
        ]
        let payload = PlaidSyncPayload(
            accounts: [
                PlaidSyncedAccount(id: "legacy-check", itemId: "bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank"),
                PlaidSyncedAccount(id: "legacy-save", itemId: "bank", name: "Savings", type: .depository, subtype: "savings", currentBalance: 600, availableBalance: 600, creditLimit: nil, institutionName: "Bank")
            ],
            transactions: [
                PlaidSyncedTransaction(id: "legacy-ach", accountId: "legacy-check", itemId: "bank", name: "ACH DEBIT UTILITIES", merchantName: nil, amount: 90, date: date, pending: false, category: "TRANSFER_OUT", removed: false),
                PlaidSyncedTransaction(id: "legacy-income", accountId: "legacy-save", itemId: "bank", name: "ACH CREDIT PAYROLL", merchantName: nil, amount: -90, date: date, pending: false, category: "TRANSFER_IN", removed: false)
            ],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(payload)
        assert(budget.cashTransfers.count == 1 && budget.cashTransfers[0].note == "Created by user", "A legacy coincidental Plaid pair should be removed without touching manual transfers")
        assert(budget.expenses.count == 1 && budget.incomes.count == 1, "Previously mispaired transactions should be reclassified with their original directions")
    }

    private static func testPlaidRemovedTransactionClearsPairedTransfer() {
        let budget = BudgetModel()
        let date = Date(timeIntervalSince1970: 1_780_500_000)
        let accounts = [
            PlaidSyncedAccount(id: "remove-check", itemId: "bank", name: "Checking", type: .depository, subtype: "checking", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank"),
            PlaidSyncedAccount(id: "remove-save", itemId: "bank", name: "Savings", type: .depository, subtype: "savings", currentBalance: 500, availableBalance: 500, creditLimit: nil, institutionName: "Bank")
        ]
        let original = PlaidSyncPayload(
            accounts: accounts,
            transactions: [
                PlaidSyncedTransaction(id: "remove-out", accountId: "remove-check", itemId: "bank", name: "TRANSFER TO SAVINGS", merchantName: nil, amount: 60, date: date, pending: false, category: "TRANSFER_OUT", removed: false),
                PlaidSyncedTransaction(id: "remove-in", accountId: "remove-save", itemId: "bank", name: "TRANSFER FROM CHECKING", merchantName: nil, amount: -60, date: date, pending: false, category: "TRANSFER_IN", removed: false)
            ],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(original)
        assert(budget.cashTransfers.count == 1, "The initial verified transfer should be imported")
        let removed = PlaidSyncPayload(
            accounts: accounts,
            transactions: [
                PlaidSyncedTransaction(id: "remove-out", accountId: "remove-check", itemId: "bank", name: "TRANSFER TO SAVINGS", merchantName: nil, amount: 60, date: date, pending: false, category: "TRANSFER_OUT", removed: true)
            ],
            creditLiabilities: [], holdings: [], investmentTransactions: [], connectionStatuses: []
        )
        _ = budget.applyPlaidSyncReconciled(removed)
        assert(budget.cashTransfers.isEmpty, "Removing a Plaid transaction must clear its auto-generated transfer pair")
    }

    private static func testPlaidCreditAccountUpdateUsesLiabilityFields() {
        let budget = BudgetModel()

        _ = budget.applyPlaidSync(
            PlaidSyncPayload(
                accounts: [
                    PlaidSyncedAccount(id: "cc-1", itemId: "item-1", name: "Travel Card", type: .credit, subtype: "credit card", currentBalance: 321.12, availableBalance: nil, creditLimit: 5_000, institutionName: "Card Bank")
                ],
                transactions: [],
                creditLiabilities: [
                    PlaidSyncedCreditLiability(accountId: "cc-1", itemId: "item-1", minimumPaymentAmount: 35, nextPaymentDueDate: Date(timeIntervalSince1970: 1_780_500_000), lastStatementBalance: 300, lastStatementIssueDate: nil, aprPercentage: 22.9)
                ],
                holdings: [],
                investmentTransactions: [],
                connectionStatuses: []
            )
        )

        let account = budget.creditAccounts.first
        assert(account?.name == "Travel Card", "Expected Plaid credit account to be created")
        assert(account?.startingBalance == 321.12, "Expected current balance to update starting balance for Plaid-managed card")
        assert(account?.creditLimit == 5_000, "Expected credit limit to come from Plaid")
        assert(account?.expectedAmount == 35, "Expected minimum payment to update expected amount")
    }

    private static func testPlaidHoldingsSnapshotPreservesTickerMetadata() {
        let budget = BudgetModel()
        budget.holdings = [
            PortfolioHolding(
                ticker: "AAPL",
                shares: 1,
                averageCost: 100,
                currentPrice: 150,
                annualDividendPerShare: 0.96,
                dividendFrequency: .quarterly,
                assetType: .dividendStock,
                dividendReliability: .high,
                notes: "Core holding"
            )
        ]

        _ = budget.applyPlaidSync(
            PlaidSyncPayload(
                accounts: [],
                transactions: [],
                creditLiabilities: [],
                holdings: [
                    PlaidSyncedHolding(accountId: "inv-1", itemId: "item-1", securityId: "sec-aapl", ticker: "aapl", name: "Apple Inc.", quantity: 3, costBasis: 330, institutionPrice: 180, institutionValue: 540, priceAsOf: nil)
                ],
                investmentTransactions: [],
                connectionStatuses: []
            )
        )

        let holding = budget.holdings.first { $0.plaidMetadata?.accountId == "inv-1" }
        assert(holding?.ticker == "AAPL", "Expected Plaid ticker to be normalized")
        assert(holding?.shares == 3, "Expected shares to come from Plaid holdings snapshot")
        assert(holding?.annualDividendPerShare == 0.96, "Expected manual dividend metadata to be preserved")
        assert(holding?.dividendReliability == .high, "Expected manual reliability metadata to be preserved")
        assert(holding?.notes == "Core holding", "Expected manual notes to be preserved")
    }

    private static func testPlaidWatchlistImportDedupesAndUppercases() {
        let budget = BudgetModel()
        budget.watchlistTickers = ["AAPL"]

        _ = budget.applyPlaidSync(
            PlaidSyncPayload(
                accounts: [],
                transactions: [],
                creditLiabilities: [],
                holdings: [
                    PlaidSyncedHolding(accountId: "inv-1", itemId: "item-1", securityId: "sec-msft", ticker: "msft", name: "Microsoft", quantity: 2, costBasis: 100, institutionPrice: 410, institutionValue: 820, priceAsOf: nil),
                    PlaidSyncedHolding(accountId: "inv-1", itemId: "item-1", securityId: "sec-aapl", ticker: "aapl", name: "Apple", quantity: 1, costBasis: 100, institutionPrice: 180, institutionValue: 180, priceAsOf: nil)
                ],
                investmentTransactions: [],
                connectionStatuses: []
            )
        )

        assert(budget.watchlistTickers == ["AAPL", "MSFT"], "Expected Plaid holdings tickers to be uppercase and deduped into watchlist")
    }

    private static func testPlaidOptionHoldingsDoNotImportAsStockTickers() {
        let budget = BudgetModel()
        budget.watchlistTickers = ["AAPL", "GOOGL251010P00240000"]
        budget.holdings = [
            PortfolioHolding(
                ticker: "GOOGL251010P00240000",
                shares: 1,
                averageCost: 2,
                currentPrice: 0,
                plaidMetadata: PlaidSourceMetadata(itemId: "item-1", accountId: "inv-1", securityId: "sec-option")
            )
        ]

        _ = budget.applyPlaidSync(
            PlaidSyncPayload(
                accounts: [],
                transactions: [],
                creditLiabilities: [],
                holdings: [
                    PlaidSyncedHolding(accountId: "inv-1", itemId: "item-1", securityId: "sec-aapl", ticker: "aapl", name: "Apple", quantity: 2, costBasis: 300, institutionPrice: 180, institutionValue: 360, priceAsOf: nil, securityType: "equity"),
                    PlaidSyncedHolding(accountId: "inv-1", itemId: "item-1", securityId: "sec-googl-put", ticker: "GOOGL251010P00240000", name: "GOOGL option", quantity: 1, costBasis: 2, institutionPrice: 0, institutionValue: -2, priceAsOf: nil, securityType: "derivative"),
                    PlaidSyncedHolding(accountId: "inv-1", itemId: "item-1", securityId: "sec-avgo-put", ticker: "AVGO251010P00325000", name: "AVGO option", quantity: 1, costBasis: 1, institutionPrice: 0, institutionValue: -1, priceAsOf: nil, securityType: nil)
                ],
                investmentTransactions: [],
                connectionStatuses: []
            )
        )

        assert(budget.holdings.map(\.ticker) == ["AAPL"], "Expected Plaid option contracts to be excluded from portfolio holdings")
        assert(budget.watchlistTickers == ["AAPL"], "Expected existing option contract tickers to be removed from watchlist on Plaid sync")
    }

    private static func testPlaidCashHoldingFeedsCashAndMarginBalances() {
        let budget = BudgetModel()
        budget.watchlistTickers = ["CUR:USD", "AAPL"]

        _ = budget.applyPlaidSync(
            PlaidSyncPayload(
                accounts: [
                    PlaidSyncedAccount(id: "inv-cash", itemId: "item-1", name: "Cash Brokerage", type: .investment, subtype: "brokerage", currentBalance: 485.50, availableBalance: 999, creditLimit: nil, institutionName: "Broker"),
                    PlaidSyncedAccount(id: "inv-margin", itemId: "item-1", name: "Margin Brokerage", type: .investment, subtype: "brokerage", currentBalance: 285, availableBalance: -999, creditLimit: nil, institutionName: "Broker")
                ],
                transactions: [],
                creditLiabilities: [],
                holdings: [
                    PlaidSyncedHolding(accountId: "inv-cash", itemId: "item-1", securityId: "sec-aapl", ticker: "AAPL", name: "Apple", quantity: 2, costBasis: 300, institutionPrice: 180, institutionValue: 360, priceAsOf: nil, securityType: "equity"),
                    PlaidSyncedHolding(accountId: "inv-cash", itemId: "item-1", securityId: "cash-usd-1", ticker: "CUR:USD", name: "US Dollar", quantity: 125.50, costBasis: nil, institutionPrice: 1, institutionValue: 125.50, priceAsOf: nil, securityType: "cash"),
                    PlaidSyncedHolding(accountId: "inv-margin", itemId: "item-1", securityId: "sec-msft", ticker: "MSFT", name: "Microsoft", quantity: 1, costBasis: 300, institutionPrice: 360, institutionValue: 360, priceAsOf: nil, securityType: "equity"),
                    PlaidSyncedHolding(accountId: "inv-margin", itemId: "item-1", securityId: "cash-usd-2", ticker: "CUR:USD", name: "US Dollar", quantity: -75, costBasis: nil, institutionPrice: 1, institutionValue: -75, priceAsOf: nil, securityType: "cash")
                ],
                investmentTransactions: [],
                connectionStatuses: []
            )
        )

        let cashAccount = budget.portfolioAccounts.first { $0.name == "Cash Brokerage" }
        let marginAccount = budget.portfolioAccounts.first { $0.name == "Margin Brokerage" }
        assert(cashAccount?.cashBalance == 125.50, "Expected CUR:USD positive value to become brokerage cash balance")
        assert(cashAccount?.marginBalance == 0, "Expected positive CUR:USD cash not to create margin")
        assert(marginAccount?.cashBalance == 0, "Expected negative CUR:USD value not to remain as negative cash")
        assert(marginAccount?.marginBalance == 75, "Expected negative CUR:USD value to become margin used")
        assert(!budget.holdings.contains(where: { $0.ticker == "CUR:USD" }), "Expected CUR:USD to be excluded from holdings")
        assert(!budget.watchlistTickers.contains("CUR:USD"), "Expected CUR:USD to be excluded from watchlist")
        assert(budget.portfolioSnapshot.cashBalance == 125.50, "Expected All Portfolios cash to aggregate positive cash balances")
        assert(budget.portfolioSnapshot.marginUsed == 75, "Expected All Portfolios margin to aggregate negative cash balances")
    }

    private static func testPlaidDuplicateTickerHoldingsStayAccountScoped() {
        let budget = BudgetModel()

        _ = budget.applyPlaidSync(
            PlaidSyncPayload(
                accounts: [
                    PlaidSyncedAccount(id: "inv-1", itemId: "item-1", name: "Brokerage A", type: .investment, subtype: "brokerage", currentBalance: 180, availableBalance: 0, creditLimit: nil, institutionName: "Broker A"),
                    PlaidSyncedAccount(id: "inv-2", itemId: "item-2", name: "Brokerage B", type: .investment, subtype: "brokerage", currentBalance: 362, availableBalance: 0, creditLimit: nil, institutionName: "Broker B")
                ],
                transactions: [],
                creditLiabilities: [],
                holdings: [
                    PlaidSyncedHolding(accountId: "inv-1", itemId: "item-1", securityId: "sec-aapl-1", ticker: "AAPL", name: "Apple", quantity: 1, costBasis: 100, institutionPrice: 180, institutionValue: 180, priceAsOf: nil, securityType: "equity"),
                    PlaidSyncedHolding(accountId: "inv-2", itemId: "item-2", securityId: "sec-aapl-2", ticker: "AAPL", name: "Apple", quantity: 2, costBasis: 260, institutionPrice: 181, institutionValue: 362, priceAsOf: nil, securityType: "equity")
                ],
                investmentTransactions: [],
                connectionStatuses: []
            )
        )

        let aaplHoldings = budget.holdings.filter { $0.ticker == "AAPL" }
        assert(aaplHoldings.count == 2, "Expected same ticker to remain as two brokerage-scoped positions")
        assert(Set(aaplHoldings.compactMap(\.portfolioAccountId)).count == 2, "Expected each Plaid holding to retain a different portfolio account ID")
        assert(aaplHoldings.map(\.shares).sorted() == [1, 2], "Expected brokerage quantities to remain independent")

        let aggregate = budget.consolidatedHoldings.first { $0.ticker == "AAPL" }
        assert(aggregate?.shares == 3, "Expected All Portfolios to sum same-ticker shares")
        assert(abs((aggregate?.averageCost ?? 0) - 120) < 0.001, "Expected All Portfolios average cost to be share weighted")
        assert(aggregate?.portfolioAccountId == nil, "Expected All Portfolios holding to be derived rather than tied to one brokerage")
    }

    private static func testManualSameTickerHoldingsStayAccountScoped() {
        let accountA = PortfolioAccount(name: "Brokerage A", cashBalance: 1_000)
        let accountB = PortfolioAccount(name: "Brokerage B", cashBalance: 1_000)
        let budget = BudgetModel()
        budget.portfolioAccounts = [accountA, accountB]
        budget.portfolioTransactions = []
        budget.holdings = []
        budget.portfolioSnapshot.cashBalance = 0
        budget.portfolioSnapshot.marginUsed = 0

        budget.addPortfolioTransaction(
            PortfolioTransaction(type: .buy, ticker: "AAPL", shares: 2, pricePerShare: 100, amount: 200, portfolioAccountId: accountA.id)
        )
        budget.addPortfolioTransaction(
            PortfolioTransaction(type: .buy, ticker: "AAPL", shares: 3, pricePerShare: 150, amount: 450, portfolioAccountId: accountB.id)
        )

        let positions = budget.holdings.filter { $0.ticker == "AAPL" }
        assert(positions.count == 2, "Expected manual same-ticker buys to produce two account-scoped holdings")
        let holdingA = positions.first { $0.portfolioAccountId == accountA.id }
        let holdingB = positions.first { $0.portfolioAccountId == accountB.id }
        assert(holdingA?.shares == 2 && holdingA?.averageCost == 100, "Expected Brokerage A quantity and cost basis to stay isolated")
        assert(holdingB?.shares == 3 && holdingB?.averageCost == 150, "Expected Brokerage B quantity and cost basis to stay isolated")

        let aggregate = budget.consolidatedHoldings.first { $0.ticker == "AAPL" }
        assert(aggregate?.shares == 5, "Expected All Portfolios to sum manual same-ticker shares")
        assert(abs((aggregate?.averageCost ?? 0) - 130) < 0.001, "Expected aggregate manual cost basis to be weighted correctly")
    }

    private static func testPortfolioCashAndMarginStayAccountScoped() {
        let accountA = PortfolioAccount(name: "Brokerage A", cashBalance: 100)
        let accountB = PortfolioAccount(name: "Brokerage B", cashBalance: 25)
        let budget = BudgetModel()
        budget.portfolioAccounts = [accountA, accountB]
        budget.portfolioTransactions = []
        budget.holdings = []
        budget.portfolioSnapshot.cashBalance = 0
        budget.portfolioSnapshot.marginUsed = 0

        budget.addPortfolioTransaction(
            PortfolioTransaction(type: .buy, ticker: "MSFT", shares: 1, pricePerShare: 200, amount: 200, portfolioAccountId: accountA.id)
        )
        budget.addPortfolioTransaction(
            PortfolioTransaction(type: .buy, ticker: "NVDA", shares: 1, pricePerShare: 75, amount: 75, portfolioAccountId: accountB.id)
        )

        let refreshedA = budget.portfolioAccounts.first { $0.id == accountA.id }
        let refreshedB = budget.portfolioAccounts.first { $0.id == accountB.id }
        assert(refreshedA?.cashBalance == 0 && refreshedA?.marginBalance == 100, "Expected Brokerage A cash and margin to update independently")
        assert(refreshedB?.cashBalance == 0 && refreshedB?.marginBalance == 50, "Expected Brokerage B cash and margin to update independently")
        assert(budget.portfolioSnapshot.cashBalance == 0, "Expected All Portfolios cash to equal account cash total")
        assert(budget.portfolioSnapshot.marginUsed == 150, "Expected All Portfolios margin to equal account margin total")
    }

    private static func testFinancialAccountCodableRoundTrip() {
        let financialAccount = FinancialAccount(
            name: "Brokerage",
            institutionName: "Example Broker",
            kind: .investment,
            source: .plaid,
            externalAccountId: "investment-1",
            externalItemId: "item-1"
        )
        let portfolioAccount = PortfolioAccount(
            financialAccountId: financialAccount.id,
            name: "Brokerage",
            cashBalance: 125.50,
            marginBalance: 40
        )

        let decodedFinancialAccount = try! JSONDecoder().decode(
            FinancialAccount.self,
            from: JSONEncoder().encode(financialAccount)
        )
        let decodedPortfolioAccount = try! JSONDecoder().decode(
            PortfolioAccount.self,
            from: JSONEncoder().encode(portfolioAccount)
        )

        assert(decodedFinancialAccount == financialAccount, "Expected financial account Codable round trip")
        assert(decodedPortfolioAccount == portfolioAccount, "Expected portfolio account Codable round trip")
    }

    private static func testLegacyAccountsMigrateToStableAccountDomain() {
        let bankId = UUID()
        let creditId = UUID()
        let budget = BudgetModel()
        budget.financialAccounts = []
        budget.portfolioAccounts = []
        budget.bankAccounts = [BankAccount(id: bankId, name: "Checking", balance: 500)]
        budget.creditAccounts = [CreditAccount(id: creditId, name: "Card", dueDay: 15)]
        budget.holdings = [PortfolioHolding(ticker: "AAPL", shares: 2, averageCost: 100, currentPrice: 180)]
        budget.portfolioSnapshot.cashBalance = 25
        budget.portfolioSnapshot.marginUsed = 10

        budget.migrateLegacyAccountsIfNeeded()
        budget.migrateLegacyAccountsIfNeeded()

        assert(budget.financialAccounts.first(where: { $0.id == bankId })?.kind == .depository, "Expected bank account to retain its stable local ID")
        assert(budget.financialAccounts.first(where: { $0.id == creditId })?.kind == .credit, "Expected credit account to retain its stable local ID")
        assert(budget.financialAccounts.filter { $0.kind == .investment }.count == 1, "Expected exactly one migrated legacy portfolio account")
        assert(budget.portfolioAccounts.count == 1, "Expected migration to be idempotent")
        assert(budget.portfolioAccounts[0].cashBalance == 25, "Expected legacy portfolio cash to migrate")
        assert(budget.portfolioAccounts[0].marginBalance == 10, "Expected legacy portfolio margin to migrate")
    }



    private static func testLegacyLedgerReferencesMigrateToUUIDs() {
        let checkingId = UUID()
        let savingsId = UUID()
        let creditId = UUID()
        let investmentFinancialId = UUID()
        let portfolioId = UUID()
        let categoryId = UUID()
        let budget = BudgetModel()
        budget.financialAccounts = [
            FinancialAccount(id: checkingId, name: "Checking", kind: .depository),
            FinancialAccount(id: savingsId, name: "Savings", kind: .depository),
            FinancialAccount(id: creditId, name: "Card", kind: .credit),
            FinancialAccount(id: investmentFinancialId, name: "Brokerage", kind: .investment)
        ]
        budget.bankAccounts = [
            BankAccount(id: checkingId, name: "Checking", balance: 500),
            BankAccount(id: savingsId, name: "Savings", balance: 100)
        ]
        budget.creditAccounts = [CreditAccount(id: creditId, name: "Card", dueDay: 15)]
        budget.portfolioAccounts = [PortfolioAccount(id: portfolioId, financialAccountId: investmentFinancialId, name: "Brokerage")]
        budget.incomes = [IncomeEntry(name: "Paycheck", amount: 100, bankName: "Checking")]
        budget.expenses = [Expense(name: "Groceries", amount: 25, section: .needs, categoryId: categoryId, paymentAccount: "Checking")]
        budget.cashTransfers = [CashTransfer(name: "Move", amount: 20, fromAccountName: "Checking", toAccountName: "Savings")]
        budget.portfolioTransactions = [PortfolioTransaction(type: .contribution, amount: 50, fundingBankAccount: "Checking")]
        budget.holdings = [PortfolioHolding(ticker: "AAPL", shares: 1, averageCost: 100, currentPrice: 180)]

        budget.migrateLegacyAccountsIfNeeded()

        assert(budget.incomes[0].bankAccountId == checkingId, "Expected legacy income bank name to migrate to UUID")
        assert(budget.expenses[0].paymentAccountId == checkingId, "Expected legacy expense payment account to migrate to UUID")
        assert(budget.cashTransfers[0].fromAccountId == checkingId, "Expected transfer source to migrate to UUID")
        assert(budget.cashTransfers[0].toAccountId == savingsId, "Expected transfer destination to migrate to UUID")
        assert(budget.portfolioTransactions[0].portfolioAccountId == portfolioId, "Expected portfolio transaction to link to stable portfolio UUID")
        assert(budget.portfolioTransactions[0].fundingBankAccountId == checkingId, "Expected portfolio funding bank to migrate to UUID")
        assert(budget.holdings[0].portfolioAccountId == portfolioId, "Expected holding to link to stable portfolio UUID")
    }

    private static func testStableCreditUUIDSurvivesRename() {
        let cardId = UUID()
        let categoryId = UUID()
        let budget = BudgetModel()
        budget.financialAccounts = [FinancialAccount(id: cardId, name: "Card", kind: .credit)]
        budget.creditAccounts = [CreditAccount(id: cardId, name: "Card", dueDay: 15, startingBalance: 100)]
        budget.expenses = [
            Expense(name: "Purchase", amount: 25, section: .needs, categoryId: categoryId, paymentAccount: "Card", paymentAccountId: cardId)
        ]
        assert(budget.creditAccountActualBalance(budget.creditAccounts[0]) == 125, "Expected expense to count against card by UUID")

        budget.creditAccounts[0].name = "Travel Card"
        budget.financialAccounts[0].name = "Travel Card"
        assert(budget.creditAccountActualBalance(budget.creditAccounts[0]) == 125, "Expected card rename not to break UUID-linked expense")
    }

    private static func testStableAccountUUIDSurvivesRename() {
        let checkingId = UUID()
        let savingsId = UUID()
        let transferId = UUID()
        let budget = BudgetModel()
        budget.financialAccounts = [
            FinancialAccount(id: checkingId, name: "Checking", kind: .depository),
            FinancialAccount(id: savingsId, name: "Savings", kind: .depository)
        ]
        budget.bankAccounts = [
            BankAccount(id: checkingId, name: "Checking", balance: 500),
            BankAccount(id: savingsId, name: "Savings", balance: 100)
        ]
        budget.addCashTransfer(CashTransfer(id: transferId, name: "Move", amount: 50, fromAccountName: "Checking", toAccountName: "Savings"))
        assert(budget.cashTransfers[0].fromAccountId == checkingId, "Expected transfer source UUID to persist")
        budget.bankAccounts[0].name = "Primary Checking"
        budget.financialAccounts[0].name = "Primary Checking"
        budget.updateCashTransfer(CashTransfer(id: transferId, name: "Move", amount: 30, fromAccountName: "Checking", toAccountName: "Savings", fromAccountId: checkingId, toAccountId: savingsId))
        assert(budget.bankAccounts.first(where: { $0.id == checkingId })?.balance == 470, "Expected renamed source to remain linked by UUID")
        assert(budget.bankAccounts.first(where: { $0.id == savingsId })?.balance == 130, "Expected destination to remain linked by UUID")
    }

    private static func testManualLedgerDoesNotMutatePlaidBalance() {
        let financialId = UUID()
        let budget = BudgetModel()
        budget.financialAccounts = [FinancialAccount(id: financialId, name: "Plaid Checking", kind: .depository, source: .plaid, externalAccountId: "plaid-checking")]
        budget.bankAccounts = [BankAccount(name: "Plaid Checking", balance: 1000, plaidMetadata: PlaidSourceMetadata(itemId: "item-1", accountId: "plaid-checking"))]
        budget.addIncomeEntry(IncomeEntry(name: "Manual adjustment", amount: 250, bankName: "Plaid Checking", bankAccountId: financialId))
        assert(budget.bankAccounts[0].balance == 1000, "Expected manual ledger actions not to mutate Plaid-authoritative balances")
        assert(budget.incomes.count == 1, "Expected manual ledger row to remain recorded")
    }

    private static func testHoldingsConsolidateToOneRowPerTicker() {
        let budget = BudgetModel()
        budget.holdings = [
            PortfolioHolding(ticker: "aapl", shares: 2, averageCost: 100, currentPrice: 180),
            PortfolioHolding(ticker: "AAPL", shares: 3, averageCost: 120, currentPrice: 181),
            PortfolioHolding(ticker: "MSFT", shares: 1, averageCost: 300, currentPrice: 420)
        ]

        let aapl = budget.consolidatedHoldings.first { $0.ticker == "AAPL" }
        assert(budget.consolidatedHoldings.count == 2, "Expected one consolidated holding per ticker")
        assert(aapl?.shares == 5, "Expected consolidated shares to include every matching ticker row")
        assert(aapl?.averageCost == 112, "Expected consolidated average cost to be share weighted")
    }
}
