import BudgetPlaid
import BudgetPersistence
import Foundation

@main
struct BudgetTracerBackendApp {
    private static var retainedServer: LocalHTTPServer?

    static func main() async throws {
        let configuration = try BackendConfiguration.load()
        if configuration.routeMode == .relayOnly,
           (configuration.appleIdentityAudience ?? "").isEmpty {
            throw BackendConfigurationError.missingAppleIdentityAudience
        }

        let database = try SQLiteDatabase(path: configuration.databasePath)
        let repository = BudgetRepository(database: database)
        try repository.migrate()
        try repository.ensureUser(id: configuration.defaultUserID)

        let plaidClient = PlaidAPIClient {
            switch configuration.plaidCredentialStore {
            case .file:
                guard let path = configuration.plaidSecretsPath else {
                    throw BackendConfigurationError.missingPlaidSecretsPath
                }
                return try PlaidLocalSecretsFile(path: path)
                    .configuration(
                        plaidEnvironment: configuration.plaidEnvironment,
                        webhookURL: configuration.webhookURL,
                        redirectURI: configuration.redirectURI
                    )
            case .environment:
                return try PlaidEnvironmentVariables().configuration(
                    plaidEnvironment: configuration.plaidEnvironment,
                    webhookURL: configuration.webhookURL,
                    redirectURI: configuration.redirectURI
                )
            case .keychain:
                return try PlaidCredentialKeychain.configuration(
                    plaidEnvironment: configuration.plaidEnvironment,
                    webhookURL: configuration.webhookURL,
                    redirectURI: configuration.redirectURI
                )
            }
        }
        let tokenVault: PlaidTokenVault = switch configuration.plaidTokenVault {
        case .file:
            FilePlaidTokenVault(path: configuration.plaidTokenVaultPath)
        case .keychain:
            KeychainPlaidTokenVault()
        }
        let plaidSyncService = PlaidSyncService(
            client: plaidClient,
            repository: repository,
            tokenVault: tokenVault
        )
        let relayIdentityVerifier: RelayIdentityVerifying = if let audience = configuration.appleIdentityAudience,
                                                               !audience.isEmpty {
            AppleIdentityRelayVerifier(audience: audience)
        } else {
            BearerRelayIdentityVerifier()
        }
        let router = BackendRouter(
            repository: repository,
            plaidSyncService: plaidSyncService,
            plaidRelayClient: plaidClient,
            relayIdentityVerifier: relayIdentityVerifier,
            routeMode: configuration.routeMode,
            defaultUserID: configuration.defaultUserID
        )
        let server = LocalHTTPServer(host: configuration.bindHost, port: configuration.port) { request in
            try await router.route(request)
        }
        retainedServer = server

        try server.start()
        print("BudgetTracerBackend listening on http://\(configuration.bindHost):\(configuration.port)")
        print("Route mode: \(configuration.routeMode.description)")
        print("Plaid environment: \(configuration.plaidEnvironment.rawValue)")
        print("Database: \(configuration.databasePath)")

        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }
}

enum BackendConfigurationError: Error, LocalizedError {
    case missingPlaidSecretsPath
    case missingAppleIdentityAudience

    var errorDescription: String? {
        switch self {
        case .missingPlaidSecretsPath:
            return "BUDGETTRACER_PLAID_SECRETS_PATH is required when BUDGETTRACER_PLAID_CREDENTIAL_STORE=file."
        case .missingAppleIdentityAudience:
            return "BUDGETTRACER_APPLE_AUDIENCE is required when BUDGETTRACER_BACKEND_ROUTE_MODE=relay-only."
        }
    }
}
