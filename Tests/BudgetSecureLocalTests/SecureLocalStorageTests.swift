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

    func testFileSecureSecretStorePersistsSecretsOutsideKeychain() throws {
        let directory = try temporaryDirectory()
            .appendingPathComponent("secrets", isDirectory: true)
        let store = FileSecureSecretStore(directoryURL: directory)

        try store.setData(Data("secret-value".utf8), for: "sqlcipher-key-v1")

        let reloadedStore = FileSecureSecretStore(directoryURL: directory)
        XCTAssertEqual(try reloadedStore.data(for: "sqlcipher-key-v1"), Data("secret-value".utf8))

        try reloadedStore.deleteAllData()
        XCTAssertNil(try store.data(for: "sqlcipher-key-v1"))
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
            infoDictionary: ["BudgetTracerPlaidRelayURL": "https://budgettracer-plaid-relay.tanner-m-leo.workers.dev"]
        )
        let environmentURL = SecureLocalAppServices.relayURL(
            environment: ["BUDGETTRACER_PLAID_RELAY_URL": "https://relay.example.com"],
            infoDictionary: ["BudgetTracerPlaidRelayURL": "https://budgettracer-plaid-relay.tanner-m-leo.workers.dev"]
        )

        XCTAssertEqual(infoURL.absoluteString, "https://budgettracer-plaid-relay.tanner-m-leo.workers.dev")
        XCTAssertEqual(environmentURL.absoluteString, "https://relay.example.com")
    }

    func testDevelopmentSecretStorePathsCanBeDrivenByEnvironment() throws {
        let stateDirectory = try temporaryDirectory()
        let secretStore = try SecureLocalAppServices.secretStore(
            environment: [
                "BUDGETTRACER_DEV_SECRET_STORE": "file",
                "BUDGETTRACER_DEV_STATE_DIR": stateDirectory.path
            ]
        )
        let configuration = try SecureLocalAppServices.storeConfiguration(
            environment: [
                "BUDGETTRACER_DEV_SECRET_STORE": "file",
                "BUDGETTRACER_DEV_STATE_DIR": stateDirectory.path,
                "BUDGETTRACER_USER_ID": "dev-user"
            ]
        )

        XCTAssertTrue(secretStore is FileSecureSecretStore)
        XCTAssertEqual(
            configuration.databaseURL.path,
            stateDirectory.appendingPathComponent("BudgetTracer.sqlite").path
        )
        XCTAssertEqual(configuration.userID, "dev-user")
    }

    func testAutomaticRelaySyncRequiresStaticIdentityToken() {
        XCTAssertFalse(SecureLocalAppServices.allowsAutomaticRelaySync(environment: [:]))
        XCTAssertFalse(
            SecureLocalAppServices.allowsAutomaticRelaySync(
                environment: ["BUDGETTRACER_APPLE_IDENTITY_TOKEN": "   "]
            )
        )
        XCTAssertTrue(
            SecureLocalAppServices.allowsAutomaticRelaySync(
                environment: ["BUDGETTRACER_APPLE_IDENTITY_TOKEN": "dev-token"]
            )
        )
    }

    @MainActor
    func testSecureLocalProviderSkipsRelayForBackgroundSyncWhenDisabled() async throws {
        guard Self.sqlCipherIsAvailable() else {
            throw XCTSkip("SQLCipher runtime is not installed for this test environment.")
        }

        let directory = try temporaryDirectory()
        let configuration = SecureLocalStoreConfiguration(
            databaseURL: directory.appendingPathComponent("BudgetTracer.sqlite"),
            userID: "local-user"
        )
        let secretStore = InMemorySecureSecretStore()
        let store = try SecureLocalStore(configuration: configuration, secretStore: secretStore)
        let tokenVault = SecurePlaidTokenVault(secretStore: secretStore)
        let accessTokenRef = try tokenVault.storeAccessToken(
            "access-token",
            userID: "local-user",
            plaidItemID: "plaid-item"
        )

        try store.repository.upsertInstitution(id: "ins-test", name: "Test Bank")
        try store.repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-test",
                userID: "local-user",
                plaidItemID: "plaid-item",
                institutionID: "ins-test",
                accessTokenRef: accessTokenRef,
                transactionsCursor: nil
            )
        )

        CountingRelayURLProtocol.reset()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [CountingRelayURLProtocol.self]
        let client = try PlaidRelayClient(
            baseURL: URL(string: "https://relay.example.com")!,
            identityTokenProvider: StaticAppleIdentityTokenProvider(token: "dev-token"),
            session: URLSession(configuration: sessionConfiguration)
        )
        let provider = SecureLocalFinancialDataProvider(
            store: store,
            relayClient: client,
            tokenVault: tokenVault,
            allowsBackgroundSync: false
        )

        let snapshot = try await provider.fetchBudgetSnapshot(freshnessPolicy: .syncIfStale(maxAge: 300))

        XCTAssertEqual(snapshot.institutions, [Institution(id: "ins-test", name: "Test Bank")])
        XCTAssertEqual(CountingRelayURLProtocol.requestCount, 0)
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

    @MainActor
    func testPlaidRelayIncludesErrorBodyInStatusFailures() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelayErrorURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = try PlaidRelayClient(
            baseURL: URL(string: "https://relay.example.com")!,
            identityTokenProvider: StaticAppleIdentityTokenProvider(token: "bad-token"),
            session: session
        )

        do {
            _ = try await client.createLinkToken(clientUserID: "local-user")
            XCTFail("Expected relay request to fail.")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Plaid relay returned HTTP 401: The bearer token is malformed."
            )
        }
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

private final class RelayErrorURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let data = #"{"error":"The bearer token is malformed."}"#.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CountingRelayURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    static func reset() {
        lock.lock()
        count = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        Self.lock.unlock()

        let data = #"{"error":"Unexpected relay request."}"#.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
