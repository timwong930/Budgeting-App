import Foundation

enum PlaidImportStatus: String, Codable, Sendable, Equatable {
    case imported
    case reconciled
    case needsReview
    case removed
}

struct PlaidSourceMetadata: Codable, Sendable, Equatable {
    var itemId: String
    var accountId: String?
    var transactionId: String?
    var investmentTransactionId: String?
    var securityId: String?
    var institutionName: String?
    var importedAt: Date
    var lastSyncedAt: Date
    var status: PlaidImportStatus
    var matchConfidence: Double?
    var isPending: Bool?

    init(
        itemId: String,
        accountId: String? = nil,
        transactionId: String? = nil,
        investmentTransactionId: String? = nil,
        securityId: String? = nil,
        institutionName: String? = nil,
        importedAt: Date = Date(),
        lastSyncedAt: Date = Date(),
        status: PlaidImportStatus = .imported,
        matchConfidence: Double? = nil,
        isPending: Bool? = nil
    ) {
        self.itemId = itemId
        self.accountId = accountId
        self.transactionId = transactionId
        self.investmentTransactionId = investmentTransactionId
        self.securityId = securityId
        self.institutionName = institutionName
        self.importedAt = importedAt
        self.lastSyncedAt = lastSyncedAt
        self.status = status
        self.matchConfidence = matchConfidence
        self.isPending = isPending
    }
}

enum PlaidAccountType: String, Codable, Sendable, Equatable {
    case depository
    case credit
    case investment
    case loan
    case other
}

struct PlaidSyncedAccount: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var itemId: String
    var name: String
    var type: PlaidAccountType
    var subtype: String?
    var currentBalance: Double?
    var availableBalance: Double?
    var creditLimit: Double?
    var institutionName: String?
}

struct PlaidSyncedTransaction: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var accountId: String
    var itemId: String
    var name: String
    var merchantName: String?
    var amount: Double
    var date: Date
    var pending: Bool
    var pendingTransactionId: String? = nil
    var category: String?
    var removed: Bool
}

struct PlaidSyncedCreditLiability: Codable, Sendable, Equatable {
    var accountId: String
    var itemId: String
    var minimumPaymentAmount: Double?
    var nextPaymentDueDate: Date?
    var lastStatementBalance: Double?
    var lastStatementIssueDate: Date?
    var aprPercentage: Double?
}

struct PlaidSyncedHolding: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(accountId)|\(securityId)" }
    var accountId: String
    var itemId: String
    var securityId: String
    var ticker: String?
    var name: String?
    var quantity: Double
    var costBasis: Double?
    var institutionPrice: Double?
    var institutionValue: Double?
    var priceAsOf: Date?
    var securityType: String? = nil
}

struct PlaidSyncedInvestmentTransaction: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var accountId: String
    var itemId: String
    var securityId: String?
    var ticker: String?
    var name: String
    var type: String
    var subtype: String?
    var amount: Double
    var quantity: Double?
    var price: Double?
    var date: Date
}

enum PlaidConnectionHealth: String, Codable, Sendable, Equatable {
    case connected
    case needsUpdate
    case error
}

struct PlaidConnectionStatus: Codable, Sendable, Equatable, Identifiable {
    var id: String { itemId }
    var itemId: String
    var institutionName: String
    var health: PlaidConnectionHealth
    var lastSyncedAt: Date?
    var errorMessage: String?
}

struct PlaidReviewItem: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var detail: String
    var amount: Double?
    var date: Date?
    var sourceId: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, detail: String, amount: Double? = nil, date: Date? = nil, sourceId: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.detail = detail
        self.amount = amount
        self.date = date
        self.sourceId = sourceId
        self.createdAt = createdAt
    }
}

struct PlaidSyncPayload: Codable, Sendable, Equatable {
    var accounts: [PlaidSyncedAccount]
    var transactions: [PlaidSyncedTransaction]
    var creditLiabilities: [PlaidSyncedCreditLiability]
    var holdings: [PlaidSyncedHolding]
    var investmentTransactions: [PlaidSyncedInvestmentTransaction]
    var connectionStatuses: [PlaidConnectionStatus]
}

struct PlaidSyncResult: Codable, Sendable, Equatable {
    var importedTransactions: Int = 0
    var reconciledTransactions: Int = 0
    var removedTransactions: Int = 0
    var importedInvestmentTransactions: Int = 0
    var updatedAccounts: Int = 0
    var updatedHoldings: Int = 0
    var reviewItems: Int = 0
}
