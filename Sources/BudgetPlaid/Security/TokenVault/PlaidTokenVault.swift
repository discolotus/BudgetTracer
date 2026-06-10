import Foundation

public protocol PlaidTokenVault {
    func storeAccessToken(_ accessToken: String, userID: String, plaidItemID: String) throws -> String
    func accessToken(for reference: String) throws -> String
}

public final class InMemoryPlaidTokenVault: PlaidTokenVault {
    private var tokens: [String: String] = [:]

    public init() {}

    public func storeAccessToken(_ accessToken: String, userID: String, plaidItemID: String) throws -> String {
        let reference = "memory://plaid-token/\(userID)/\(plaidItemID)"
        tokens[reference] = accessToken
        return reference
    }

    public func accessToken(for reference: String) throws -> String {
        guard let token = tokens[reference] else {
            throw PlaidTokenVaultError.missingToken(reference)
        }

        return token
    }
}

public enum PlaidTokenVaultError: Error, LocalizedError {
    case missingToken(String)
    case invalidReference(String)

    public var errorDescription: String? {
        switch self {
        case let .missingToken(reference):
            return "Missing Plaid access token for reference \(reference)."
        case let .invalidReference(reference):
            return "Invalid Plaid token reference \(reference)."
        }
    }
}
