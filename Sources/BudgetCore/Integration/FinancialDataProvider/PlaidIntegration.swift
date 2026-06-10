import Foundation

public enum PlaidConnectionState: Hashable, Sendable {
    case notConnected
    case connecting
    case connected(institutionCount: Int, lastSyncedAt: Date?)
    case failed(message: String)
}

public protocol FinancialDataProvider: Sendable {
    func fetchBudgetSnapshot() async throws -> BudgetSnapshot
    func setRegularMonthly(transactionID: BudgetTransaction.ID, isRegularMonthly: Bool) async throws -> BudgetSnapshot
}

public extension FinancialDataProvider {
    func setRegularMonthly(transactionID: BudgetTransaction.ID, isRegularMonthly: Bool) async throws -> BudgetSnapshot {
        var snapshot = try await fetchBudgetSnapshot()
        if isRegularMonthly {
            snapshot.recurringTransactionIDs.insert(transactionID)
        } else {
            snapshot.recurringTransactionIDs.remove(transactionID)
        }
        return snapshot
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
