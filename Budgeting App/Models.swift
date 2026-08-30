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
import FoundationModels

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
    var paymentAccountId: UUID?
    var note: String
    var creditCardPaymentTarget: String?
    var creditCardPaymentTargetId: UUID?
    var plaidMetadata: PlaidSourceMetadata?

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        date: Date = Date(),
        section: BudgetSection,
        categoryId: UUID,
        paymentAccount: String = "",
        paymentAccountId: UUID? = nil,
        note: String = "",
        creditCardPaymentTarget: String? = nil,
        creditCardPaymentTargetId: UUID? = nil,
        plaidMetadata: PlaidSourceMetadata? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
        self.section = section
        self.categoryId = categoryId
        self.paymentAccount = paymentAccount
        self.paymentAccountId = paymentAccountId
        self.note = note
        self.creditCardPaymentTarget = creditCardPaymentTarget
        self.creditCardPaymentTargetId = creditCardPaymentTargetId
        self.plaidMetadata = plaidMetadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case date
        case section
        case categoryId
        case paymentAccount
        case paymentAccountId
        case note
        case creditCardPaymentTarget
        case creditCardPaymentTargetId
        case plaidMetadata
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
        paymentAccountId = try container.decodeIfPresent(UUID.self, forKey: .paymentAccountId)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        creditCardPaymentTarget = try container.decodeIfPresent(String.self, forKey: .creditCardPaymentTarget)
        creditCardPaymentTargetId = try container.decodeIfPresent(UUID.self, forKey: .creditCardPaymentTargetId)
        plaidMetadata = try container.decodeIfPresent(PlaidSourceMetadata.self, forKey: .plaidMetadata)
        if creditCardPaymentTarget == nil {
            creditCardPaymentTarget = Self.extractCreditCardTarget(from: &note)
        }
    }

    private static func extractCreditCardTarget(from note: inout String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[CC_PAYMENT:") else { return nil }
        guard let endIndex = trimmed.firstIndex(of: "]") else { return nil }
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 12)
        guard startIndex < endIndex else { return nil }
        let accountName = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !accountName.isEmpty {
            let afterMarker = trimmed.index(after: endIndex)
            note = String(trimmed[afterMarker...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return accountName
        }
        return nil
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
    var plaidMetadata: PlaidSourceMetadata?

    init(
        id: UUID = UUID(),
        name: String,
        closingDay: Int = 1,
        dueDay: Int,
        startingBalance: Double = 0,
        expectedAmount: Double = 0,
        creditLimit: Double = 0,
        isActive: Bool = true,
        note: String = "",
        plaidMetadata: PlaidSourceMetadata? = nil
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
        self.plaidMetadata = plaidMetadata
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
        case plaidMetadata
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
        plaidMetadata = try container.decodeIfPresent(PlaidSourceMetadata.self, forKey: .plaidMetadata)
    }
}

struct BankAccount: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var balance: Double
    var note: String
    var plaidMetadata: PlaidSourceMetadata?

    init(id: UUID = UUID(), name: String, balance: Double = 0, note: String = "", plaidMetadata: PlaidSourceMetadata? = nil) {
        self.id = id
        self.name = name
        self.balance = balance
        self.note = note
        self.plaidMetadata = plaidMetadata
    }
}

enum FinancialAccountSource: String, Codable, Sendable, Equatable {
    case manual
    case plaid
}

enum FinancialAccountKind: String, Codable, Sendable, Equatable {
    case depository
    case credit
    case investment
    case loan
    case other
}

struct FinancialAccount: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var institutionName: String?
    var kind: FinancialAccountKind
    var source: FinancialAccountSource
    var externalAccountId: String?
    var externalItemId: String?
    var isActive: Bool
    var lastSyncedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        institutionName: String? = nil,
        kind: FinancialAccountKind,
        source: FinancialAccountSource = .manual,
        externalAccountId: String? = nil,
        externalItemId: String? = nil,
        isActive: Bool = true,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.institutionName = institutionName
        self.kind = kind
        self.source = source
        self.externalAccountId = externalAccountId
        self.externalItemId = externalItemId
        self.isActive = isActive
        self.lastSyncedAt = lastSyncedAt
    }
}

struct PortfolioAccount: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var financialAccountId: UUID?
    var name: String
    var cashBalance: Double
    var marginBalance: Double
    var isActive: Bool

    init(
        id: UUID = UUID(),
        financialAccountId: UUID? = nil,
        name: String,
        cashBalance: Double = 0,
        marginBalance: Double = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.financialAccountId = financialAccountId
        self.name = name
        self.cashBalance = cashBalance
        self.marginBalance = marginBalance
        self.isActive = isActive
    }
}

struct CashTransfer: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var amount: Double
    var date: Date
    var fromAccountName: String
    var toAccountName: String
    var fromAccountId: UUID?
    var toAccountId: UUID?
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        date: Date = Date(),
        fromAccountName: String,
        toAccountName: String,
        fromAccountId: UUID? = nil,
        toAccountId: UUID? = nil,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
        self.fromAccountName = fromAccountName
        self.toAccountName = toAccountName
        self.fromAccountId = fromAccountId
        self.toAccountId = toAccountId
        self.note = note
    }
}

struct WatchlistAlertSettings: Codable, Sendable, Equatable {
    var isEnabled: Bool
    var percentMoveThreshold: Double
    var priceAbove: Double?
    var priceBelow: Double?

    init(
        isEnabled: Bool = true,
        percentMoveThreshold: Double = 1.5,
        priceAbove: Double? = nil,
        priceBelow: Double? = nil
    ) {
        self.isEnabled = isEnabled
        self.percentMoveThreshold = max(percentMoveThreshold, 0.25)
        self.priceAbove = priceAbove
        self.priceBelow = priceBelow
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
    var bankAccountId: UUID?
    var plaidMetadata: PlaidSourceMetadata?

    init(id: UUID = UUID(), name: String, amount: Double, date: Date = Date(), bankName: String = "", bankAccountId: UUID? = nil, plaidMetadata: PlaidSourceMetadata? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
        self.bankName = bankName
        self.bankAccountId = bankAccountId
        self.plaidMetadata = plaidMetadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case date
        case bankName
        case bankAccountId
        case plaidMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decode(Double.self, forKey: .amount)
        date = try container.decode(Date.self, forKey: .date)
        bankName = try container.decodeIfPresent(String.self, forKey: .bankName) ?? ""
        bankAccountId = try container.decodeIfPresent(UUID.self, forKey: .bankAccountId)
        plaidMetadata = try container.decodeIfPresent(PlaidSourceMetadata.self, forKey: .plaidMetadata)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(date, forKey: .date)
        try container.encode(bankName, forKey: .bankName)
        try container.encodeIfPresent(bankAccountId, forKey: .bankAccountId)
        try container.encodeIfPresent(plaidMetadata, forKey: .plaidMetadata)
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
    var creditCardPaymentTarget: String?

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
        note: String = "",
        creditCardPaymentTarget: String? = nil
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
        self.creditCardPaymentTarget = creditCardPaymentTarget
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
        case creditCardPaymentTarget
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
        creditCardPaymentTarget = try container.decodeIfPresent(String.self, forKey: .creditCardPaymentTarget)
        if creditCardPaymentTarget == nil {
            creditCardPaymentTarget = Self.extractCreditCardTarget(from: &note)
        }
    }

    private static func extractCreditCardTarget(from note: inout String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[CC_PAYMENT:") else { return nil }
        guard let endIndex = trimmed.firstIndex(of: "]") else { return nil }
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 12)
        guard startIndex < endIndex else { return nil }
        let accountName = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !accountName.isEmpty {
            let afterMarker = trimmed.index(after: endIndex)
            note = String(trimmed[afterMarker...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return accountName
        }
        return nil
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
    var portfolioAccountId: UUID?
    var fundingBankAccount: String?
    var fundingBankAccountId: UUID?
    var plaidMetadata: PlaidSourceMetadata?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        type: PortfolioTransactionType,
        ticker: String? = nil,
        shares: Double? = nil,
        pricePerShare: Double? = nil,
        amount: Double,
        notes: String? = nil,
        portfolioAccountId: UUID? = nil,
        fundingBankAccount: String? = nil,
        fundingBankAccountId: UUID? = nil,
        plaidMetadata: PlaidSourceMetadata? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.ticker = ticker
        self.shares = shares
        self.pricePerShare = pricePerShare
        self.amount = amount
        self.notes = notes
        self.portfolioAccountId = portfolioAccountId
        self.fundingBankAccount = fundingBankAccount
        self.fundingBankAccountId = fundingBankAccountId
        self.plaidMetadata = plaidMetadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case type
        case ticker
        case shares
        case pricePerShare
        case amount
        case notes
        case portfolioAccountId
        case fundingBankAccount
        case fundingBankAccountId
        case plaidMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        type = try container.decode(PortfolioTransactionType.self, forKey: .type)
        ticker = try container.decodeIfPresent(String.self, forKey: .ticker)
        shares = try container.decodeIfPresent(Double.self, forKey: .shares)
        pricePerShare = try container.decodeIfPresent(Double.self, forKey: .pricePerShare)
        amount = try container.decode(Double.self, forKey: .amount)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        portfolioAccountId = try container.decodeIfPresent(UUID.self, forKey: .portfolioAccountId)
        fundingBankAccount = try container.decodeIfPresent(String.self, forKey: .fundingBankAccount)
        fundingBankAccountId = try container.decodeIfPresent(UUID.self, forKey: .fundingBankAccountId)
        plaidMetadata = try container.decodeIfPresent(PlaidSourceMetadata.self, forKey: .plaidMetadata)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(ticker, forKey: .ticker)
        try container.encodeIfPresent(shares, forKey: .shares)
        try container.encodeIfPresent(pricePerShare, forKey: .pricePerShare)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(portfolioAccountId, forKey: .portfolioAccountId)
        try container.encodeIfPresent(fundingBankAccount, forKey: .fundingBankAccount)
        try container.encodeIfPresent(fundingBankAccountId, forKey: .fundingBankAccountId)
        try container.encodeIfPresent(plaidMetadata, forKey: .plaidMetadata)
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
    var portfolioAccountId: UUID?
    var plaidMetadata: PlaidSourceMetadata?

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
        nextPayDate: Date? = nil,
        portfolioAccountId: UUID? = nil,
        plaidMetadata: PlaidSourceMetadata? = nil
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
        self.portfolioAccountId = portfolioAccountId
        self.plaidMetadata = plaidMetadata
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

struct TickerNote: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var ticker: String
    var title: String?
    var text: String
    var url: String?
    var urlTitle: String?
    var category: String?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), ticker: String, title: String? = nil, text: String, url: String? = nil, urlTitle: String? = nil, category: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.ticker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.text = text
        self.url = url?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.urlTitle = urlTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.category = category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

let noteCategories = ["Idea", "Research", "YouTube", "News", "Earnings", "Technical", "Analysis"]

struct TickerNewsArticle: Identifiable, Codable, Sendable, Equatable {
    var id: String { url }
    var headline: String
    var source: String
    var summary: String
    var url: String
    var imageURL: String?
    var publishedAt: Date
}

struct TickerResearch: Codable, Sendable, Equatable {
    var bullCase: String
    var bearCase: String
    var newsSummary: String
    var articles: [TickerNewsArticle]
    var updatedAt: Date?

    init(
        bullCase: String = "",
        bearCase: String = "",
        newsSummary: String = "",
        articles: [TickerNewsArticle] = [],
        updatedAt: Date? = nil
    ) {
        self.bullCase = bullCase
        self.bearCase = bearCase
        self.newsSummary = newsSummary
        self.articles = articles
        self.updatedAt = updatedAt
    }
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

struct TickerPricePoint: Identifiable, Sendable, Equatable {
    let id: UUID
    var date: Date
    var close: Double

    init(id: UUID = UUID(), date: Date, close: Double) {
        self.id = id
        self.date = date
        self.close = close
    }

    static func closes(from points: [TickerPricePoint]) -> [Double] {
        points.map(\.close)
    }

    static func estimated(from closes: [Double], endingOn endDate: Date = Date()) -> [TickerPricePoint] {
        guard !closes.isEmpty else { return [] }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        var date = calendar.startOfDay(for: endDate)
        var points: [TickerPricePoint] = []

        for close in closes.reversed() {
            points.insert(TickerPricePoint(date: date, close: close), at: 0)
            repeat {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
                date = previous
            } while calendar.isDateInWeekend(date)
        }

        return points
    }

    static func closesForIndicators(history: [TickerPricePoint], currentPrice: Double?) -> [Double] {
        var closes = closes(from: history)
        guard let currentPrice, currentPrice > 0 else { return closes }
        if closes.isEmpty { return [currentPrice] }

        if let lastDate = history.last?.date,
           Calendar.current.isDateInToday(lastDate) {
            closes[closes.count - 1] = currentPrice
        } else {
            closes.append(currentPrice)
        }
        return closes
    }
}

struct MACDResult: Equatable, Sendable {
    let line: Double
    let signal: Double
    let histogram: Double
}

enum TickerIndicators {
    static func sma(_ values: [Double], period: Int) -> Double? {
        guard period > 0, values.count >= period else { return nil }
        return values.suffix(period).reduce(0, +) / Double(period)
    }

    static func ema(_ values: [Double], period: Int) -> Double? {
        guard period > 0, values.count >= period else { return nil }
        let multiplier = 2.0 / Double(period + 1)
        var ema = values.prefix(period).reduce(0, +) / Double(period)
        for price in values.dropFirst(period) {
            ema = ((price - ema) * multiplier) + ema
        }
        return ema
    }

    static func emaValues(_ values: [Double], period: Int) -> [Double] {
        guard period > 0, values.count >= period else { return [] }
        let multiplier = 2.0 / Double(period + 1)
        var output = [Double](repeating: 0, count: values.count)
        var ema = values.prefix(period).reduce(0, +) / Double(period)
        output[period - 1] = ema
        for index in period..<values.count {
            ema = ((values[index] - ema) * multiplier) + ema
            output[index] = ema
        }
        return output
    }

    static func rsi(_ values: [Double], period: Int = 14) -> Double? {
        guard period > 0, values.count > period else { return nil }

        var averageGain = 0.0
        var averageLoss = 0.0
        for index in 1...period {
            let delta = values[index] - values[index - 1]
            if delta >= 0 {
                averageGain += delta
            } else {
                averageLoss += abs(delta)
            }
        }
        averageGain /= Double(period)
        averageLoss /= Double(period)

        if values.count > period + 1 {
            for index in (period + 1)..<values.count {
                let delta = values[index] - values[index - 1]
                let gain = max(delta, 0)
                let loss = max(-delta, 0)
                averageGain = ((averageGain * Double(period - 1)) + gain) / Double(period)
                averageLoss = ((averageLoss * Double(period - 1)) + loss) / Double(period)
            }
        }

        if averageLoss == 0 {
            return averageGain == 0 ? 50 : 100
        }
        let relativeStrength = averageGain / averageLoss
        return 100 - (100 / (1 + relativeStrength))
    }

    static func macd(
        _ values: [Double],
        fastPeriod: Int = 12,
        slowPeriod: Int = 26,
        signalPeriod: Int = 9
    ) -> MACDResult? {
        guard fastPeriod > 0,
              slowPeriod > fastPeriod,
              signalPeriod > 0,
              values.count >= slowPeriod + signalPeriod - 1 else {
            return nil
        }

        let fastEMA = emaValues(values, period: fastPeriod)
        let slowEMA = emaValues(values, period: slowPeriod)
        let macdSeries = (slowPeriod - 1..<values.count).map { fastEMA[$0] - slowEMA[$0] }
        guard let line = macdSeries.last,
              let signal = ema(macdSeries, period: signalPeriod) else {
            return nil
        }
        return MACDResult(line: line, signal: signal, histogram: line - signal)
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
    let watchlistAlertSettings: [String: WatchlistAlertSettings]?
    let tickerNotes: [String: [TickerNote]]?
    let tickerResearch: [String: TickerResearch]?
    let cachedQuotes: [String: CachedQuote]?
    let portfolioValueHistory: [PortfolioValuePoint]?
    let portfolioTransactions: [PortfolioTransaction]?
    let marginSettings: MarginSettings?
    let recurringElectricBill: RecurringMarginBill?
    let recurringPayments: [RecurringPayment]?
    let creditAccounts: [CreditAccount]?
    let bankAccounts: [BankAccount]?
    let cashTransfers: [CashTransfer]?
    let plaidConnectionStatuses: [PlaidConnectionStatus]?
    let plaidReviewItems: [PlaidReviewItem]?
    let financialAccounts: [FinancialAccount]?
    let portfolioAccounts: [PortfolioAccount]?

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
        case watchlistAlertSettings
        case tickerNotes
        case tickerResearch
        case cachedQuotes
        case portfolioValueHistory
        case portfolioTransactions
        case marginSettings
        case recurringElectricBill
        case recurringPayments
        case creditAccounts
        case bankAccounts
        case cashTransfers
        case plaidConnectionStatuses
        case plaidReviewItems
        case financialAccounts
        case portfolioAccounts
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
        watchlistAlertSettings: [String: WatchlistAlertSettings],
        tickerNotes: [String: [TickerNote]],
        tickerResearch: [String: TickerResearch],
        cachedQuotes: [String: CachedQuote],
        portfolioValueHistory: [PortfolioValuePoint],
        portfolioTransactions: [PortfolioTransaction],
        marginSettings: MarginSettings,
        recurringElectricBill: RecurringMarginBill,
        recurringPayments: [RecurringPayment],
        creditAccounts: [CreditAccount],
        bankAccounts: [BankAccount],
        cashTransfers: [CashTransfer],
        plaidConnectionStatuses: [PlaidConnectionStatus],
        plaidReviewItems: [PlaidReviewItem],
        financialAccounts: [FinancialAccount],
        portfolioAccounts: [PortfolioAccount]
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
        self.watchlistAlertSettings = watchlistAlertSettings
        self.tickerNotes = tickerNotes
        self.tickerResearch = tickerResearch
        self.cachedQuotes = cachedQuotes
        self.portfolioValueHistory = portfolioValueHistory
        self.portfolioTransactions = portfolioTransactions
        self.marginSettings = marginSettings
        self.recurringElectricBill = recurringElectricBill
        self.recurringPayments = recurringPayments
        self.creditAccounts = creditAccounts
        self.bankAccounts = bankAccounts
        self.cashTransfers = cashTransfers
        self.plaidConnectionStatuses = plaidConnectionStatuses
        self.plaidReviewItems = plaidReviewItems
        self.financialAccounts = financialAccounts
        self.portfolioAccounts = portfolioAccounts
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
        watchlistAlertSettings = try container.decodeIfPresent([String: WatchlistAlertSettings].self, forKey: .watchlistAlertSettings)
        tickerNotes = try container.decodeIfPresent([String: [TickerNote]].self, forKey: .tickerNotes)
        tickerResearch = try container.decodeIfPresent([String: TickerResearch].self, forKey: .tickerResearch)
        cachedQuotes = try container.decodeIfPresent([String: CachedQuote].self, forKey: .cachedQuotes)
        portfolioValueHistory = try container.decodeIfPresent([PortfolioValuePoint].self, forKey: .portfolioValueHistory)
        portfolioTransactions = try container.decodeIfPresent([PortfolioTransaction].self, forKey: .portfolioTransactions)
        marginSettings = try container.decodeIfPresent(MarginSettings.self, forKey: .marginSettings)
        recurringElectricBill = try container.decodeIfPresent(RecurringMarginBill.self, forKey: .recurringElectricBill)
        recurringPayments = try container.decodeIfPresent([RecurringPayment].self, forKey: .recurringPayments)
        creditAccounts = try container.decodeIfPresent([CreditAccount].self, forKey: .creditAccounts)
        bankAccounts = try container.decodeIfPresent([BankAccount].self, forKey: .bankAccounts)
        cashTransfers = try container.decodeIfPresent([CashTransfer].self, forKey: .cashTransfers)
        plaidConnectionStatuses = try container.decodeIfPresent([PlaidConnectionStatus].self, forKey: .plaidConnectionStatuses)
        plaidReviewItems = try container.decodeIfPresent([PlaidReviewItem].self, forKey: .plaidReviewItems)
        financialAccounts = try container.decodeIfPresent([FinancialAccount].self, forKey: .financialAccounts)
        portfolioAccounts = try container.decodeIfPresent([PortfolioAccount].self, forKey: .portfolioAccounts)
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
    @Published var watchlistAlertSettings: [String: WatchlistAlertSettings] = [:]
    @Published var tickerNotes: [String: [TickerNote]] = [:]
    @Published var tickerResearch: [String: TickerResearch] = [:]
    @Published var cachedQuotes: [String: CachedQuote] = [:]
    @Published var marketDataWarning: String?
    @Published var portfolioValueHistory: [PortfolioValuePoint] = []
    @Published var portfolioTransactions: [PortfolioTransaction] = []
    @Published var marginSettings: MarginSettings = MarginSettings()
    @Published var recurringElectricBill: RecurringMarginBill = RecurringMarginBill()
    @Published var recurringPayments: [RecurringPayment] = []
    @Published var creditAccounts: [CreditAccount] = []
    @Published var bankAccounts: [BankAccount] = []
    @Published var cashTransfers: [CashTransfer] = []
    @Published var plaidConnectionStatuses: [PlaidConnectionStatus] = []
    @Published var plaidReviewItems: [PlaidReviewItem] = []
    @Published var financialAccounts: [FinancialAccount] = []
    @Published var portfolioAccounts: [PortfolioAccount] = []

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

    var consolidatedHoldings: [PortfolioHolding] {
        let grouped = Dictionary(grouping: holdings) { holding in
            holding.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }

        return grouped.compactMap { ticker, tickerHoldings in
            guard !ticker.isEmpty, var combined = tickerHoldings.first else { return nil }
            let totalShares = tickerHoldings.reduce(0) { $0 + $1.shares }
            let totalCost = tickerHoldings.reduce(0) { $0 + ($1.shares * $1.averageCost) }
            combined.ticker = ticker
            combined.shares = totalShares
            combined.averageCost = totalShares != 0 ? totalCost / totalShares : 0
            combined.currentPrice = cachedQuotes[ticker]?.price
                ?? tickerHoldings.first(where: { $0.currentPrice > 0 })?.currentPrice
                ?? combined.currentPrice
            combined.annualDividendPerShare = tickerHoldings.first(where: { $0.annualDividendPerShare > 0 })?.annualDividendPerShare
                ?? combined.annualDividendPerShare
            combined.notes = tickerHoldings.first(where: { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.notes
                ?? combined.notes
            combined.plaidMetadata = tickerHoldings.first(where: { $0.plaidMetadata != nil })?.plaidMetadata
                ?? combined.plaidMetadata
            return combined
        }
        .sorted { $0.ticker < $1.ticker }
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
        saveToDisk(async: true)
    }

    func saveNow() {
        saveToDisk(async: false)
    }

    private var hasUserData: Bool {
        income > 0 || !incomes.isEmpty || !expenses.isEmpty ||
        !savingsGoals.isEmpty || !portfolioTransactions.isEmpty ||
        !holdings.isEmpty || !marginBills.isEmpty ||
        !creditAccounts.isEmpty || !bankAccounts.isEmpty ||
        !cashTransfers.isEmpty || !recurringPayments.isEmpty ||
        !plaidConnectionStatuses.isEmpty || !plaidReviewItems.isEmpty ||
        needsCategories.contains { $0.allocatedAmount > 0 } ||
        wantsCategories.contains { $0.allocatedAmount > 0 }
    }

    private func saveToDisk(async: Bool) {
        guard hasUserData else {
            logger.notice("Skipping save — no user data exists yet (protecting iCloud data)")
            return
        }

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
            watchlistAlertSettings: watchlistAlertSettings,
            tickerNotes: tickerNotes,
            tickerResearch: tickerResearch,
            cachedQuotes: cachedQuotes,
            portfolioValueHistory: portfolioValueHistory,
            portfolioTransactions: portfolioTransactions,
            marginSettings: marginSettings,
            recurringElectricBill: recurringElectricBill,
            recurringPayments: recurringPayments,
            creditAccounts: creditAccounts,
            bankAccounts: bankAccounts,
            cashTransfers: cashTransfers,
            plaidConnectionStatuses: plaidConnectionStatuses,
            plaidReviewItems: plaidReviewItems,
            financialAccounts: financialAccounts,
            portfolioAccounts: portfolioAccounts
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

        let work = {
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

        if async {
            saveQueue.async(execute: work)
        } else {
            work()
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
        watchlistAlertSettings = Self.normalizedWatchlistAlertSettings(snapshot.watchlistAlertSettings ?? [:])
        tickerNotes = Self.normalizedTickerNotes(snapshot.tickerNotes ?? [:])
        tickerResearch = Self.normalizedTickerResearch(snapshot.tickerResearch ?? [:])
        cachedQuotes = snapshot.cachedQuotes ?? [:]
        portfolioValueHistory = snapshot.portfolioValueHistory ?? []
        portfolioTransactions = snapshot.portfolioTransactions ?? []
        marginSettings = snapshot.marginSettings ?? MarginSettings()
        recurringElectricBill = snapshot.recurringElectricBill ?? RecurringMarginBill()
        recurringPayments = snapshot.recurringPayments ?? []
        creditAccounts = snapshot.creditAccounts ?? []
        bankAccounts = snapshot.bankAccounts ?? []
        cashTransfers = snapshot.cashTransfers ?? []
        plaidConnectionStatuses = snapshot.plaidConnectionStatuses ?? []
        plaidReviewItems = snapshot.plaidReviewItems ?? []
        financialAccounts = snapshot.financialAccounts ?? []
        portfolioAccounts = snapshot.portfolioAccounts ?? []
        migrateLegacyAccountsIfNeeded()

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
        migratePortfolioValueHistory()
    }

    func migrateLegacyAccountsIfNeeded() {
        for bankAccount in bankAccounts where !hasFinancialAccount(id: bankAccount.id, metadata: bankAccount.plaidMetadata) {
            financialAccounts.append(
                FinancialAccount(
                    id: bankAccount.id,
                    name: bankAccount.name,
                    institutionName: bankAccount.plaidMetadata?.institutionName,
                    kind: .depository,
                    source: bankAccount.plaidMetadata == nil ? .manual : .plaid,
                    externalAccountId: bankAccount.plaidMetadata?.accountId,
                    externalItemId: bankAccount.plaidMetadata?.itemId,
                    lastSyncedAt: bankAccount.plaidMetadata?.lastSyncedAt
                )
            )
        }

        for creditAccount in creditAccounts where !hasFinancialAccount(id: creditAccount.id, metadata: creditAccount.plaidMetadata) {
            financialAccounts.append(
                FinancialAccount(
                    id: creditAccount.id,
                    name: creditAccount.name,
                    institutionName: creditAccount.plaidMetadata?.institutionName,
                    kind: .credit,
                    source: creditAccount.plaidMetadata == nil ? .manual : .plaid,
                    externalAccountId: creditAccount.plaidMetadata?.accountId,
                    externalItemId: creditAccount.plaidMetadata?.itemId,
                    isActive: creditAccount.isActive,
                    lastSyncedAt: creditAccount.plaidMetadata?.lastSyncedAt
                )
            )
        }

        let hasLegacyPortfolio = !holdings.isEmpty || !portfolioTransactions.isEmpty ||
            portfolioSnapshot.cashBalance != 0 || portfolioSnapshot.marginUsed != 0
        if hasLegacyPortfolio, portfolioAccounts.isEmpty {
            let plaidMetadata = holdings.compactMap(\.plaidMetadata).first
            let source: FinancialAccountSource = plaidMetadata == nil ? .manual : .plaid
            let financialAccount = FinancialAccount(
                name: "Main Portfolio",
                kind: .investment,
                source: source,
                externalAccountId: plaidMetadata?.accountId,
                externalItemId: plaidMetadata?.itemId,
                lastSyncedAt: plaidMetadata?.lastSyncedAt
            )
            financialAccounts.append(financialAccount)
            portfolioAccounts.append(
                PortfolioAccount(
                    financialAccountId: financialAccount.id,
                    name: financialAccount.name,
                    cashBalance: portfolioSnapshot.cashBalance,
                    marginBalance: portfolioSnapshot.marginUsed
                )
            )
        }

        migrateStableAccountReferencesIfNeeded()
    }

    private func migrateStableAccountReferencesIfNeeded() {
        for index in incomes.indices where incomes[index].bankAccountId == nil {
            incomes[index].bankAccountId = resolveFinancialAccountId(legacyName: incomes[index].bankName, allowedKinds: [.depository], metadata: incomes[index].plaidMetadata)
        }
        for index in expenses.indices {
            if expenses[index].paymentAccountId == nil {
                expenses[index].paymentAccountId = resolveFinancialAccountId(legacyName: expenses[index].paymentAccount, allowedKinds: [.depository, .credit], metadata: expenses[index].plaidMetadata)
            }
            if expenses[index].creditCardPaymentTargetId == nil, let target = creditCardPaymentTarget(for: expenses[index]) {
                expenses[index].creditCardPaymentTargetId = resolveFinancialAccountId(legacyName: target, allowedKinds: [.credit])
            }
        }
        for index in cashTransfers.indices {
            if cashTransfers[index].fromAccountId == nil { cashTransfers[index].fromAccountId = resolveFinancialAccountId(legacyName: cashTransfers[index].fromAccountName, allowedKinds: [.depository]) }
            if cashTransfers[index].toAccountId == nil { cashTransfers[index].toAccountId = resolveFinancialAccountId(legacyName: cashTransfers[index].toAccountName, allowedKinds: [.depository]) }
        }
        for index in portfolioTransactions.indices {
            if portfolioTransactions[index].portfolioAccountId == nil { portfolioTransactions[index].portfolioAccountId = resolvePortfolioAccountId(metadata: portfolioTransactions[index].plaidMetadata) }
            if portfolioTransactions[index].fundingBankAccountId == nil, let name = portfolioTransactions[index].fundingBankAccount { portfolioTransactions[index].fundingBankAccountId = resolveFinancialAccountId(legacyName: name, allowedKinds: [.depository]) }
        }
        for index in holdings.indices where holdings[index].portfolioAccountId == nil {
            holdings[index].portfolioAccountId = resolvePortfolioAccountId(metadata: holdings[index].plaidMetadata)
        }
    }

    private func resolveFinancialAccountId(legacyName: String, allowedKinds: [FinancialAccountKind], metadata: PlaidSourceMetadata? = nil) -> UUID? {
        if let externalId = metadata?.accountId, let account = financialAccounts.first(where: { $0.externalAccountId == externalId && allowedKinds.contains($0.kind) }) { return account.id }
        let normalized = normalizedAccountName(legacyName)
        guard !normalized.isEmpty else { return nil }
        let matches = financialAccounts.filter { allowedKinds.contains($0.kind) && normalizedAccountName($0.name) == normalized }
        if matches.count == 1 { return matches[0].id }
        if matches.count > 1 { return nil }
        var candidates: [(UUID, String, FinancialAccountKind, PlaidSourceMetadata?)] = []
        if allowedKinds.contains(.depository) { candidates += bankAccounts.filter { normalizedAccountName($0.name) == normalized }.map { ($0.id, $0.name, .depository, $0.plaidMetadata) } }
        if allowedKinds.contains(.credit) { candidates += creditAccounts.filter { normalizedAccountName($0.name) == normalized }.map { ($0.id, $0.name, .credit, $0.plaidMetadata) } }
        guard candidates.count == 1 else { return nil }
        let candidate = candidates[0]
        if !financialAccounts.contains(where: { $0.id == candidate.0 }) {
            financialAccounts.append(FinancialAccount(id: candidate.0, name: candidate.1, institutionName: candidate.3?.institutionName, kind: candidate.2, source: candidate.3 == nil ? .manual : .plaid, externalAccountId: candidate.3?.accountId, externalItemId: candidate.3?.itemId, lastSyncedAt: candidate.3?.lastSyncedAt))
        }
        return candidate.0
    }

    private func resolvePortfolioAccountId(metadata: PlaidSourceMetadata?) -> UUID? {
        if let externalId = metadata?.accountId, let financial = financialAccounts.first(where: { $0.externalAccountId == externalId }), let portfolio = portfolioAccounts.first(where: { $0.financialAccountId == financial.id }) { return portfolio.id }
        let active = portfolioAccounts.filter(\.isActive)
        return active.count == 1 ? active[0].id : nil
    }

    private func hasFinancialAccount(id: UUID, metadata: PlaidSourceMetadata?) -> Bool {
        if financialAccounts.contains(where: { $0.id == id }) {
            return true
        }
        if let externalAccountId = metadata?.accountId {
            return financialAccounts.contains { $0.externalAccountId == externalAccountId }
        }
        return false
    }

    private func migratePortfolioValueHistory() {
        var fixedCount = 0
        for i in portfolioValueHistory.indices {
            let point = portfolioValueHistory[i]
            if point.netValue > point.grossValue {
                let correctedNet = point.grossValue - portfolioSnapshot.marginUsed
                portfolioValueHistory[i] = PortfolioValuePoint(
                    id: point.id,
                    date: point.date,
                    grossValue: point.grossValue,
                    netValue: correctedNet
                )
                fixedCount += 1
            }
        }
        if fixedCount > 0 {
            logger.notice("Migrated \(fixedCount) portfolio history points with incorrect net worth values")
        }
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

    private static func normalizedWatchlistAlertSettings(_ settings: [String: WatchlistAlertSettings]) -> [String: WatchlistAlertSettings] {
        settings.reduce(into: [String: WatchlistAlertSettings]()) { result, item in
            let ticker = item.key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !ticker.isEmpty else { return }
            var cleanSettings = item.value
            cleanSettings.percentMoveThreshold = max(cleanSettings.percentMoveThreshold, 0.25)
            if let priceAbove = cleanSettings.priceAbove, priceAbove <= 0 {
                cleanSettings.priceAbove = nil
            }
            if let priceBelow = cleanSettings.priceBelow, priceBelow <= 0 {
                cleanSettings.priceBelow = nil
            }
            result[ticker] = cleanSettings
        }
    }

    private static func normalizedTickerNotes(_ notes: [String: [TickerNote]]) -> [String: [TickerNote]] {
        notes.reduce(into: [String: [TickerNote]]()) { result, item in
            let ticker = item.key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !ticker.isEmpty else { return }
            result[ticker] = item.value
                .map { note in
                    TickerNote(
                        id: note.id,
                        ticker: ticker,
                        title: note.title,
                        text: note.text,
                        url: note.url,
                        urlTitle: note.urlTitle,
                        category: note.category,
                        createdAt: note.createdAt,
                        updatedAt: note.updatedAt
                    )
                }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private static func normalizedTickerResearch(_ research: [String: TickerResearch]) -> [String: TickerResearch] {
        research.reduce(into: [String: TickerResearch]()) { result, item in
            let ticker = item.key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !ticker.isEmpty else { return }
            result[ticker] = item.value
        }
    }

    func addTickerNote(ticker: String, title: String? = nil, text: String, url: String? = nil, urlTitle: String? = nil, category: String? = nil) {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTicker.isEmpty, !cleanText.isEmpty else { return }
        var notes = tickerNotes[cleanTicker] ?? []
        notes.insert(TickerNote(ticker: cleanTicker, title: title, text: cleanText, url: url, urlTitle: urlTitle, category: category), at: 0)
        tickerNotes[cleanTicker] = notes
        saveNow()
    }

    func updateTickerNote(_ note: TickerNote, title: String? = nil, text: String, url: String? = nil, urlTitle: String? = nil, category: String? = nil) {
        updateTickerNote(id: note.id, ticker: note.ticker, title: title, text: text, url: url, urlTitle: urlTitle, category: category)
    }

    func updateTickerNote(id: UUID, ticker: String, title: String? = nil, text: String, url: String? = nil, urlTitle: String? = nil, category: String? = nil) {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTicker.isEmpty, !cleanText.isEmpty else { return }
        guard var notes = tickerNotes[cleanTicker],
              let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        notes[index].text = cleanText
        notes[index].url = url?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        notes[index].urlTitle = urlTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        notes[index].category = category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        notes[index].updatedAt = Date()
        tickerNotes[cleanTicker] = notes.sorted { $0.updatedAt > $1.updatedAt }
        saveNow()
    }

    func deleteTickerNote(_ note: TickerNote) {
        let cleanTicker = note.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard var notes = tickerNotes[cleanTicker] else { return }
        notes.removeAll { $0.id == note.id }
        tickerNotes[cleanTicker] = notes
        saveNow()
    }

    func notes(for ticker: String) -> [TickerNote] {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return tickerNotes[cleanTicker] ?? []
    }

    @available(iOS 26.0, *)
    func summarizeNotes(for ticker: String) async throws -> String {
        let notes = notes(for: ticker)
        guard !notes.isEmpty else { return "No notes to summarize." }
        guard case .available = SystemLanguageModel.default.availability else {
            throw NSError(domain: "BudgetModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence is not available on this device."])
        }

        let notesText = notes.enumerated().map { i, note in
            var parts: [String] = []
            if let title = note.title { parts.append("Title: \(title)") }
            parts.append("Note: \(note.text)")
            if let url = note.url { parts.append("URL: \(url)") }
            if let category = note.category { parts.append("Category: \(category)") }
            return "\(i+1). " + parts.joined(separator: "\n   ")
        }.joined(separator: "\n\n")

        let session = LanguageModelSession(instructions: """
        You are a concise investment research assistant. Create a true synthesis of the user's ticker notes, not a note-by-note rewrite.
        Return only 3-5 markdown bullets.
        Combine duplicate points.
        Focus on the investment thesis, material risks, catalysts, and open questions.
        Do not include an introduction, conclusion, or source list.
        """)
        let response = try await session.respond(to: """
        Summarize these notes about stock \(ticker.uppercased()).
        Output only 3-5 concise markdown bullets:

        \(notesText)
        """)
        return response.content
    }

    func watchlistAlertSettings(for ticker: String) -> WatchlistAlertSettings {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return watchlistAlertSettings[cleanTicker] ?? WatchlistAlertSettings()
    }

    func setWatchlistAlertSettings(_ settings: WatchlistAlertSettings, for ticker: String) {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else { return }
        watchlistAlertSettings[cleanTicker] = settings
    }

    func setTickerResearch(_ research: TickerResearch, for ticker: String) {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else { return }
        tickerResearch[cleanTicker] = research
    }

    var marginUsedFromLedger: Double {
        portfolioTransactions
            .filter { !isPlaidAuthoritativePortfolioAccount($0.portfolioAccountId) }
            .reduce(0) { partial, tx in
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
        let ordered = portfolioTransactions
            .filter { !isPlaidAuthoritativePortfolioAccount($0.portfolioAccountId) }
            .sorted { $0.date < $1.date }
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
                nextPayDate: holdings.first(where: { $0.ticker.uppercased() == ticker })?.nextPayDate,
                portfolioAccountId: resolvePortfolioAccountId(metadata: nil)
            )
        }.sorted { $0.ticker < $1.ticker }
    }

    func addPortfolioTransaction(
        _ transaction: PortfolioTransaction,
        affectsBalances: Bool = true,
        fundingBankAccount: String? = nil
    ) {
        var transaction = transaction
        if transaction.type == .contribution, transaction.fundingBankAccount == nil {
            let cleanFundingBankAccount = fundingBankAccount?.trimmingCharacters(in: .whitespacesAndNewlines)
            transaction.fundingBankAccount = cleanFundingBankAccount?.isEmpty == false ? cleanFundingBankAccount : nil
        }
        if transaction.portfolioAccountId == nil {
            transaction.portfolioAccountId = resolvePortfolioAccountId(metadata: transaction.plaidMetadata)
        }
        if transaction.fundingBankAccountId == nil, let fundingName = transaction.fundingBankAccount {
            transaction.fundingBankAccountId = resolveFinancialAccountId(legacyName: fundingName, allowedKinds: [.depository])
        }
        portfolioTransactions.append(transaction)
        let isPlaidAuthoritative = isPlaidAuthoritativePortfolioAccount(transaction.portfolioAccountId)
        if affectsBalances && !isPlaidAuthoritative {
            applyCashImpact(for: transaction)
        }
        roundPortfolioCashBalance()
        if !isPlaidAuthoritative {
            synchronizeLegacyMarginStateFromLedger()
            recordPortfolioValueHistory()
        }
    }

    func updatePortfolioTransaction(_ updatedTransaction: PortfolioTransaction) {
        guard let index = portfolioTransactions.firstIndex(where: { $0.id == updatedTransaction.id }) else { return }
        let previousTransaction = portfolioTransactions[index]
        let previousIsPlaid = isPlaidAuthoritativePortfolioAccount(previousTransaction.portfolioAccountId)
        if !previousIsPlaid {
            reverseEditableCashImpact(for: previousTransaction)
        }

        var resolvedTransaction = updatedTransaction
        if resolvedTransaction.portfolioAccountId == nil {
            resolvedTransaction.portfolioAccountId = resolvePortfolioAccountId(metadata: resolvedTransaction.plaidMetadata)
        }
        if resolvedTransaction.fundingBankAccountId == nil, let fundingName = resolvedTransaction.fundingBankAccount {
            resolvedTransaction.fundingBankAccountId = resolveFinancialAccountId(legacyName: fundingName, allowedKinds: [.depository])
        }
        portfolioTransactions[index] = resolvedTransaction

        let updatedIsPlaid = isPlaidAuthoritativePortfolioAccount(resolvedTransaction.portfolioAccountId)
        if !updatedIsPlaid {
            applyEditableCashImpact(for: resolvedTransaction)
        }
        roundPortfolioCashBalance()
        if !previousIsPlaid || !updatedIsPlaid {
            synchronizeLegacyMarginStateFromLedger()
            recordPortfolioValueHistory()
        }
    }

    func deletePortfolioTransaction(id: UUID) {
        guard let index = portfolioTransactions.firstIndex(where: { $0.id == id }) else { return }
        let removedTransaction = portfolioTransactions.remove(at: index)
        let isPlaidAuthoritative = isPlaidAuthoritativePortfolioAccount(removedTransaction.portfolioAccountId)
        if !isPlaidAuthoritative {
            reverseEditableCashImpact(for: removedTransaction)
        }
        roundPortfolioCashBalance()
        if !isPlaidAuthoritative {
            synchronizeLegacyMarginStateFromLedger()
            recordPortfolioValueHistory()
        }
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

        addPortfolioTransaction(
            PortfolioTransaction(
                date: date,
                type: .buy,
                ticker: cleanTicker,
                shares: sharesBought,
                pricePerShare: pricePerShare,
                amount: dollarsInvested,
                notes: fundingSource == .newContribution ? "Funding: New Contribution" : "Funding: Cash/Margin"
            )
        )
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

    private func applyCashImpact(for transaction: PortfolioTransaction) {
        let amount = transaction.amount
        guard amount != 0 else { return }

        switch transaction.type {
        case .contribution:
            applyBankAccountDelta(
                accountId: transaction.fundingBankAccountId,
                legacyName: transaction.fundingBankAccount ?? "",
                delta: -amount
            )
            let marginPaydown = min(max(marginUsedFromLedger, 0), max(amount, 0))
            if marginPaydown > 0 {
                portfolioTransactions.append(
                    PortfolioTransaction(
                        date: transaction.date,
                        type: .manualAdjustment,
                        amount: -marginPaydown,
                        notes: "Cash contribution applied to margin balance"
                    )
                )
            }
            portfolioSnapshot.cashBalance += max(amount - marginPaydown, 0)
        case .dividend:
            portfolioSnapshot.cashBalance += amount
        case .buy:
            let cashUsed = min(max(portfolioSnapshot.cashBalance, 0), max(amount, 0))
            portfolioSnapshot.cashBalance = max(portfolioSnapshot.cashBalance - cashUsed, 0)
            let marginDraw = max(amount - cashUsed, 0)
            guard marginDraw > 0 else { return }
            portfolioTransactions.append(
                PortfolioTransaction(
                    date: transaction.date,
                    type: .manualAdjustment,
                    amount: marginDraw,
                    notes: "Auto margin draw for \(transaction.ticker ?? "investment") buy"
                )
            )
        case .sell:
            let marginPaydown = min(max(portfolioSnapshot.marginUsed, 0), max(amount, 0))
            portfolioSnapshot.cashBalance += max(amount - marginPaydown, 0)
        case .billPaidByMargin, .marginInterest, .manualAdjustment:
            break
        }
        roundPortfolioCashBalance()
    }

    private func reverseCashImpact(for transaction: PortfolioTransaction) {
        let amount = transaction.amount
        guard amount != 0 else { return }

        switch transaction.type {
        case .contribution:
            applyBankAccountDelta(
                accountId: transaction.fundingBankAccountId,
                legacyName: transaction.fundingBankAccount ?? "",
                delta: amount
            )
            portfolioSnapshot.cashBalance -= amount
        case .dividend:
            portfolioSnapshot.cashBalance -= amount
        case .buy:
            portfolioSnapshot.cashBalance += min(max(amount, 0), amount)
        case .sell:
            portfolioSnapshot.cashBalance -= amount
        case .billPaidByMargin, .marginInterest, .manualAdjustment:
            break
        }
        portfolioSnapshot.cashBalance = max(portfolioSnapshot.cashBalance, 0)
        roundPortfolioCashBalance()
    }

    private func roundPortfolioCashBalance() {
        portfolioSnapshot.cashBalance = (portfolioSnapshot.cashBalance * 100).rounded() / 100
    }

    private func applyEditableCashImpact(for transaction: PortfolioTransaction) {
        switch transaction.type {
        case .contribution, .dividend:
            applyCashImpact(for: transaction)
        case .buy, .sell, .billPaidByMargin, .marginInterest, .manualAdjustment:
            break
        }
    }

    private func reverseEditableCashImpact(for transaction: PortfolioTransaction) {
        switch transaction.type {
        case .contribution, .dividend:
            reverseCashImpact(for: transaction)
        case .buy, .sell, .billPaidByMargin, .marginInterest, .manualAdjustment:
            break
        }
    }

    func synchronizeLegacyMarginStateFromLedger() {
        let legacyMarginUsed = max(portfolioSnapshot.marginUsed, 0)
        if portfolioTransactions.isEmpty, legacyMarginUsed > 0 {
            portfolioTransactions.append(
                PortfolioTransaction(
                    type: .manualAdjustment,
                    amount: legacyMarginUsed,
                    notes: "Imported existing margin balance"
                )
            )
        }

        let legacyTransactions = portfolioTransactions.filter { !isPlaidAuthoritativePortfolioAccount($0.portfolioAccountId) }
        let derivedHoldings = holdingsFromTransactions
        if !derivedHoldings.isEmpty || !legacyTransactions.isEmpty {
            holdings = derivedHoldings
            portfolioSnapshot.marginUsed = max(marginUsedFromLedger, 0)
        }

        sweepCashAgainstMarginIfNeeded()

        portfolioSnapshot.freeMarginLimit = marginSettings.interestFreeMarginLimit
        portfolioSnapshot.marginInterestRate = marginSettings.marginInterestRate
    }

    private func sweepCashAgainstMarginIfNeeded() {
        let availableCash = max(portfolioSnapshot.cashBalance, 0)
        let currentMargin = max(marginUsedFromLedger, 0)
        let sweepAmount = min(availableCash, currentMargin)
        guard sweepAmount > 0 else {
            roundPortfolioCashBalance()
            return
        }

        let roundedSweep = (sweepAmount * 100).rounded() / 100
        guard roundedSweep > 0 else { return }

        portfolioTransactions.append(
            PortfolioTransaction(
                type: .manualAdjustment,
                amount: -roundedSweep,
                notes: "Cash balance swept to pay down margin"
            )
        )
        portfolioSnapshot.cashBalance = max(availableCash - roundedSweep, 0)
        portfolioSnapshot.marginUsed = max(currentMargin - roundedSweep, 0)
        roundPortfolioCashBalance()
    }

    private func recordPortfolioValueHistory() {
        let holdingsValue = holdings.reduce(0) { partial, holding in
            let quote = cachedQuotes[holding.ticker.uppercased()]?.price ?? holding.currentPrice
            return partial + holding.shares * quote
        }
        let gross = holdingsValue + portfolioSnapshot.cashBalance
        let net = gross - portfolioSnapshot.marginUsed
        let now = Date()

        if let last = portfolioValueHistory.last, now.timeIntervalSince(last.date) < 60 {
            portfolioValueHistory[portfolioValueHistory.count - 1] = PortfolioValuePoint(
                id: last.id,
                date: now,
                grossValue: gross,
                netValue: net
            )
        } else {
            portfolioValueHistory.append(PortfolioValuePoint(date: now, grossValue: gross, netValue: net))
            if portfolioValueHistory.count > 500 {
                portfolioValueHistory = Array(portfolioValueHistory.suffix(500))
            }
        }
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
        var resolved = entry
        if resolved.bankAccountId == nil { resolved.bankAccountId = resolveFinancialAccountId(legacyName: resolved.bankName, allowedKinds: [.depository], metadata: resolved.plaidMetadata) }
        incomes.append(resolved)
        applyBalanceImpact(for: resolved, multiplier: 1)
    }

    func updateIncomeEntry(_ updatedEntry: IncomeEntry) {
        guard let index = incomes.firstIndex(where: { $0.id == updatedEntry.id }) else { return }
        let previousEntry = incomes[index]
        applyBalanceImpact(for: previousEntry, multiplier: -1)
        var resolved = updatedEntry
        if resolved.bankAccountId == nil { resolved.bankAccountId = resolveFinancialAccountId(legacyName: resolved.bankName, allowedKinds: [.depository], metadata: resolved.plaidMetadata) }
        incomes[index] = resolved
        applyBalanceImpact(for: resolved, multiplier: 1)
    }

    func deleteIncomeEntry(id: UUID) {
        guard let index = incomes.firstIndex(where: { $0.id == id }) else { return }
        let removedEntry = incomes.remove(at: index)
        applyBalanceImpact(for: removedEntry, multiplier: -1)
    }

    func addExpense(_ expense: Expense) {
        let resolved = resolvingAccountReferences(for: expense)
        expenses.append(resolved)
        applyBalanceImpact(for: resolved, multiplier: 1)
    }

    func updateExpense(_ updatedExpense: Expense) {
        guard let index = expenses.firstIndex(where: { $0.id == updatedExpense.id }) else { return }
        let previousExpense = expenses[index]
        applyBalanceImpact(for: previousExpense, multiplier: -1)
        let resolved = resolvingAccountReferences(for: updatedExpense)
        expenses[index] = resolved
        applyBalanceImpact(for: resolved, multiplier: 1)
    }

    func deleteExpense(id: UUID) {
        guard let index = expenses.firstIndex(where: { $0.id == id }) else { return }
        let removedExpense = expenses.remove(at: index)
        applyBalanceImpact(for: removedExpense, multiplier: -1)
    }

    func addCashTransfer(_ transfer: CashTransfer) {
        let resolved = resolvingAccountReferences(for: transfer)
        guard canApplyCashTransfer(resolved) else { return }
        cashTransfers.append(resolved)
        applyBalanceImpact(for: resolved, multiplier: 1)
    }

    func updateCashTransfer(_ updatedTransfer: CashTransfer) {
        let resolved = resolvingAccountReferences(for: updatedTransfer)
        guard canApplyCashTransfer(resolved), let index = cashTransfers.firstIndex(where: { $0.id == resolved.id }) else { return }
        let previousTransfer = cashTransfers[index]
        applyBalanceImpact(for: previousTransfer, multiplier: -1)
        cashTransfers[index] = resolved
        applyBalanceImpact(for: resolved, multiplier: 1)
    }

    func deleteCashTransfer(id: UUID) {
        guard let index = cashTransfers.firstIndex(where: { $0.id == id }) else { return }
        let removedTransfer = cashTransfers.remove(at: index)
        applyBalanceImpact(for: removedTransfer, multiplier: -1)
    }

    func removeExpenses(for categoryId: UUID) {
        let removedExpenses = expenses.filter { $0.categoryId == categoryId }
        expenses.removeAll { $0.categoryId == categoryId }
        for expense in removedExpenses {
            applyBalanceImpact(for: expense, multiplier: -1)
        }
    }

    func creditAccountActualBalance(_ account: CreditAccount) -> Double {
        if account.plaidMetadata != nil {
            return account.startingBalance
        }
        let normalizedName = normalizedAccountName(account.name)
        guard !normalizedName.isEmpty else { return 0 }
        let stableAccountId = financialAccountId(for: account)
        return expenses.reduce(account.startingBalance) { partial, expense in
            if let targetId = expense.creditCardPaymentTargetId {
                if targetId == stableAccountId {
                    return partial - expense.amount
                }
            } else if let paidCard = creditCardPaymentTarget(for: expense),
                      paidCard.caseInsensitiveCompare(account.name) == .orderedSame {
                return partial - expense.amount
            }

            if let paymentAccountId = expense.paymentAccountId {
                guard paymentAccountId == stableAccountId else { return partial }
            } else {
                let paymentAccount = normalizedAccountName(expense.paymentAccount)
                guard paymentAccount == normalizedName else { return partial }
            }
            return partial + expense.amount
        }
    }

    func isCreditCardPayment(_ expense: Expense) -> Bool {
        creditCardPaymentTarget(for: expense) != nil
    }

    func creditCardPaymentTarget(for expense: Expense) -> String? {
        if let targetId = expense.creditCardPaymentTargetId,
           let account = financialAccounts.first(where: { $0.id == targetId }) {
            return account.name
        }
        if let target = expense.creditCardPaymentTarget?.trimmingCharacters(in: .whitespacesAndNewlines),
           !target.isEmpty {
            return target
        }
        return creditCardPaymentTarget(from: expense.note)
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
            guard !isCreditCardPayment(expense) else { continue }
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

    private func resolvingAccountReferences(for expense: Expense) -> Expense {
        var resolved = expense
        if resolved.paymentAccountId == nil { resolved.paymentAccountId = resolveFinancialAccountId(legacyName: resolved.paymentAccount, allowedKinds: [.depository, .credit], metadata: resolved.plaidMetadata) }
        if resolved.creditCardPaymentTargetId == nil, let target = creditCardPaymentTarget(for: resolved) { resolved.creditCardPaymentTargetId = resolveFinancialAccountId(legacyName: target, allowedKinds: [.credit]) }
        return resolved
    }

    private func resolvingAccountReferences(for transfer: CashTransfer) -> CashTransfer {
        var resolved = transfer
        if resolved.fromAccountId == nil { resolved.fromAccountId = resolveFinancialAccountId(legacyName: resolved.fromAccountName, allowedKinds: [.depository]) }
        if resolved.toAccountId == nil { resolved.toAccountId = resolveFinancialAccountId(legacyName: resolved.toAccountName, allowedKinds: [.depository]) }
        return resolved
    }

    private func applyBalanceImpact(for income: IncomeEntry, multiplier: Double) {
        applyBankAccountDelta(accountId: income.bankAccountId, legacyName: income.bankName, delta: income.amount * multiplier)
    }

    private func applyBalanceImpact(for expense: Expense, multiplier: Double) {
        applyBankAccountDelta(accountId: expense.paymentAccountId, legacyName: expense.paymentAccount, delta: -expense.amount * multiplier)
    }

    private func applyBalanceImpact(for transfer: CashTransfer, multiplier: Double) {
        applyBankAccountDelta(accountId: transfer.fromAccountId, legacyName: transfer.fromAccountName, delta: -transfer.amount * multiplier)
        applyBankAccountDelta(accountId: transfer.toAccountId, legacyName: transfer.toAccountName, delta: transfer.amount * multiplier)
    }

    private func canApplyCashTransfer(_ transfer: CashTransfer) -> Bool {
        guard transfer.amount > 0, let from = bankAccountIndex(accountId: transfer.fromAccountId, legacyName: transfer.fromAccountName), let to = bankAccountIndex(accountId: transfer.toAccountId, legacyName: transfer.toAccountName) else { return false }
        return from != to
    }

    private func applyBankAccountDelta(accountId: UUID?, legacyName: String, delta: Double) {
        guard let index = bankAccountIndex(accountId: accountId, legacyName: legacyName) else { return }
        guard bankAccounts[index].plaidMetadata == nil else { return }
        if let accountId, financialAccounts.first(where: { $0.id == accountId })?.source == .plaid { return }
        bankAccounts[index].balance = ((bankAccounts[index].balance + delta) * 100).rounded() / 100
    }

    private func bankAccountIndex(accountId: UUID?, legacyName: String) -> Int? {
        if let accountId {
            if let direct = bankAccounts.firstIndex(where: { $0.id == accountId }) { return direct }
            guard let financial = financialAccounts.first(where: { $0.id == accountId }) else { return nil }
            if let externalId = financial.externalAccountId, let matched = bankAccounts.firstIndex(where: { $0.plaidMetadata?.accountId == externalId }) { return matched }
            let normalized = normalizedAccountName(financial.name)
            let matches = bankAccounts.indices.filter { normalizedAccountName(bankAccounts[$0].name) == normalized }
            return matches.count == 1 ? matches[0] : nil
        }
        let normalized = normalizedAccountName(legacyName)
        guard !normalized.isEmpty else { return nil }
        let matches = bankAccounts.indices.filter { normalizedAccountName(bankAccounts[$0].name) == normalized }
        return matches.count == 1 ? matches[0] : nil
    }

    private func financialAccountId(for creditAccount: CreditAccount) -> UUID? {
        if let externalId = creditAccount.plaidMetadata?.accountId,
           let financialAccount = financialAccounts.first(where: { $0.externalAccountId == externalId && $0.kind == .credit }) {
            return financialAccount.id
        }
        if financialAccounts.contains(where: { $0.id == creditAccount.id && $0.kind == .credit }) {
            return creditAccount.id
        }
        let normalized = normalizedAccountName(creditAccount.name)
        let matches = financialAccounts.filter { $0.kind == .credit && normalizedAccountName($0.name) == normalized }
        return matches.count == 1 ? matches[0].id : nil
    }

    private func isPlaidAuthoritativePortfolioAccount(_ portfolioAccountId: UUID?) -> Bool {
        guard let portfolioAccountId,
              let portfolioAccount = portfolioAccounts.first(where: { $0.id == portfolioAccountId }),
              let financialAccountId = portfolioAccount.financialAccountId,
              let financialAccount = financialAccounts.first(where: { $0.id == financialAccountId }) else {
            return false
        }
        return financialAccount.source == .plaid
    }

    private func normalizedAccountName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func creditCardPaymentTarget(from note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[CC_PAYMENT:"),
              let endIndex = trimmed.firstIndex(of: "]") else {
            return nil
        }
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: 12)
        guard startIndex < endIndex else { return nil }
        let accountName = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return accountName.isEmpty ? nil : accountName
    }
}
