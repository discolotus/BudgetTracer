import BudgetCore
import Foundation

public actor RepositoryFinancialDataProvider: FinancialDataProvider {
    private let repository: BudgetRepository
    private let userID: String

    public init(repository: BudgetRepository, userID: String) {
        self.repository = repository
        self.userID = userID
    }

    public func fetchBudgetSnapshot() async throws -> BudgetSnapshot {
        try repository.fetchSnapshot(userID: userID)
    }

    public func saveAssignmentRule(
        _ rule: BudgetAssignmentRule,
        applyToExisting: Bool
    ) async throws -> BudgetSnapshot {
        try repository.upsertAssignmentRule(rule, userID: userID)

        if applyToExisting {
            try repository.applyAssignmentRules(userID: userID, ruleIDs: [rule.id])
        }

        return try repository.fetchSnapshot(userID: userID)
    }

    public func deleteAssignmentRule(id: BudgetAssignmentRule.ID) async throws -> BudgetSnapshot {
        try repository.deleteAssignmentRule(id: id, userID: userID)
        return try repository.fetchSnapshot(userID: userID)
    }
}
