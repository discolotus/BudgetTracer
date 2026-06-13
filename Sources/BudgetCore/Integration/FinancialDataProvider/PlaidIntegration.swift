import Foundation

public enum PlaidConnectionState: Hashable, Sendable {
    case notConnected
    case connecting
    case connected(institutionCount: Int, lastSyncedAt: Date?)
    case failed(message: String)
}

public enum BudgetSnapshotFreshnessPolicy: Hashable, Sendable {
    case cached
    case syncIfStale(maxAge: TimeInterval)
    case forceSync
}

public protocol FinancialDataProvider: Sendable {
    func fetchBudgetSnapshot() async throws -> BudgetSnapshot
    func fetchBudgetSnapshot(freshnessPolicy: BudgetSnapshotFreshnessPolicy) async throws -> BudgetSnapshot
    func createPlaidLinkToken() async throws -> String
    func exchangePlaidPublicToken(_ publicToken: String, institutionID: String?) async throws -> BudgetSnapshot
    func createSandboxPlaidItem(institutionID: String?) async throws -> BudgetSnapshot
    func setRegularMonthly(transactionID: BudgetTransaction.ID, isRegularMonthly: Bool) async throws -> BudgetSnapshot
    func setCategory(transactionID: BudgetTransaction.ID, categoryID: BudgetCategory.ID?) async throws -> BudgetSnapshot
}

public extension FinancialDataProvider {
    func fetchBudgetSnapshot(freshnessPolicy: BudgetSnapshotFreshnessPolicy) async throws -> BudgetSnapshot {
        try await fetchBudgetSnapshot()
    }

    func setRegularMonthly(transactionID: BudgetTransaction.ID, isRegularMonthly: Bool) async throws -> BudgetSnapshot {
        var snapshot = try await fetchBudgetSnapshot()
        if isRegularMonthly {
            snapshot.recurringTransactionIDs.insert(transactionID)
        } else {
            snapshot.recurringTransactionIDs.remove(transactionID)
        }
        return snapshot
    }

    func setCategory(transactionID: BudgetTransaction.ID, categoryID: BudgetCategory.ID?) async throws -> BudgetSnapshot {
        var snapshot = try await fetchBudgetSnapshot()
        snapshot.transactions = snapshot.transactions.map { transaction in
            guard transaction.id == transactionID else {
                return transaction
            }

            var updated = transaction
            updated.categoryID = categoryID
            return updated
        }
        return snapshot
    }

    func createPlaidLinkToken() async throws -> String {
        throw PlaidIntegrationError.requiresBackend
    }

    func exchangePlaidPublicToken(_ publicToken: String, institutionID: String?) async throws -> BudgetSnapshot {
        throw PlaidIntegrationError.requiresBackend
    }

    func createSandboxPlaidItem(institutionID: String? = nil) async throws -> BudgetSnapshot {
        throw PlaidIntegrationError.requiresBackend
    }
}

public struct PlaidDataProvider: FinancialDataProvider {
    public init() {}

    public func fetchBudgetSnapshot() async throws -> BudgetSnapshot {
        throw PlaidIntegrationError.requiresBackend
    }
}

public enum PlaidIntegrationError: LocalizedError, Sendable {
    case requiresBackend

    public var errorDescription: String? {
        switch self {
        case .requiresBackend:
            return "Plaid must be accessed through the backend sync service so access tokens and client secrets are never stored in the Apple app."
        }
    }
}
