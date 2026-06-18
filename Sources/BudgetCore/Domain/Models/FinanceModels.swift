import Foundation

public struct Institution: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum AccountKind: String, CaseIterable, Codable, Hashable, Sendable {
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

public struct AccountOverride: Codable, Hashable, Sendable {
    public var kind: AccountKind?
    public var includesInAvailableCash: Bool?
    public var includesInCreditCardDebt: Bool?

    public init(
        kind: AccountKind? = nil,
        includesInAvailableCash: Bool? = nil,
        includesInCreditCardDebt: Bool? = nil
    ) {
        self.kind = kind
        self.includesInAvailableCash = includesInAvailableCash
        self.includesInCreditCardDebt = includesInCreditCardDebt
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

public extension BudgetCategory {
    /// Seeded for a new or empty user so the Budgets tab and category picker are never blank.
    static let defaultSeed: [BudgetCategory] = [
        BudgetCategory(id: "default-income", name: "Income"),
        BudgetCategory(id: "default-housing", name: "Housing"),
        BudgetCategory(id: "default-groceries", name: "Groceries"),
        BudgetCategory(id: "default-other", name: "Other")
    ]
}

public enum CategoryAssignmentSource: String, Codable, Hashable, Sendable {
    case manual
    case plaid
    case rule
}

public enum AssignmentRuleMatchField: String, CaseIterable, Codable, Hashable, Sendable {
    case merchantName
    case note
}

public enum AssignmentRuleTextOperator: String, CaseIterable, Codable, Hashable, Sendable {
    case contains
    case equals
    case beginsWith
}

public enum AssignmentRuleAmountFilter: String, CaseIterable, Codable, Hashable, Sendable {
    case any
    case expensesOnly
    case incomeOnly
}

public struct BudgetAssignmentRule: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var merchantContains: String
    public var categoryID: BudgetCategory.ID
    public var isEnabled: Bool
    public var matchField: AssignmentRuleMatchField
    public var matchOperator: AssignmentRuleTextOperator
    public var amountFilter: AssignmentRuleAmountFilter
    public var accountID: FinancialAccount.ID?

    public init(
        id: String,
        name: String,
        merchantContains: String,
        categoryID: BudgetCategory.ID,
        isEnabled: Bool = true,
        matchField: AssignmentRuleMatchField = .merchantName,
        matchOperator: AssignmentRuleTextOperator = .contains,
        amountFilter: AssignmentRuleAmountFilter = .any,
        accountID: FinancialAccount.ID? = nil
    ) {
        self.id = id
        self.name = name
        self.merchantContains = merchantContains
        self.categoryID = categoryID
        self.isEnabled = isEnabled
        self.matchField = matchField
        self.matchOperator = matchOperator
        self.amountFilter = amountFilter
        self.accountID = accountID
    }

    public func matches(_ transaction: BudgetTransaction) -> Bool {
        guard isEnabled else {
            return false
        }

        if let accountID, transaction.accountID != accountID {
            return false
        }

        guard amountFilter.matches(transaction.amount) else {
            return false
        }

        let needle = merchantContains.normalizedRuleText
        guard !needle.isEmpty else {
            return false
        }

        let haystack = matchField.text(in: transaction).normalizedRuleText
        guard !haystack.isEmpty else {
            return false
        }

        switch matchOperator {
        case .contains:
            return haystack.contains(needle)
        case .equals:
            return haystack == needle
        case .beginsWith:
            return haystack.hasPrefix(needle)
        }
    }
}

public struct BudgetTransaction: Identifiable, Hashable, Sendable {
    public var id: String
    public var accountID: FinancialAccount.ID
    public var categoryID: BudgetCategory.ID?
    public var categoryAssignmentSource: CategoryAssignmentSource?
    public var categoryAssignmentRuleID: BudgetAssignmentRule.ID?
    public var postedAt: Date
    public var occurredAt: Date
    public var merchantName: String
    public var amount: Money
    public var note: String?

    public init(
        id: String,
        accountID: FinancialAccount.ID,
        categoryID: BudgetCategory.ID?,
        categoryAssignmentSource: CategoryAssignmentSource? = nil,
        categoryAssignmentRuleID: BudgetAssignmentRule.ID? = nil,
        postedAt: Date,
        occurredAt: Date? = nil,
        merchantName: String,
        amount: Money,
        note: String? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.categoryID = categoryID
        self.categoryAssignmentSource = categoryAssignmentSource
        self.categoryAssignmentRuleID = categoryAssignmentRuleID
        self.postedAt = postedAt
        self.occurredAt = occurredAt ?? postedAt
        self.merchantName = merchantName
        self.amount = amount
        self.note = note
    }
}

public extension BudgetTransaction {
    var hasManualCategoryAssignment: Bool {
        categoryAssignmentSource == .manual || (categoryID != nil && categoryAssignmentSource == nil)
    }
}

private extension String {
    var normalizedRuleText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension AssignmentRuleMatchField {
    func text(in transaction: BudgetTransaction) -> String {
        switch self {
        case .merchantName:
            return transaction.merchantName
        case .note:
            return transaction.note ?? ""
        }
    }
}

private extension AssignmentRuleAmountFilter {
    func matches(_ amount: Money) -> Bool {
        switch self {
        case .any:
            return true
        case .expensesOnly:
            return amount.isExpense
        case .incomeOnly:
            return amount.isIncome
        }
    }
}
