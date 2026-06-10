import Foundation

public protocol PlaidAPIClientProtocol {
    func createLinkToken(userID: String) async throws -> PlaidLinkTokenResponse
    func createSandboxPublicToken(institutionID: String, products: [String]) async throws -> PlaidSandboxPublicTokenResponse
    func exchangePublicToken(_ publicToken: String) async throws -> PlaidPublicTokenExchangeResponse
    func syncTransactions(accessToken: String, cursor: String?) async throws -> PlaidTransactionsSyncResponse
}

public final class PlaidAPIClient: PlaidAPIClientProtocol {
    private let configurationProvider: () throws -> PlaidConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configuration: PlaidConfiguration, session: URLSession = .shared) {
        self.configurationProvider = { configuration }
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public init(configurationProvider: @escaping () throws -> PlaidConfiguration, session: URLSession = .shared) {
        self.configurationProvider = configurationProvider
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func createLinkToken(userID: String) async throws -> PlaidLinkTokenResponse {
        let configuration = try configurationProvider()
        let response: PlaidLinkTokenResponse = try await post(
            path: "/link/token/create",
            body: PlaidLinkTokenRequest(
                clientID: configuration.clientID,
                secret: configuration.secret,
                clientName: configuration.clientName,
                user: PlaidLinkUser(clientUserID: userID),
                products: ["transactions"],
                countryCodes: ["US"],
                language: "en",
                webhook: configuration.webhookURL?.absoluteString,
                transactions: PlaidLinkTransactions(daysRequested: configuration.daysRequested)
            )
        )
        return response
    }

    public func createSandboxPublicToken(institutionID: String, products: [String] = ["transactions"]) async throws -> PlaidSandboxPublicTokenResponse {
        let configuration = try configurationProvider()
        let response: PlaidSandboxPublicTokenResponse = try await post(
            path: "/sandbox/public_token/create",
            body: PlaidSandboxPublicTokenRequest(
                clientID: configuration.clientID,
                secret: configuration.secret,
                institutionID: institutionID,
                initialProducts: products
            )
        )
        return response
    }

    public func exchangePublicToken(_ publicToken: String) async throws -> PlaidPublicTokenExchangeResponse {
        let configuration = try configurationProvider()
        let response: PlaidPublicTokenExchangeResponse = try await post(
            path: "/item/public_token/exchange",
            body: PlaidPublicTokenExchangeRequest(
                clientID: configuration.clientID,
                secret: configuration.secret,
                publicToken: publicToken
            )
        )
        return response
    }

    public func syncTransactions(accessToken: String, cursor: String?) async throws -> PlaidTransactionsSyncResponse {
        let configuration = try configurationProvider()
        var response = PlaidTransactionsSyncResponse.empty
        var nextCursor = cursor
        var hasMore = true

        while hasMore {
            let page: PlaidTransactionsSyncResponse = try await post(
                path: "/transactions/sync",
                body: PlaidTransactionsSyncRequest(
                    clientID: configuration.clientID,
                    secret: configuration.secret,
                    accessToken: accessToken,
                    cursor: nextCursor
                )
            )

            response.append(page)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        }

        return response
    }

    private func post<Request: Encodable, Response: Decodable>(path: String, body: Request) async throws -> Response {
        let configuration = try configurationProvider()
        var request = URLRequest(url: configuration.environment.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, urlResponse) = try await session.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw PlaidHTTPError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let plaidError = try? decoder.decode(PlaidErrorResponse.self, from: data) {
                throw PlaidHTTPError.api(plaidError)
            }

            throw PlaidHTTPError.statusCode(httpResponse.statusCode)
        }

        return try decoder.decode(Response.self, from: data)
    }
}

public enum PlaidHTTPError: Error, LocalizedError {
    case invalidResponse
    case statusCode(Int)
    case api(PlaidErrorResponse)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Plaid returned an invalid HTTP response."
        case let .statusCode(statusCode):
            return "Plaid returned HTTP \(statusCode)."
        case let .api(error):
            return "\(error.errorCode): \(error.errorMessage)"
        }
    }
}

public struct PlaidErrorResponse: Decodable, Hashable, Sendable {
    public var errorType: String
    public var errorCode: String
    public var errorMessage: String
    public var requestID: String?

    enum CodingKeys: String, CodingKey {
        case errorType = "error_type"
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case requestID = "request_id"
    }
}
