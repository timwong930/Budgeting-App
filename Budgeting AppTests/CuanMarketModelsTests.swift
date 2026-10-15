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
