import BudgetCore
import BudgetPersistence
import BudgetPlaid
import Foundation

public actor SecureLocalFinancialDataProvider: FinancialDataProvider {
    public nonisolated var storesAccountOverrides: Bool { true }

    private let store: SecureLocalStore
    private let relayClient: PlaidRelayClient
    private let tokenVault: SecurePlaidTokenVault
    private let allowsBackgroundSync: Bool
    private let clock: @Sendable () -> Date
    private var isDeleted = false

    public init(
        store: SecureLocalStore,
        relayClient: PlaidRelayClient,
        tokenVault: SecurePlaidTokenVault,
        allowsBackgroundSync: Bool = true,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.relayClient = relayClient
        self.tokenVault = tokenVault
        self.allowsBackgroundSync = allowsBackgroundSync
        self.clock = clock
    }

    public func fetchBudgetSnapshot() async throws -> BudgetSnapshot {
        try ensureStoreIsOpen()
        return try store.repository.fetchSnapshot(userID: store.configuration.userID)
    }

    public func fetchBudgetSnapshot(freshnessPolicy: BudgetSnapshotFreshnessPolicy) async throws -> BudgetSnapshot {
        try ensureStoreIsOpen()

        let userID = store.configuration.userID
        let itemIDs: [String]
        switch freshnessPolicy {
        case .cached:
            itemIDs = []
        case .syncIfStale(let maxAge):
            if allowsBackgroundSync {
                itemIDs = try store.repository
                    .plaidItemsNeedingSync(userID: userID, maxAge: maxAge, asOf: clock())
                    .map(\.id)
            } else {
                itemIDs = []
            }
        case .forceSync:
            itemIDs = try store.repository.plaidItems(userID: userID).map(\.id)
        }

        for itemID in itemIDs {
            _ = try await syncItem(id: itemID)
        }

        return try store.repository.fetchSnapshot(userID: userID)
    }

    public func createPlaidLinkToken() async throws -> String {
        try ensureStoreIsOpen()
        return try await relayClient.createLinkToken(clientUserID: store.configuration.userID)
    }

    public func exchangePlaidPublicToken(_ publicToken: String, institutionID: String?) async throws -> BudgetSnapshot {
        try ensureStoreIsOpen()

        let userID = store.configuration.userID
        let exchange = try await relayClient.exchangePublicToken(publicToken, institutionID: institutionID)
        let tokenRef = try tokenVault.storeAccessToken(
            exchange.accessToken,
            userID: userID,
            plaidItemID: exchange.plaidItemID
        )

        if let institutionID {
            try store.repository.upsertInstitution(id: institutionID, name: institutionID)
        }

        try store.repository.upsertPlaidItem(
            PlaidItemRecord(
                id: exchange.itemID,
                userID: userID,
                plaidItemID: exchange.plaidItemID,
                institutionID: institutionID,
                accessTokenRef: tokenRef,
                transactionsCursor: nil
            )
        )

        return try await syncItem(id: exchange.itemID)
    }

    public func createSandboxPlaidItem(institutionID: String?) async throws -> BudgetSnapshot {
        throw SecureLocalFinancialDataProviderError.sandboxCreationRequiresDevelopmentBackend
    }

    public func setRegularMonthly(transactionID: BudgetTransaction.ID, isRegularMonthly: Bool) async throws -> BudgetSnapshot {
        try ensureStoreIsOpen()
        try store.repository.setRegularMonthly(
            transactionID: transactionID,
            isRegularMonthly: isRegularMonthly,
            userID: store.configuration.userID
        )
        return try store.repository.fetchSnapshot(userID: store.configuration.userID)
    }

    public func setCategory(transactionID: BudgetTransaction.ID, categoryID: BudgetCategory.ID?) async throws -> BudgetSnapshot {
        try ensureStoreIsOpen()
        try store.repository.setCategory(
            transactionID: transactionID,
            categoryID: categoryID,
            userID: store.configuration.userID
        )
        return try store.repository.fetchSnapshot(userID: store.configuration.userID)
    }

    public func saveAssignmentRule(
        _ rule: BudgetAssignmentRule,
        applyToExisting: Bool
    ) async throws -> BudgetSnapshot {
        try ensureStoreIsOpen()
        let userID = store.configuration.userID
        try store.repository.upsertAssignmentRule(rule, userID: userID)

        if applyToExisting {
            try store.repository.applyAssignmentRules(userID: userID, ruleIDs: [rule.id])
        }

        return try store.repository.fetchSnapshot(userID: userID)
    }

    public func deleteAssignmentRule(id: BudgetAssignmentRule.ID) async throws -> BudgetSnapshot {
        try ensureStoreIsOpen()
        let userID = store.configuration.userID
        try store.repository.deleteAssignmentRule(id: id, userID: userID)
        return try store.repository.fetchSnapshot(userID: userID)
    }

    public func setAccountOverride(accountID: FinancialAccount.ID, override: AccountOverride?) async throws -> BudgetSnapshot {
        try ensureStoreIsOpen()
        try store.repository.setAccountOverride(
            accountID: accountID,
            override: override,
            userID: store.configuration.userID
        )
        return try store.repository.fetchSnapshot(userID: store.configuration.userID)
    }

    public func saveCategory(_ category: BudgetCategory) async throws -> BudgetSnapshot {
        try ensureStoreIsOpen()
        try store.repository.upsertBudgetCategory(
            id: category.id,
            userID: store.configuration.userID,
            name: category.name,
            monthlyLimitMinorUnits: category.monthlyLimit?.minorUnits,
            currencyCode: category.monthlyLimit?.currencyCode ?? "USD"
        )
        return try store.repository.fetchSnapshot(userID: store.configuration.userID)
    }

    public func deleteCategory(id: BudgetCategory.ID) async throws -> BudgetSnapshot {
        try ensureStoreIsOpen()
        try store.repository.deleteBudgetCategory(id: id, userID: store.configuration.userID)
        return try store.repository.fetchSnapshot(userID: store.configuration.userID)
    }

    public func deleteLocalData() async throws {
        try ensureStoreIsOpen()

        let items = try store.repository.plaidItems(userID: store.configuration.userID)
        for item in items {
            if let accessToken = try? tokenVault.accessToken(for: item.accessTokenRef) {
                try? await relayClient.removeItem(accessToken: accessToken)
            }
        }

        try tokenVault.deleteAllTokens()
        try store.deleteDatabaseFiles()
        isDeleted = true
    }

    private func syncItem(id itemID: String) async throws -> BudgetSnapshot {
        guard let item = try store.repository.plaidItem(id: itemID) else {
            throw SecureLocalFinancialDataProviderError.itemNotFound(itemID)
        }

        let syncEventID = try store.repository.recordSyncStarted(itemID: item.id, startedAt: clock())
        var addedCount = 0
        var modifiedCount = 0
        var removedCount = 0

        do {
            let accessToken = try tokenVault.accessToken(for: item.accessTokenRef)
            let accountResponse = try await relayClient.getAccounts(accessToken: accessToken)
            for account in accountResponse.accounts {
                try store.repository.upsertAccount(account.storedAccount(userID: item.userID, itemID: item.id))
            }

            let response = try await relayClient.syncTransactions(
                accessToken: accessToken,
                cursor: item.transactionsCursor
            )

            for account in response.accounts {
                try store.repository.upsertAccount(account.storedAccount(userID: item.userID, itemID: item.id))
            }

            for transaction in response.added + response.modified {
                try store.repository.upsertTransaction(transaction.storedTransaction(userID: item.userID, itemID: item.id))
            }

            for removed in response.removed {
                try store.repository.markTransactionRemoved(plaidTransactionID: removed.transactionID, at: clock())
            }

            addedCount = response.added.count
            modifiedCount = response.modified.count
            removedCount = response.removed.count

            let finishedAt = clock()
            try store.repository.applyAutomaticCategoryAssignments(userID: item.userID)
            try store.repository.updateTransactionsCursor(
                itemID: item.id,
                cursor: response.nextCursor,
                syncedAt: finishedAt
            )
            try store.repository.finishSyncEvent(
                id: syncEventID,
                status: "succeeded",
                addedCount: addedCount,
                modifiedCount: modifiedCount,
                removedCount: removedCount,
                finishedAt: finishedAt
            )

            return try store.repository.fetchSnapshot(userID: item.userID)
        } catch {
            try? store.repository.finishSyncEvent(
                id: syncEventID,
                status: "failed",
                addedCount: addedCount,
                modifiedCount: modifiedCount,
                removedCount: removedCount,
                errorMessage: String(error.localizedDescription.prefix(500)),
                finishedAt: clock()
            )
            throw error
        }
    }

    private func ensureStoreIsOpen() throws {
        if isDeleted {
            throw SecureLocalStoreError.databaseReopenRequiredAfterDeletion
        }
    }
}

public enum SecureLocalFinancialDataProviderError: Error, LocalizedError, Sendable {
    case sandboxCreationRequiresDevelopmentBackend
    case itemNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .sandboxCreationRequiresDevelopmentBackend:
            return "Sandbox Item creation is only available through the development backend."
        case .itemNotFound(let itemID):
            return "No local Plaid item exists with id \(itemID)."
        }
    }
}
