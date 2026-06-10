import Foundation

public final class FilePlaidTokenVault: PlaidTokenVault {
    private let path: String
    private let lock = NSLock()

    public init(path: String) {
        self.path = path
    }

    public func storeAccessToken(_ accessToken: String, userID: String, plaidItemID: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        var store = try loadStore()
        let reference = "file://plaid-token/\(userID)/\(plaidItemID)"
        store.tokens[reference] = accessToken
        try saveStore(store)
        return reference
    }

    public func accessToken(for reference: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        guard reference.hasPrefix("file://plaid-token/") else {
            throw PlaidTokenVaultError.invalidReference(reference)
        }

        let store = try loadStore()
        guard let token = store.tokens[reference] else {
            throw PlaidTokenVaultError.missingToken(reference)
        }

        return token
    }

    private func loadStore() throws -> TokenStore {
        guard FileManager.default.fileExists(atPath: path) else {
            return TokenStore(tokens: [:])
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        if data.isEmpty {
            return TokenStore(tokens: [:])
        }

        return try JSONDecoder().decode(TokenStore.self, from: data)
    }

    private func saveStore(_ store: TokenStore) throws {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let data = try JSONEncoder().encode(store)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}

private struct TokenStore: Codable {
    var version: Int = 1
    var tokens: [String: String]
}
