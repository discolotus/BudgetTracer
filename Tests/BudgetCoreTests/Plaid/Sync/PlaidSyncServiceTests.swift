import BudgetCore
import BudgetPersistence
import BudgetPlaid
import XCTest

final class PlaidSyncServiceTests: XCTestCase {
    func testSyncAppliesPlaidTransactionsSyncChangesToDatabase() async throws {
        let database = try SQLiteDatabase(path: ":memory:")
        let repository = BudgetRepository(database: database)
        try repository.migrate()
        try repository.ensureUser(id: "user-1")
        let vault = InMemoryPlaidTokenVault()
        let tokenRef = try vault.storeAccessToken("access-token", userID: "user-1", plaidItemID: "item-1")
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-1",
                userID: "user-1",
                plaidItemID: "item-1",
                institutionID: nil,
                accessTokenRef: tokenRef,
                transactionsCursor: nil
            )
        )

        let client = FakePlaidClient(
            syncResponses: [
                PlaidTransactionsSyncResponse(
                accounts: [
                    PlaidAccount(
                        accountID: "account-1",
                        balances: PlaidBalances(
                            available: Decimal(4500),
                            current: Decimal(5000),
                            isoCurrencyCode: "USD",
                            unofficialCurrencyCode: nil
                        ),
                        mask: "0000",
                        name: "Checking",
                        officialName: nil,
                        type: "depository",
                        subtype: "checking"
                    )
                ],
                added: [
                    PlaidTransaction(
                        transactionID: "txn-payroll",
                        accountID: "account-1",
                        pendingTransactionID: nil,
                        name: "PAYROLL",
                        merchantName: "Payroll",
                        date: "2026-06-01",
                        authorizedDate: nil,
                        amount: Decimal(-3200),
                        isoCurrencyCode: "USD",
                        unofficialCurrencyCode: nil,
                        paymentChannel: "other",
                        pending: false,
                        personalFinanceCategory: PlaidPersonalFinanceCategory(primary: "INCOME", detailed: "INCOME_WAGES")
                    ),
                    PlaidTransaction(
                        transactionID: "txn-rent",
                        accountID: "account-1",
                        pendingTransactionID: nil,
                        name: "RENT",
                        merchantName: "Rent",
                        date: "2026-06-02",
                        authorizedDate: nil,
                        amount: Decimal(2100),
                        isoCurrencyCode: "USD",
                        unofficialCurrencyCode: nil,
                        paymentChannel: "other",
                        pending: false,
                        personalFinanceCategory: PlaidPersonalFinanceCategory(primary: "RENT_AND_UTILITIES", detailed: "RENT_AND_UTILITIES_RENT")
                    )
                ],
                modified: [],
                removed: [],
                nextCursor: "cursor-page-1",
                hasMore: true,
                requestID: "request-1"
                ),
                PlaidTransactionsSyncResponse(
                    accounts: [],
                    added: [],
                    modified: [],
                    removed: [],
                    nextCursor: "cursor-1",
                    hasMore: false,
                    requestID: "request-2"
                )
            ]
            )
        let service = PlaidSyncService(client: client, repository: repository, tokenVault: vault)
        let snapshot = try await service.syncItem(id: "item-1")
        let item = try XCTUnwrap(repository.plaidItem(id: "item-1"))
        let syncEvent = try XCTUnwrap(repository.latestSyncEvent(itemID: "item-1"))

        XCTAssertEqual(item.transactionsCursor, "cursor-1")
        XCTAssertEqual(snapshot.accounts.first?.currentBalance, Money(minorUnits: 500_000))
        XCTAssertEqual(snapshot.monthlyIncome, Money(minorUnits: 320_000))
        XCTAssertEqual(snapshot.monthlySpending, Money(minorUnits: 210_000))
        XCTAssertEqual(client.observedCursors, [nil, "cursor-page-1"])
        XCTAssertEqual(syncEvent.status, "succeeded")
        XCTAssertEqual(syncEvent.addedCount, 2)
        XCTAssertEqual(syncEvent.modifiedCount, 0)
        XCTAssertEqual(syncEvent.removedCount, 0)
    }

    func testSyncMapsMoneyMarketAndCdAccountsAsInvestments() async throws {
        let database = try SQLiteDatabase(path: ":memory:")
        let repository = BudgetRepository(database: database)
        try repository.migrate()
        try repository.ensureUser(id: "user-1")
        let vault = InMemoryPlaidTokenVault()
        let tokenRef = try vault.storeAccessToken("access-token", userID: "user-1", plaidItemID: "item-1")
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-1",
                userID: "user-1",
                plaidItemID: "item-1",
                institutionID: nil,
                accessTokenRef: tokenRef,
                transactionsCursor: nil
            )
        )

        let client = FakePlaidClient(
            syncResponse: PlaidTransactionsSyncResponse(
                accounts: [
                    PlaidAccount(
                        accountID: "checking",
                        balances: PlaidBalances(
                            available: Decimal(1200),
                            current: Decimal(1200),
                            isoCurrencyCode: "USD",
                            unofficialCurrencyCode: nil
                        ),
                        mask: nil,
                        name: "Checking",
                        officialName: nil,
                        type: "depository",
                        subtype: "checking"
                    ),
                    PlaidAccount(
                        accountID: "money-market",
                        balances: PlaidBalances(
                            available: Decimal(9000),
                            current: Decimal(9000),
                            isoCurrencyCode: "USD",
                            unofficialCurrencyCode: nil
                        ),
                        mask: nil,
                        name: "Money Market",
                        officialName: nil,
                        type: "depository",
                        subtype: "money market"
                    ),
                    PlaidAccount(
                        accountID: "cd",
                        balances: PlaidBalances(
                            available: nil,
                            current: Decimal(3000),
                            isoCurrencyCode: "USD",
                            unofficialCurrencyCode: nil
                        ),
                        mask: nil,
                        name: "Certificate of Deposit",
                        officialName: nil,
                        type: "depository",
                        subtype: "cd"
                    )
                ],
                added: [],
                modified: [],
                removed: [],
                nextCursor: "cursor-1",
                hasMore: false,
                requestID: "request-1"
            )
        )
        let service = PlaidSyncService(client: client, repository: repository, tokenVault: vault)
        let snapshot = try await service.syncItem(id: "item-1")
        let accountsByID = Dictionary(uniqueKeysWithValues: snapshot.accounts.map { ($0.id, $0) })

        XCTAssertEqual(accountsByID["checking"]?.kind, .checking)
        XCTAssertEqual(accountsByID["money-market"]?.kind, .investment)
        XCTAssertEqual(accountsByID["cd"]?.kind, .investment)
        XCTAssertEqual(snapshot.availableCash, .dollars(1200))
    }

    func testSyncStoresAccountsFromAccountsGetEvenWhenTheyHaveNoTransactions() async throws {
        let database = try SQLiteDatabase(path: ":memory:")
        let repository = BudgetRepository(database: database)
        try repository.migrate()
        try repository.ensureUser(id: "user-1")
        let vault = InMemoryPlaidTokenVault()
        let tokenRef = try vault.storeAccessToken("access-token", userID: "user-1", plaidItemID: "item-1")
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-1",
                userID: "user-1",
                plaidItemID: "item-1",
                institutionID: nil,
                accessTokenRef: tokenRef,
                transactionsCursor: nil
            )
        )

        let client = FakePlaidClient(
            syncResponse: PlaidTransactionsSyncResponse(
                accounts: [],
                added: [],
                modified: [],
                removed: [],
                nextCursor: "cursor-1",
                hasMore: false,
                requestID: "request-1"
            )
        )
        client.accountsResponse = PlaidAccountsGetResponse(
            accounts: [
                PlaidAccount(
                    accountID: "checking",
                    balances: PlaidBalances(
                        available: Decimal(1200),
                        current: Decimal(1200),
                        isoCurrencyCode: "USD",
                        unofficialCurrencyCode: nil
                    ),
                    mask: nil,
                    name: "Checking",
                    officialName: nil,
                    type: "depository",
                    subtype: "checking"
                ),
                PlaidAccount(
                    accountID: "brokerage",
                    balances: PlaidBalances(
                        available: nil,
                        current: Decimal(9500),
                        isoCurrencyCode: "USD",
                        unofficialCurrencyCode: nil
                    ),
                    mask: nil,
                    name: "Brokerage",
                    officialName: nil,
                    type: "investment",
                    subtype: "brokerage"
                ),
                PlaidAccount(
                    accountID: "card",
                    balances: PlaidBalances(
                        available: nil,
                        current: Decimal(250),
                        isoCurrencyCode: "USD",
                        unofficialCurrencyCode: nil
                    ),
                    mask: nil,
                    name: "Credit Card",
                    officialName: nil,
                    type: "credit",
                    subtype: "credit card"
                ),
                PlaidAccount(
                    accountID: "loan",
                    balances: PlaidBalances(
                        available: nil,
                        current: Decimal(15000),
                        isoCurrencyCode: "USD",
                        unofficialCurrencyCode: nil
                    ),
                    mask: nil,
                    name: "Loan",
                    officialName: nil,
                    type: "loan",
                    subtype: "student"
                )
            ],
            requestID: "accounts-request"
        )

        let service = PlaidSyncService(client: client, repository: repository, tokenVault: vault)
        let snapshot = try await service.syncItem(id: "item-1")
        let accountsByID = Dictionary(uniqueKeysWithValues: snapshot.accounts.map { ($0.id, $0) })

        XCTAssertEqual(client.observedAccountGetAccessTokens, ["access-token"])
        XCTAssertEqual(accountsByID.keys.sorted(), ["brokerage", "card", "checking", "loan"])
        XCTAssertEqual(accountsByID["checking"]?.kind, .checking)
        XCTAssertEqual(accountsByID["brokerage"]?.kind, .investment)
        XCTAssertEqual(accountsByID["card"]?.kind, .creditCard)
        XCTAssertEqual(accountsByID["loan"]?.kind, .loan)
        XCTAssertTrue(snapshot.transactions.isEmpty)
    }

    func testSyncMarksRemovedTransactionsWithoutDeletingUserAnnotations() async throws {
        let database = try SQLiteDatabase(path: ":memory:")
        let repository = BudgetRepository(database: database)
        try repository.migrate()
        try repository.ensureUser(id: "user-1")
        let vault = InMemoryPlaidTokenVault()
        let tokenRef = try vault.storeAccessToken("access-token", userID: "user-1", plaidItemID: "item-1")
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-1",
                userID: "user-1",
                plaidItemID: "item-1",
                institutionID: nil,
                accessTokenRef: tokenRef,
                transactionsCursor: "cursor-1"
            )
        )
        try repository.upsertAccount(
            StoredAccount(
                id: "account-1",
                userID: "user-1",
                itemID: "item-1",
                plaidAccountID: "account-1",
                name: "Checking",
                officialName: nil,
                kind: .checking,
                plaidType: "depository",
                plaidSubtype: "checking",
                mask: nil,
                currencyCode: "USD",
                currentBalanceMinorUnits: 100_000,
                availableBalanceMinorUnits: nil
            )
        )
        try repository.upsertTransaction(
            StoredTransaction(
                id: "txn-old",
                userID: "user-1",
                itemID: "item-1",
                accountID: "account-1",
                plaidTransactionID: "txn-old",
                pendingTransactionID: nil,
                merchantName: "Old Pending",
                originalName: nil,
                postedDate: DateCoding.day(from: "2026-06-01")!,
                authorizedDate: nil,
                amountMinorUnits: -4_200,
                currencyCode: "USD",
                paymentChannel: nil,
                personalFinanceCategoryPrimary: nil,
                personalFinanceCategoryDetailed: nil,
                isPending: true
            )
        )
        try repository.setRegularMonthly(transactionID: "txn-old", isRegularMonthly: true, userID: "user-1")

        let client = FakePlaidClient(
            syncResponse: PlaidTransactionsSyncResponse(
                accounts: [],
                added: [],
                modified: [],
                removed: [PlaidRemovedTransaction(transactionID: "txn-old", accountID: "account-1")],
                nextCursor: "cursor-2",
                hasMore: false,
                requestID: "request-2"
            )
        )
        let service = PlaidSyncService(client: client, repository: repository, tokenVault: vault)
        let snapshot = try await service.syncItem(id: "item-1")

        XCTAssertTrue(snapshot.transactions.isEmpty)
        XCTAssertTrue(snapshot.recurringTransactionIDs.isEmpty)
        XCTAssertEqual(try repository.plaidItem(id: "item-1")?.transactionsCursor, "cursor-2")
    }

    func testSyncFailureRecordsFailedSyncEventWithoutAdvancingCursor() async throws {
        let database = try SQLiteDatabase(path: ":memory:")
        let repository = BudgetRepository(database: database)
        try repository.migrate()
        try repository.ensureUser(id: "user-1")
        let vault = InMemoryPlaidTokenVault()
        let tokenRef = try vault.storeAccessToken("access-token", userID: "user-1", plaidItemID: "item-1")
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-1",
                userID: "user-1",
                plaidItemID: "item-1",
                institutionID: nil,
                accessTokenRef: tokenRef,
                transactionsCursor: "cursor-before"
            )
        )

        let client = FakePlaidClient(syncError: PlaidSyncTestError.simulatedFailure)
        let service = PlaidSyncService(client: client, repository: repository, tokenVault: vault)

        do {
            _ = try await service.syncItem(id: "item-1")
            XCTFail("Expected sync to fail.")
        } catch PlaidSyncTestError.simulatedFailure {
        }

        let item = try XCTUnwrap(repository.plaidItem(id: "item-1"))
        let syncEvent = try XCTUnwrap(repository.latestSyncEvent(itemID: "item-1"))

        XCTAssertEqual(item.transactionsCursor, "cursor-before")
        XCTAssertEqual(syncEvent.status, "failed")
        XCTAssertNotNil(syncEvent.finishedAt)
        XCTAssertNotNil(syncEvent.errorMessage)
    }

    func testFileTokenVaultPersistsTokenWithoutKeychain() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let path = directory.appendingPathComponent("tokens.json").path
        let vault = FilePlaidTokenVault(path: path)

        let reference = try vault.storeAccessToken("access-token", userID: "user-1", plaidItemID: "item-1")
        let reloadedVault = FilePlaidTokenVault(path: path)

        XCTAssertEqual(try reloadedVault.accessToken(for: reference), "access-token")
    }

    func testLocalSecretsFileBuildsSandboxConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("PlaidSecrets.imported").path
        try """
        PLAID_CLIENT_ID=test-client
        PLAID_SANDBOX_SECRET='test-secret'
        PLAID_REDIRECT_URI=https://example.com/plaid/oauth
        """.write(toFile: path, atomically: true, encoding: .utf8)

        let configuration = try PlaidLocalSecretsFile(path: path)
            .sandboxConfiguration(webhookURL: URL(string: "https://example.com/webhook"))

        XCTAssertEqual(configuration.clientID, "test-client")
        XCTAssertEqual(configuration.secret, "test-secret")
        XCTAssertEqual(configuration.environment, .sandbox)
        XCTAssertEqual(configuration.webhookURL?.absoluteString, "https://example.com/webhook")
        XCTAssertEqual(configuration.redirectURI?.absoluteString, "https://example.com/plaid/oauth")
    }
}

private final class FakePlaidClient: PlaidAPIClientProtocol {
    var syncResponses: [PlaidTransactionsSyncResponse]
    var syncError: Error?
    var accountsResponse = PlaidAccountsGetResponse.empty
    var observedCursors: [String?] = []
    var observedAccountGetAccessTokens: [String] = []

    init(syncResponse: PlaidTransactionsSyncResponse) {
        self.syncResponses = [syncResponse]
    }

    init(syncResponses: [PlaidTransactionsSyncResponse]) {
        self.syncResponses = syncResponses
    }

    init(syncError: Error) {
        self.syncResponses = []
        self.syncError = syncError
    }

    func createLinkToken(userID: String) async throws -> PlaidLinkTokenResponse {
        PlaidLinkTokenResponse(linkToken: "link-token", expiration: "2026-06-09T00:00:00Z", requestID: nil)
    }

    func createSandboxPublicToken(institutionID: String, products: [String]) async throws -> PlaidSandboxPublicTokenResponse {
        PlaidSandboxPublicTokenResponse(publicToken: "public-token", requestID: nil)
    }

    func exchangePublicToken(_ publicToken: String) async throws -> PlaidPublicTokenExchangeResponse {
        PlaidPublicTokenExchangeResponse(accessToken: "access-token", itemID: "item-1", requestID: nil)
    }

    func getAccounts(accessToken: String) async throws -> PlaidAccountsGetResponse {
        observedAccountGetAccessTokens.append(accessToken)
        return accountsResponse
    }

    func syncTransactions(accessToken: String, cursor: String?) async throws -> PlaidTransactionsSyncResponse {
        observedCursors.append(cursor)
        if let syncError {
            throw syncError
        }

        guard !syncResponses.isEmpty else {
            throw PlaidSyncTestError.missingResponse
        }

        return syncResponses.removeFirst()
    }

    func removeItem(accessToken: String) async throws -> PlaidItemRemoveResponse {
        PlaidItemRemoveResponse(requestID: nil)
    }
}

private enum PlaidSyncTestError: Error {
    case simulatedFailure
    case missingResponse
}
