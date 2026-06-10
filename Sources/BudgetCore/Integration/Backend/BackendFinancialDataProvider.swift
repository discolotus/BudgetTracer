import Foundation

public struct BackendFinancialDataProvider: FinancialDataProvider {
    private let baseURL: URL

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8790")!) {
        self.baseURL = baseURL
    }

    public func fetchBudgetSnapshot() async throws -> BudgetSnapshot {
        let url = baseURL.appendingPathComponent("snapshot")
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw BackendFinancialDataProviderError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackendSnapshotResponse.self, from: data).snapshot
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
    var transactions: [BackendTransaction]
    var recurringTransactionIDs: [String]

    var snapshot: BudgetSnapshot {
        BudgetSnapshot(
            institutions: institutions.map(\.institution),
            accounts: accounts.map(\.account),
            categories: categories.map(\.category),
            transactions: transactions.map(\.transaction),
            recurringTransactionIDs: Set(recurringTransactionIDs)
        )
    }

    enum CodingKeys: String, CodingKey {
        case institutions
        case accounts
        case categories
        case transactions
        case recurringTransactionIDs = "recurring_transaction_ids"
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

private struct BackendTransaction: Decodable {
    var id: String
    var accountID: String
    var categoryID: String?
    var postedAt: Date
    var occurredAt: Date?
    var merchantName: String
    var amount: BackendMoney

    var transaction: BudgetTransaction {
        BudgetTransaction(
            id: id,
            accountID: accountID,
            categoryID: categoryID,
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
