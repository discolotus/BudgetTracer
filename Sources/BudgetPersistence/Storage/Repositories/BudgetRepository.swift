import BudgetCore
import Foundation

public final class BudgetRepository {
    private let database: SQLiteDatabase
    private let clock: () -> Date

    public init(database: SQLiteDatabase, clock: @escaping () -> Date = Date.init) {
        self.database = database
        self.clock = clock
    }

    public func migrate() throws {
        try database.execute(DatabaseSchema.sql)
        try addColumnIfMissing(table: "transactions", column: "occurred_at", definition: "TEXT")
    }

    public func ensureUser(id: String) throws {
        try database.run(
            """
            INSERT OR IGNORE INTO users(id, created_at)
            VALUES (?, ?)
            """,
            bindings: [.text(id), .text(nowString())]
        )
        try seedDefaultCategoriesIfEmpty(userID: id)
    }

    /// Seeds the default category set the first time a user has none. Idempotent.
    public func seedDefaultCategoriesIfEmpty(userID: String) throws {
        let existing = try database.query(
            "SELECT COUNT(*) AS count FROM budget_categories WHERE user_id = ?",
            bindings: [.text(userID)]
        ).first?["count"]?.int64 ?? 0

        guard existing == 0 else {
            return
        }

        for category in BudgetCategory.defaultSeed {
            try upsertBudgetCategory(id: category.id, userID: userID, name: category.name)
        }
    }

    public func deleteBudgetCategory(id: String, userID: String) throws {
        try database.run(
            "DELETE FROM budget_categories WHERE id = ? AND user_id = ?",
            bindings: [.text(id), .text(userID)]
        )
    }

    public func upsertInstitution(id: String, name: String) throws {
        let now = nowString()
        try database.run(
            """
            INSERT INTO institutions(id, name, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              updated_at = excluded.updated_at
            """,
            bindings: [.text(id), .text(name), .text(now), .text(now)]
        )
    }

    public func upsertPlaidItem(_ item: PlaidItemRecord) throws {
        let now = nowString()
        try database.run(
            """
            INSERT INTO plaid_items(
              id, user_id, plaid_item_id, institution_id, access_token_ref,
              transactions_cursor, status, needs_reauth, last_successful_sync_at,
              created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              plaid_item_id = excluded.plaid_item_id,
              institution_id = excluded.institution_id,
              access_token_ref = excluded.access_token_ref,
              transactions_cursor = excluded.transactions_cursor,
              status = excluded.status,
              needs_reauth = excluded.needs_reauth,
              last_successful_sync_at = excluded.last_successful_sync_at,
              updated_at = excluded.updated_at
            """,
            bindings: [
                .text(item.id),
                .text(item.userID),
                .text(item.plaidItemID),
                item.institutionID.map(SQLiteValue.text) ?? .null,
                .text(item.accessTokenRef),
                item.transactionsCursor.map(SQLiteValue.text) ?? .null,
                .text(item.status),
                .bool(item.needsReauth),
                item.lastSuccessfulSyncAt.map { .text(DateCoding.string(from: $0)) } ?? .null,
                .text(now),
                .text(now)
            ]
        )
    }

    public func plaidItem(id: String) throws -> PlaidItemRecord? {
        let rows = try database.query(
            """
            SELECT id, user_id, plaid_item_id, institution_id, access_token_ref,
                   transactions_cursor, status, needs_reauth, last_successful_sync_at
            FROM plaid_items
            WHERE id = ?
            LIMIT 1
            """,
            bindings: [.text(id)]
        )

        return try rows.first.map(PlaidItemRecord.init(row:))
    }

    public func plaidItem(plaidItemID: String) throws -> PlaidItemRecord? {
        let rows = try database.query(
            """
            SELECT id, user_id, plaid_item_id, institution_id, access_token_ref,
                   transactions_cursor, status, needs_reauth, last_successful_sync_at
            FROM plaid_items
            WHERE plaid_item_id = ?
            LIMIT 1
            """,
            bindings: [.text(plaidItemID)]
        )

        return try rows.first.map(PlaidItemRecord.init(row:))
    }

    public func plaidItems(userID: String) throws -> [PlaidItemRecord] {
        try database.query(
            """
            SELECT id, user_id, plaid_item_id, institution_id, access_token_ref,
                   transactions_cursor, status, needs_reauth, last_successful_sync_at
            FROM plaid_items
            WHERE user_id = ?
            ORDER BY created_at
            """,
            bindings: [.text(userID)]
        ).map(PlaidItemRecord.init(row:))
    }

    public func plaidItemCount(userID: String) throws -> Int {
        let rows = try database.query(
            """
            SELECT COUNT(*) AS count
            FROM plaid_items
            WHERE user_id = ?
            """,
            bindings: [.text(userID)]
        )

        return Int(rows.first?["count"]?.int64 ?? 0)
    }

    public func plaidItemsNeedingSync(userID: String, maxAge: TimeInterval, asOf date: Date) throws -> [PlaidItemRecord] {
        try plaidItems(userID: userID).filter { item in
            guard !item.needsReauth else {
                return false
            }

            guard let lastSuccessfulSyncAt = item.lastSuccessfulSyncAt else {
                return true
            }

            return date.timeIntervalSince(lastSuccessfulSyncAt) >= maxAge
        }
    }

    public func snapshotLastSuccessfulSyncAt(userID: String) throws -> Date? {
        let items = try plaidItems(userID: userID)
        guard !items.isEmpty else {
            return nil
        }

        let syncDates = items.compactMap(\.lastSuccessfulSyncAt)
        guard syncDates.count == items.count else {
            return nil
        }

        return syncDates.min()
    }

    public func updateTransactionsCursor(itemID: String, cursor: String, syncedAt: Date) throws {
        try database.run(
            """
            UPDATE plaid_items
            SET transactions_cursor = ?, last_successful_sync_at = ?, status = 'connected', updated_at = ?
            WHERE id = ?
            """,
            bindings: [
                .text(cursor),
                .text(DateCoding.string(from: syncedAt)),
                .text(nowString()),
                .text(itemID)
            ]
        )
    }

    public func upsertAccount(_ account: StoredAccount) throws {
        let now = nowString()
        try database.run(
            """
            INSERT INTO accounts(
              id, user_id, item_id, plaid_account_id, name, official_name, kind,
              plaid_type, plaid_subtype, mask, iso_currency_code,
              current_balance_minor_units, available_balance_minor_units,
              created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(plaid_account_id) DO UPDATE SET
              name = excluded.name,
              official_name = excluded.official_name,
              kind = excluded.kind,
              plaid_type = excluded.plaid_type,
              plaid_subtype = excluded.plaid_subtype,
              mask = excluded.mask,
              iso_currency_code = excluded.iso_currency_code,
              current_balance_minor_units = excluded.current_balance_minor_units,
              available_balance_minor_units = excluded.available_balance_minor_units,
              updated_at = excluded.updated_at
            """,
            bindings: [
                .text(account.id),
                .text(account.userID),
                .text(account.itemID),
                .text(account.plaidAccountID),
                .text(account.name),
                account.officialName.map(SQLiteValue.text) ?? .null,
                .text(account.kind.rawValue),
                account.plaidType.map(SQLiteValue.text) ?? .null,
                account.plaidSubtype.map(SQLiteValue.text) ?? .null,
                account.mask.map(SQLiteValue.text) ?? .null,
                .text(account.currencyCode),
                .integer(account.currentBalanceMinorUnits),
                account.availableBalanceMinorUnits.map(SQLiteValue.integer) ?? .null,
                .text(now),
                .text(now)
            ]
        )
    }

    public func upsertTransaction(_ transaction: StoredTransaction) throws {
        let now = nowString()
        try database.run(
            """
            INSERT INTO transactions(
              id, user_id, item_id, account_id, plaid_transaction_id, pending_transaction_id,
              merchant_name, original_name, posted_date, occurred_at, authorized_date,
              amount_minor_units, iso_currency_code, payment_channel,
              personal_finance_category_primary, personal_finance_category_detailed,
              is_pending, removed_at, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
            ON CONFLICT(plaid_transaction_id) DO UPDATE SET
              account_id = excluded.account_id,
              pending_transaction_id = excluded.pending_transaction_id,
              merchant_name = excluded.merchant_name,
              original_name = excluded.original_name,
              posted_date = excluded.posted_date,
              occurred_at = excluded.occurred_at,
              authorized_date = excluded.authorized_date,
              amount_minor_units = excluded.amount_minor_units,
              iso_currency_code = excluded.iso_currency_code,
              payment_channel = excluded.payment_channel,
              personal_finance_category_primary = excluded.personal_finance_category_primary,
              personal_finance_category_detailed = excluded.personal_finance_category_detailed,
              is_pending = excluded.is_pending,
              removed_at = NULL,
              updated_at = excluded.updated_at
            """,
            bindings: [
                .text(transaction.id),
                .text(transaction.userID),
                .text(transaction.itemID),
                .text(transaction.accountID),
                .text(transaction.plaidTransactionID),
                transaction.pendingTransactionID.map(SQLiteValue.text) ?? .null,
                .text(transaction.merchantName),
                transaction.originalName.map(SQLiteValue.text) ?? .null,
                .text(DateCoding.dayString(from: transaction.postedDate)),
                .text(DateCoding.string(from: transaction.occurredAt)),
                transaction.authorizedDate.map { .text(DateCoding.dayString(from: $0)) } ?? .null,
                .integer(transaction.amountMinorUnits),
                .text(transaction.currencyCode),
                transaction.paymentChannel.map(SQLiteValue.text) ?? .null,
                transaction.personalFinanceCategoryPrimary.map(SQLiteValue.text) ?? .null,
                transaction.personalFinanceCategoryDetailed.map(SQLiteValue.text) ?? .null,
                .bool(transaction.isPending),
                .text(now),
                .text(now)
            ]
        )

        try database.run(
            """
            INSERT OR IGNORE INTO transaction_annotations(transaction_id, user_id, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            """,
            bindings: [.text(transaction.id), .text(transaction.userID), .text(now), .text(now)]
        )
    }

    public func markTransactionRemoved(plaidTransactionID: String, at date: Date = Date()) throws {
        try database.run(
            """
            UPDATE transactions
            SET removed_at = ?, updated_at = ?
            WHERE plaid_transaction_id = ?
            """,
            bindings: [
                .text(DateCoding.string(from: date)),
                .text(nowString()),
                .text(plaidTransactionID)
            ]
        )
    }

    public func setRegularMonthly(transactionID: String, isRegularMonthly: Bool, userID: String) throws {
        let now = nowString()
        try database.run(
            """
            INSERT INTO transaction_annotations(transaction_id, user_id, is_regular_monthly, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(transaction_id) DO UPDATE SET
              is_regular_monthly = excluded.is_regular_monthly,
              updated_at = excluded.updated_at
            """,
            bindings: [.text(transactionID), .text(userID), .bool(isRegularMonthly), .text(now), .text(now)]
        )
    }

    public func upsertBudgetCategory(
        id: String,
        userID: String,
        name: String,
        monthlyLimitMinorUnits: Int64? = nil,
        currencyCode: String = "USD"
    ) throws {
        let now = nowString()
        try database.run(
            """
            INSERT INTO budget_categories(id, user_id, name, monthly_limit_minor_units, iso_currency_code, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              monthly_limit_minor_units = excluded.monthly_limit_minor_units,
              iso_currency_code = excluded.iso_currency_code,
              updated_at = excluded.updated_at
            """,
            bindings: [
                .text(id),
                .text(userID),
                .text(name),
                monthlyLimitMinorUnits.map(SQLiteValue.integer) ?? .null,
                .text(currencyCode),
                .text(now),
                .text(now)
            ]
        )
    }

    public func setCategory(transactionID: String, categoryID: String?, userID: String) throws {
        let now = nowString()
        try database.run(
            """
            INSERT INTO transaction_annotations(transaction_id, user_id, category_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(transaction_id) DO UPDATE SET
              category_id = excluded.category_id,
              updated_at = excluded.updated_at
            """,
            bindings: [
                .text(transactionID),
                .text(userID),
                categoryID.map(SQLiteValue.text) ?? .null,
                .text(now),
                .text(now)
            ]
        )
    }

    public func recordWebhookEvent(_ event: PlaidWebhookEventRecord) throws {
        try database.run(
            """
            INSERT OR IGNORE INTO plaid_webhook_events(
              id, plaid_item_id, webhook_type, webhook_code, received_at, payload_json
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(event.id),
                event.plaidItemID.map(SQLiteValue.text) ?? .null,
                .text(event.webhookType),
                .text(event.webhookCode),
                .text(DateCoding.string(from: event.receivedAt)),
                .text(event.payloadJSON)
            ]
        )
    }

    public func markWebhookProcessed(id: String, processedAt: Date = Date()) throws {
        try database.run(
            """
            UPDATE plaid_webhook_events
            SET processed_at = ?
            WHERE id = ?
            """,
            bindings: [.text(DateCoding.string(from: processedAt)), .text(id)]
        )
    }

    public func isWebhookProcessed(id: String) throws -> Bool {
        let rows = try database.query(
            """
            SELECT processed_at
            FROM plaid_webhook_events
            WHERE id = ?
            LIMIT 1
            """,
            bindings: [.text(id)]
        )

        guard let processedAt = rows.first?["processed_at"] else {
            return false
        }

        return processedAt.string != nil
    }

    public func recordSyncStarted(itemID: String, startedAt: Date = Date()) throws -> String {
        let id = UUID().uuidString
        try database.run(
            """
            INSERT INTO sync_events(id, item_id, started_at, status)
            VALUES (?, ?, ?, ?)
            """,
            bindings: [
                .text(id),
                .text(itemID),
                .text(DateCoding.string(from: startedAt)),
                .text("running")
            ]
        )
        return id
    }

    public func finishSyncEvent(
        id: String,
        status: String,
        addedCount: Int,
        modifiedCount: Int,
        removedCount: Int,
        errorMessage: String? = nil,
        finishedAt: Date = Date()
    ) throws {
        try database.run(
            """
            UPDATE sync_events
            SET finished_at = ?,
                status = ?,
                added_count = ?,
                modified_count = ?,
                removed_count = ?,
                error_message = ?
            WHERE id = ?
            """,
            bindings: [
                .text(DateCoding.string(from: finishedAt)),
                .text(status),
                .integer(Int64(addedCount)),
                .integer(Int64(modifiedCount)),
                .integer(Int64(removedCount)),
                errorMessage.map(SQLiteValue.text) ?? .null,
                .text(id)
            ]
        )
    }

    public func syncEvent(id: String) throws -> PlaidSyncEventRecord? {
        let rows = try database.query(
            """
            SELECT id, item_id, started_at, finished_at, status,
                   added_count, modified_count, removed_count, error_message
            FROM sync_events
            WHERE id = ?
            LIMIT 1
            """,
            bindings: [.text(id)]
        )

        return try rows.first.map(PlaidSyncEventRecord.init(row:))
    }

    public func latestSyncEvent(itemID: String) throws -> PlaidSyncEventRecord? {
        let rows = try database.query(
            """
            SELECT id, item_id, started_at, finished_at, status,
                   added_count, modified_count, removed_count, error_message
            FROM sync_events
            WHERE item_id = ?
            ORDER BY started_at DESC
            LIMIT 1
            """,
            bindings: [.text(itemID)]
        )

        return try rows.first.map(PlaidSyncEventRecord.init(row:))
    }

    public func fetchSnapshot(userID: String) throws -> BudgetSnapshot {
        let institutions = try database.query(
            """
            SELECT DISTINCT institutions.id, institutions.name
            FROM institutions
            JOIN plaid_items ON plaid_items.institution_id = institutions.id
            WHERE plaid_items.user_id = ?
            ORDER BY institutions.name
            """,
            bindings: [.text(userID)]
        ).map { row in
            Institution(id: try requiredString("id", row), name: try requiredString("name", row))
        }

        let accounts = try database.query(
            """
            SELECT plaid_account_id, institution_id, accounts.name, kind,
                   plaid_type, plaid_subtype, current_balance_minor_units, iso_currency_code
            FROM accounts
            JOIN plaid_items ON plaid_items.id = accounts.item_id
            WHERE accounts.user_id = ?
            ORDER BY accounts.name
            """,
            bindings: [.text(userID)]
        ).map { row in
            FinancialAccount(
                id: try requiredString("plaid_account_id", row),
                institutionID: row["institution_id"]?.string ?? "",
                name: try requiredString("name", row),
                kind: AccountKind(rawValue: try requiredString("kind", row)) ?? .other,
                plaidType: row["plaid_type"]?.string,
                plaidSubtype: row["plaid_subtype"]?.string,
                currentBalance: Money(
                    minorUnits: try requiredInt64("current_balance_minor_units", row),
                    currencyCode: row["iso_currency_code"]?.string ?? "USD"
                )
            )
        }

        let categories = try database.query(
            """
            SELECT id, name, monthly_limit_minor_units, iso_currency_code
            FROM budget_categories
            WHERE user_id = ?
            ORDER BY name
            """,
            bindings: [.text(userID)]
        ).map { row in
            BudgetCategory(
                id: try requiredString("id", row),
                name: try requiredString("name", row),
                monthlyLimit: row["monthly_limit_minor_units"]?.int64.map {
                    Money(minorUnits: $0, currencyCode: row["iso_currency_code"]?.string ?? "USD")
                }
            )
        }

        let transactions = try database.query(
            """
            SELECT transactions.plaid_transaction_id, transactions.account_id,
                   transaction_annotations.category_id, posted_date, occurred_at, merchant_name,
                   amount_minor_units, iso_currency_code
            FROM transactions
            LEFT JOIN transaction_annotations ON transaction_annotations.transaction_id = transactions.id
            WHERE transactions.user_id = ? AND removed_at IS NULL
            ORDER BY posted_date DESC
            """,
            bindings: [.text(userID)]
        ).map { row in
            BudgetTransaction(
                id: try requiredString("plaid_transaction_id", row),
                accountID: try requiredString("account_id", row),
                categoryID: row["category_id"]?.string,
                postedAt: DateCoding.day(from: try requiredString("posted_date", row)) ?? Date(timeIntervalSince1970: 0),
                occurredAt: row["occurred_at"]?.string.flatMap { DateCoding.date(from: $0) },
                merchantName: try requiredString("merchant_name", row),
                amount: Money(
                    minorUnits: try requiredInt64("amount_minor_units", row),
                    currencyCode: row["iso_currency_code"]?.string ?? "USD"
                )
            )
        }

        let recurringIDs = try Set(database.query(
            """
            SELECT transactions.plaid_transaction_id
            FROM transaction_annotations
            JOIN transactions ON transactions.id = transaction_annotations.transaction_id
            WHERE transaction_annotations.user_id = ?
              AND transaction_annotations.is_regular_monthly = 1
              AND transactions.removed_at IS NULL
            """,
            bindings: [.text(userID)]
        ).map { try requiredString("plaid_transaction_id", $0) })

        return BudgetSnapshot(
            institutions: institutions,
            accounts: accounts,
            categories: categories,
            transactions: transactions,
            recurringTransactionIDs: recurringIDs,
            lastSuccessfulSyncAt: try snapshotLastSuccessfulSyncAt(userID: userID)
        )
    }

    private func nowString() -> String {
        DateCoding.string(from: clock())
    }

    private func addColumnIfMissing(table: String, column: String, definition: String) throws {
        let columns = try database.query("PRAGMA table_info(\(table))")
            .compactMap { $0["name"]?.string }

        guard !columns.contains(column) else {
            return
        }

        try database.run("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }
}

public struct PlaidItemRecord: Hashable, Sendable {
    public var id: String
    public var userID: String
    public var plaidItemID: String
    public var institutionID: String?
    public var accessTokenRef: String
    public var transactionsCursor: String?
    public var status: String
    public var needsReauth: Bool
    public var lastSuccessfulSyncAt: Date?

    public init(
        id: String,
        userID: String,
        plaidItemID: String,
        institutionID: String?,
        accessTokenRef: String,
        transactionsCursor: String?,
        status: String = "connected",
        needsReauth: Bool = false,
        lastSuccessfulSyncAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.plaidItemID = plaidItemID
        self.institutionID = institutionID
        self.accessTokenRef = accessTokenRef
        self.transactionsCursor = transactionsCursor
        self.status = status
        self.needsReauth = needsReauth
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    }

    init(row: [String: SQLiteValue]) throws {
        self.init(
            id: try requiredString("id", row),
            userID: try requiredString("user_id", row),
            plaidItemID: try requiredString("plaid_item_id", row),
            institutionID: row["institution_id"]?.string,
            accessTokenRef: try requiredString("access_token_ref", row),
            transactionsCursor: row["transactions_cursor"]?.string,
            status: try requiredString("status", row),
            needsReauth: row["needs_reauth"]?.bool ?? false,
            lastSuccessfulSyncAt: row["last_successful_sync_at"]?.string.flatMap(DateCoding.date(from:))
        )
    }
}

public struct PlaidWebhookEventRecord: Hashable, Sendable {
    public var id: String
    public var plaidItemID: String?
    public var webhookType: String
    public var webhookCode: String
    public var receivedAt: Date
    public var payloadJSON: String

    public init(
        id: String,
        plaidItemID: String?,
        webhookType: String,
        webhookCode: String,
        receivedAt: Date,
        payloadJSON: String
    ) {
        self.id = id
        self.plaidItemID = plaidItemID
        self.webhookType = webhookType
        self.webhookCode = webhookCode
        self.receivedAt = receivedAt
        self.payloadJSON = payloadJSON
    }
}

public struct PlaidSyncEventRecord: Hashable, Sendable {
    public var id: String
    public var itemID: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var status: String
    public var addedCount: Int
    public var modifiedCount: Int
    public var removedCount: Int
    public var errorMessage: String?

    public init(
        id: String,
        itemID: String,
        startedAt: Date,
        finishedAt: Date?,
        status: String,
        addedCount: Int,
        modifiedCount: Int,
        removedCount: Int,
        errorMessage: String?
    ) {
        self.id = id
        self.itemID = itemID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.addedCount = addedCount
        self.modifiedCount = modifiedCount
        self.removedCount = removedCount
        self.errorMessage = errorMessage
    }

    init(row: [String: SQLiteValue]) throws {
        self.init(
            id: try requiredString("id", row),
            itemID: try requiredString("item_id", row),
            startedAt: row["started_at"]?.string.flatMap(DateCoding.date(from:)) ?? Date(timeIntervalSince1970: 0),
            finishedAt: row["finished_at"]?.string.flatMap(DateCoding.date(from:)),
            status: try requiredString("status", row),
            addedCount: Int(row["added_count"]?.int64 ?? 0),
            modifiedCount: Int(row["modified_count"]?.int64 ?? 0),
            removedCount: Int(row["removed_count"]?.int64 ?? 0),
            errorMessage: row["error_message"]?.string
        )
    }
}

public struct StoredAccount: Hashable, Sendable {
    public var id: String
    public var userID: String
    public var itemID: String
    public var plaidAccountID: String
    public var name: String
    public var officialName: String?
    public var kind: AccountKind
    public var plaidType: String?
    public var plaidSubtype: String?
    public var mask: String?
    public var currencyCode: String
    public var currentBalanceMinorUnits: Int64
    public var availableBalanceMinorUnits: Int64?

    public init(
        id: String,
        userID: String,
        itemID: String,
        plaidAccountID: String,
        name: String,
        officialName: String?,
        kind: AccountKind,
        plaidType: String?,
        plaidSubtype: String?,
        mask: String?,
        currencyCode: String,
        currentBalanceMinorUnits: Int64,
        availableBalanceMinorUnits: Int64?
    ) {
        self.id = id
        self.userID = userID
        self.itemID = itemID
        self.plaidAccountID = plaidAccountID
        self.name = name
        self.officialName = officialName
        self.kind = kind
        self.plaidType = plaidType
        self.plaidSubtype = plaidSubtype
        self.mask = mask
        self.currencyCode = currencyCode
        self.currentBalanceMinorUnits = currentBalanceMinorUnits
        self.availableBalanceMinorUnits = availableBalanceMinorUnits
    }
}

public struct StoredTransaction: Hashable, Sendable {
    public var id: String
    public var userID: String
    public var itemID: String
    public var accountID: String
    public var plaidTransactionID: String
    public var pendingTransactionID: String?
    public var merchantName: String
    public var originalName: String?
    public var postedDate: Date
    public var authorizedDate: Date?
    public var occurredAt: Date
    public var amountMinorUnits: Int64
    public var currencyCode: String
    public var paymentChannel: String?
    public var personalFinanceCategoryPrimary: String?
    public var personalFinanceCategoryDetailed: String?
    public var isPending: Bool

    public init(
        id: String,
        userID: String,
        itemID: String,
        accountID: String,
        plaidTransactionID: String,
        pendingTransactionID: String?,
        merchantName: String,
        originalName: String?,
        postedDate: Date,
        authorizedDate: Date?,
        occurredAt: Date? = nil,
        amountMinorUnits: Int64,
        currencyCode: String,
        paymentChannel: String?,
        personalFinanceCategoryPrimary: String?,
        personalFinanceCategoryDetailed: String?,
        isPending: Bool
    ) {
        self.id = id
        self.userID = userID
        self.itemID = itemID
        self.accountID = accountID
        self.plaidTransactionID = plaidTransactionID
        self.pendingTransactionID = pendingTransactionID
        self.merchantName = merchantName
        self.originalName = originalName
        self.postedDate = postedDate
        self.authorizedDate = authorizedDate
        self.occurredAt = occurredAt ?? postedDate
        self.amountMinorUnits = amountMinorUnits
        self.currencyCode = currencyCode
        self.paymentChannel = paymentChannel
        self.personalFinanceCategoryPrimary = personalFinanceCategoryPrimary
        self.personalFinanceCategoryDetailed = personalFinanceCategoryDetailed
        self.isPending = isPending
    }
}

public enum DateCoding {
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        dateFormatter.date(from: string) ?? dateFormatterWithoutFractionalSeconds.date(from: string)
    }

    public static func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    public static func day(from string: String) -> Date? {
        dayFormatter.date(from: string)
    }
}

private func requiredString(_ name: String, _ row: [String: SQLiteValue]) throws -> String {
    guard let value = row[name]?.string else {
        throw SQLiteError.missingColumn(name)
    }

    return value
}

private func requiredInt64(_ name: String, _ row: [String: SQLiteValue]) throws -> Int64 {
    guard let value = row[name]?.int64 else {
        throw SQLiteError.missingColumn(name)
    }

    return value
}
