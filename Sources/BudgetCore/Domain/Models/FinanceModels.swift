import Foundation

public struct Institution: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum AccountKind: String, CaseIterable, Hashable, Sendable {
    case checking
    case savings
    case creditCard
    case investment
    case loan
    case other
}

public struct FinancialAccount: Identifiable, Hashable, Sendable {
    public var id: String
    public var institutionID: Institution.ID
    public var name: String
    public var kind: AccountKind
    public var plaidType: String?
    public var plaidSubtype: String?
    public var currentBalance: Money

    public init(
        id: String,
        institutionID: Institution.ID,
        name: String,
        kind: AccountKind,
        plaidType: String? = nil,
        plaidSubtype: String? = nil,
        currentBalance: Money
    ) {
        self.id = id
        self.institutionID = institutionID
        self.name = name
        self.kind = kind
        self.plaidType = plaidType
        self.plaidSubtype = plaidSubtype
        self.currentBalance = currentBalance
    }
}

public struct BudgetCategory: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var monthlyLimit: Money?

    public init(id: String, name: String, monthlyLimit: Money? = nil) {
        self.id = id
        self.name = name
        self.monthlyLimit = monthlyLimit
    }
}

public struct BudgetTransaction: Identifiable, Hashable, Sendable {
    public var id: String
    public var accountID: FinancialAccount.ID
    public var categoryID: BudgetCategory.ID?
    public var postedAt: Date
    public var occurredAt: Date
    public var merchantName: String
    public var amount: Money
    public var note: String?

    public init(
        id: String,
        accountID: FinancialAccount.ID,
        categoryID: BudgetCategory.ID?,
        postedAt: Date,
        occurredAt: Date? = nil,
        merchantName: String,
        amount: Money,
        note: String? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.categoryID = categoryID
        self.postedAt = postedAt
        self.occurredAt = occurredAt ?? postedAt
        self.merchantName = merchantName
        self.amount = amount
        self.note = note
    }
}
