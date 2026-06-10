import BudgetPlaid
import BudgetPersistence
import Foundation

@main
struct BudgetTracerBackendApp {
    private static var retainedServer: LocalHTTPServer?

    static func main() async throws {
        let configuration = try BackendConfiguration.load()
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
                    .sandboxConfiguration(webhookURL: configuration.webhookURL)
            case .keychain:
                return try PlaidCredentialKeychain.sandboxConfiguration(webhookURL: configuration.webhookURL)
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
        let router = BackendRouter(
            repository: repository,
            plaidSyncService: plaidSyncService,
            defaultUserID: configuration.defaultUserID
        )
        let server = LocalHTTPServer(port: configuration.port) { request in
            try await router.route(request)
        }
        retainedServer = server

        try server.start()
        print("BudgetTracerBackend listening on http://127.0.0.1:\(configuration.port)")
        print("Database: \(configuration.databasePath)")

        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }
}

enum BackendConfigurationError: Error, LocalizedError {
    case missingPlaidSecretsPath

    var errorDescription: String? {
        switch self {
        case .missingPlaidSecretsPath:
            return "BUDGETTRACER_PLAID_SECRETS_PATH is required when BUDGETTRACER_PLAID_CREDENTIAL_STORE=file."
        }
    }
}
