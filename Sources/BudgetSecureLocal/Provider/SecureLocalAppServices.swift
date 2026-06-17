import BudgetCore
import Foundation

public enum SecureLocalAppServices {
    @MainActor
    public static func makeFinancialDataProvider(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) throws -> SecureLocalFinancialDataProvider {
        let secretStore = KeychainSecureSecretStore()
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
            tokenVault: tokenVault
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

    static func relayURL(
        environment: [String: String],
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> URL {
        nonEmpty(environment["BUDGETTRACER_PLAID_RELAY_URL"]).flatMap(URL.init(string:))
            ?? nonEmpty(infoDictionary?["BudgetTracerPlaidRelayURL"] as? String).flatMap(URL.init(string:))
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

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
