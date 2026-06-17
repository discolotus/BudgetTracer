import BudgetPlaid
import Foundation

struct BackendConfiguration {
    var bindHost: String
    var port: UInt16
    var databasePath: String
    var defaultUserID: String
    var webhookURL: URL?
    var redirectURI: URL?
    var routeMode: BackendRouteMode
    var plaidEnvironment: PlaidEnvironment
    var plaidCredentialStore: PlaidCredentialStoreMode
    var plaidSecretsPath: String?
    var plaidTokenVault: PlaidTokenVaultMode
    var plaidTokenVaultPath: String
    var appleIdentityAudience: String?

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> BackendConfiguration {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let stateDirectory = home.appendingPathComponent(".budgettracer", isDirectory: true)
        let secretsDirectory = stateDirectory.appendingPathComponent("secrets", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: secretsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let defaultSecretsPath = secretsDirectory.appendingPathComponent("PlaidSecrets.imported").path
        let credentialStoreMode = PlaidCredentialStoreMode(rawValue: environment["BUDGETTRACER_PLAID_CREDENTIAL_STORE"] ?? "file") ?? .file
        let tokenVaultMode = PlaidTokenVaultMode(rawValue: environment["BUDGETTRACER_PLAID_TOKEN_VAULT"] ?? "file") ?? .file
        let plaidEnvironment = PlaidEnvironment(
            rawValue: (
                environment["BUDGETTRACER_PLAID_ENVIRONMENT"]
                    ?? environment["PLAID_ENVIRONMENT"]
                    ?? "sandbox"
            ).lowercased()
        ) ?? .sandbox

        return BackendConfiguration(
            bindHost: environment["BUDGETTRACER_BACKEND_HOST"] ?? "127.0.0.1",
            port: UInt16(environment["BUDGETTRACER_BACKEND_PORT"] ?? "") ?? 8790,
            databasePath: environment["BUDGETTRACER_DATABASE_PATH"] ?? stateDirectory.appendingPathComponent("BudgetTracer.sqlite").path,
            defaultUserID: environment["BUDGETTRACER_USER_ID"] ?? "local-user",
            webhookURL: environment["PLAID_WEBHOOK_URL"].flatMap(URL.init(string:)),
            redirectURI: environment["PLAID_REDIRECT_URI"].flatMap(URL.init(string:)),
            routeMode: BackendRouteMode(environment: environment),
            plaidEnvironment: plaidEnvironment,
            plaidCredentialStore: credentialStoreMode,
            plaidSecretsPath: environment["BUDGETTRACER_PLAID_SECRETS_PATH"] ?? defaultSecretsPath,
            plaidTokenVault: tokenVaultMode,
            plaidTokenVaultPath: environment["BUDGETTRACER_PLAID_TOKEN_VAULT_PATH"]
                ?? secretsDirectory.appendingPathComponent("plaid_access_tokens.json").path,
            appleIdentityAudience: environment["BUDGETTRACER_APPLE_AUDIENCE"]
        )
    }
}

enum PlaidCredentialStoreMode: String {
    case file
    case environment
    case keychain
}

enum PlaidTokenVaultMode: String {
    case file
    case keychain
}

enum BackendRouteMode: Equatable {
    case development
    case relayOnly

    init(environment: [String: String]) {
        if environment["BUDGETTRACER_RELAY_ONLY"] == "1" {
            self = .relayOnly
            return
        }

        switch (environment["BUDGETTRACER_BACKEND_ROUTE_MODE"] ?? "development").lowercased() {
        case "relay-only", "relay_only", "relay":
            self = .relayOnly
        default:
            self = .development
        }
    }

    var description: String {
        switch self {
        case .development:
            return "development"
        case .relayOnly:
            return "relay-only"
        }
    }
}
