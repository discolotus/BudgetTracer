import BudgetCore
import Foundation

public enum SecureLocalAppServices {
    @MainActor
    public static func makeFinancialDataProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) throws -> SecureLocalFinancialDataProvider {
        let secretStore = try secretStore(environment: environment)
        let tokenVault = SecurePlaidTokenVault(secretStore: secretStore)
        let store = try SecureLocalStore(
            configuration: try storeConfiguration(environment: environment),
            secretStore: secretStore
        )
        let relayClient = try PlaidRelayClient(
            baseURL: relayURL(environment: environment, infoDictionary: infoDictionary),
            identityTokenProvider: identityProvider(environment: environment),
            securityPolicy: relaySecurityPolicy(environment: environment)
        )

        return SecureLocalFinancialDataProvider(
            store: store,
            relayClient: relayClient,
            tokenVault: tokenVault,
            allowsBackgroundSync: allowsAutomaticRelaySync(environment: environment)
        )
    }

    public static func usesSecureLocalMode(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> Bool {
        if let dataMode = nonEmpty(environment["BUDGETTRACER_DATA_MODE"]) {
            return dataMode.lowercased() == "secure-local"
        }

        if let secureLocal = nonEmpty(environment["BUDGETTRACER_SECURE_LOCAL"]) {
            return ["1", "true", "yes"].contains(secureLocal.lowercased())
        }

        return nonEmpty(infoDictionary?["BudgetTracerDataMode"] as? String)?.lowercased() == "secure-local"
    }

    static func secretStore(environment: [String: String]) throws -> any SecureSecretStore {
        switch developmentSecretStoreMode(environment: environment) {
        case "file":
            return FileSecureSecretStore(directoryURL: developmentSecretStoreURL(environment: environment))
        case nil, "keychain":
            return KeychainSecureSecretStore()
        case let mode?:
            throw SecureLocalAppServicesError.unsupportedDevelopmentSecretStore(mode)
        }
    }

    static func storeConfiguration(environment: [String: String]) throws -> SecureLocalStoreConfiguration {
        if let databasePath = nonEmpty(environment["BUDGETTRACER_SECURE_DATABASE_PATH"]) {
            return SecureLocalStoreConfiguration(
                databaseURL: fileURL(from: databasePath),
                userID: environment["BUDGETTRACER_USER_ID"] ?? "local-user"
            )
        }

        if developmentSecretStoreMode(environment: environment) == "file" {
            return SecureLocalStoreConfiguration(
                databaseURL: try secureDevelopmentStateDirectory(environment: environment)
                    .appendingPathComponent("BudgetTracer.sqlite"),
                userID: environment["BUDGETTRACER_USER_ID"] ?? "local-user"
            )
        }

        return try SecureLocalStoreConfiguration.appContainer(
            userID: environment["BUDGETTRACER_USER_ID"] ?? "local-user"
        )
    }

    static func relayURL(
        environment: [String: String],
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> URL {
        nonEmpty(environment["BUDGETTRACER_PLAID_RELAY_URL"]).flatMap(URL.init(string:))
            ?? nonEmpty(infoDictionary?["BudgetTracerPlaidRelayURL"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://budgettracer-plaid-relay.tanner-m-leo.workers.dev")!
    }

    private static func relaySecurityPolicy(environment: [String: String]) -> PlaidRelaySecurityPolicy {
        environment["BUDGETTRACER_ALLOW_INSECURE_LOCAL_RELAY"] == "1"
            ? .allowInsecureLocalhost
            : .httpsOnly
    }

    static func allowsAutomaticRelaySync(environment: [String: String]) -> Bool {
        nonEmpty(environment["BUDGETTRACER_APPLE_IDENTITY_TOKEN"]) != nil
    }

    @MainActor
    private static func identityProvider(environment: [String: String]) -> any AppleIdentityTokenProvider {
        if let staticToken = nonEmpty(environment["BUDGETTRACER_APPLE_IDENTITY_TOKEN"]) {
            return StaticAppleIdentityTokenProvider(token: staticToken)
        }

        #if canImport(AuthenticationServices)
        return CachedAppleIdentityTokenProvider(upstream: SignInWithAppleIdentityTokenProvider())
        #else
        return StaticAppleIdentityTokenProvider(token: "")
        #endif
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func developmentSecretStoreMode(environment: [String: String]) -> String? {
        nonEmpty(environment["BUDGETTRACER_DEV_SECRET_STORE"])?.lowercased()
    }

    private static func developmentSecretStoreURL(environment: [String: String]) -> URL {
        if let path = nonEmpty(environment["BUDGETTRACER_DEV_SECRET_STORE_PATH"]) {
            return fileURL(from: path)
        }

        return developmentStateDirectory(environment: environment)
            .appendingPathComponent("secrets", isDirectory: true)
    }

    private static func developmentStateDirectory(environment: [String: String]) -> URL {
        if let path = nonEmpty(environment["BUDGETTRACER_DEV_STATE_DIR"]) {
            return fileURL(from: path)
        }

        return fileURL(from: "~/.budgettracer/secure-local-dev")
    }

    private static func secureDevelopmentStateDirectory(environment: [String: String]) throws -> URL {
        let url = developmentStateDirectory(environment: environment)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: secureDirectoryAttributes
        )
        try FileManager.default.setAttributes(secureDirectoryAttributes, ofItemAtPath: url.path)
        return url
    }

    private static func fileURL(from path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static var secureDirectoryAttributes: [FileAttributeKey: Any] {
        [.posixPermissions: 0o700]
    }
}

public enum SecureLocalAppServicesError: Error, LocalizedError, Sendable {
    case unsupportedDevelopmentSecretStore(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedDevelopmentSecretStore(let mode):
            return "Unsupported development secret store '\(mode)'. Use 'file' or 'keychain'."
        }
    }
}
