import BudgetPersistence
import Foundation

public struct SecureLocalKeyMaterial: Sendable {
    public static let databaseKeyAccount = "sqlcipher-key-v1"

    private let secretStore: SecureSecretStore

    public init(secretStore: SecureSecretStore) {
        self.secretStore = secretStore
    }

    public func databaseKey(existingStoreRequiresKey: Bool) throws -> SQLiteEncryptionKey {
        if let data = try secretStore.data(for: Self.databaseKeyAccount) {
            return try SQLiteEncryptionKey(data: data)
        }

        guard !existingStoreRequiresKey else {
            throw SecureLocalStoreError.missingDatabaseKeyForExistingStore
        }

        let data = try SecureRandom.data(byteCount: 32)
        try secretStore.setData(data, for: Self.databaseKeyAccount)
        return try SQLiteEncryptionKey(data: data)
    }
}
