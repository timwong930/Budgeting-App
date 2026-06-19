import AppIntents
import SwiftUI

// MARK: - Entity Types

@available(iOS 26.0, *)
struct PortfolioSummaryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Portfolio Summary" }
    static var defaultQuery: PortfolioSummaryQuery { PortfolioSummaryQuery() }

    var id: String = "summary"
    var totalValue: Double
    var netValue: Double
    var cashBalance: Double
    var marginUsed: Double
    var equityPercent: Double
    var monthlyDividends: Double
    var positionCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(dollar(netValue))",
            subtitle: "\(positionCount) positions"
        )
    }
}

@available(iOS 26.0, *)
struct PortfolioSummaryQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async -> [PortfolioSummaryEntity] {
        return identifiers.map { _ in makeSummary() }
    }

    @MainActor
    func suggestedEntities() async -> [PortfolioSummaryEntity] {
        return [makeSummary()]
    }

    private func makeSummary() -> PortfolioSummaryEntity {
        let budget = BudgetModel()
        let snapshot = budget.portfolioSnapshot
        let totalValue = snapshot.portfolioValue
        let cashBalance = snapshot.cashBalance
        let marginUsed = snapshot.marginUsed
        let netValue = MarginCalculator.netEquity(portfolioValue: totalValue, marginUsed: marginUsed)
        let equityPct = MarginCalculator.equityPercent(portfolioValue: totalValue, marginUsed: marginUsed)
        let annualDividendIncome = budget.holdings.reduce(0) { $0 + $1.shares * $1.annualDividendPerShare }
        return PortfolioSummaryEntity(
            totalValue: totalValue,
            netValue: netValue,
            cashBalance: cashBalance,
            marginUsed: marginUsed,
            equityPercent: equityPct,
            monthlyDividends: annualDividendIncome / 12,
            positionCount: budget.holdings.count
        )
    }
}

@available(iOS 26.0, *)
struct PositionEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Portfolio Position" }
    static var defaultQuery: PositionQuery { PositionQuery() }

    var id: String
    var ticker: String
    var shares: Double
    var averageCost: Double
    var currentPrice: Double
    var marketValue: Double
    var unrealizedPL: Double
    var unrealizedPLPercent: Double
    var costBasis: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(ticker) – \(dollar(marketValue))",
            subtitle: "\(sharesFormatted) shares"
        )
    }

    private var sharesFormatted: String {
        shares.formatted(.number.precision(.fractionLength(0...4)))
    }
}

@available(iOS 26.0, *)
struct PositionQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async -> [PositionEntity] {
        let budget = BudgetModel()
        return identifiers.compactMap { ticker in
            budget.holdings.first(where: { $0.ticker.uppercased() == ticker.uppercased() }).map { makePosition(holding: $0) }
        }
    }

    @MainActor
    func suggestedEntities() async -> [PositionEntity] {
        let budget = BudgetModel()
        return budget.holdings.map { makePosition(holding: $0) }
    }

    private func makePosition(holding: PortfolioHolding) -> PositionEntity {
        let marketValue = holding.shares * holding.currentPrice
        let costBasis = holding.shares * holding.averageCost
        let unrealized = marketValue - costBasis
        let unrealizedPct = costBasis > 0 ? unrealized / costBasis : 0
        return PositionEntity(
            id: holding.ticker.uppercased(),
            ticker: holding.ticker.uppercased(),
            shares: holding.shares,
            averageCost: holding.averageCost,
            currentPrice: holding.currentPrice,
            marketValue: marketValue,
            unrealizedPL: unrealized,
            unrealizedPLPercent: unrealizedPct,
            costBasis: costBasis
        )
    }
}

@available(iOS 26.0, *)
struct QuoteEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Stock Quote" }
    static var defaultQuery: QuoteQuery { QuoteQuery() }

    var id: String
    var ticker: String
    var price: Double
    var change: Double
    var percentChange: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(ticker) \(dollar(price))",
            subtitle: "\(changeFormatted) (\(percentFormatted))"
        )
    }

    private var changeFormatted: String { change.formatted(.number.precision(.fractionLength(2))) }
    private var percentFormatted: String { percentChange.formatted(.number.precision(.fractionLength(2))) + "%" }
}

@available(iOS 26.0, *)
struct QuoteQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async -> [QuoteEntity] {
        let budget = BudgetModel()
        return identifiers.compactMap { ticker in
            let key = ticker.uppercased()
            guard let cached = budget.cachedQuotes[key] else { return nil }
            return QuoteEntity(id: key, ticker: key, price: cached.price, change: 0, percentChange: 0)
        }
    }
}

@available(iOS 26.0, *)
struct WatchlistItemEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Watchlist Item" }
    static var defaultQuery: WatchlistItemQuery { WatchlistItemQuery() }

    var id: String
    var ticker: String
    var price: Double
    var priceText: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(ticker)", subtitle: "\(priceText)")
    }
}

@available(iOS 26.0, *)
struct WatchlistItemQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async -> [WatchlistItemEntity] {
        let budget = BudgetModel()
        return identifiers.map { ticker in
            let key = ticker.uppercased()
            let price = budget.cachedQuotes[key]?.price ?? 0
            return WatchlistItemEntity(id: key, ticker: key, price: price, priceText: price > 0 ? dollar(price) : "--")
        }
    }

    @MainActor
    func suggestedEntities() async -> [WatchlistItemEntity] {
        let budget = BudgetModel()
        return budget.watchlistTickers.map { ticker in
            let key = ticker.uppercased()
            let price = budget.cachedQuotes[key]?.price ?? 0
            return WatchlistItemEntity(id: key, ticker: key, price: price, priceText: price > 0 ? dollar(price) : "--")
        }
    }
}

@available(iOS 26.0, *)
struct BudgetStatusEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Budget Status" }
    static var defaultQuery: BudgetStatusQuery { BudgetStatusQuery() }

    var id: String = "budget"
    var monthlyIncome: Double
    var needsBudget: Double
    var needsAllocated: Double
    var needsRemaining: Double
    var wantsBudget: Double
    var wantsAllocated: Double
    var wantsRemaining: Double
    var savingsBudget: Double
    var savingsAllocated: Double
    var savingsRemaining: Double
    var totalRemaining: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Budget: \(dollar(totalRemaining)) remaining",
            subtitle: "\(dollar(monthlyIncome))/mo"
        )
    }
}

@available(iOS 26.0, *)
struct BudgetStatusQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async -> [BudgetStatusEntity] {
        return [makeStatus()]
    }

    @MainActor
    func suggestedEntities() async -> [BudgetStatusEntity] {
        return [makeStatus()]
    }

    private func makeStatus() -> BudgetStatusEntity {
        let budget = BudgetModel()
        return BudgetStatusEntity(
            monthlyIncome: budget.monthlyIncome,
            needsBudget: budget.needsBudget,
            needsAllocated: budget.totalNeedsAllocated,
            needsRemaining: budget.needsRemaining,
            wantsBudget: budget.wantsBudget,
            wantsAllocated: budget.totalWantsAllocated,
            wantsRemaining: budget.wantsRemaining,
            savingsBudget: budget.savingsBudget,
            savingsAllocated: budget.totalSavingsAllocated,
            savingsRemaining: budget.savingsRemaining,
            totalRemaining: budget.totalRemainingBudget
        )
    }
}

@available(iOS 26.0, *)
struct AccountEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Account" }
    static var defaultQuery: AccountQuery { AccountQuery() }

    var id: String
    var name: String
    var balance: Double
    var accountType: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(dollar(balance))")
    }
}

@available(iOS 26.0, *)
struct AccountQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async -> [AccountEntity] {
        let budget = BudgetModel()
        return identifiers.compactMap { id in
            if let bank = budget.bankAccounts.first(where: { $0.id.uuidString == id }) {
                return AccountEntity(id: bank.id.uuidString, name: bank.name, balance: bank.balance, accountType: "Bank")
            }
            return nil
        }
    }

    @MainActor
    func suggestedEntities() async -> [AccountEntity] {
        let budget = BudgetModel()
        return budget.bankAccounts.map {
            AccountEntity(id: $0.id.uuidString, name: $0.name, balance: $0.balance, accountType: "Bank")
        }
    }
}

// MARK: - TickerNote (existing)

@available(iOS 26.0, *)
struct TickerNoteQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async -> [TickerNoteEntity] {
        let budget = BudgetModel()
        let allNotes = budget.tickerNotes.values.flatMap { $0 }
        return identifiers.compactMap { id in
            allNotes.first(where: { $0.id == id }).map { TickerNoteEntity(note: $0) }
        }
    }
}

struct TickerNoteEntity: Identifiable, AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Ticker Note" }
    static var defaultQuery: TickerNoteQuery { TickerNoteQuery() }

    var id: UUID
    var ticker: String
    var title: String?
    var text: String
    var url: String?
    var urlTitle: String?
    var category: String?
    var createdAt: Date
    var updatedAt: Date

    init(note: TickerNote) {
        self.id = note.id
        self.ticker = note.ticker
        self.title = note.title
        self.text = note.text
        self.url = note.url
        self.urlTitle = note.urlTitle
        self.category = note.category
        self.createdAt = note.createdAt
        self.updatedAt = note.updatedAt
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title ?? text)",
            subtitle: "\(ticker) - \(category ?? "Note")"
        )
    }
}

// MARK: - Helpers

private func dollar(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
}

// MARK: - Read Intents

@available(iOS 26.0, *)
struct GetPortfolioSummaryIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Portfolio Summary" }
    static var description: IntentDescription { "Returns total portfolio value, net value, cash, margin, and equity percentage." }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PortfolioSummaryEntity> & ProvidesDialog {
        let summary = await PortfolioSummaryQuery().suggestedEntities().first!
        return .result(value: summary, dialog: "Portfolio net value: \(dollar(summary.netValue)) across \(summary.positionCount) positions.")
    }
}

@available(iOS 26.0, *)
struct GetNetWorthIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Net Worth" }
    static var description: IntentDescription { "Calculates total net worth across bank accounts, portfolio, and savings." }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let budget = BudgetModel()
        let bankTotal = budget.bankAccounts.reduce(0) { $0 + $1.balance }
        let savingsTotal = budget.savingsGoals.reduce(0) { $0 + $1.currentAmount }
        let snapshot = budget.portfolioSnapshot
        let portfolioNet = MarginCalculator.netEquity(portfolioValue: snapshot.portfolioValue, marginUsed: snapshot.marginUsed)
        let netWorth = bankTotal + savingsTotal + portfolioNet

        return .result(dialog: "Net worth: \(dollar(netWorth))")
    }
}

@available(iOS 26.0, *)
struct GetPositionForTickerIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Position for Ticker" }
    static var description: IntentDescription { "Returns shares, average cost, current price, and P&L for a position." }

    @Parameter(title: "Ticker", description: "Stock ticker symbol (e.g. AAPL)")
    var ticker: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<PositionEntity> & ProvidesDialog {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else { throw $ticker.needsValueError() }
        let budget = BudgetModel()
        guard let holding = budget.holdings.first(where: { $0.ticker.uppercased() == cleanTicker }) else {
            throw $ticker.needsValueError()
        }
        let entity = PositionEntity(
            id: cleanTicker,
            ticker: cleanTicker,
            shares: holding.shares,
            averageCost: holding.averageCost,
            currentPrice: holding.currentPrice,
            marketValue: holding.shares * holding.currentPrice,
            unrealizedPL: holding.shares * (holding.currentPrice - holding.averageCost),
            unrealizedPLPercent: holding.averageCost > 0 ? (holding.currentPrice - holding.averageCost) / holding.averageCost : 0,
            costBasis: holding.shares * holding.averageCost
        )
        let shrs = holding.shares.formatted(.number.precision(.fractionLength(0...4)))
        return .result(value: entity, dialog: "\(cleanTicker): \(shrs) shares at \(dollar(holding.averageCost))")
    }
}

@available(iOS 26.0, *)
struct GetStockQuoteIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Stock Quote" }
    static var description: IntentDescription { "Returns the current price for a ticker from cached data." }

    @Parameter(title: "Ticker", description: "Stock ticker symbol (e.g. AAPL)")
    var ticker: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<QuoteEntity> & ProvidesDialog {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else { throw $ticker.needsValueError() }
        let budget = BudgetModel()
        let price = budget.cachedQuotes[cleanTicker]?.price ?? 0
        let entity = QuoteEntity(id: cleanTicker, ticker: cleanTicker, price: price, change: 0, percentChange: 0)
        return .result(value: entity, dialog: "\(cleanTicker): \(dollar(price))")
    }
}

@available(iOS 26.0, *)
struct GetWatchlistPricesIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Watchlist Prices" }
    static var description: IntentDescription { "Returns all watchlist tickers with their current prices." }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[WatchlistItemEntity]> & ProvidesDialog {
        let budget = BudgetModel()
        let items = budget.watchlistTickers.map { ticker in
            let key = ticker.uppercased()
            let price = budget.cachedQuotes[key]?.price ?? 0
            return WatchlistItemEntity(id: key, ticker: key, price: price, priceText: price > 0 ? dollar(price) : "--")
        }
        return .result(value: items, dialog: "\(items.count) tickers in watchlist.")
    }
}

@available(iOS 26.0, *)
struct GetBudgetStatusIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Budget Status" }
    static var description: IntentDescription { "Returns monthly income, budget allocations, and remaining amounts." }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<BudgetStatusEntity> & ProvidesDialog {
        let entity = await BudgetStatusQuery().suggestedEntities().first!
        return .result(
            value: entity,
            dialog: "Remaining: Needs \(dollar(entity.needsRemaining)), Wants \(dollar(entity.wantsRemaining)), Savings \(dollar(entity.savingsRemaining))."
        )
    }
}

// MARK: - Write Intents

@available(iOS 26.0, *)
struct AddPortfolioTransactionIntent: AppIntent {
    static var title: LocalizedStringResource { "Add Portfolio Transaction" }
    static var description: IntentDescription { "Records a buy, sell, dividend, contribution, or manual adjustment in the portfolio ledger." }

    @Parameter(title: "Type", description: "Transaction type (contribution, buy, sell, dividend, manualAdjustment)", requestValueDialog: "Choose transaction type")
    var transactionType: String

    @Parameter(title: "Ticker", description: "Stock ticker (required for buy, sell, dividend)")
    var ticker: String?

    @Parameter(title: "Shares", description: "Number of shares (for buy and sell)")
    var shares: Double?

    @Parameter(title: "Total Amount", description: "Total dollar amount")
    var amount: Double

    @Parameter(title: "Date", description: "Transaction date (defaults to today)")
    var date: Date?

    @Parameter(title: "Notes", description: "Optional notes")
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$transactionType)") {
            \.$ticker
            \.$shares
            \.$amount
            \.$date
            \.$notes
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleanTicker = ticker?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let rawType = transactionType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let type: PortfolioTransactionType
        switch rawType {
        case "contribution": type = .contribution
        case "buy": type = .buy
        case "sell": type = .sell
        case "dividend": type = .dividend
        case "manualadjustment", "manual_adjustment", "adjustment": type = .manualAdjustment
        default: throw $transactionType.needsValueError()
        }

        if type == .buy || type == .sell || type == .dividend {
            guard cleanTicker?.isEmpty == false else { throw $ticker.needsValueError() }
        }

        let budget = BudgetModel()
        let transaction = PortfolioTransaction(
            date: date ?? Date(),
            type: type,
            ticker: cleanTicker,
            shares: shares,
            pricePerShare: nil,
            amount: amount,
            notes: cleanNotes
        )
        budget.addPortfolioTransaction(transaction)
        budget.saveNow()

        let label = rawType.prefix(1).uppercased() + rawType.dropFirst()
        let tickerStr = cleanTicker.map { " for \($0)" } ?? ""
        return .result(dialog: "\(label) of \(dollar(amount)) recorded\(tickerStr).")
    }
}

@available(iOS 26.0, *)
struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource { "Add Expense" }
    static var description: IntentDescription { "Logs an expense in the budget." }

    @Parameter(title: "Name", description: "Expense name")
    var name: String

    @Parameter(title: "Amount", description: "Expense amount")
    var amount: Double

    @Parameter(title: "Section", description: "Needs or Wants", requestValueDialog: "Choose section")
    var section: String

    @Parameter(title: "Category Name", description: "Category name (e.g. Groceries, Dining)")
    var categoryName: String?

    @Parameter(title: "Account", description: "Payment account name")
    var paymentAccount: String?

    @Parameter(title: "Notes", description: "Optional notes")
    var notes: String?

    @Parameter(title: "Date", description: "Expense date (defaults to today)")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$name) expense") {
            \.$amount
            \.$section
            \.$categoryName
            \.$paymentAccount
            \.$notes
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw $name.needsValueError() }

        let budget = BudgetModel()
        let rawSection = section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let budgetSection: BudgetSection = rawSection == "needs" ? .needs : .wants
        let cleanCategoryName = categoryName?.trimmingCharacters(in: .whitespacesAndNewlines)

        let categoryId: UUID
        if let catName = cleanCategoryName, !catName.isEmpty {
            let categories = budgetSection == .needs ? budget.needsCategories : budget.wantsCategories
            if let match = categories.first(where: { $0.name.localizedCaseInsensitiveContains(catName) }) {
                categoryId = match.id
            } else {
                throw $categoryName.needsValueError()
            }
        } else {
            let categories = budgetSection == .needs ? budget.needsCategories : budget.wantsCategories
            guard let first = categories.first else {
                throw $name.needsValueError()
            }
            categoryId = first.id
        }

        let expense = Expense(
            name: cleanName,
            amount: amount,
            date: date ?? Date(),
            section: budgetSection,
            categoryId: categoryId,
            paymentAccount: paymentAccount?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "",
            note: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ""
        )
        budget.expenses.append(expense)
        budget.saveNow()

        return .result(dialog: "\(cleanName) expense of \(dollar(amount)) added to \(budgetSection.title).")
    }
}

@available(iOS 26.0, *)
struct AddWatchlistTickerIntent: AppIntent {
    static var title: LocalizedStringResource { "Add Watchlist Ticker" }
    static var description: IntentDescription { "Adds a stock ticker to your watchlist." }

    @Parameter(title: "Ticker", description: "Stock ticker symbol (e.g. AAPL)")
    var ticker: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else { throw $ticker.needsValueError() }

        let budget = BudgetModel()
        guard !budget.watchlistTickers.contains(cleanTicker) else {
            return .result(dialog: "\(cleanTicker) is already in your watchlist.")
        }
        budget.watchlistTickers.append(cleanTicker)
        budget.saveNow()

        return .result(dialog: "\(cleanTicker) added to watchlist.")
    }
}

// MARK: - Note Intents (existing)

@available(iOS 26.0, *)
struct AddTickerNoteIntent: AppIntent {
    static var title: LocalizedStringResource { "Add Note to Ticker" }
    static var description: IntentDescription {
        "Adds a research note with optional title, URL, and category to a stock ticker."
    }

    @Parameter(title: "Ticker", description: "Stock ticker symbol (e.g. AAPL)")
    var ticker: String

    @Parameter(title: "Note", description: "The note content")
    var text: String

    @Parameter(title: "Title", description: "Optional note title or headline")
    var title: String?

    @Parameter(title: "URL", description: "Optional reference URL (YouTube link, article, etc.)")
    var url: String?

    @Parameter(title: "URL Label", description: "Display label for the URL")
    var urlTitle: String?

    @Parameter(title: "Category", description: "Note category")
    var noteCategory: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add note to \(\.$ticker)") {
            \.$text
            \.$title
            \.$url
            \.$urlTitle
            \.$noteCategory
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTicker.isEmpty else { throw $ticker.needsValueError() }
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { throw $text.needsValueError() }

        let budget = BudgetModel()
        budget.addTickerNote(
            ticker: cleanTicker,
            title: title,
            text: cleanText,
            url: url?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            urlTitle: urlTitle,
            category: noteCategory
        )
        budget.saveNow()

        return .result(dialog: "Note added to \(cleanTicker.uppercased()).")
    }
}

@available(iOS 26.0, *)
struct GetTickerNotesIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Ticker Notes" }
    static var description: IntentDescription { "Retrieves all notes for a given stock ticker." }

    @Parameter(title: "Ticker", description: "Stock ticker symbol (e.g. AAPL)")
    var ticker: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TickerNoteEntity]> & ProvidesDialog {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else { throw $ticker.needsValueError() }

        let budget = BudgetModel()
        let notes = budget.notes(for: cleanTicker)
        let entities = notes.map { TickerNoteEntity(note: $0) }

        return .result(
            value: entities,
            dialog: "\(entities.count) note\(entities.count == 1 ? "" : "s") found for \(cleanTicker)."
        )
    }
}

// MARK: - App Shortcuts

@available(iOS 26.0, *)
struct MomosMoneyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTickerNoteIntent(),
            phrases: [
                "Add a note to \(.applicationName)",
                "Save a note in \(.applicationName)",
                "Log a note for a ticker in \(.applicationName)",
                "Add ticker note in \(.applicationName)"
            ],
            shortTitle: "Add Ticker Note",
            systemImageName: "note.text.badge.plus"
        )
        AppShortcut(
            intent: GetPortfolioSummaryIntent(),
            phrases: [
                "Get my portfolio summary from \(.applicationName)",
                "What's my portfolio value in \(.applicationName)",
                "Portfolio summary in \(.applicationName)"
            ],
            shortTitle: "Portfolio Summary",
            systemImageName: "chart.pie"
        )
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense to \(.applicationName)",
                "Log an expense in \(.applicationName)",
                "Track an expense in \(.applicationName)"
            ],
            shortTitle: "Add Expense",
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: AddPortfolioTransactionIntent(),
            phrases: [
                "Add a transaction to \(.applicationName)",
                "Log a trade in \(.applicationName)",
                "Record a portfolio transaction in \(.applicationName)"
            ],
            shortTitle: "Portfolio Transaction",
            systemImageName: "arrow.left.arrow.right"
        )
        AppShortcut(
            intent: GetNetWorthIntent(),
            phrases: [
                "What's my net worth in \(.applicationName)",
                "Get net worth from \(.applicationName)",
                "Net worth in \(.applicationName)"
            ],
            shortTitle: "Net Worth",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: GetStockQuoteIntent(),
            phrases: [
                "Get a stock quote from \(.applicationName)",
                "Check price in \(.applicationName)",
                "Stock quote in \(.applicationName)"
            ],
            shortTitle: "Stock Quote",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
        AppShortcut(
            intent: GetWatchlistPricesIntent(),
            phrases: [
                "Get my watchlist from \(.applicationName)",
                "Watchlist prices in \(.applicationName)",
                "What's on my watchlist in \(.applicationName)"
            ],
            shortTitle: "Watchlist",
            systemImageName: "eye"
        )
        AppShortcut(
            intent: GetBudgetStatusIntent(),
            phrases: [
                "Get my budget from \(.applicationName)",
                "Budget status in \(.applicationName)",
                "How's my budget in \(.applicationName)"
            ],
            shortTitle: "Budget Status",
            systemImageName: "chart.bar"
        )
    }
}
