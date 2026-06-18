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
    var storesAccountOverrides: Bool { get }

    func fetchBudgetSnapshot() async throws -> BudgetSnapshot
    func fetchBudgetSnapshot(freshnessPolicy: BudgetSnapshotFreshnessPolicy) async throws -> BudgetSnapshot
    func createPlaidLinkToken() async throws -> String
    func exchangePlaidPublicToken(_ publicToken: String, institutionID: String?) async throws -> BudgetSnapshot
    func createSandboxPlaidItem(institutionID: String?) async throws -> BudgetSnapshot
    func setRegularMonthly(transactionID: BudgetTransaction.ID, isRegularMonthly: Bool) async throws -> BudgetSnapshot
    func setCategory(transactionID: BudgetTransaction.ID, categoryID: BudgetCategory.ID?) async throws -> BudgetSnapshot
    func saveAssignmentRule(_ rule: BudgetAssignmentRule, applyToExisting: Bool) async throws -> BudgetSnapshot
    func deleteAssignmentRule(id: BudgetAssignmentRule.ID) async throws -> BudgetSnapshot
    func setAccountOverride(accountID: FinancialAccount.ID, override: AccountOverride?) async throws -> BudgetSnapshot
    func saveCategory(_ category: BudgetCategory) async throws -> BudgetSnapshot
    func deleteCategory(id: BudgetCategory.ID) async throws -> BudgetSnapshot
    func deleteLocalData() async throws
}

public extension FinancialDataProvider {
    var storesAccountOverrides: Bool { false }

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
            updated.categoryAssignmentSource = .manual
            updated.categoryAssignmentRuleID = nil
            return updated
        }
        return snapshot
    }

    func saveAssignmentRule(_ rule: BudgetAssignmentRule, applyToExisting: Bool) async throws -> BudgetSnapshot {
        var snapshot = try await fetchBudgetSnapshot()
        if let index = snapshot.assignmentRules.firstIndex(where: { $0.id == rule.id }) {
            snapshot.assignmentRules[index] = rule
        } else {
            snapshot.assignmentRules.append(rule)
        }

        if applyToExisting {
            snapshot = BudgetAssignmentRuleEngine.applying(rule, to: snapshot)
        }

        return snapshot
    }

    func deleteAssignmentRule(id: BudgetAssignmentRule.ID) async throws -> BudgetSnapshot {
        var snapshot = try await fetchBudgetSnapshot()
        snapshot.assignmentRules.removeAll { $0.id == id }
        return snapshot
    }

    func setAccountOverride(accountID: FinancialAccount.ID, override: AccountOverride?) async throws -> BudgetSnapshot {
        var snapshot = try await fetchBudgetSnapshot()
        snapshot.accountOverrides[accountID] = override
        return snapshot
    }

    func saveCategory(_ category: BudgetCategory) async throws -> BudgetSnapshot {
        var snapshot = try await fetchBudgetSnapshot()
        if let index = snapshot.categories.firstIndex(where: { $0.id == category.id }) {
            snapshot.categories[index] = category
        } else {
            snapshot.categories.append(category)
        }
        return snapshot
    }

    func deleteCategory(id: BudgetCategory.ID) async throws -> BudgetSnapshot {
        var snapshot = try await fetchBudgetSnapshot()
        snapshot.categories.removeAll { $0.id == id }
        snapshot.transactions = snapshot.transactions.map { transaction in
            guard transaction.categoryID == id else {
                return transaction
            }

            var updated = transaction
            updated.categoryID = nil
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

    func deleteLocalData() async throws {}
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
