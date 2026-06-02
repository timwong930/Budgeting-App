//
//  Models.swift
//  Budgeting App
//
//  Created by Timothy Wong on 1/16/26.
//

import Foundation
import Combine
import OSLog
#if canImport(WidgetKit)
import WidgetKit
#endif

enum PayFrequency: String, CaseIterable, Identifiable, Codable, Sendable {
    case weekly = "Weekly"
    case biWeekly = "Bi-Weekly"
    case monthly = "Monthly"
    case annually = "Annually"
    
    var id: String { rawValue }
    
    var multiplier: Double {
        switch self {
        case .weekly: return 52.0
        case .biWeekly: return 26.0
        case .monthly: return 12.0
        case .annually: return 1.0
        }
    }
}

enum BudgetSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case needs
    case wants

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needs:
            return "Needs"
        case .wants:
            return "Wants"
        }
    }
}

struct Category: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var allocatedAmount: Double
    var spentAmount: Double
    
    init(id: UUID = UUID(), name: String, allocatedAmount: Double, spentAmount: Double = 0) {
        self.id = id
        self.name = name
        self.allocatedAmount = allocatedAmount
        self.spentAmount = spentAmount
    }
    
    var remaining: Double {
        allocatedAmount - spentAmount
    }
}

struct Expense: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var amount: Double
    var date: Date
    var section: BudgetSection
    var categoryId: UUID
    var paymentAccount: String
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        date: Date = Date(),
        section: BudgetSection,
        categoryId: UUID,
        paymentAccount: String = "",
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
        self.section = section
        self.categoryId = categoryId
        self.paymentAccount = paymentAccount
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case date
        case section
        case categoryId
        case paymentAccount
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Double.self, forKey: .amount)
        date = try container.decode(Date.self, forKey: .date)
        section = try container.decode(BudgetSection.self, forKey: .section)
        categoryId = try container.decode(UUID.self, forKey: .categoryId)
        paymentAccount = try container.decodeIfPresent(String.self, forKey: .paymentAccount) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct CreditAccount: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var closingDay: Int
    var dueDay: Int
    var startingBalance: Double
    var expectedAmount: Double
    var creditLimit: Double
    var isActive: Bool
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        closingDay: Int = 1,
        dueDay: Int,
        startingBalance: Double = 0,
        expectedAmount: Double = 0,
        creditLimit: Double = 0,
        isActive: Bool = true,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.closingDay = min(max(closingDay, 1), 31)
        self.dueDay = min(max(dueDay, 1), 31)
        self.startingBalance = startingBalance
        self.expectedAmount = expectedAmount
        self.creditLimit = max(creditLimit, 0)
        self.isActive = isActive
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case closingDay
        case dueDay
        case startingBalance
        case expectedAmount
        case creditLimit
        case isActive
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        closingDay = min(max(try container.decodeIfPresent(Int.self, forKey: .closingDay) ?? 1, 1), 31)
        dueDay = min(max(try container.decodeIfPresent(Int.self, forKey: .dueDay) ?? 1, 1), 31)
        startingBalance = try container.decodeIfPresent(Double.self, forKey: .startingBalance) ?? 0
        expectedAmount = try container.decodeIfPresent(Double.self, forKey: .expectedAmount) ?? 0
        creditLimit = max(try container.decodeIfPresent(Double.self, forKey: .creditLimit) ?? 0, 0)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct BankAccount: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var balance: Double
    var note: String

    init(id: UUID = UUID(), name: String, balance: Double = 0, note: String = "") {
        self.id = id
        self.name = name
        self.balance = balance
        self.note = note
    }
}

struct SavingsEntry: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var amount: Double
    var date: Date
    var goalId: UUID

    init(id: UUID = UUID(), name: String, amount: Double, date: Date = Date(), goalId: UUID) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
        self.goalId = goalId
    }
}

struct IncomeEntry: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var amount: Double
    var date: Date
    var bankName: String

    init(id: UUID = UUID(), name: String, amount: Double, date: Date = Date(), bankName: String = "") {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
        self.bankName = bankName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case date
        case bankName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Double.self, forKey: .amount)
        date = try container.decode(Date.self, forKey: .date)
        bankName = try container.decodeIfPresent(String.self, forKey: .bankName) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(date, forKey: .date)
        try container.encode(bankName, forKey: .bankName)
    }
}

enum RecurringPaymentKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case expense
    case income

    var id: String { rawValue }
}

struct RecurringPayment: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var amount: Double
    var dayOfMonth: Int
    var startDate: Date
    var kind: RecurringPaymentKind
    var isActive: Bool
    var paidOccurrenceKeys: [String]
    var section: BudgetSection
    var categoryId: UUID?
    var paymentAccount: String
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        dayOfMonth: Int,
        startDate: Date = Date(),
        kind: RecurringPaymentKind = .expense,
        isActive: Bool = true,
        paidOccurrenceKeys: [String] = [],
        section: BudgetSection = .needs,
        categoryId: UUID? = nil,
        paymentAccount: String = "",
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dayOfMonth = min(max(dayOfMonth, 1), 31)
        self.startDate = startDate
        self.kind = kind
        self.isActive = isActive
        self.paidOccurrenceKeys = paidOccurrenceKeys
        self.section = section
        self.categoryId = categoryId
        self.paymentAccount = paymentAccount
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case dayOfMonth
        case startDate
        case kind
        case isActive
        case paidOccurrenceKeys
        case section
        case categoryId
        case paymentAccount
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Double.self, forKey: .amount)
        dayOfMonth = min(max(try container.decode(Int.self, forKey: .dayOfMonth), 1), 31)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate) ?? Date()
        kind = try container.decodeIfPresent(RecurringPaymentKind.self, forKey: .kind) ?? .expense
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        paidOccurrenceKeys = try container.decodeIfPresent([String].self, forKey: .paidOccurrenceKeys) ?? []
        section = try container.decodeIfPresent(BudgetSection.self, forKey: .section) ?? .needs
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        paymentAccount = try container.decodeIfPresent(String.self, forKey: .paymentAccount) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct SavingsGoal: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var targetAmount: Double
    var currentAmount: Double
    var monthlyContribution: Double
    var accountName: String
    
    init(id: UUID = UUID(), name: String, targetAmount: Double, currentAmount: Double = 0, monthlyContribution: Double = 0, accountName: String) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.monthlyContribution = monthlyContribution
        self.accountName = accountName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case targetAmount
        case currentAmount
        case monthlyContribution
        case accountName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        targetAmount = try container.decode(Double.self, forKey: .targetAmount)
        currentAmount = try container.decode(Double.self, forKey: .currentAmount)
        monthlyContribution = try container.decodeIfPresent(Double.self, forKey: .monthlyContribution) ?? 0
        accountName = try container.decode(String.self, forKey: .accountName)
    }
    
    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentAmount / targetAmount, 1.0)
    }
    
    var remaining: Double {
        max(targetAmount - currentAmount, 0)
    }

    var displayName: String {
        if !name.isEmpty {
            return name
        }
        return accountName
    }
}

struct PortfolioSnapshot: Codable, Sendable, Equatable {
    var portfolioValue: Double
    var cashBalance: Double
    var marginUsed: Double
    var freeMarginLimit: Double
    var marginInterestRate: Double

    init(
        portfolioValue: Double = 0,
        cashBalance: Double = 0,
        marginUsed: Double = 0,
        freeMarginLimit: Double = 1000,
        marginInterestRate: Double = 0.08
    ) {
        self.portfolioValue = portfolioValue
        self.cashBalance = cashBalance
        self.marginUsed = marginUsed
        self.freeMarginLimit = freeMarginLimit
        self.marginInterestRate = marginInterestRate
    }
}

struct DividendPayment: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var ticker: String
    var amount: Double
    var payDate: Date

    init(id: UUID = UUID(), ticker: String, amount: Double, payDate: Date = Date()) {
        self.id = id
        self.ticker = ticker
        self.amount = amount
        self.payDate = payDate
    }
}

struct MarginBill: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var amount: Double
    var dueDate: Date
    var paidUsingMargin: Bool
    var isRecurring: Bool

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        dueDate: Date = Date(),
        paidUsingMargin: Bool = true,
        isRecurring: Bool = true
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.paidUsingMargin = paidUsingMargin
        self.isRecurring = isRecurring
    }
}

enum PortfolioTransactionType: String, CaseIterable, Identifiable, Codable, Sendable {
    case contribution
    case buy
    case sell
    case dividend
    case billPaidByMargin
    case marginInterest
    case manualAdjustment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contribution: return "Contribution"
        case .buy: return "Buy"
        case .sell: return "Sell"
        case .dividend: return "Dividend"
        case .billPaidByMargin: return "Bill Paid by Margin"
        case .marginInterest: return "Margin Interest"
        case .manualAdjustment: return "Manual Adjustment"
        }
    }
}

enum InvestmentFundingSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case cash = "Cash"
    case margin = "Margin"
    case newContribution = "New Contribution"

    var id: String { rawValue }
}

struct PortfolioTransaction: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var date: Date
    var type: PortfolioTransactionType
    var ticker: String?
    var shares: Double?
    var pricePerShare: Double?
    var amount: Double
    var notes: String?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        type: PortfolioTransactionType,
        ticker: String? = nil,
        shares: Double? = nil,
        pricePerShare: Double? = nil,
        amount: Double,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.ticker = ticker
        self.shares = shares
        self.pricePerShare = pricePerShare
        self.amount = amount
        self.notes = notes
    }
}

struct MarginSettings: Codable, Sendable, Equatable {
    var totalMarginAvailable: Double
    var interestFreeMarginLimit: Double
    var marginInterestRate: Double
    var maintenanceRequirementPercent: Double
    var personalMarginCap: Double
    var warningThresholdPercent: Double
    var dangerThresholdPercent: Double

    init(
        totalMarginAvailable: Double = 0,
        interestFreeMarginLimit: Double = 1000,
        marginInterestRate: Double = 0.08,
        maintenanceRequirementPercent: Double = 0.30,
        personalMarginCap: Double = 1000,
        warningThresholdPercent: Double = 0.70,
        dangerThresholdPercent: Double = 0.90
    ) {
        self.totalMarginAvailable = totalMarginAvailable
        self.interestFreeMarginLimit = interestFreeMarginLimit
        self.marginInterestRate = marginInterestRate
        self.maintenanceRequirementPercent = maintenanceRequirementPercent
        self.personalMarginCap = personalMarginCap
        self.warningThresholdPercent = warningThresholdPercent
        self.dangerThresholdPercent = dangerThresholdPercent
    }
}

struct RecurringMarginBill: Codable, Sendable, Equatable {
    var name: String
    var expectedAmount: Double
    var dueDay: Int
    var isActive: Bool
    var paidByMargin: Bool

    init(
        name: String = "Electricity",
        expectedAmount: Double = 0,
        dueDay: Int = 1,
        isActive: Bool = true,
        paidByMargin: Bool = true
    ) {
        self.name = name
        self.expectedAmount = expectedAmount
        self.dueDay = min(max(dueDay, 1), 31)
        self.isActive = isActive
        self.paidByMargin = paidByMargin
    }
}

enum DividendFrequency: String, CaseIterable, Identifiable, Codable, Sendable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case annual = "Annual"
    case irregular = "Irregular"

    var id: String { rawValue }

    var paymentsPerYear: Double {
        switch self {
        case .weekly: return 52
        case .monthly: return 12
        case .quarterly: return 4
        case .annual: return 1
        case .irregular: return 0
        }
    }
}

enum PortfolioAssetType: String, CaseIterable, Identifiable, Codable, Sendable {
    case growthStock = "Growth Stock"
    case dividendStock = "Dividend Stock"
    case dividendETF = "Dividend ETF"
    case coveredCallETF = "Covered-Call ETF"
    case speculative = "Speculative"
    case cashLike = "Cash-Like"

    var id: String { rawValue }
}

enum DividendReliability: String, CaseIterable, Identifiable, Codable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }
}

struct PortfolioHolding: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var ticker: String
    var shares: Double
    var averageCost: Double
    var currentPrice: Double
    var annualDividendPerShare: Double
    var dividendFrequency: DividendFrequency
    var assetType: PortfolioAssetType
    var dividendReliability: DividendReliability
    var notes: String
    var nextExDividendDate: Date?
    var nextPayDate: Date?

    init(
        id: UUID = UUID(),
        ticker: String,
        shares: Double,
        averageCost: Double,
        currentPrice: Double,
        annualDividendPerShare: Double,
        dividendFrequency: DividendFrequency,
        assetType: PortfolioAssetType = .dividendStock,
        dividendReliability: DividendReliability = .medium,
        notes: String = "",
        nextExDividendDate: Date? = nil,
        nextPayDate: Date? = nil
    ) {
        self.id = id
        self.ticker = ticker
        self.shares = shares
        self.averageCost = averageCost
        self.currentPrice = currentPrice
        self.annualDividendPerShare = annualDividendPerShare
        self.dividendFrequency = dividendFrequency
        self.assetType = assetType
        self.dividendReliability = dividendReliability
        self.notes = notes
        self.nextExDividendDate = nextExDividendDate
        self.nextPayDate = nextPayDate
    }
}

enum MarketDataProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case alphaVantage = "Alpha Vantage"
    case finnhub = "Finnhub"

    var id: String { rawValue }
}

enum AlpacaMarketDataFeed: String, CaseIterable, Identifiable, Codable, Sendable {
    case iex = "IEX"
    case sip = "SIP"

    var id: String { rawValue }

    var apiValue: String { rawValue.lowercased() }
}

struct MarketDataSettings: Codable, Sendable, Equatable {
    var provider: MarketDataProvider
    var apiKey: String
    var alpacaAPIKeyId: String
    var alpacaSecretKey: String
    var alpacaFeed: AlpacaMarketDataFeed
    var useAlpacaFallback: Bool

    init(
        provider: MarketDataProvider = .alphaVantage,
        apiKey: String = "",
        alpacaAPIKeyId: String = "",
        alpacaSecretKey: String = "",
        alpacaFeed: AlpacaMarketDataFeed = .iex,
        useAlpacaFallback: Bool = true
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.alpacaAPIKeyId = alpacaAPIKeyId
        self.alpacaSecretKey = alpacaSecretKey
        self.alpacaFeed = alpacaFeed
        self.useAlpacaFallback = useAlpacaFallback
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case apiKey
        case alpacaAPIKeyId
        case alpacaSecretKey
        case alpacaFeed
        case useAlpacaFallback
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(MarketDataProvider.self, forKey: .provider) ?? .alphaVantage
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        alpacaAPIKeyId = try container.decodeIfPresent(String.self, forKey: .alpacaAPIKeyId) ?? ""
        alpacaSecretKey = try container.decodeIfPresent(String.self, forKey: .alpacaSecretKey) ?? ""
        alpacaFeed = try container.decodeIfPresent(AlpacaMarketDataFeed.self, forKey: .alpacaFeed) ?? .iex
        useAlpacaFallback = try container.decodeIfPresent(Bool.self, forKey: .useAlpacaFallback) ?? true
    }

    var hasPrimaryAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAlpacaCredentials: Bool {
        !alpacaAPIKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !alpacaSecretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canFetchMarketData: Bool {
        hasPrimaryAPIKey || (useAlpacaFallback && hasAlpacaCredentials)
    }
}

struct CachedQuote: Codable, Sendable, Equatable {
    var ticker: String
    var price: Double
    var updatedAt: Date
}

struct PortfolioValuePoint: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var date: Date
    var grossValue: Double
    var netValue: Double

    init(id: UUID = UUID(), date: Date = Date(), grossValue: Double, netValue: Double) {
        self.id = id
        self.date = date
        self.grossValue = grossValue
        self.netValue = netValue
    }
}

struct MarginScenarioResult: Identifiable, Sendable, Equatable {
    let id = UUID()
    let drawdown: Double
    let stressPortfolioValue: Double
    let stressEquity: Double
}

enum MarginCalculator {
    static func netEquity(portfolioValue: Double, marginUsed: Double) -> Double {
        portfolioValue - marginUsed
    }

    static func equityPercent(portfolioValue: Double, marginUsed: Double) -> Double {
        guard portfolioValue > 0 else { return 0 }
        return netEquity(portfolioValue: portfolioValue, marginUsed: marginUsed) / portfolioValue
    }

    static func paidMargin(marginUsed: Double, freeMarginLimit: Double) -> Double {
        max(0, marginUsed - freeMarginLimit)
    }

    static func monthlyInterest(marginUsed: Double, freeMarginLimit: Double, marginInterestRate: Double) -> Double {
        paidMargin(marginUsed: marginUsed, freeMarginLimit: freeMarginLimit) * marginInterestRate / 12.0
    }

    static func monthlySpread(monthlyDividends: Double, monthlyInterest: Double, monthlyBillsPaidByMargin: Double) -> Double {
        monthlyDividends - monthlyInterest - monthlyBillsPaidByMargin
    }

    static func stressPortfolioValue(portfolioValue: Double, drawdown: Double) -> Double {
        portfolioValue * (1 - drawdown)
    }

    static func stressEquity(portfolioValue: Double, marginUsed: Double, drawdown: Double) -> Double {
        stressPortfolioValue(portfolioValue: portfolioValue, drawdown: drawdown) - marginUsed
    }
}

private struct BudgetSnapshotStore: Codable, Sendable {
    let income: Double
    let incomeByMonth: [String: Double]?
    let needsAllocationsByMonth: [String: [UUID: Double]]?
    let wantsAllocationsByMonth: [String: [UUID: Double]]?
    let payFrequency: PayFrequency
    let needsCategories: [Category]
    let wantsCategories: [Category]
    let savingsGoals: [SavingsGoal]
    let incomes: [IncomeEntry]?
    let expenses: [Expense]
    let savingsEntries: [SavingsEntry]?
    let portfolioSnapshot: PortfolioSnapshot?
    let marginBills: [MarginBill]?
    let dividendPayments: [DividendPayment]?
    let holdings: [PortfolioHolding]?
    let marketDataSettings: MarketDataSettings?
    let watchlistTickers: [String]?
    let cachedQuotes: [String: CachedQuote]?
    let portfolioValueHistory: [PortfolioValuePoint]?
    let portfolioTransactions: [PortfolioTransaction]?
    let marginSettings: MarginSettings?
    let recurringElectricBill: RecurringMarginBill?
    let recurringPayments: [RecurringPayment]?
    let creditAccounts: [CreditAccount]?
    let bankAccounts: [BankAccount]?

    enum CodingKeys: String, CodingKey {
        case income
        case incomeByMonth
        case needsAllocationsByMonth
        case wantsAllocationsByMonth
        case payFrequency
        case needsCategories
        case wantsCategories
        case savingsGoals
        case incomes
        case expenses
        case savingsEntries
        case portfolioSnapshot
        case marginBills
        case dividendPayments
        case holdings
        case marketDataSettings
        case watchlistTickers
        case cachedQuotes
        case portfolioValueHistory
        case portfolioTransactions
        case marginSettings
        case recurringElectricBill
        case recurringPayments
        case creditAccounts
        case bankAccounts
    }

    init(
        income: Double,
        incomeByMonth: [String: Double],
        needsAllocationsByMonth: [String: [UUID: Double]],
        wantsAllocationsByMonth: [String: [UUID: Double]],
        payFrequency: PayFrequency,
        needsCategories: [Category],
        wantsCategories: [Category],
        savingsGoals: [SavingsGoal],
        incomes: [IncomeEntry],
        expenses: [Expense],
        savingsEntries: [SavingsEntry],
        portfolioSnapshot: PortfolioSnapshot,
        marginBills: [MarginBill],
        dividendPayments: [DividendPayment],
        holdings: [PortfolioHolding],
        marketDataSettings: MarketDataSettings,
        watchlistTickers: [String],
        cachedQuotes: [String: CachedQuote],
        portfolioValueHistory: [PortfolioValuePoint],
        portfolioTransactions: [PortfolioTransaction],
        marginSettings: MarginSettings,
        recurringElectricBill: RecurringMarginBill,
        recurringPayments: [RecurringPayment],
        creditAccounts: [CreditAccount],
        bankAccounts: [BankAccount]
    ) {
        self.income = income
        self.incomeByMonth = incomeByMonth
        self.needsAllocationsByMonth = needsAllocationsByMonth
        self.wantsAllocationsByMonth = wantsAllocationsByMonth
        self.payFrequency = payFrequency
        self.needsCategories = needsCategories
        self.wantsCategories = wantsCategories
        self.savingsGoals = savingsGoals
        self.incomes = incomes
        self.expenses = expenses
        self.savingsEntries = savingsEntries
        self.portfolioSnapshot = portfolioSnapshot
        self.marginBills = marginBills
        self.dividendPayments = dividendPayments
        self.holdings = holdings
        self.marketDataSettings = marketDataSettings
        self.watchlistTickers = watchlistTickers
        self.cachedQuotes = cachedQuotes
        self.portfolioValueHistory = portfolioValueHistory
        self.portfolioTransactions = portfolioTransactions
        self.marginSettings = marginSettings
        self.recurringElectricBill = recurringElectricBill
        self.recurringPayments = recurringPayments
        self.creditAccounts = creditAccounts
        self.bankAccounts = bankAccounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        income = try container.decode(Double.self, forKey: .income)
        incomeByMonth = try container.decodeIfPresent([String: Double].self, forKey: .incomeByMonth)
        needsAllocationsByMonth = try container.decodeIfPresent([String: [UUID: Double]].self, forKey: .needsAllocationsByMonth)
        wantsAllocationsByMonth = try container.decodeIfPresent([String: [UUID: Double]].self, forKey: .wantsAllocationsByMonth)
        payFrequency = try container.decode(PayFrequency.self, forKey: .payFrequency)
        needsCategories = try container.decode([Category].self, forKey: .needsCategories)
        wantsCategories = try container.decode([Category].self, forKey: .wantsCategories)
        savingsGoals = try container.decode([SavingsGoal].self, forKey: .savingsGoals)
        incomes = try container.decodeIfPresent([IncomeEntry].self, forKey: .incomes)
        expenses = try container.decodeIfPresent([Expense].self, forKey: .expenses) ?? []
        savingsEntries = try container.decodeIfPresent([SavingsEntry].self, forKey: .savingsEntries)
        portfolioSnapshot = try container.decodeIfPresent(PortfolioSnapshot.self, forKey: .portfolioSnapshot)
        marginBills = try container.decodeIfPresent([MarginBill].self, forKey: .marginBills)
        dividendPayments = try container.decodeIfPresent([DividendPayment].self, forKey: .dividendPayments)
        holdings = try container.decodeIfPresent([PortfolioHolding].self, forKey: .holdings)
        marketDataSettings = try container.decodeIfPresent(MarketDataSettings.self, forKey: .marketDataSettings)
        watchlistTickers = try container.decodeIfPresent([String].self, forKey: .watchlistTickers)
        cachedQuotes = try container.decodeIfPresent([String: CachedQuote].self, forKey: .cachedQuotes)
        portfolioValueHistory = try container.decodeIfPresent([PortfolioValuePoint].self, forKey: .portfolioValueHistory)
        portfolioTransactions = try container.decodeIfPresent([PortfolioTransaction].self, forKey: .portfolioTransactions)
        marginSettings = try container.decodeIfPresent(MarginSettings.self, forKey: .marginSettings)
        recurringElectricBill = try container.decodeIfPresent(RecurringMarginBill.self, forKey: .recurringElectricBill)
        recurringPayments = try container.decodeIfPresent([RecurringPayment].self, forKey: .recurringPayments)
        creditAccounts = try container.decodeIfPresent([CreditAccount].self, forKey: .creditAccounts)
        bankAccounts = try container.decodeIfPresent([BankAccount].self, forKey: .bankAccounts)
    }
}

class BudgetModel: ObservableObject {
    static let appGroupIdentifier = "group.Timothy-Wong.Budgeting-App"
    @Published var income: Double = 0
    @Published var incomeByMonth: [String: Double] = [:]
    @Published var needsAllocationsByMonth: [String: [UUID: Double]] = [:]
    @Published var wantsAllocationsByMonth: [String: [UUID: Double]] = [:]
    @Published var payFrequency: PayFrequency = .monthly
    @Published var needsCategories: [Category] = []
    @Published var wantsCategories: [Category] = []
    @Published var savingsGoals: [SavingsGoal] = []
    @Published var incomes: [IncomeEntry] = []
    @Published var expenses: [Expense] = [] {
        didSet {
            recalculateSpent()
        }
    }
    @Published var savingsEntries: [SavingsEntry] = []
    @Published var portfolioSnapshot: PortfolioSnapshot = PortfolioSnapshot()
    @Published var marginBills: [MarginBill] = []
    @Published var dividendPayments: [DividendPayment] = []
    @Published var holdings: [PortfolioHolding] = []
    @Published var marketDataSettings: MarketDataSettings = MarketDataSettings()
    @Published var watchlistTickers: [String] = ["AAPL", "MSFT", "NVDA", "AMZN", "GOOGL", "TSLA"]
    @Published var cachedQuotes: [String: CachedQuote] = [:]
    @Published var marketDataWarning: String?
    @Published var portfolioValueHistory: [PortfolioValuePoint] = []
    @Published var portfolioTransactions: [PortfolioTransaction] = []
    @Published var marginSettings: MarginSettings = MarginSettings()
    @Published var recurringElectricBill: RecurringMarginBill = RecurringMarginBill()
    @Published var recurringPayments: [RecurringPayment] = []
    @Published var creditAccounts: [CreditAccount] = []
    @Published var bankAccounts: [BankAccount] = []

    private static let saveFileName = "budget.json"
    private let localSaveURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(saveFileName)
    private var saveCancellable: AnyCancellable?
    private let saveQueue = DispatchQueue(label: "BudgetModel.save", qos: .utility)
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Timothy-Wong.Budgeting-App",
        category: "BudgetModel"
    )

    init() {
        load()
        saveCancellable = objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleSave()
            }
    }
    
    var annualIncome: Double {
        income * payFrequency.multiplier
    }
    
    var monthlyIncome: Double {
        annualIncome / 12.0
    }
    
    var needsBudget: Double {
        monthlyIncome * 0.50
    }
    
    var savingsBudget: Double {
        monthlyIncome * 0.30
    }
    
    var wantsBudget: Double {
        monthlyIncome * 0.20
    }
    
    var totalNeedsAllocated: Double {
        needsCategories.reduce(0) { $0 + $1.allocatedAmount }
    }
    
    var totalNeedsSpent: Double {
        needsCategories.reduce(0) { $0 + $1.spentAmount }
    }
    
    var totalWantsAllocated: Double {
        wantsCategories.reduce(0) { $0 + $1.allocatedAmount }
    }
    
    var totalWantsSpent: Double {
        wantsCategories.reduce(0) { $0 + $1.spentAmount }
    }
    
    var totalSavingsAllocated: Double {
        savingsGoals.reduce(0) { $0 + $1.monthlyContribution }
    }
    
    var totalSavingsCurrent: Double {
        savingsGoals.reduce(0) { $0 + $1.currentAmount }
    }
    
    var needsRemaining: Double {
        needsBudget - totalNeedsAllocated
    }
    
    var wantsRemaining: Double {
        wantsBudget - totalWantsAllocated
    }
    
    var savingsRemaining: Double {
        savingsBudget - totalSavingsAllocated
    }
    
    var totalRemainingBudget: Double {
        needsRemaining + wantsRemaining + savingsRemaining
    }

    private func scheduleSave() {
        let snapshot = BudgetSnapshotStore(
            income: income,
            incomeByMonth: incomeByMonth,
            needsAllocationsByMonth: needsAllocationsByMonth,
            wantsAllocationsByMonth: wantsAllocationsByMonth,
            payFrequency: payFrequency,
            needsCategories: needsCategories,
            wantsCategories: wantsCategories,
            savingsGoals: savingsGoals,
            incomes: incomes,
            expenses: expenses,
            savingsEntries: savingsEntries,
            portfolioSnapshot: portfolioSnapshot,
            marginBills: marginBills,
            dividendPayments: dividendPayments,
            holdings: holdings,
            marketDataSettings: marketDataSettings,
            watchlistTickers: watchlistTickers,
            cachedQuotes: cachedQuotes,
            portfolioValueHistory: portfolioValueHistory,
            portfolioTransactions: portfolioTransactions,
            marginSettings: marginSettings,
            recurringElectricBill: recurringElectricBill,
            recurringPayments: recurringPayments,
            creditAccounts: creditAccounts,
            bankAccounts: bankAccounts
        )

        let localSaveURL = localSaveURL
        let sharedSaveURL = sharedSaveURL()
        let iCloudSaveURL = iCloudSaveURL()
        let logger = logger
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            logger.error("Failed to encode budget snapshot: \(error.localizedDescription, privacy: .public)")
            return
        }

        saveQueue.async {
            do {
                try data.write(to: localSaveURL, options: Data.WritingOptions.atomic)
                if let sharedSaveURL {
                    let sharedDirectory = sharedSaveURL.deletingLastPathComponent()
                    if !FileManager.default.fileExists(atPath: sharedDirectory.path) {
                        try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
                    }
                    try data.write(to: sharedSaveURL, options: Data.WritingOptions.atomic)
                }

                if let iCloudSaveURL {
                    let iCloudDirectory = iCloudSaveURL.deletingLastPathComponent()
                    if !FileManager.default.fileExists(atPath: iCloudDirectory.path) {
                        try FileManager.default.createDirectory(at: iCloudDirectory, withIntermediateDirectories: true)
                    }
                    try data.write(to: iCloudSaveURL, options: Data.WritingOptions.atomic)
                }
            } catch {
                logger.error("Failed to save budget snapshot: \(error.localizedDescription, privacy: .public)")
            }

            #if canImport(WidgetKit)
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
            }
            #endif
        }
    }

    private func load() {
        let candidateURLs = [iCloudSaveURL(), sharedSaveURL(), localSaveURL].compactMap { $0 }
        let saveURL = mostRecentSaveURL(from: candidateURLs) ?? localSaveURL

        let data: Data
        do {
            data = try Data(contentsOf: saveURL)
        } catch {
            let nsError = error as NSError
            if nsError.domain != NSCocoaErrorDomain || nsError.code != NSFileReadNoSuchFileError {
                logger.error("Failed to read budget snapshot: \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        let snapshot: BudgetSnapshotStore
        do {
            snapshot = try JSONDecoder().decode(BudgetSnapshotStore.self, from: data)
        } catch {
            logger.error("Failed to decode budget snapshot: \(error.localizedDescription, privacy: .public)")
            return
        }

        payFrequency = snapshot.payFrequency
        incomeByMonth = snapshot.incomeByMonth ?? [:]
        needsAllocationsByMonth = snapshot.needsAllocationsByMonth ?? [:]
        wantsAllocationsByMonth = snapshot.wantsAllocationsByMonth ?? [:]
        if incomeByMonth.isEmpty, snapshot.income > 0 {
            incomeByMonth[Self.monthKey(for: Date())] = snapshot.income
        }
        income = incomeByMonth[Self.monthKey(for: Date())] ?? snapshot.income
        needsCategories = snapshot.needsCategories
        wantsCategories = snapshot.wantsCategories
        savingsGoals = snapshot.savingsGoals
        incomes = snapshot.incomes ?? []
        expenses = snapshot.expenses
        savingsEntries = snapshot.savingsEntries ?? []
        portfolioSnapshot = snapshot.portfolioSnapshot ?? PortfolioSnapshot()
        marginBills = snapshot.marginBills ?? []
        dividendPayments = snapshot.dividendPayments ?? []
        holdings = snapshot.holdings ?? []
        marketDataSettings = snapshot.marketDataSettings ?? MarketDataSettings()
        watchlistTickers = Self.normalizedTickers(snapshot.watchlistTickers ?? ["AAPL", "MSFT", "NVDA", "AMZN", "GOOGL", "TSLA"])
        cachedQuotes = snapshot.cachedQuotes ?? [:]
        portfolioValueHistory = snapshot.portfolioValueHistory ?? []
        portfolioTransactions = snapshot.portfolioTransactions ?? []
        marginSettings = snapshot.marginSettings ?? MarginSettings()
        recurringElectricBill = snapshot.recurringElectricBill ?? RecurringMarginBill()
        recurringPayments = snapshot.recurringPayments ?? []
        creditAccounts = snapshot.creditAccounts ?? []
        bankAccounts = snapshot.bankAccounts ?? []

        if expenses.isEmpty {
            let importedNeeds = needsCategories.compactMap { category -> Expense? in
                guard category.spentAmount > 0 else { return nil }
                return Expense(name: "Imported Spend", amount: category.spentAmount, date: Date(), section: .needs, categoryId: category.id)
            }
            let importedWants = wantsCategories.compactMap { category -> Expense? in
                guard category.spentAmount > 0 else { return nil }
                return Expense(name: "Imported Spend", amount: category.spentAmount, date: Date(), section: .wants, categoryId: category.id)
            }
            if !importedNeeds.isEmpty || !importedWants.isEmpty {
                expenses = importedNeeds + importedWants
            }
        }

        recalculateSpent()
        synchronizeLegacyMarginStateFromLedger()
    }

    private func iCloudSaveURL() -> URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(Self.saveFileName)
    }

    private func sharedSaveURL() -> URL? {
        guard let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            return nil
        }

        return sharedContainerURL.appendingPathComponent(Self.saveFileName)
    }

    private func mostRecentSaveURL(from urls: [URL]) -> URL? {
        urls
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .max { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate < rhsDate
            }
    }

    private static func normalizedTickers(_ tickers: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for raw in tickers {
            let ticker = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !ticker.isEmpty else { continue }
            guard seen.insert(ticker).inserted else { continue }
            normalized.append(ticker)
        }
        return normalized
    }

    var marginUsedFromLedger: Double {
        portfolioTransactions.reduce(0) { partial, tx in
            switch tx.type {
            case .billPaidByMargin:
                return partial + tx.amount
            case .marginInterest:
                return partial + tx.amount
            case .sell:
                return partial - tx.amount
            case .manualAdjustment:
                return partial + tx.amount
            case .buy, .contribution, .dividend:
                return partial
            }
        }
    }

    var holdingsFromTransactions: [PortfolioHolding] {
        var buckets: [String: (shares: Double, cost: Double)] = [:]
        let ordered = portfolioTransactions.sorted { $0.date < $1.date }
        for tx in ordered {
            let ticker = tx.ticker?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
            switch tx.type {
            case .buy:
                guard !ticker.isEmpty else { continue }
                let shares = tx.shares ?? 0
                let totalCost = tx.amount
                var item = buckets[ticker, default: (0, 0)]
                item.shares += shares
                item.cost += totalCost
                buckets[ticker] = item
            case .sell:
                guard !ticker.isEmpty else { continue }
                let sharesToSell = max(tx.shares ?? 0, 0)
                guard sharesToSell > 0, var item = buckets[ticker], item.shares > 0 else { continue }
                let average = item.shares > 0 ? item.cost / item.shares : 0
                let sold = min(sharesToSell, item.shares)
                item.shares -= sold
                item.cost = max(item.cost - average * sold, 0)
                buckets[ticker] = item
            default:
                continue
            }
        }

        return buckets.compactMap { ticker, bucket in
            guard bucket.shares > 0 else { return nil }
            let quote = cachedQuotes[ticker]?.price ?? 0
            return PortfolioHolding(
                ticker: ticker,
                shares: bucket.shares,
                averageCost: bucket.shares > 0 ? bucket.cost / bucket.shares : 0,
                currentPrice: quote,
                annualDividendPerShare: holdings.first(where: { $0.ticker.uppercased() == ticker })?.annualDividendPerShare ?? 0,
                dividendFrequency: holdings.first(where: { $0.ticker.uppercased() == ticker })?.dividendFrequency ?? .quarterly,
                assetType: holdings.first(where: { $0.ticker.uppercased() == ticker })?.assetType ?? .dividendStock,
                dividendReliability: holdings.first(where: { $0.ticker.uppercased() == ticker })?.dividendReliability ?? .medium,
                notes: holdings.first(where: { $0.ticker.uppercased() == ticker })?.notes ?? "",
                nextExDividendDate: holdings.first(where: { $0.ticker.uppercased() == ticker })?.nextExDividendDate,
                nextPayDate: holdings.first(where: { $0.ticker.uppercased() == ticker })?.nextPayDate
            )
        }.sorted { $0.ticker < $1.ticker }
    }

    func addPortfolioTransaction(_ transaction: PortfolioTransaction) {
        portfolioTransactions.append(transaction)
        synchronizeLegacyMarginStateFromLedger()
    }

    func addInvestment(
        ticker: String,
        dollarsInvested: Double,
        sharesBought: Double,
        pricePerShare: Double,
        date: Date,
        fundingSource: InvestmentFundingSource
    ) {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else { return }

        if fundingSource == .newContribution {
            addPortfolioTransaction(
                PortfolioTransaction(
                    date: date,
                    type: .contribution,
                    amount: dollarsInvested,
                    notes: "Auto contribution for \(cleanTicker) buy"
                )
            )
            portfolioSnapshot.cashBalance += dollarsInvested
        }

        addPortfolioTransaction(
            PortfolioTransaction(
                date: date,
                type: .buy,
                ticker: cleanTicker,
                shares: sharesBought,
                pricePerShare: pricePerShare,
                amount: dollarsInvested,
                notes: "Funding: \(fundingSource.rawValue)"
            )
        )

        switch fundingSource {
        case .cash, .newContribution:
            portfolioSnapshot.cashBalance = max(portfolioSnapshot.cashBalance - dollarsInvested, 0)
        case .margin:
            addPortfolioTransaction(
                PortfolioTransaction(
                    date: date,
                    type: .manualAdjustment,
                    amount: dollarsInvested,
                    notes: "Margin draw for \(cleanTicker) buy"
                )
            )
        }
        synchronizeLegacyMarginStateFromLedger()
    }

    func markElectricBillPaidByMargin(actualAmount: Double, date: Date) {
        addPortfolioTransaction(
            PortfolioTransaction(
                date: date,
                type: .billPaidByMargin,
                amount: actualAmount,
                notes: recurringElectricBill.name
            )
        )
    }

    func synchronizeLegacyMarginStateFromLedger() {
        let derivedHoldings = holdingsFromTransactions
        if !derivedHoldings.isEmpty || !portfolioTransactions.isEmpty {
            holdings = derivedHoldings
            portfolioSnapshot.marginUsed = max(marginUsedFromLedger, 0)
        }

        portfolioSnapshot.freeMarginLimit = marginSettings.interestFreeMarginLimit
        portfolioSnapshot.marginInterestRate = marginSettings.marginInterestRate
    }

    func categoryName(for expense: Expense) -> String {
        switch expense.section {
        case .needs:
            return needsCategories.first(where: { $0.id == expense.categoryId })?.name ?? "Needs"
        case .wants:
            return wantsCategories.first(where: { $0.id == expense.categoryId })?.name ?? "Wants"
        }
    }

    func savingsGoalName(for entry: SavingsEntry) -> String {
        savingsGoals.first(where: { $0.id == entry.goalId })?.displayName ?? "Savings"
    }

    func addIncomeEntry(_ entry: IncomeEntry) {
        incomes.append(entry)
        applyBalanceImpact(for: entry, multiplier: 1)
    }

    func updateIncomeEntry(_ updatedEntry: IncomeEntry) {
        guard let index = incomes.firstIndex(where: { $0.id == updatedEntry.id }) else { return }
        let previousEntry = incomes[index]
        applyBalanceImpact(for: previousEntry, multiplier: -1)
        incomes[index] = updatedEntry
        applyBalanceImpact(for: updatedEntry, multiplier: 1)
    }

    func deleteIncomeEntry(id: UUID) {
        guard let index = incomes.firstIndex(where: { $0.id == id }) else { return }
        let removedEntry = incomes.remove(at: index)
        applyBalanceImpact(for: removedEntry, multiplier: -1)
    }

    func addExpense(_ expense: Expense) {
        expenses.append(expense)
        applyBalanceImpact(for: expense, multiplier: 1)
    }

    func updateExpense(_ updatedExpense: Expense) {
        guard let index = expenses.firstIndex(where: { $0.id == updatedExpense.id }) else { return }
        let previousExpense = expenses[index]
        applyBalanceImpact(for: previousExpense, multiplier: -1)
        expenses[index] = updatedExpense
        applyBalanceImpact(for: updatedExpense, multiplier: 1)
    }

    func deleteExpense(id: UUID) {
        guard let index = expenses.firstIndex(where: { $0.id == id }) else { return }
        let removedExpense = expenses.remove(at: index)
        applyBalanceImpact(for: removedExpense, multiplier: -1)
    }

    func removeExpenses(for categoryId: UUID) {
        let removedExpenses = expenses.filter { $0.categoryId == categoryId }
        expenses.removeAll { $0.categoryId == categoryId }
        for expense in removedExpenses {
            applyBalanceImpact(for: expense, multiplier: -1)
        }
    }

    func creditAccountActualBalance(_ account: CreditAccount) -> Double {
        let normalizedName = normalizedAccountName(account.name)
        guard !normalizedName.isEmpty else { return 0 }
        return expenses.reduce(account.startingBalance) { partial, expense in
            if let paidCard = creditCardPaymentTarget(from: expense.note),
               paidCard.caseInsensitiveCompare(account.name) == .orderedSame {
                return partial - expense.amount
            }
            let paymentAccount = normalizedAccountName(expense.paymentAccount)
            guard paymentAccount == normalizedName else { return partial }
            return partial + expense.amount
        }
    }

    func creditCardPaymentTarget(from note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[CC_PAYMENT:") else { return nil }
        guard let endIndex = trimmed.firstIndex(of: "]") else { return nil }
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 12)
        guard startIndex < endIndex else { return nil }
        let accountName = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return accountName.isEmpty ? nil : accountName
    }

    func applyMonthlyAllocations(for date: Date) {
        let key = Self.monthKey(for: date)
        let previousKey = Self.monthKey(for: Calendar.current.date(byAdding: .month, value: -1, to: date) ?? date)

        if incomeByMonth[key] == nil {
            incomeByMonth[key] = incomeByMonth[previousKey] ?? income
        }

        var needsMonth = needsAllocationsByMonth[key] ?? [:]
        for index in needsCategories.indices {
            let id = needsCategories[index].id
            let value = needsMonth[id]
                ?? needsAllocationsByMonth[previousKey]?[id]
                ?? needsCategories[index].allocatedAmount
            needsMonth[id] = value
            needsCategories[index].allocatedAmount = value
        }
        needsAllocationsByMonth[key] = needsMonth

        var wantsMonth = wantsAllocationsByMonth[key] ?? [:]
        for index in wantsCategories.indices {
            let id = wantsCategories[index].id
            let value = wantsMonth[id]
                ?? wantsAllocationsByMonth[previousKey]?[id]
                ?? wantsCategories[index].allocatedAmount
            wantsMonth[id] = value
            wantsCategories[index].allocatedAmount = value
        }
        wantsAllocationsByMonth[key] = wantsMonth
    }

    func setAllocation(_ amount: Double, for categoryId: UUID, section: BudgetSection, date: Date) {
        let key = Self.monthKey(for: date)
        switch section {
        case .needs:
            var month = needsAllocationsByMonth[key] ?? [:]
            month[categoryId] = amount
            needsAllocationsByMonth[key] = month
        case .wants:
            var month = wantsAllocationsByMonth[key] ?? [:]
            month[categoryId] = amount
            wantsAllocationsByMonth[key] = month
        }
    }

    func removeAllocation(for categoryId: UUID, section: BudgetSection) {
        switch section {
        case .needs:
            for key in Array(needsAllocationsByMonth.keys) {
                needsAllocationsByMonth[key]?[categoryId] = nil
            }
        case .wants:
            for key in Array(wantsAllocationsByMonth.keys) {
                wantsAllocationsByMonth[key]?[categoryId] = nil
            }
        }
    }

    func addSavingsEntry(_ entry: SavingsEntry) {
        savingsEntries.append(entry)
        adjustSavingsGoalBalance(for: entry.goalId, delta: entry.amount)
    }

    func updateSavingsEntry(_ updatedEntry: SavingsEntry) {
        guard let index = savingsEntries.firstIndex(where: { $0.id == updatedEntry.id }) else { return }
        let previousEntry = savingsEntries[index]
        savingsEntries[index] = updatedEntry

        if previousEntry.goalId == updatedEntry.goalId {
            adjustSavingsGoalBalance(for: updatedEntry.goalId, delta: updatedEntry.amount - previousEntry.amount)
        } else {
            adjustSavingsGoalBalance(for: previousEntry.goalId, delta: -previousEntry.amount)
            adjustSavingsGoalBalance(for: updatedEntry.goalId, delta: updatedEntry.amount)
        }
    }

    func deleteSavingsEntry(id: UUID) {
        guard let index = savingsEntries.firstIndex(where: { $0.id == id }) else { return }
        let removedEntry = savingsEntries.remove(at: index)
        adjustSavingsGoalBalance(for: removedEntry.goalId, delta: -removedEntry.amount)
    }

    func removeSavingsGoal(id: UUID) {
        savingsGoals.removeAll { $0.id == id }
        savingsEntries.removeAll { $0.goalId == id }
    }

    func income(for date: Date) -> Double {
        incomeByMonth[Self.monthKey(for: date)] ?? 0
    }

    func setIncome(_ value: Double, for date: Date) {
        incomeByMonth[Self.monthKey(for: date)] = value
    }

    static func monthKey(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    private func recalculateSpent() {
        guard !expenses.isEmpty else {
            for index in needsCategories.indices {
                needsCategories[index].spentAmount = 0
            }
            for index in wantsCategories.indices {
                wantsCategories[index].spentAmount = 0
            }
            return
        }

        var needsTotals: [UUID: Double] = [:]
        var wantsTotals: [UUID: Double] = [:]

        for expense in expenses {
            switch expense.section {
            case .needs:
                needsTotals[expense.categoryId, default: 0] += expense.amount
            case .wants:
                wantsTotals[expense.categoryId, default: 0] += expense.amount
            }
        }

        for index in needsCategories.indices {
            let id = needsCategories[index].id
            needsCategories[index].spentAmount = needsTotals[id, default: 0]
        }

        for index in wantsCategories.indices {
            let id = wantsCategories[index].id
            wantsCategories[index].spentAmount = wantsTotals[id, default: 0]
        }
    }

    private func adjustSavingsGoalBalance(for goalId: UUID, delta: Double) {
        guard let index = savingsGoals.firstIndex(where: { $0.id == goalId }) else { return }
        let updatedAmount = savingsGoals[index].currentAmount + delta
        savingsGoals[index].currentAmount = max(updatedAmount, 0)
    }

    private func applyBalanceImpact(for income: IncomeEntry, multiplier: Double) {
        applyBankAccountDelta(named: income.bankName, delta: income.amount * multiplier)
    }

    private func applyBalanceImpact(for expense: Expense, multiplier: Double) {
        applyBankAccountDelta(named: expense.paymentAccount, delta: -expense.amount * multiplier)
    }

    private func applyBankAccountDelta(named accountName: String, delta: Double) {
        let normalized = normalizedAccountName(accountName)
        guard !normalized.isEmpty else { return }
        guard let index = bankAccounts.firstIndex(where: { normalizedAccountName($0.name) == normalized }) else { return }
        bankAccounts[index].balance += delta
    }

    private func normalizedAccountName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
