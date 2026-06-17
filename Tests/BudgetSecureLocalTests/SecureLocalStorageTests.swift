import BudgetCore
import BudgetPersistence
import BudgetPlaid
@testable import BudgetSecureLocal
import XCTest

final class SecureLocalStorageTests: XCTestCase {
    func testSecureStoreFailsClosedWhenSQLCipherIsUnavailable() throws {
        guard !Self.sqlCipherIsAvailable() else {
            throw XCTSkip("SQLCipher is available; covered by encrypted round-trip test.")
        }

        let directory = try temporaryDirectory()
        let configuration = SecureLocalStoreConfiguration(
            databaseURL: directory.appendingPathComponent("BudgetTracer.sqlite"),
            userID: "local-user"
        )

        XCTAssertThrowsError(
            try SecureLocalStore(
                configuration: configuration,
                secretStore: InMemorySecureSecretStore()
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, SQLiteError.encryptionUnavailable.localizedDescription)
        }
    }

    func testSecureStoreEncryptsLedgerAndRejectsWrongKeyWhenSQLCipherIsAvailable() throws {
        guard Self.sqlCipherIsAvailable() else {
            throw XCTSkip("SQLCipher runtime is not installed for this test environment.")
        }

        let directory = try temporaryDirectory()
        let databaseURL = directory.appendingPathComponent("BudgetTracer.sqlite")
        let configuration = SecureLocalStoreConfiguration(databaseURL: databaseURL, userID: "local-user")
        let secretStore = InMemorySecureSecretStore()
        let store = try SecureLocalStore(configuration: configuration, secretStore: secretStore)

        try store.repository.upsertInstitution(id: "ins-secure", name: "Sensitive Bank")
        try store.repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-secure",
                userID: "local-user",
                plaidItemID: "plaid-item-secure",
                institutionID: "ins-secure",
                accessTokenRef: "keychain://token",
                transactionsCursor: nil
            )
        )
        try store.repository.upsertAccount(
            StoredAccount(
                id: "account-secure",
                userID: "local-user",
                itemID: "item-secure",
                plaidAccountID: "account-secure",
                name: "Sensitive Checking",
                officialName: nil,
                kind: .checking,
                plaidType: "depository",
                plaidSubtype: "checking",
                mask: "1234",
                currencyCode: "USD",
                currentBalanceMinorUnits: 123_456,
                availableBalanceMinorUnits: nil
            )
        )
        try store.repository.upsertTransaction(
            StoredTransaction(
                id: "txn-secure",
                userID: "local-user",
                itemID: "item-secure",
                accountID: "account-secure",
                plaidTransactionID: "txn-secure",
                pendingTransactionID: nil,
                merchantName: "Sensitive Coffee",
                originalName: nil,
                postedDate: DateCoding.day(from: "2026-06-13")!,
                authorizedDate: nil,
                amountMinorUnits: -999,
                currencyCode: "USD",
                paymentChannel: nil,
                personalFinanceCategoryPrimary: nil,
                personalFinanceCategoryDetailed: nil,
                isPending: false
            )
        )
        store.database.close()

        let sidecarBytes = try SecureLocalStore.databaseFiles(for: databaseURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { try Data(contentsOf: $0) }
        XCTAssertFalse(sidecarBytes.contains { data in
            String(data: data, encoding: .utf8)?.contains("Sensitive Coffee") == true
        })

        let wrongKeyStore = InMemorySecureSecretStore(
            values: [SecureLocalKeyMaterial.databaseKeyAccount: Data(repeating: 1, count: 32)]
        )
        XCTAssertThrowsError(try SecureLocalStore(configuration: configuration, secretStore: wrongKeyStore))
    }

    func testSecurePlaidTokenVaultStoresAccessTokensInSecretStore() throws {
        let secretStore = InMemorySecureSecretStore()
        let vault = SecurePlaidTokenVault(secretStore: secretStore)

        let reference = try vault.storeAccessToken("access-token", userID: "local-user", plaidItemID: "item-1")

        XCTAssertEqual(try vault.accessToken(for: reference), "access-token")
        try vault.deleteAllTokens()
        XCTAssertThrowsError(try vault.accessToken(for: reference))
    }

    func testSecureLocalModeCanBeDrivenByAppInfoDictionary() {
        XCTAssertTrue(
            SecureLocalAppServices.usesSecureLocalMode(
                environment: [:],
                infoDictionary: ["BudgetTracerDataMode": "secure-local"]
            )
        )
        XCTAssertFalse(
            SecureLocalAppServices.usesSecureLocalMode(
                environment: ["BUDGETTRACER_DATA_MODE": "demo"],
                infoDictionary: ["BudgetTracerDataMode": "secure-local"]
            )
        )
    }

    func testRelayURLCanBeDrivenByAppInfoDictionaryAndOverriddenByEnvironment() {
        let infoURL = SecureLocalAppServices.relayURL(
            environment: [:],
            infoDictionary: ["BudgetTracerPlaidRelayURL": "https://api.budgettracer.app"]
        )
        let environmentURL = SecureLocalAppServices.relayURL(
            environment: ["BUDGETTRACER_PLAID_RELAY_URL": "https://relay.example.com"],
            infoDictionary: ["BudgetTracerPlaidRelayURL": "https://api.budgettracer.app"]
        )

        XCTAssertEqual(infoURL.absoluteString, "https://api.budgettracer.app")
        XCTAssertEqual(environmentURL.absoluteString, "https://relay.example.com")
    }

    @MainActor
    func testPlaidRelayRejectsInsecureNonLocalhostURL() {
        XCTAssertThrowsError(
            try PlaidRelayClient(
                baseURL: URL(string: "http://example.com")!,
                identityTokenProvider: StaticAppleIdentityTokenProvider(token: "signed-apple-token")
            )
        )
    }

    private static func sqlCipherIsAvailable() -> Bool {
        (try? SQLiteDatabase(path: ":memory:").cipherVersion()) != nil
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BudgetSecureLocalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
