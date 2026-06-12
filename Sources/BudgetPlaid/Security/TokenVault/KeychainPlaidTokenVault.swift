import Foundation

public final class KeychainPlaidTokenVault: PlaidTokenVault {
    private let serviceName: String
    private var cachedTokens: [String: String] = [:]

    public init(serviceName: String = "com.budgettracer.plaid.access-tokens") {
        self.serviceName = serviceName
    }

    public func storeAccessToken(_ accessToken: String, userID: String, plaidItemID: String) throws -> String {
        let account = accountName(userID: userID, plaidItemID: plaidItemID)
        try KeychainStore.setPassword(accessToken, serviceName: serviceName, accountName: account)
        let reference = "keychain://\(serviceName)/\(account)"
        cachedTokens[reference] = accessToken
        return reference
    }

    public func accessToken(for reference: String) throws -> String {
        if let token = cachedTokens[reference] {
            return token
        }

        let account = try accountName(from: reference)
        let token = try KeychainStore.password(serviceName: serviceName, accountName: account)
        cachedTokens[reference] = token
        return token
    }

    private func accountName(userID: String, plaidItemID: String) -> String {
        "\(userID):\(plaidItemID)"
    }

    private func accountName(from reference: String) throws -> String {
        let prefix = "keychain://\(serviceName)/"
        guard reference.hasPrefix(prefix), reference.count > prefix.count else {
            throw PlaidTokenVaultError.invalidReference(reference)
        }

        return String(reference.dropFirst(prefix.count))
    }
}

public enum PlaidCredentialKeychain {
    public static let sandboxServiceName = "com.budgettracer.plaid.sandbox"
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cachedSandboxConfiguration: PlaidConfiguration?

    public static func sandboxConfiguration(webhookURL: URL? = nil, redirectURI: URL? = nil) throws -> PlaidConfiguration {
        lock.lock()
        defer { lock.unlock() }

        if var cachedSandboxConfiguration {
            cachedSandboxConfiguration.webhookURL = webhookURL
            cachedSandboxConfiguration.redirectURI = redirectURI
            return cachedSandboxConfiguration
        }

        let configuration = try PlaidConfiguration(
            clientID: KeychainStore.password(serviceName: sandboxServiceName, accountName: "PLAID_CLIENT_ID"),
            secret: KeychainStore.password(serviceName: sandboxServiceName, accountName: "PLAID_SANDBOX_SECRET"),
            environment: .sandbox,
            webhookURL: webhookURL,
            redirectURI: redirectURI
        )
        cachedSandboxConfiguration = configuration
        return configuration
    }
}

enum KeychainStore {
    static func setPassword(_ password: String, serviceName: String, accountName: String) throws {
        _ = try runSecurity([
            "add-generic-password",
            "-a", accountName,
            "-s", serviceName,
            "-w", password,
            "-U"
        ])
    }

    static func password(serviceName: String, accountName: String) throws -> String {
        try runSecurity([
            "find-generic-password",
            "-w",
            "-a", accountName,
            "-s", serviceName
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runSecurity(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "security command failed"
            throw KeychainError.command(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

enum KeychainError: Error, LocalizedError {
    case command(String)

    var errorDescription: String? {
        switch self {
        case let .command(message):
            return message
        }
    }
}
