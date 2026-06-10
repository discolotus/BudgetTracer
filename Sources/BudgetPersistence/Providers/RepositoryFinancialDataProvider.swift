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
}
