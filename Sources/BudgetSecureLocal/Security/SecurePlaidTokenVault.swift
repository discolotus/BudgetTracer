import BudgetPlaid
import Foundation

public final class SecurePlaidTokenVault: PlaidTokenVault, @unchecked Sendable {
    private let secretStore: SecureSecretStore
    private let referencePrefix = "keychain://com.budgettracer.secure-local/plaid-token/"

    public init(secretStore: SecureSecretStore) {
        self.secretStore = secretStore
    }

    public func storeAccessToken(_ accessToken: String, userID: String, plaidItemID: String) throws -> String {
        let account = accountName(userID: userID, plaidItemID: plaidItemID)
        guard let data = accessToken.data(using: .utf8) else {
            throw PlaidTokenVaultError.invalidReference(account)
        }

        try secretStore.setData(data, for: account)
        return referencePrefix + account
    }

    public func accessToken(for reference: String) throws -> String {
        guard reference.hasPrefix(referencePrefix) else {
            throw PlaidTokenVaultError.invalidReference(reference)
        }

        let account = String(reference.dropFirst(referencePrefix.count))
        guard let data = try secretStore.data(for: account),
              let accessToken = String(data: data, encoding: .utf8) else {
            throw PlaidTokenVaultError.missingToken(reference)
        }

        return accessToken
    }

    public func deleteAllTokens() throws {
        try secretStore.deleteAllData()
    }

    private func accountName(userID: String, plaidItemID: String) -> String {
        "plaid-token:\(userID):\(plaidItemID)"
    }
}
