import BudgetPersistence
import Foundation

public enum SecureLocalStoreError: Error, LocalizedError, Sendable {
    case missingApplicationSupportDirectory
    case missingDatabaseKeyForExistingStore
    case databaseReopenRequiredAfterDeletion

    public var errorDescription: String? {
        switch self {
        case .missingApplicationSupportDirectory:
            return "Could not locate the Application Support directory."
        case .missingDatabaseKeyForExistingStore:
            return "An encrypted BudgetTracer database exists, but its Keychain key is missing."
        case .databaseReopenRequiredAfterDeletion:
            return "Secure local data was deleted and the database must be reopened."
        }
    }
}

public struct SecureLocalStoreConfiguration: Sendable {
    public var databaseURL: URL
    public var userID: String

    public init(databaseURL: URL, userID: String = "local-user") {
        self.databaseURL = databaseURL
        self.userID = userID
    }

    public static func appContainer(
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        userID: String = "local-user"
    ) throws -> SecureLocalStoreConfiguration {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SecureLocalStoreError.missingApplicationSupportDirectory
        }

        let folderName = bundleIdentifier ?? "com.budgettracer.secure-local"
        let directory = applicationSupport.appendingPathComponent(folderName, isDirectory: true)
        return SecureLocalStoreConfiguration(
            databaseURL: directory.appendingPathComponent("BudgetTracer.sqlite"),
            userID: userID
        )
    }
}

public final class SecureLocalStore: @unchecked Sendable {
    public let configuration: SecureLocalStoreConfiguration
    public let database: SQLiteDatabase
    public let repository: BudgetRepository

    private let fileManager: FileManager

    public init(
        configuration: SecureLocalStoreConfiguration,
        secretStore: SecureSecretStore,
        fileManager: FileManager = .default
    ) throws {
        self.configuration = configuration
        self.fileManager = fileManager

        let databaseDirectory = configuration.databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: databaseDirectory,
            withIntermediateDirectories: true,
            attributes: Self.secureDirectoryAttributes
        )

        let databaseExists = Self.databaseFiles(for: configuration.databaseURL)
            .contains { fileManager.fileExists(atPath: $0.path) }
        let keyMaterial = SecureLocalKeyMaterial(secretStore: secretStore)
        let databaseKey = try keyMaterial.databaseKey(existingStoreRequiresKey: databaseExists)
        let database = try SQLiteDatabase(path: configuration.databaseURL.path, encryptionKey: databaseKey)
        let repository = BudgetRepository(database: database)
        try repository.migrate()
        try repository.ensureUser(id: configuration.userID)
        Self.applyFileProtection(to: Self.databaseFiles(for: configuration.databaseURL), fileManager: fileManager)

        self.database = database
        self.repository = repository
    }

    public func deleteDatabaseFiles() throws {
        database.close()
        for url in Self.databaseFiles(for: configuration.databaseURL) where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public static func databaseFiles(for databaseURL: URL) -> [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            URL(fileURLWithPath: databaseURL.path + "-journal")
        ]
    }

    private static var secureDirectoryAttributes: [FileAttributeKey: Any] {
        #if os(iOS)
        return [.protectionKey: FileProtectionType.complete]
        #else
        return [:]
        #endif
    }

    private static func applyFileProtection(to urls: [URL], fileManager: FileManager) {
        #if os(iOS)
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        }
        #endif
    }
}
