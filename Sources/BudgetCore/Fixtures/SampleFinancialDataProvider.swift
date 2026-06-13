import Foundation

/// In-memory provider for demo and preview mode. Holds a mutable snapshot so that
/// recurring and category edits accumulate across a session instead of resetting to
/// the static fixture on every fetch.
public actor SampleFinancialDataProvider: FinancialDataProvider {
    private var snapshot: BudgetSnapshot

    public init(snapshot: BudgetSnapshot = SampleBudgetData.snapshot) {
        self.snapshot = snapshot
    }

    public func fetchBudgetSnapshot() async throws -> BudgetSnapshot {
        snapshot
    }

    public func setRegularMonthly(
        transactionID: BudgetTransaction.ID,
        isRegularMonthly: Bool
    ) async throws -> BudgetSnapshot {
        if isRegularMonthly {
            snapshot.recurringTransactionIDs.insert(transactionID)
        } else {
            snapshot.recurringTransactionIDs.remove(transactionID)
        }
        return snapshot
    }

    public func setCategory(
        transactionID: BudgetTransaction.ID,
        categoryID: BudgetCategory.ID?
    ) async throws -> BudgetSnapshot {
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

    public func saveCategory(_ category: BudgetCategory) async throws -> BudgetSnapshot {
        if let index = snapshot.categories.firstIndex(where: { $0.id == category.id }) {
            snapshot.categories[index] = category
        } else {
            snapshot.categories.append(category)
        }
        return snapshot
    }

    public func deleteCategory(id: BudgetCategory.ID) async throws -> BudgetSnapshot {
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
}
