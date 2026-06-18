import BudgetCore
@testable import BudgetTracerSharedUI
import XCTest

final class TransactionSearchTests: XCTestCase {
    private func makeTransaction(
        id: String = "txn-1",
        accountID: String = "account-1",
        categoryID: String? = nil,
        postedAt: Date = Date(timeIntervalSince1970: 1_780_000_000),
        merchantName: String = "City Power"
    ) -> BudgetTransaction {
        BudgetTransaction(
            id: id,
            accountID: accountID,
            categoryID: categoryID,
            postedAt: postedAt,
            merchantName: merchantName,
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

    func testListFilterLimitsResultsToSelectedAccount() {
        let checking = makeTransaction(id: "checking-txn", accountID: "checking")
        let card = makeTransaction(id: "card-txn", accountID: "card")
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [],
            transactions: [checking, card]
        )

        let result = TransactionListFilter.transactions(
            in: snapshot,
            searchText: "",
            selectedAccountID: "checking"
        )

        XCTAssertEqual(result.map(\.id), ["checking-txn"])
    }

    func testListFilterCombinesAccountAndSearch() {
        let selectedMatch = makeTransaction(
            id: "selected-match",
            accountID: "checking",
            merchantName: "City Power"
        )
        let selectedNonMatch = makeTransaction(
            id: "selected-non-match",
            accountID: "checking",
            merchantName: "Corner Cafe"
        )
        let otherAccountMatch = makeTransaction(
            id: "other-account-match",
            accountID: "card",
            merchantName: "City Power"
        )
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [],
            transactions: [selectedMatch, selectedNonMatch, otherAccountMatch]
        )

        let result = TransactionListFilter.transactions(
            in: snapshot,
            searchText: "city",
            selectedAccountID: "checking"
        )

        XCTAssertEqual(result.map(\.id), ["selected-match"])
    }
}
