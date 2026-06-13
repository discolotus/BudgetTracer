import BudgetCore
import BudgetPersistence
import XCTest

final class BudgetPersistenceTests: XCTestCase {
    func testRepositoryPersistsSnapshotAndRecurringAnnotationsWithoutStoringRawPlaidToken() throws {
        let repository = try makeRepository()
        try repository.ensureUser(id: "user-1")
        try repository.upsertInstitution(id: "ins_1", name: "Test Bank")
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-1",
                userID: "user-1",
                plaidItemID: "plaid-item-1",
                institutionID: "ins_1",
                accessTokenRef: "vault://token/item-1",
                transactionsCursor: nil
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
                mask: "1234",
                currencyCode: "USD",
                currentBalanceMinorUnits: 125_000,
                availableBalanceMinorUnits: 120_000
            )
        )
        try repository.upsertTransaction(
            StoredTransaction(
                id: "txn-1",
                userID: "user-1",
                itemID: "item-1",
                accountID: "account-1",
                plaidTransactionID: "txn-1",
                pendingTransactionID: nil,
                merchantName: "Payroll",
                originalName: "PAYROLL",
                postedDate: DateCoding.day(from: "2026-06-01")!,
                authorizedDate: nil,
                amountMinorUnits: 300_000,
                currencyCode: "USD",
                paymentChannel: "other",
                personalFinanceCategoryPrimary: "INCOME",
                personalFinanceCategoryDetailed: "INCOME_WAGES",
                isPending: false
            )
        )
        try repository.setRegularMonthly(transactionID: "txn-1", isRegularMonthly: true, userID: "user-1")

        let item = try XCTUnwrap(repository.plaidItem(id: "item-1"))
        let snapshot = try repository.fetchSnapshot(userID: "user-1")

        XCTAssertEqual(item.accessTokenRef, "vault://token/item-1")
        XCTAssertEqual(snapshot.institutions, [Institution(id: "ins_1", name: "Test Bank")])
        XCTAssertEqual(snapshot.accounts.first?.currentBalance, Money(minorUnits: 125_000))
        XCTAssertEqual(snapshot.transactions.first?.amount, Money(minorUnits: 300_000))
        XCTAssertEqual(snapshot.recurringTransactionIDs, ["txn-1"])
    }

    func testRepositoryFetchSnapshotIncludesAllAccountsAndTransactionsRegardlessOfPlotEligibility() throws {
        let repository = try makeRepository()
        try repository.ensureUser(id: "user-1")
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-1",
                userID: "user-1",
                plaidItemID: "plaid-item-1",
                institutionID: nil,
                accessTokenRef: "vault://token/item-1",
                transactionsCursor: nil
            )
        )

        let accounts: [StoredAccount] = [
            StoredAccount(
                id: "checking",
                userID: "user-1",
                itemID: "item-1",
                plaidAccountID: "checking",
                name: "Checking",
                officialName: nil,
                kind: .checking,
                plaidType: "depository",
                plaidSubtype: "checking",
                mask: nil,
                currencyCode: "USD",
                currentBalanceMinorUnits: 100_000,
                availableBalanceMinorUnits: nil
            ),
            StoredAccount(
                id: "investment",
                userID: "user-1",
                itemID: "item-1",
                plaidAccountID: "investment",
                name: "Investment",
                officialName: nil,
                kind: .investment,
                plaidType: "investment",
                plaidSubtype: "brokerage",
                mask: nil,
                currencyCode: "USD",
                currentBalanceMinorUnits: 900_000,
                availableBalanceMinorUnits: nil
            ),
            StoredAccount(
                id: "loan",
                userID: "user-1",
                itemID: "item-1",
                plaidAccountID: "loan",
                name: "Loan",
                officialName: nil,
                kind: .loan,
                plaidType: "loan",
                plaidSubtype: "student",
                mask: nil,
                currencyCode: "USD",
                currentBalanceMinorUnits: 1_500_000,
                availableBalanceMinorUnits: nil
            )
        ]
        for account in accounts {
            try repository.upsertAccount(account)
        }

        try repository.upsertTransaction(
            StoredTransaction(
                id: "txn-checking",
                userID: "user-1",
                itemID: "item-1",
                accountID: "checking",
                plaidTransactionID: "txn-checking",
                pendingTransactionID: nil,
                merchantName: "Market",
                originalName: nil,
                postedDate: DateCoding.day(from: "2026-06-01")!,
                authorizedDate: nil,
                amountMinorUnits: -4_200,
                currencyCode: "USD",
                paymentChannel: nil,
                personalFinanceCategoryPrimary: nil,
                personalFinanceCategoryDetailed: nil,
                isPending: false
            )
        )
        try repository.upsertTransaction(
            StoredTransaction(
                id: "txn-investment",
                userID: "user-1",
                itemID: "item-1",
                accountID: "investment",
                plaidTransactionID: "txn-investment",
                pendingTransactionID: nil,
                merchantName: "Dividend",
                originalName: nil,
                postedDate: DateCoding.day(from: "2026-06-02")!,
                authorizedDate: nil,
                amountMinorUnits: 2_500,
                currencyCode: "USD",
                paymentChannel: nil,
                personalFinanceCategoryPrimary: nil,
                personalFinanceCategoryDetailed: nil,
                isPending: true
            )
        )

        let snapshot = try repository.fetchSnapshot(userID: "user-1")

        XCTAssertEqual(snapshot.accounts.map(\.id).sorted(), ["checking", "investment", "loan"])
        XCTAssertEqual(snapshot.transactions.map(\.id).sorted(), ["txn-checking", "txn-investment"])
        XCTAssertEqual(snapshot.transactions.first { $0.id == "txn-investment" }?.accountID, "investment")
    }

    func testRepositoryListsPlaidItemsAndRecordsWebhookEvents() throws {
        let repository = try makeRepository()
        try repository.ensureUser(id: "user-1")
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-1",
                userID: "user-1",
                plaidItemID: "plaid-item-1",
                institutionID: nil,
                accessTokenRef: "vault://token/item-1",
                transactionsCursor: "cursor-1"
            )
        )
        try repository.recordWebhookEvent(
            PlaidWebhookEventRecord(
                id: "webhook-1",
                plaidItemID: "plaid-item-1",
                webhookType: "TRANSACTIONS",
                webhookCode: "SYNC_UPDATES_AVAILABLE",
                receivedAt: Date(),
                payloadJSON: #"{"webhook_code":"SYNC_UPDATES_AVAILABLE"}"#
            )
        )
        try repository.markWebhookProcessed(id: "webhook-1")
        let syncEventID = try repository.recordSyncStarted(itemID: "item-1")
        try repository.finishSyncEvent(
            id: syncEventID,
            status: "succeeded",
            addedCount: 2,
            modifiedCount: 1,
            removedCount: 0
        )

        let items = try repository.plaidItems(userID: "user-1")
        let syncEvent = try XCTUnwrap(repository.latestSyncEvent(itemID: "item-1"))

        XCTAssertEqual(items.map(\.id), ["item-1"])
        XCTAssertEqual(items.first?.transactionsCursor, "cursor-1")
        XCTAssertEqual(try repository.plaidItemCount(userID: "user-1"), 1)
        XCTAssertTrue(try repository.isWebhookProcessed(id: "webhook-1"))
        XCTAssertEqual(syncEvent.id, syncEventID)
        XCTAssertEqual(syncEvent.status, "succeeded")
        XCTAssertEqual(syncEvent.addedCount, 2)
        XCTAssertEqual(syncEvent.modifiedCount, 1)
    }

    func testRepositoryIdentifiesPlaidItemsThatNeedFreshnessSync() throws {
        let repository = try makeRepository()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try repository.ensureUser(id: "user-1")
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "old-item",
                userID: "user-1",
                plaidItemID: "plaid-old",
                institutionID: nil,
                accessTokenRef: "vault://token/old",
                transactionsCursor: "cursor-old",
                lastSuccessfulSyncAt: now.addingTimeInterval(-600)
            )
        )
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "fresh-item",
                userID: "user-1",
                plaidItemID: "plaid-fresh",
                institutionID: nil,
                accessTokenRef: "vault://token/fresh",
                transactionsCursor: "cursor-fresh",
                lastSuccessfulSyncAt: now.addingTimeInterval(-60)
            )
        )
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "never-synced-item",
                userID: "user-1",
                plaidItemID: "plaid-never",
                institutionID: nil,
                accessTokenRef: "vault://token/never",
                transactionsCursor: nil
            )
        )
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "reauth-item",
                userID: "user-1",
                plaidItemID: "plaid-reauth",
                institutionID: nil,
                accessTokenRef: "vault://token/reauth",
                transactionsCursor: nil,
                needsReauth: true
            )
        )

        let staleItemIDs = try repository
            .plaidItemsNeedingSync(userID: "user-1", maxAge: 300, asOf: now)
            .map(\.id)

        XCTAssertEqual(staleItemIDs, ["old-item", "never-synced-item"])
        XCTAssertNil(try repository.snapshotLastSuccessfulSyncAt(userID: "user-1"))
    }

    func testRepositoryReportsOldestSuccessfulSyncAsSnapshotFreshness() throws {
        let repository = try makeRepository()
        let newestSync = Date(timeIntervalSince1970: 1_800_000_000)
        let oldestSync = newestSync.addingTimeInterval(-120)
        try repository.ensureUser(id: "user-1")
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-1",
                userID: "user-1",
                plaidItemID: "plaid-item-1",
                institutionID: nil,
                accessTokenRef: "vault://token/item-1",
                transactionsCursor: "cursor-1",
                lastSuccessfulSyncAt: newestSync
            )
        )
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-2",
                userID: "user-1",
                plaidItemID: "plaid-item-2",
                institutionID: nil,
                accessTokenRef: "vault://token/item-2",
                transactionsCursor: "cursor-2",
                lastSuccessfulSyncAt: oldestSync
            )
        )

        XCTAssertEqual(try repository.snapshotLastSuccessfulSyncAt(userID: "user-1"), oldestSync)
        XCTAssertEqual(try repository.fetchSnapshot(userID: "user-1").lastSuccessfulSyncAt, oldestSync)
    }

    func testSetCategoryPersistsAndRoundTripsThroughSnapshot() throws {
        let repository = try makeRepository()
        try repository.ensureUser(id: "user-1")
        try repository.upsertPlaidItem(
            PlaidItemRecord(
                id: "item-1",
                userID: "user-1",
                plaidItemID: "plaid-item-1",
                institutionID: nil,
                accessTokenRef: "vault://token/item-1",
                transactionsCursor: nil
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
                id: "txn-1",
                userID: "user-1",
                itemID: "item-1",
                accountID: "account-1",
                plaidTransactionID: "txn-1",
                pendingTransactionID: nil,
                merchantName: "City Power",
                originalName: nil,
                postedDate: DateCoding.day(from: "2026-06-01")!,
                authorizedDate: nil,
                amountMinorUnits: -12_000,
                currencyCode: "USD",
                paymentChannel: nil,
                personalFinanceCategoryPrimary: nil,
                personalFinanceCategoryDetailed: nil,
                isPending: false
            )
        )
        try repository.upsertBudgetCategory(id: "cat-utilities", userID: "user-1", name: "Utilities")

        try repository.setCategory(transactionID: "txn-1", categoryID: "cat-utilities", userID: "user-1")
        var snapshot = try repository.fetchSnapshot(userID: "user-1")
        XCTAssertEqual(snapshot.transactions.first?.categoryID, "cat-utilities")

        try repository.setCategory(transactionID: "txn-1", categoryID: nil, userID: "user-1")
        snapshot = try repository.fetchSnapshot(userID: "user-1")
        XCTAssertNil(snapshot.transactions.first?.categoryID)
    }

    private func makeRepository() throws -> BudgetRepository {
        let database = try SQLiteDatabase(path: ":memory:")
        let repository = BudgetRepository(database: database)
        try repository.migrate()
        return repository
    }
}
