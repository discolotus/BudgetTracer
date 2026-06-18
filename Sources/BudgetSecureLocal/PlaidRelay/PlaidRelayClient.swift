import BudgetPlaid
import Foundation

public enum PlaidRelaySecurityPolicy: Sendable {
    case httpsOnly
    case allowInsecureLocalhost
}

public struct PlaidRelayClient: Sendable {
    private let baseURL: URL
    private let identityTokenProvider: any AppleIdentityTokenProvider
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL,
        identityTokenProvider: any AppleIdentityTokenProvider,
        session: URLSession = .shared,
        securityPolicy: PlaidRelaySecurityPolicy = .httpsOnly
    ) throws {
        try Self.validate(baseURL: baseURL, securityPolicy: securityPolicy)
        self.baseURL = baseURL
        self.identityTokenProvider = identityTokenProvider
        self.session = session
    }

    public func createLinkToken(clientUserID: String) async throws -> String {
        let response: PlaidLinkTokenResponse = try await post(
            path: "v1/plaid/link-token",
            body: LinkTokenRelayRequest(clientUserID: clientUserID)
        )
        return response.linkToken
    }

    public func exchangePublicToken(
        _ publicToken: String,
        institutionID: String?
    ) async throws -> PlaidRelayExchangePublicTokenResponse {
        try await post(
            path: "v1/plaid/exchange-public-token",
            body: ExchangePublicTokenRelayRequest(
                publicToken: publicToken,
                institutionID: institutionID
            )
        )
    }

    public func getAccounts(accessToken: String) async throws -> PlaidAccountsGetResponse {
        try await post(
            path: "v1/plaid/accounts/get",
            body: AccessTokenRelayRequest(accessToken: accessToken)
        )
    }

    public func syncTransactions(accessToken: String, cursor: String?) async throws -> PlaidTransactionsSyncResponse {
        var merged = PlaidTransactionsSyncResponse.empty
        var nextCursor = cursor
        var hasMore = true

        while hasMore {
            let page: PlaidTransactionsSyncResponse = try await post(
                path: "v1/plaid/transactions/sync",
                body: TransactionsSyncRelayRequest(accessToken: accessToken, cursor: nextCursor)
            )
            merged.append(page)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        }

        return merged
    }

    public func removeItem(accessToken: String) async throws {
        let _: EmptyRelayResponse = try await post(
            path: "v1/plaid/item/remove",
            body: AccessTokenRelayRequest(accessToken: accessToken)
        )
    }

    private func post<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await identityTokenProvider.identityToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaidRelayClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlaidRelayClientError.statusCode(
                httpResponse.statusCode,
                message: Self.errorMessage(from: data)
            )
        }

        return try decoder.decode(ResponseBody.self, from: data)
    }

    private static func errorMessage(from data: Data) -> String? {
        if let relayError = try? JSONDecoder().decode(RelayErrorResponse.self, from: data) {
            return relayError.error
        }

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private static func validate(baseURL: URL, securityPolicy: PlaidRelaySecurityPolicy) throws {
        if baseURL.scheme == "https" {
            return
        }

        if case .allowInsecureLocalhost = securityPolicy,
           baseURL.scheme == "http",
           ["127.0.0.1", "localhost", "::1"].contains(baseURL.host ?? "") {
            return
        }

        throw PlaidRelayClientError.insecureBaseURL(baseURL.absoluteString)
    }
}

public struct PlaidRelayExchangePublicTokenResponse: Codable, Hashable, Sendable {
    public var accessToken: String
    public var itemID: String
    public var plaidItemID: String

    public init(accessToken: String, itemID: String, plaidItemID: String) {
        self.accessToken = accessToken
        self.itemID = itemID
        self.plaidItemID = plaidItemID
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case itemID = "item_id"
        case plaidItemID = "plaid_item_id"
    }
}

public enum PlaidRelayClientError: Error, LocalizedError, Sendable {
    case insecureBaseURL(String)
    case invalidResponse
    case statusCode(Int, message: String?)

    public var errorDescription: String? {
        switch self {
        case .insecureBaseURL(let url):
            return "Plaid relay URL must use HTTPS: \(url)"
        case .invalidResponse:
            return "Plaid relay returned an invalid response."
        case .statusCode(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Plaid relay returned HTTP \(statusCode): \(message)"
            }
            return "Plaid relay returned HTTP \(statusCode)."
        }
    }
}

private struct RelayErrorResponse: Decodable {
    var error: String?
}

private struct LinkTokenRelayRequest: Encodable {
    var clientUserID: String

    enum CodingKeys: String, CodingKey {
        case clientUserID = "client_user_id"
    }
}

private struct ExchangePublicTokenRelayRequest: Encodable {
    var publicToken: String
    var institutionID: String?

    enum CodingKeys: String, CodingKey {
        case publicToken = "public_token"
        case institutionID = "institution_id"
    }
}

private struct AccessTokenRelayRequest: Encodable {
    var accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct TransactionsSyncRelayRequest: Encodable {
    var accessToken: String
    var cursor: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case cursor
    }
}

private struct EmptyRelayResponse: Decodable {}
