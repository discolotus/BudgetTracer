import Foundation
import Security

public protocol SecureSecretStore: Sendable {
    func data(for account: String) throws -> Data?
    func setData(_ data: Data, for account: String) throws
    func deleteData(for account: String) throws
    func deleteAllData() throws
}

public enum SecureSecretStoreError: Error, LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status \(status)."
        case .invalidData:
            return "Keychain returned invalid data."
        }
    }
}

public final class KeychainSecureSecretStore: SecureSecretStore, @unchecked Sendable {
    private let serviceName: String
    private let accessGroup: String?
    private let accessible: CFString

    public init(
        serviceName: String = "com.budgettracer.secure-local",
        accessGroup: String? = nil,
        accessible: CFString = kSecAttrAccessibleWhenUnlocked
    ) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
        self.accessible = accessible
    }

    public func data(for account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SecureSecretStoreError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw SecureSecretStoreError.invalidData
        }

        return data
    }

    public func setData(_ data: Data, for account: String) throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw SecureSecretStoreError.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = accessible

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureSecretStoreError.unexpectedStatus(addStatus)
        }
    }

    public func deleteData(for account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureSecretStoreError.unexpectedStatus(status)
        }
    }

    public func deleteAllData() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureSecretStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

public final class InMemorySecureSecretStore: SecureSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init(values: [String: Data] = [:]) {
        self.values = values
    }

    public func data(for account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    public func setData(_ data: Data, for account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[account] = data
    }

    public func deleteData(for account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: account)
    }

    public func deleteAllData() throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
    }
}

public final class FileSecureSecretStore: SecureSecretStore, @unchecked Sendable {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public func data(for account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let url = fileURL(for: account)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return try Data(contentsOf: url)
    }

    public func setData(_ data: Data, for account: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try ensureDirectoryExists()
        let url = fileURL(for: account)
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes(Self.secureFileAttributes, ofItemAtPath: url.path)
    }

    public func deleteData(for account: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let url = fileURL(for: account)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func deleteAllData() throws {
        lock.lock()
        defer { lock.unlock() }

        if fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }
    }

    private func ensureDirectoryExists() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: Self.secureDirectoryAttributes
        )
        try fileManager.setAttributes(Self.secureDirectoryAttributes, ofItemAtPath: directoryURL.path)
    }

    private func fileURL(for account: String) -> URL {
        let encoded = Data(account.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directoryURL.appendingPathComponent("\(encoded).secret", isDirectory: false)
    }

    private static var secureDirectoryAttributes: [FileAttributeKey: Any] {
        [.posixPermissions: 0o700]
    }

    private static var secureFileAttributes: [FileAttributeKey: Any] {
        [.posixPermissions: 0o600]
    }
}

enum SecureRandom {
    static func data(byteCount: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw SecureSecretStoreError.unexpectedStatus(status)
        }
        return Data(bytes)
    }
}
