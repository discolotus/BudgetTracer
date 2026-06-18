import BudgetCore
import Foundation

struct HealthResponse: Encodable {
    var status: String
    var userID: String
    var plaidItemCount: Int
}

struct UserScopedRequest: Decodable {
    var userID: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

struct LinkTokenResponse: Encodable {
    var linkToken: String

    enum CodingKeys: String, CodingKey {
        case linkToken = "link_token"
    }
}

struct ExchangePublicTokenRequest: Decodable {
    var publicToken: String
    var institutionID: String?
    var userID: String?

    enum CodingKeys: String, CodingKey {
        case publicToken = "public_token"
        case institutionID = "institution_id"
        case userID = "user_id"
    }
}

struct ExchangePublicTokenResponse: Encodable {
    var itemID: String
    var plaidItemID: String
    var snapshot: SnapshotResponse

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case plaidItemID = "plaid_item_id"
        case snapshot
    }
}

struct CreateSandboxItemRequest: Decodable {
    var institutionID: String?
    var userID: String?

    enum CodingKeys: String, CodingKey {
        case institutionID = "institution_id"
        case userID = "user_id"
    }
}

struct SandboxItemResponse: Encodable {
    var institutionID: String
    var snapshot: SnapshotResponse

    enum CodingKeys: String, CodingKey {
        case institutionID = "institution_id"
        case snapshot
    }
}

struct SyncRequest: Decodable {
    var itemID: String?
    var userID: String?

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case userID = "user_id"
    }
}

struct SyncResponse: Encodable {
    var syncedItemIDs: [String]
    var snapshot: SnapshotResponse

    enum CodingKeys: String, CodingKey {
        case syncedItemIDs = "synced_item_ids"
        case snapshot
    }
}

struct PlaidWebhookRequest: Decodable {
    var webhookType: String
    var webhookCode: String
    var itemID: String?

    enum CodingKeys: String, CodingKey {
        case webhookType = "webhook_type"
        case webhookCode = "webhook_code"
        case itemID = "item_id"
    }
}

struct WebhookResponse: Encodable {
    var accepted: Bool
    var syncedItemID: String?

    enum CodingKeys: String, CodingKey {
        case accepted
        case syncedItemID = "synced_item_id"
    }
}

struct UpdateRegularMonthlyRequest: Decodable {
    var transactionID: String
    var isRegularMonthly: Bool
    var userID: String?

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case isRegularMonthly = "is_regular_monthly"
        case userID = "user_id"
    }
}

struct UpdateCategoryRequest: Decodable {
    var transactionID: String
    var categoryID: String?
    var userID: String?

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case categoryID = "category_id"
        case userID = "user_id"
    }
}

struct UpsertCategoryRequest: Decodable {
    var id: String?
    var name: String
    var monthlyLimitMinorUnits: Int64?
    var userID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case monthlyLimitMinorUnits = "monthly_limit_minor_units"
        case userID = "user_id"
    }
}

struct DeleteCategoryRequest: Decodable {
    var id: String
    var userID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
    }
}

struct UpsertAssignmentRuleRequest: Decodable {
    var id: String?
    var name: String
    var merchantContains: String
    var matchField: String?
    var matchOperator: String?
    var amountFilter: String?
    var accountID: String?
    var categoryID: String
    var isEnabled: Bool?
    var applyToExisting: Bool?
    var userID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case merchantContains = "merchant_contains"
        case matchField = "match_field"
        case matchOperator = "match_operator"
        case amountFilter = "amount_filter"
        case accountID = "account_id"
        case categoryID = "category_id"
        case isEnabled = "is_enabled"
        case applyToExisting = "apply_to_existing"
        case userID = "user_id"
    }
}

struct DeleteAssignmentRuleRequest: Decodable {
    var id: String
    var userID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
    }
}

struct RelayLinkTokenRequest: Decodable {
    var clientUserID: String?

    enum CodingKeys: String, CodingKey {
        case clientUserID = "client_user_id"
    }
}

struct RelayExchangePublicTokenRequest: Decodable {
    var publicToken: String
    var institutionID: String?

    enum CodingKeys: String, CodingKey {
        case publicToken = "public_token"
        case institutionID = "institution_id"
    }
}

struct RelayExchangePublicTokenResponse: Encodable {
    var accessToken: String
    var itemID: String
    var plaidItemID: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case itemID = "item_id"
        case plaidItemID = "plaid_item_id"
    }
}

struct RelayAccessTokenRequest: Decodable {
    var accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

struct RelayTransactionsSyncRequest: Decodable {
    var accessToken: String
    var cursor: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case cursor
    }
}

struct RelayEmptyResponse: Encodable {}

struct SnapshotResponse: Encodable {
    var institutions: [InstitutionResponse]
    var accounts: [AccountResponse]
    var categories: [CategoryResponse]
    var assignmentRules: [AssignmentRuleResponse]
    var transactions: [TransactionResponse]
    var recurringTransactionIDs: [String]
    var lastSuccessfulSyncAt: Date?
    var freshness: SnapshotFreshnessResponse?
    var normalizedMonthlyCashFlow: [NormalizedCashFlowPointResponse]
    var normalizedMonthlySpending: [NormalizedSpendingPointResponse]
    var cumulativeTransactionSpending: [CumulativeTransactionSpendingPointResponse]

    init(snapshot: BudgetSnapshot, freshness: SnapshotFreshnessResponse? = nil) {
        institutions = snapshot.institutions.map(InstitutionResponse.init)
        accounts = snapshot.accounts.map(AccountResponse.init)
        categories = snapshot.categories.map(CategoryResponse.init)
        assignmentRules = snapshot.assignmentRules.map(AssignmentRuleResponse.init)
        transactions = snapshot.transactions.map(TransactionResponse.init)
        recurringTransactionIDs = Array(snapshot.recurringTransactionIDs).sorted()
        lastSuccessfulSyncAt = snapshot.lastSuccessfulSyncAt
        self.freshness = freshness
        normalizedMonthlyCashFlow = snapshot.normalizedMonthlyCashFlow().map(NormalizedCashFlowPointResponse.init)
        normalizedMonthlySpending = snapshot.normalizedMonthlySpending().map(NormalizedSpendingPointResponse.init)
        cumulativeTransactionSpending = snapshot.cumulativeTransactionSpending().map(CumulativeTransactionSpendingPointResponse.init)
    }

    enum CodingKeys: String, CodingKey {
        case institutions
        case accounts
        case categories
        case assignmentRules = "assignment_rules"
        case transactions
        case recurringTransactionIDs = "recurring_transaction_ids"
        case lastSuccessfulSyncAt = "last_successful_sync_at"
        case freshness
        case normalizedMonthlyCashFlow = "normalized_monthly_cash_flow"
        case normalizedMonthlySpending = "normalized_monthly_spending"
        case cumulativeTransactionSpending = "cumulative_transaction_spending"
    }
}

struct SnapshotFreshnessResponse: Encodable {
    var policy: String
    var syncedItemIDs: [String]

    enum CodingKeys: String, CodingKey {
        case policy
        case syncedItemIDs = "synced_item_ids"
    }
}

struct InstitutionResponse: Encodable {
    var id: String
    var name: String

    init(_ institution: Institution) {
        id = institution.id
        name = institution.name
    }
}

struct AccountResponse: Encodable {
    var id: String
    var institutionID: String
    var name: String
    var kind: String
    var plaidType: String?
    var plaidSubtype: String?
    var currentBalance: MoneyResponse

    init(_ account: FinancialAccount) {
        id = account.id
        institutionID = account.institutionID
        name = account.name
        kind = account.kind.rawValue
        plaidType = account.plaidType
        plaidSubtype = account.plaidSubtype
        currentBalance = MoneyResponse(account.currentBalance)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case institutionID = "institution_id"
        case name
        case kind
        case plaidType = "plaid_type"
        case plaidSubtype = "plaid_subtype"
        case currentBalance = "current_balance"
    }
}

struct CategoryResponse: Encodable {
    var id: String
    var name: String
    var monthlyLimit: MoneyResponse?

    init(_ category: BudgetCategory) {
        id = category.id
        name = category.name
        monthlyLimit = category.monthlyLimit.map(MoneyResponse.init)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case monthlyLimit = "monthly_limit"
    }
}

struct AssignmentRuleResponse: Encodable {
    var id: String
    var name: String
    var merchantContains: String
    var matchField: String
    var matchOperator: String
    var amountFilter: String
    var accountID: String?
    var categoryID: String
    var isEnabled: Bool

    init(_ rule: BudgetAssignmentRule) {
        id = rule.id
        name = rule.name
        merchantContains = rule.merchantContains
        matchField = rule.matchField.rawValue
        matchOperator = rule.matchOperator.rawValue
        amountFilter = rule.amountFilter.rawValue
        accountID = rule.accountID
        categoryID = rule.categoryID
        isEnabled = rule.isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case merchantContains = "merchant_contains"
        case matchField = "match_field"
        case matchOperator = "match_operator"
        case amountFilter = "amount_filter"
        case accountID = "account_id"
        case categoryID = "category_id"
        case isEnabled = "is_enabled"
    }
}

struct TransactionResponse: Encodable {
    var id: String
    var accountID: String
    var categoryID: String?
    var categoryAssignmentSource: String?
    var categoryAssignmentRuleID: String?
    var postedAt: Date
    var occurredAt: Date
    var merchantName: String
    var amount: MoneyResponse

    init(_ transaction: BudgetTransaction) {
        id = transaction.id
        accountID = transaction.accountID
        categoryID = transaction.categoryID
        categoryAssignmentSource = transaction.categoryAssignmentSource?.rawValue
        categoryAssignmentRuleID = transaction.categoryAssignmentRuleID
        postedAt = transaction.postedAt
        occurredAt = transaction.occurredAt
        merchantName = transaction.merchantName
        amount = MoneyResponse(transaction.amount)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case categoryID = "category_id"
        case categoryAssignmentSource = "category_assignment_source"
        case categoryAssignmentRuleID = "category_assignment_rule_id"
        case postedAt = "posted_at"
        case occurredAt = "occurred_at"
        case merchantName = "merchant_name"
        case amount
    }
}

struct NormalizedCashFlowPointResponse: Encodable {
    var date: Date
    var dailyNet: MoneyResponse
    var runningCashBalance: MoneyResponse
    var runningCreditDebt: MoneyResponse
    var runningCashMinusCreditDebt: MoneyResponse
    var hasPostedCashTransactions: Bool
    var hasPostedCardTransactions: Bool

    init(_ point: NormalizedCashFlowPoint) {
        date = point.date
        dailyNet = MoneyResponse(point.dailyNet)
        runningCashBalance = MoneyResponse(point.runningCashBalance)
        runningCreditDebt = MoneyResponse(point.runningCreditDebt)
        runningCashMinusCreditDebt = MoneyResponse(point.runningCashMinusCreditDebt)
        hasPostedCashTransactions = point.hasPostedCashTransactions
        hasPostedCardTransactions = point.hasPostedCardTransactions
    }

    enum CodingKeys: String, CodingKey {
        case date
        case dailyNet = "daily_net"
        case runningCashBalance = "running_cash_balance"
        case runningCreditDebt = "running_credit_debt"
        case runningCashMinusCreditDebt = "running_cash_minus_credit_debt"
        case hasPostedCashTransactions = "has_posted_cash_transactions"
        case hasPostedCardTransactions = "has_posted_card_transactions"
    }
}

struct NormalizedSpendingPointResponse: Encodable {
    var date: Date
    var actualSpending: MoneyResponse
    var actualIncome: MoneyResponse
    var normalizedSpending: MoneyResponse
    var normalizedIncome: MoneyResponse
    var cumulativeNormalizedSpending: MoneyResponse
    var cumulativeNormalizedIncome: MoneyResponse
    var averagedRecurringSpending: MoneyResponse
    var averagedTransactionMarkers: [AveragedTransactionMarkerResponse]

    init(_ point: NormalizedSpendingPoint) {
        date = point.date
        actualSpending = MoneyResponse(point.actualSpending)
        actualIncome = MoneyResponse(point.actualIncome)
        normalizedSpending = MoneyResponse(point.normalizedSpending)
        normalizedIncome = MoneyResponse(point.normalizedIncome)
        cumulativeNormalizedSpending = MoneyResponse(point.cumulativeNormalizedSpending)
        cumulativeNormalizedIncome = MoneyResponse(point.cumulativeNormalizedIncome)
        averagedRecurringSpending = MoneyResponse(point.averagedRecurringSpending)
        averagedTransactionMarkers = point.averagedTransactionMarkers.map(AveragedTransactionMarkerResponse.init)
    }

    enum CodingKeys: String, CodingKey {
        case date
        case actualSpending = "actual_spending"
        case actualIncome = "actual_income"
        case normalizedSpending = "normalized_spending"
        case normalizedIncome = "normalized_income"
        case cumulativeNormalizedSpending = "cumulative_normalized_spending"
        case cumulativeNormalizedIncome = "cumulative_normalized_income"
        case averagedRecurringSpending = "averaged_recurring_spending"
        case averagedTransactionMarkers = "averaged_transaction_markers"
    }
}

struct AveragedTransactionMarkerResponse: Encodable {
    var transactionID: String
    var merchantName: String
    var amount: MoneyResponse

    init(_ marker: AveragedTransactionMarker) {
        transactionID = marker.transactionID
        merchantName = marker.merchantName
        amount = MoneyResponse(marker.amount)
    }

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case merchantName = "merchant_name"
        case amount
    }
}

struct CumulativeTransactionSpendingPointResponse: Encodable {
    var transactionID: String
    var occurredAt: Date
    var merchantName: String
    var amount: MoneyResponse
    var cumulativeSpending: MoneyResponse
    var isAveraged: Bool

    init(_ point: CumulativeTransactionSpendingPoint) {
        transactionID = point.transactionID
        occurredAt = point.occurredAt
        merchantName = point.merchantName
        amount = MoneyResponse(point.amount)
        cumulativeSpending = MoneyResponse(point.cumulativeSpending)
        isAveraged = point.isAveraged
    }

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case occurredAt = "occurred_at"
        case merchantName = "merchant_name"
        case amount
        case cumulativeSpending = "cumulative_spending"
        case isAveraged = "is_averaged"
    }
}

struct MoneyResponse: Encodable {
    var minorUnits: Int64
    var currencyCode: String
    var formatted: String

    init(_ money: Money) {
        minorUnits = money.minorUnits
        currencyCode = money.currencyCode
        formatted = money.formatted
    }

    enum CodingKeys: String, CodingKey {
        case minorUnits = "minor_units"
        case currencyCode = "currency_code"
        case formatted
    }
}
