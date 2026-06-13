import BudgetCore
import Foundation
import SwiftUI

public enum PlaidLinkState: Hashable, Sendable {
    case idle
    case preparing
    case ready
    case exchanging
    case succeeded
    case failed(message: String)
}

@MainActor
public final class BudgetWorkspace: ObservableObject {
    @Published public private(set) var snapshot: BudgetSnapshot
    @Published public private(set) var connectionState: PlaidConnectionState
    @Published public private(set) var plaidLinkState: PlaidLinkState
    @Published public private(set) var accountOverrides: [FinancialAccount.ID: AccountOverride]

    public let requiresAppLock: Bool

    private let dataProvider: FinancialDataProvider
    private let userDefaults: UserDefaults
    private static let accountOverridesStorageKey = "BudgetTracer.accountOverrides.v1"

    public init(
        snapshot: BudgetSnapshot = SampleBudgetData.snapshot,
        connectionState: PlaidConnectionState = .notConnected,
        plaidLinkState: PlaidLinkState = .idle,
        dataProvider: FinancialDataProvider = PlaidDataProvider(),
        userDefaults: UserDefaults = .standard,
        requiresAppLock: Bool = false
    ) {
        self.snapshot = snapshot
        self.connectionState = connectionState
        self.plaidLinkState = plaidLinkState
        self.dataProvider = dataProvider
        self.userDefaults = userDefaults
        self.requiresAppLock = requiresAppLock
        self.accountOverrides = dataProvider.storesAccountOverrides
            ? snapshot.accountOverrides
            : Self.loadAccountOverrides(from: userDefaults)
    }

    public var displaySnapshot: BudgetSnapshot {
        snapshot.applying(accountOverrides: accountOverrides)
    }

    public func refresh(forceSync: Bool = false) async {
        connectionState = .connecting

        do {
            let freshnessPolicy: BudgetSnapshotFreshnessPolicy = forceSync ? .forceSync : .syncIfStale(maxAge: 300)
            applySnapshot(try await dataProvider.fetchBudgetSnapshot(freshnessPolicy: freshnessPolicy))
            markConnected()
        } catch {
            connectionState = .failed(message: error.localizedDescription)
        }
    }

    @discardableResult
    public func preparePlaidLink() async -> String? {
        plaidLinkState = .preparing

        do {
            let linkToken = try await dataProvider.createPlaidLinkToken()
            plaidLinkState = .ready
            return linkToken
        } catch {
            plaidLinkState = .failed(message: error.localizedDescription)
            return nil
        }
    }

    public func finishPlaidLink(publicToken: String, institutionID: String? = nil) async {
        plaidLinkState = .exchanging

        do {
            applySnapshot(try await dataProvider.exchangePlaidPublicToken(publicToken, institutionID: institutionID))
            markConnected()
            plaidLinkState = .succeeded
        } catch {
            plaidLinkState = .failed(message: error.localizedDescription)
        }
    }

    public func createSandboxPlaidItem(institutionID: String? = nil) async {
        plaidLinkState = .exchanging

        do {
            applySnapshot(try await dataProvider.createSandboxPlaidItem(institutionID: institutionID))
            markConnected()
            plaidLinkState = .succeeded
        } catch {
            plaidLinkState = .failed(message: error.localizedDescription)
        }
    }

    public func cancelPlaidLink() {
        plaidLinkState = .idle
    }

    public func failPlaidLink(message: String) {
        plaidLinkState = .failed(message: message)
    }

    /// Applies a recurring change to every transaction in a series (e.g. all months of a bill).
    public func setRecurring(_ transactionIDs: [BudgetTransaction.ID], isRecurring: Bool) {
        guard !transactionIDs.isEmpty else { return }

        for id in transactionIDs {
            if isRecurring {
                snapshot.recurringTransactionIDs.insert(id)
            } else {
                snapshot.recurringTransactionIDs.remove(id)
            }
        }

        Task {
            do {
                var latest = snapshot
                for id in transactionIDs {
                    latest = try await dataProvider.setRegularMonthly(transactionID: id, isRegularMonthly: isRecurring)
                }
                applySnapshot(latest)
                markConnected()
            } catch {
                connectionState = .failed(message: error.localizedDescription)
            }
        }
    }

    /// Marking a transaction regular-monthly (or not) sweeps every transaction sharing its
    /// merchant, so all occurrences of a recurring bill group together instead of leaving
    /// other instances dangling in the list.
    public func setRecurringForSeries(containing transactionID: BudgetTransaction.ID, isRecurring: Bool) {
        guard let transaction = snapshot.transactions.first(where: { $0.id == transactionID }) else {
            return
        }

        let key = RecurringSeries.normalizedMerchant(transaction.merchantName)
        let ids = snapshot.transactions
            .filter { RecurringSeries.normalizedMerchant($0.merchantName) == key }
            .map(\.id)

        setRecurring(ids, isRecurring: isRecurring)
    }

    /// Assigns a budget to every transaction in a series.
    public func setCategory(_ transactionIDs: [BudgetTransaction.ID], categoryID: BudgetCategory.ID?) {
        guard !transactionIDs.isEmpty else { return }

        let ids = Set(transactionIDs)
        snapshot.transactions = snapshot.transactions.map { transaction in
            guard ids.contains(transaction.id) else {
                return transaction
            }

            var updated = transaction
            updated.categoryID = categoryID
            return updated
        }

        Task {
            do {
                var latest = snapshot
                for id in transactionIDs {
                    latest = try await dataProvider.setCategory(transactionID: id, categoryID: categoryID)
                }
                applySnapshot(latest)
                markConnected()
            } catch {
                connectionState = .failed(message: error.localizedDescription)
            }
        }
    }

    public func setCategory(_ transactionID: BudgetTransaction.ID, categoryID: BudgetCategory.ID?) {
        snapshot.transactions = snapshot.transactions.map { transaction in
            guard transaction.id == transactionID else {
                return transaction
            }

            var updated = transaction
            updated.categoryID = categoryID
            return updated
        }

        Task {
            do {
                applySnapshot(
                    try await dataProvider.setCategory(
                        transactionID: transactionID,
                        categoryID: categoryID
                    )
                )
                markConnected()
            } catch {
                connectionState = .failed(message: error.localizedDescription)
            }
        }
    }

    @discardableResult
    public func addCategory(name: String, monthlyLimit: Money?) -> BudgetCategory {
        let category = BudgetCategory(id: UUID().uuidString, name: name, monthlyLimit: monthlyLimit)
        saveCategory(category)
        return category
    }

    public func saveCategory(_ category: BudgetCategory) {
        if let index = snapshot.categories.firstIndex(where: { $0.id == category.id }) {
            snapshot.categories[index] = category
        } else {
            snapshot.categories.append(category)
        }

        Task {
            do {
                applySnapshot(try await dataProvider.saveCategory(category))
                markConnected()
            } catch {
                connectionState = .failed(message: error.localizedDescription)
            }
        }
    }

    public func deleteCategory(_ categoryID: BudgetCategory.ID) {
        snapshot.categories.removeAll { $0.id == categoryID }
        snapshot.transactions = snapshot.transactions.map { transaction in
            guard transaction.categoryID == categoryID else {
                return transaction
            }

            var updated = transaction
            updated.categoryID = nil
            return updated
        }

        Task {
            do {
                applySnapshot(try await dataProvider.deleteCategory(id: categoryID))
                markConnected()
            } catch {
                connectionState = .failed(message: error.localizedDescription)
            }
        }
    }

    public func setAccount(_ accountID: FinancialAccount.ID, kind: AccountKind) {
        var override = accountOverrides[accountID] ?? AccountOverride()
        override.kind = kind
        if kind == .checking {
            override.includesInAvailableCash = override.includesInAvailableCash ?? true
        } else {
            override.includesInAvailableCash = false
        }
        setAccountOverride(accountID, override: override)
    }

    public func setAccount(_ accountID: FinancialAccount.ID, includesInAvailableCash: Bool) {
        var override = accountOverrides[accountID] ?? AccountOverride()
        override.includesInAvailableCash = includesInAvailableCash
        setAccountOverride(accountID, override: override)
    }

    public func resetAccountOverride(_ accountID: FinancialAccount.ID) {
        setAccountOverride(accountID, override: nil)
    }

    public func deleteLocalData() {
        snapshot = Self.emptySnapshot
        accountOverrides = [:]
        plaidLinkState = .idle
        connectionState = .notConnected

        Task {
            do {
                try await dataProvider.deleteLocalData()
            } catch {
                connectionState = .failed(message: error.localizedDescription)
            }
        }
    }

    private static func loadAccountOverrides(from userDefaults: UserDefaults) -> [FinancialAccount.ID: AccountOverride] {
        guard let data = userDefaults.data(forKey: accountOverridesStorageKey) else {
            return [:]
        }

        return (try? JSONDecoder().decode([FinancialAccount.ID: AccountOverride].self, from: data)) ?? [:]
    }

    private func persistAccountOverrides() {
        guard let data = try? JSONEncoder().encode(accountOverrides) else {
            return
        }

        userDefaults.set(data, forKey: Self.accountOverridesStorageKey)
    }

    private func setAccountOverride(_ accountID: FinancialAccount.ID, override: AccountOverride?) {
        accountOverrides[accountID] = override

        guard dataProvider.storesAccountOverrides else {
            persistAccountOverrides()
            return
        }

        Task {
            do {
                applySnapshot(
                    try await dataProvider.setAccountOverride(
                        accountID: accountID,
                        override: override
                    )
                )
                markConnected()
            } catch {
                connectionState = .failed(message: error.localizedDescription)
            }
        }
    }

    private func applySnapshot(_ snapshot: BudgetSnapshot) {
        self.snapshot = snapshot
        if dataProvider.storesAccountOverrides {
            accountOverrides = snapshot.accountOverrides
        }
    }

    private func markConnected() {
        connectionState = .connected(
            institutionCount: snapshot.institutions.count,
            lastSyncedAt: snapshot.lastSuccessfulSyncAt
        )
    }

    private static var emptySnapshot: BudgetSnapshot {
        BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: BudgetCategory.defaultSeed,
            transactions: []
        )
    }
}
