import BudgetCore
import Foundation

public enum SecureLocalAppServices {
    @MainActor
    public static func makeFinancialDataProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SecureLocalFinancialDataProvider {
        let secretStore = KeychainSecureSecretStore()
        let tokenVault = SecurePlaidTokenVault(secretStore: secretStore)
        let store = try SecureLocalStore(
            configuration: try storeConfiguration(environment: environment),
            secretStore: secretStore
        )
        let relayClient = try PlaidRelayClient(
            baseURL: relayURL(environment: environment),
            identityTokenProvider: identityProvider(environment: environment),
            securityPolicy: relaySecurityPolicy(environment: environment)
        )

        return SecureLocalFinancialDataProvider(
            store: store,
            relayClient: relayClient,
            tokenVault: tokenVault
        )
    }

    public static func usesSecureLocalMode(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["BUDGETTRACER_DATA_MODE"] == "secure-local"
            || environment["BUDGETTRACER_SECURE_LOCAL"] == "1"
    }

    private static func storeConfiguration(environment: [String: String]) throws -> SecureLocalStoreConfiguration {
        if let databasePath = environment["BUDGETTRACER_SECURE_DATABASE_PATH"], !databasePath.isEmpty {
            return SecureLocalStoreConfiguration(
                databaseURL: URL(fileURLWithPath: databasePath),
                userID: environment["BUDGETTRACER_USER_ID"] ?? "local-user"
            )
        }

        return try SecureLocalStoreConfiguration.appContainer(
            userID: environment["BUDGETTRACER_USER_ID"] ?? "local-user"
        )
    }

    private static func relayURL(environment: [String: String]) -> URL {
        environment["BUDGETTRACER_PLAID_RELAY_URL"].flatMap(URL.init(string:))
            ?? URL(string: "https://api.budgettracer.app")!
    }

    private static func relaySecurityPolicy(environment: [String: String]) -> PlaidRelaySecurityPolicy {
        environment["BUDGETTRACER_ALLOW_INSECURE_LOCAL_RELAY"] == "1"
            ? .allowInsecureLocalhost
            : .httpsOnly
    }

    @MainActor
    private static func identityProvider(environment: [String: String]) -> any AppleIdentityTokenProvider {
        if let staticToken = environment["BUDGETTRACER_APPLE_IDENTITY_TOKEN"], !staticToken.isEmpty {
            return StaticAppleIdentityTokenProvider(token: staticToken)
        }

        #if canImport(AuthenticationServices)
        return CachedAppleIdentityTokenProvider(upstream: SignInWithAppleIdentityTokenProvider())
        #else
        return StaticAppleIdentityTokenProvider(token: "")
        #endif
    }
}
