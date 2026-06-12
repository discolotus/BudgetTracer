import BudgetCore
import BudgetPersistence
import Foundation

public final class PlaidSyncService {
    private let client: PlaidAPIClientProtocol
    private let repository: BudgetRepository
    private let tokenVault: PlaidTokenVault
    private let clock: () -> Date

    public init(
        client: PlaidAPIClientProtocol,
        repository: BudgetRepository,
        tokenVault: PlaidTokenVault,
        clock: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.repository = repository
        self.tokenVault = tokenVault
        self.clock = clock
    }

    public func createLinkToken(userID: String) async throws -> String {
        try await client.createLinkToken(userID: userID).linkToken
    }

    public func createSandboxItemAndSync(
        userID: String,
        institutionID: String = "ins_109508"
    ) async throws -> BudgetSnapshot {
        let publicToken = try await client.createSandboxPublicToken(
            institutionID: institutionID,
            products: ["transactions"]
        ).publicToken
        let item = try await exchangePublicToken(publicToken, userID: userID, institutionID: institutionID)
        return try await syncItem(id: item.id)
    }

    @discardableResult
    public func exchangePublicToken(_ publicToken: String, userID: String, institutionID: String? = nil) async throws -> PlaidItemRecord {
        try repository.ensureUser(id: userID)
        if let institutionID {
            try repository.upsertInstitution(id: institutionID, name: institutionID)
        }

        let exchange = try await client.exchangePublicToken(publicToken)
        let tokenRef = try tokenVault.storeAccessToken(exchange.accessToken, userID: userID, plaidItemID: exchange.itemID)
        let item = PlaidItemRecord(
            id: exchange.itemID,
            userID: userID,
            plaidItemID: exchange.itemID,
            institutionID: institutionID,
            accessTokenRef: tokenRef,
            transactionsCursor: nil
        )

        try repository.upsertPlaidItem(item)
        return item
    }

    public func syncItem(id itemID: String) async throws -> BudgetSnapshot {
        guard let item = try repository.plaidItem(id: itemID) else {
            throw PlaidSyncError.itemNotFound(itemID)
        }

        let syncEventID = try repository.recordSyncStarted(itemID: item.id, startedAt: clock())
        var addedCount = 0
        var modifiedCount = 0
        var removedCount = 0

        do {
            let accessToken = try tokenVault.accessToken(for: item.accessTokenRef)
            let accountResponse = try await client.getAccounts(accessToken: accessToken)
            for account in accountResponse.accounts {
                try repository.upsertAccount(account.storedAccount(userID: item.userID, itemID: item.id))
            }

            var nextCursor = item.transactionsCursor
            var hasMore = true

            while hasMore {
                let response = try await client.syncTransactions(accessToken: accessToken, cursor: nextCursor)

                for account in response.accounts {
                    try repository.upsertAccount(account.storedAccount(userID: item.userID, itemID: item.id))
                }

                for transaction in response.added + response.modified {
                    try repository.upsertTransaction(transaction.storedTransaction(userID: item.userID, itemID: item.id))
                }

                for removed in response.removed {
                    try repository.markTransactionRemoved(plaidTransactionID: removed.transactionID, at: clock())
                }

                addedCount += response.added.count
                modifiedCount += response.modified.count
                removedCount += response.removed.count
                nextCursor = response.nextCursor
                hasMore = response.hasMore
            }

            let finishedAt = clock()
            guard let finalCursor = nextCursor else {
                throw PlaidSyncError.missingTransactionsCursor
            }

            try repository.updateTransactionsCursor(itemID: item.id, cursor: finalCursor, syncedAt: finishedAt)
            try repository.finishSyncEvent(
                id: syncEventID,
                status: "succeeded",
                addedCount: addedCount,
                modifiedCount: modifiedCount,
                removedCount: removedCount,
                finishedAt: finishedAt
            )

            return try repository.fetchSnapshot(userID: item.userID)
        } catch {
            try? repository.finishSyncEvent(
                id: syncEventID,
                status: "failed",
                addedCount: addedCount,
                modifiedCount: modifiedCount,
                removedCount: removedCount,
                errorMessage: sanitizedErrorMessage(error),
                finishedAt: clock()
            )

            throw error
        }
    }
}

public enum PlaidSyncError: Error, LocalizedError {
    case itemNotFound(String)
    case invalidPlaidDate(String)
    case missingTransactionsCursor

    public var errorDescription: String? {
        switch self {
        case let .itemNotFound(itemID):
            return "No Plaid item exists with id \(itemID)."
        case let .invalidPlaidDate(date):
            return "Plaid returned an invalid transaction date: \(date)."
        case .missingTransactionsCursor:
            return "Plaid did not return a transactions cursor."
        }
    }
}

private func sanitizedErrorMessage(_ error: Error) -> String {
    let message = error.localizedDescription
    return String(message.prefix(500))
}

private extension PlaidAccount {
    func storedAccount(userID: String, itemID: String) -> StoredAccount {
        let currencyCode = balances.isoCurrencyCode ?? "USD"
        return StoredAccount(
            id: accountID,
            userID: userID,
            itemID: itemID,
            plaidAccountID: accountID,
            name: name,
            officialName: officialName,
            kind: accountKind,
            plaidType: type,
            plaidSubtype: subtype,
            mask: mask,
            currencyCode: currencyCode,
            currentBalanceMinorUnits: Money.dollars(balances.current ?? 0, currencyCode: currencyCode).minorUnits,
            availableBalanceMinorUnits: balances.available.map { Money.dollars($0, currencyCode: currencyCode).minorUnits }
        )
    }

    var accountKind: AccountKind {
        switch (type, subtype) {
        case ("depository", "checking"):
            return .checking
        case ("depository", "savings"):
            return .savings
        case ("investment", _):
            return .investment
        case ("depository", "money market"), ("depository", "cd"):
            return .investment
        case ("credit", _):
            return .creditCard
        case ("loan", _):
            return .loan
        default:
            return .other
        }
    }
}

private extension PlaidTransaction {
    func storedTransaction(userID: String, itemID: String) throws -> StoredTransaction {
        guard let postedDate = DateCoding.day(from: date) else {
            throw PlaidSyncError.invalidPlaidDate(date)
        }

        let currencyCode = isoCurrencyCode ?? "USD"

        return StoredTransaction(
            id: transactionID,
            userID: userID,
            itemID: itemID,
            accountID: accountID,
            plaidTransactionID: transactionID,
            pendingTransactionID: pendingTransactionID,
            merchantName: merchantName ?? name,
            originalName: name,
            postedDate: postedDate,
            authorizedDate: authorizedDate.flatMap(DateCoding.day(from:)),
            occurredAt: DateCoding.date(from: datetime ?? "")
                ?? DateCoding.date(from: authorizedDatetime ?? "")
                ?? postedDate,
            amountMinorUnits: Money.dollars(-amount, currencyCode: currencyCode).minorUnits,
            currencyCode: currencyCode,
            paymentChannel: paymentChannel,
            personalFinanceCategoryPrimary: personalFinanceCategory?.primary,
            personalFinanceCategoryDetailed: personalFinanceCategory?.detailed,
            isPending: pending
        )
    }
}
