import BudgetCore
import XCTest

final class SampleFinancialDataProviderTests: XCTestCase {
    func testSequentialRecurringTogglesAccumulate() async throws {
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [],
            transactions: [
                BudgetTransaction(id: "a", accountID: "acct", categoryID: nil, postedAt: Date(), merchantName: "A", amount: Money(minorUnits: -100)),
                BudgetTransaction(id: "b", accountID: "acct", categoryID: nil, postedAt: Date(), merchantName: "B", amount: Money(minorUnits: -200))
            ]
        )
        let provider = SampleFinancialDataProvider(snapshot: snapshot)

        _ = try await provider.setRegularMonthly(transactionID: "a", isRegularMonthly: true)
        let result = try await provider.setRegularMonthly(transactionID: "b", isRegularMonthly: true)

        // Toggling b must not drop a — the prior edit accumulates.
        XCTAssertEqual(result.recurringTransactionIDs, ["a", "b"])
    }

    func testSaveCategoryAddsThenRenames() async throws {
        let provider = SampleFinancialDataProvider(
            snapshot: BudgetSnapshot(institutions: [], accounts: [], categories: [], transactions: [])
        )

        _ = try await provider.saveCategory(BudgetCategory(id: "c1", name: "Travel"))
        var result = try await provider.saveCategory(BudgetCategory(id: "c1", name: "Trips", monthlyLimit: Money(minorUnits: 50_000)))

        XCTAssertEqual(result.categories.count, 1)
        XCTAssertEqual(result.categories.first?.name, "Trips")
        XCTAssertEqual(result.categories.first?.monthlyLimit, Money(minorUnits: 50_000))

        result = try await provider.deleteCategory(id: "c1")
        XCTAssertTrue(result.categories.isEmpty)
    }

    func testDeleteCategoryClearsAssignedTransactions() async throws {
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [BudgetCategory(id: "cat", name: "Utilities")],
            transactions: [
                BudgetTransaction(id: "a", accountID: "acct", categoryID: "cat", postedAt: Date(), merchantName: "A", amount: Money(minorUnits: -100))
            ]
        )
        let provider = SampleFinancialDataProvider(snapshot: snapshot)

        let result = try await provider.deleteCategory(id: "cat")

        XCTAssertTrue(result.categories.isEmpty)
        XCTAssertNil(result.transactions.first?.categoryID)
    }

    func testSetCategoryUpdatesHeldSnapshot() async throws {
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [BudgetCategory(id: "cat", name: "Utilities")],
            transactions: [
                BudgetTransaction(id: "a", accountID: "acct", categoryID: nil, postedAt: Date(), merchantName: "A", amount: Money(minorUnits: -100))
            ]
        )
        let provider = SampleFinancialDataProvider(snapshot: snapshot)

        _ = try await provider.setCategory(transactionID: "a", categoryID: "cat")
        let result = try await provider.fetchBudgetSnapshot()

        XCTAssertEqual(result.transactions.first?.categoryID, "cat")
    }
}
