import Foundation

public struct BackendFinancialDataProvider: FinancialDataProvider {
    private let baseURL: URL

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8790")!) {
        self.baseURL = baseURL
    }

    public func fetchBudgetSnapshot() async throws -> BudgetSnapshot {
        try await fetchBudgetSnapshot(freshnessPolicy: .cached)
    }

    public func fetchBudgetSnapshot(freshnessPolicy: BudgetSnapshotFreshnessPolicy) async throws -> BudgetSnapshot {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("snapshot"),
            resolvingAgainstBaseURL: false
        ) else {
            throw BackendFinancialDataProviderError.invalidResponse
        }
        components.queryItems = freshnessPolicy.backendQueryItems

        guard let url = components.url else {
            throw BackendFinancialDataProviderError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw BackendFinancialDataProviderError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackendSnapshotResponse.self, from: data).snapshot
    }

    public func createPlaidLinkToken() async throws -> String {
        let response: BackendLinkTokenResponse = try await postJSON(
            path: "plaid/link-token",
            body: BackendUserScopedRequest()
        )
        return response.linkToken
    }

    public func exchangePlaidPublicToken(_ publicToken: String, institutionID: String?) async throws -> BudgetSnapshot {
        let response: BackendExchangePublicTokenResponse = try await postJSON(
            path: "plaid/exchange-public-token",
            body: BackendExchangePublicTokenRequest(
                publicToken: publicToken,
                institutionID: institutionID
            )
        )
        return response.snapshot.snapshot
    }

    public func createSandboxPlaidItem(institutionID: String? = nil) async throws -> BudgetSnapshot {
        let response: BackendSandboxItemResponse = try await postJSON(
            path: "plaid/sandbox/create-item",
            body: BackendCreateSandboxItemRequest(institutionID: institutionID)
        )
        return response.snapshot.snapshot
    }

    public func setRegularMonthly(transactionID: BudgetTransaction.ID, isRegularMonthly: Bool) async throws -> BudgetSnapshot {
        let url = baseURL.appendingPathComponent("transactions/regular-monthly")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            UpdateRegularMonthlyRequest(
                transactionID: transactionID,
                isRegularMonthly: isRegularMonthly
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw BackendFinancialDataProviderError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackendSnapshotResponse.self, from: data).snapshot
    }

    public func setCategory(transactionID: BudgetTransaction.ID, categoryID: BudgetCategory.ID?) async throws -> BudgetSnapshot {
        let url = baseURL.appendingPathComponent("transactions/category")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            UpdateCategoryRequest(
                transactionID: transactionID,
                categoryID: categoryID
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw BackendFinancialDataProviderError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackendSnapshotResponse.self, from: data).snapshot
    }

    public func saveAssignmentRule(
        _ rule: BudgetAssignmentRule,
        applyToExisting: Bool
    ) async throws -> BudgetSnapshot {
        try await sendJSON(
            path: "assignment-rules",
            method: "PUT",
            body: UpsertAssignmentRuleRequest(
                id: rule.id,
                name: rule.name,
                merchantContains: rule.merchantContains,
                matchField: rule.matchField.rawValue,
                matchOperator: rule.matchOperator.rawValue,
                amountFilter: rule.amountFilter.rawValue,
                accountID: rule.accountID,
                categoryID: rule.categoryID,
                isEnabled: rule.isEnabled,
                applyToExisting: applyToExisting
            )
        )
    }

    public func deleteAssignmentRule(id: BudgetAssignmentRule.ID) async throws -> BudgetSnapshot {
        try await sendJSON(
            path: "assignment-rules",
            method: "DELETE",
            body: DeleteAssignmentRuleRequest(id: id)
        )
    }

    public func saveCategory(_ category: BudgetCategory) async throws -> BudgetSnapshot {
        try await sendJSON(
            path: "categories",
            method: "PUT",
            body: UpsertCategoryRequest(
                id: category.id,
                name: category.name,
                monthlyLimitMinorUnits: category.monthlyLimit?.minorUnits
            )
        )
    }

    public func deleteCategory(id: BudgetCategory.ID) async throws -> BudgetSnapshot {
        try await sendJSON(
            path: "categories",
            method: "DELETE",
            body: DeleteCategoryRequest(id: id)
        )
    }

    private func sendJSON<RequestBody: Encodable>(
        path: String,
        method: String,
        body: RequestBody
    ) async throws -> BudgetSnapshot {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw BackendFinancialDataProviderError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackendSnapshotResponse.self, from: data).snapshot
    }

    private func postJSON<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw BackendFinancialDataProviderError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ResponseBody.self, from: data)
    }
}

public enum BackendFinancialDataProviderError: Error, LocalizedError {
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "BudgetTracer backend returned an invalid response."
        }
    }
}

private struct BackendSnapshotResponse: Decodable {
    var institutions: [BackendInstitution]
    var accounts: [BackendAccount]
    var categories: [BackendCategory]
    var assignmentRules: [BackendAssignmentRule]?
    var transactions: [BackendTransaction]
    var recurringTransactionIDs: [String]
    var lastSuccessfulSyncAt: Date?

    var snapshot: BudgetSnapshot {
        BudgetSnapshot(
            institutions: institutions.map(\.institution),
            accounts: accounts.map(\.account),
            categories: categories.map(\.category),
            assignmentRules: assignmentRules?.map(\.rule) ?? [],
            transactions: transactions.map(\.transaction),
            recurringTransactionIDs: Set(recurringTransactionIDs),
            lastSuccessfulSyncAt: lastSuccessfulSyncAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case institutions
        case accounts
        case categories
        case assignmentRules = "assignment_rules"
        case transactions
        case recurringTransactionIDs = "recurring_transaction_ids"
        case lastSuccessfulSyncAt = "last_successful_sync_at"
    }
}

private extension BudgetSnapshotFreshnessPolicy {
    var backendQueryItems: [URLQueryItem]? {
        switch self {
        case .cached:
            return nil
        case .syncIfStale(let maxAge):
            return [
                URLQueryItem(name: "freshness", value: "sync_if_stale"),
                URLQueryItem(name: "max_age_seconds", value: String(maxAge))
            ]
        case .forceSync:
            return [URLQueryItem(name: "freshness", value: "force_sync")]
        }
    }
}

private struct UpdateRegularMonthlyRequest: Encodable {
    var transactionID: String
    var isRegularMonthly: Bool

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case isRegularMonthly = "is_regular_monthly"
    }
}

private struct UpdateCategoryRequest: Encodable {
    var transactionID: String
    var categoryID: String?

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case categoryID = "category_id"
    }
}

private struct UpsertCategoryRequest: Encodable {
    var id: String?
    var name: String
    var monthlyLimitMinorUnits: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case monthlyLimitMinorUnits = "monthly_limit_minor_units"
    }
}

private struct UpsertAssignmentRuleRequest: Encodable {
    var id: String
    var name: String
    var merchantContains: String
    var matchField: String
    var matchOperator: String
    var amountFilter: String
    var accountID: String?
    var categoryID: String
    var isEnabled: Bool
    var applyToExisting: Bool

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
    }
}

private struct DeleteAssignmentRuleRequest: Encodable {
    var id: String
}

private struct DeleteCategoryRequest: Encodable {
    var id: String
}

private struct BackendUserScopedRequest: Encodable {
    var userID: String?

    init(userID: String? = nil) {
        self.userID = userID
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

private struct BackendLinkTokenResponse: Decodable {
    var linkToken: String

    enum CodingKeys: String, CodingKey {
        case linkToken = "link_token"
    }
}

private struct BackendExchangePublicTokenRequest: Encodable {
    var publicToken: String
    var institutionID: String?

    enum CodingKeys: String, CodingKey {
        case publicToken = "public_token"
        case institutionID = "institution_id"
    }
}

private struct BackendExchangePublicTokenResponse: Decodable {
    var snapshot: BackendSnapshotResponse
}

private struct BackendCreateSandboxItemRequest: Encodable {
    var institutionID: String?

    enum CodingKeys: String, CodingKey {
        case institutionID = "institution_id"
    }
}

private struct BackendSandboxItemResponse: Decodable {
    var snapshot: BackendSnapshotResponse
}

private struct BackendInstitution: Decodable {
    var id: String
    var name: String

    var institution: Institution {
        Institution(id: id, name: name)
    }
}

private struct BackendAccount: Decodable {
    var id: String
    var institutionID: String
    var name: String
    var kind: String
    var plaidType: String?
    var plaidSubtype: String?
    var currentBalance: BackendMoney

    var account: FinancialAccount {
        FinancialAccount(
            id: id,
            institutionID: institutionID,
            name: name,
            kind: AccountKind(rawValue: kind) ?? .other,
            plaidType: plaidType,
            plaidSubtype: plaidSubtype,
            currentBalance: currentBalance.money
        )
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

private struct BackendCategory: Decodable {
    var id: String
    var name: String
    var monthlyLimit: BackendMoney?

    var category: BudgetCategory {
        BudgetCategory(id: id, name: name, monthlyLimit: monthlyLimit?.money)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case monthlyLimit = "monthly_limit"
    }
}

private struct BackendAssignmentRule: Decodable {
    var id: String
    var name: String
    var merchantContains: String
    var matchField: String?
    var matchOperator: String?
    var amountFilter: String?
    var accountID: String?
    var categoryID: String
    var isEnabled: Bool?

    var rule: BudgetAssignmentRule {
        BudgetAssignmentRule(
            id: id,
            name: name,
            merchantContains: merchantContains,
            categoryID: categoryID,
            isEnabled: isEnabled ?? true,
            matchField: matchField.flatMap(AssignmentRuleMatchField.init(rawValue:)) ?? .merchantName,
            matchOperator: matchOperator.flatMap(AssignmentRuleTextOperator.init(rawValue:)) ?? .contains,
            amountFilter: amountFilter.flatMap(AssignmentRuleAmountFilter.init(rawValue:)) ?? .any,
            accountID: accountID
        )
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

private struct BackendTransaction: Decodable {
    var id: String
    var accountID: String
    var categoryID: String?
    var categoryAssignmentSource: String?
    var categoryAssignmentRuleID: String?
    var postedAt: Date
    var occurredAt: Date?
    var merchantName: String
    var amount: BackendMoney

    var transaction: BudgetTransaction {
        BudgetTransaction(
            id: id,
            accountID: accountID,
            categoryID: categoryID,
            categoryAssignmentSource: categoryAssignmentSource.flatMap(CategoryAssignmentSource.init(rawValue:)),
            categoryAssignmentRuleID: categoryAssignmentRuleID,
            postedAt: postedAt,
            occurredAt: occurredAt,
            merchantName: merchantName,
            amount: amount.money
        )
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

private struct BackendMoney: Decodable {
    var minorUnits: Int64
    var currencyCode: String

    var money: Money {
        Money(minorUnits: minorUnits, currencyCode: currencyCode)
    }

    enum CodingKeys: String, CodingKey {
        case minorUnits = "minor_units"
        case currencyCode = "currency_code"
    }
}
