import BudgetCore
@testable import BudgetTracerSharedUI
import XCTest

final class TransactionSearchTests: XCTestCase {
    private func makeTransaction(categoryID: String?) -> BudgetTransaction {
        BudgetTransaction(
            id: "txn-1",
            accountID: "account-1",
            categoryID: categoryID,
            postedAt: Date(timeIntervalSince1970: 1_780_000_000),
            merchantName: "City Power",
            amount: Money(minorUnits: -12_000),
            note: "Autopay"
        )
    }

    func testMatchesByCategoryName() {
        let transaction = makeTransaction(categoryID: "cat-utilities")
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [BudgetCategory(id: "cat-utilities", name: "Utilities")],
            transactions: [transaction]
        )

        XCTAssertTrue(TransactionSearch.matches(transaction, query: "utilities", in: snapshot))
        XCTAssertTrue(TransactionSearch.matches(transaction, query: "city", in: snapshot))
    }

    func testDoesNotMatchUnrelatedCategory() {
        let transaction = makeTransaction(categoryID: "cat-utilities")
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [BudgetCategory(id: "cat-utilities", name: "Utilities")],
            transactions: [transaction]
        )

        XCTAssertFalse(TransactionSearch.matches(transaction, query: "groceries", in: snapshot))
    }

    func testMatchesByNote() {
        let transaction = makeTransaction(categoryID: nil)
        XCTAssertTrue(TransactionSearch.matches(transaction, query: "autopay"))
    }
}
