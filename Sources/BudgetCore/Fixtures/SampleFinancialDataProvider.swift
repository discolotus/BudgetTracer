import Foundation

public struct SampleFinancialDataProvider: FinancialDataProvider {
    public init() {}

    public func fetchBudgetSnapshot() async throws -> BudgetSnapshot {
        SampleBudgetData.snapshot
    }
}
