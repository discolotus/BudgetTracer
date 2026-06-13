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

    private let dataProvider: FinancialDataProvider
    private let userDefaults: UserDefaults
    private static let accountOverridesStorageKey = "BudgetTracer.accountOverrides.v1"

    public init(
        snapshot: BudgetSnapshot = SampleBudgetData.snapshot,
        connectionState: PlaidConnectionState = .notConnected,
        plaidLinkState: PlaidLinkState = .idle,
        dataProvider: FinancialDataProvider = PlaidDataProvider(),
        userDefaults: UserDefaults = .standard
    ) {
        self.snapshot = snapshot
        self.connectionState = connectionState
        self.plaidLinkState = plaidLinkState
        self.dataProvider = dataProvider
        self.userDefaults = userDefaults
        self.accountOverrides = Self.loadAccountOverrides(from: userDefaults)
    }

    public var displaySnapshot: BudgetSnapshot {
        snapshot.applying(accountOverrides: accountOverrides)
    }

    public func refresh(forceSync: Bool = false) async {
        connectionState = .connecting

        do {
            let freshnessPolicy: BudgetSnapshotFreshnessPolicy = forceSync ? .forceSync : .syncIfStale(maxAge: 300)
            snapshot = try await dataProvider.fetchBudgetSnapshot(freshnessPolicy: freshnessPolicy)
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
            snapshot = try await dataProvider.exchangePlaidPublicToken(publicToken, institutionID: institutionID)
            markConnected()
            plaidLinkState = .succeeded
        } catch {
            plaidLinkState = .failed(message: error.localizedDescription)
        }
    }

    public func createSandboxPlaidItem(institutionID: String? = nil) async {
        plaidLinkState = .exchanging

        do {
            snapshot = try await dataProvider.createSandboxPlaidItem(institutionID: institutionID)
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

    public func setTransaction(_ transactionID: BudgetTransaction.ID, isRecurring: Bool) {
        if isRecurring {
            snapshot.recurringTransactionIDs.insert(transactionID)
        } else {
            snapshot.recurringTransactionIDs.remove(transactionID)
        }

        Task {
            do {
                snapshot = try await dataProvider.setRegularMonthly(
                    transactionID: transactionID,
                    isRegularMonthly: isRecurring
                )
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
                snapshot = try await dataProvider.setCategory(
                    transactionID: transactionID,
                    categoryID: categoryID
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
                snapshot = try await dataProvider.saveCategory(category)
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
                snapshot = try await dataProvider.deleteCategory(id: categoryID)
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
        accountOverrides[accountID] = override
        persistAccountOverrides()
    }

    public func setAccount(_ accountID: FinancialAccount.ID, includesInAvailableCash: Bool) {
        var override = accountOverrides[accountID] ?? AccountOverride()
        override.includesInAvailableCash = includesInAvailableCash
        accountOverrides[accountID] = override
        persistAccountOverrides()
    }

    public func resetAccountOverride(_ accountID: FinancialAccount.ID) {
        accountOverrides.removeValue(forKey: accountID)
        persistAccountOverrides()
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

    private func markConnected() {
        connectionState = .connected(
            institutionCount: snapshot.institutions.count,
            lastSyncedAt: snapshot.lastSuccessfulSyncAt
        )
    }
}
