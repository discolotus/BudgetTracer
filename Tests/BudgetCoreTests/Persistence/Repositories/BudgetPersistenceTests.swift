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

    private func makeRepository() throws -> BudgetRepository {
        let database = try SQLiteDatabase(path: ":memory:")
        let repository = BudgetRepository(database: database)
        try repository.migrate()
        return repository
    }
}
