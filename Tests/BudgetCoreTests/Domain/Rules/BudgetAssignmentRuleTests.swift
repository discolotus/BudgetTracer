import BudgetCore
import XCTest

final class BudgetAssignmentRuleTests: XCTestCase {
    func testRuleMatchesConfiguredTextFieldAndOperator() {
        let transaction = BudgetTransaction(
            id: "txn-1",
            accountID: "account-1",
            categoryID: nil,
            postedAt: Date(timeIntervalSince1970: 0),
            merchantName: "Starbucks Reserve",
            amount: Money(minorUnits: -1_250),
            note: "Airport coffee"
        )

        XCTAssertTrue(rule(matchText: "starbucks", textOperator: .contains).matches(transaction))
        XCTAssertTrue(rule(matchText: "star", textOperator: .beginsWith).matches(transaction))
        XCTAssertFalse(rule(matchText: "starbucks", textOperator: .equals).matches(transaction))
        XCTAssertTrue(rule(matchText: "airport", field: .note, textOperator: .contains).matches(transaction))
    }

    func testRuleFiltersByAmountAndAccount() {
        let creditExpense = BudgetTransaction(
            id: "txn-credit",
            accountID: "credit",
            categoryID: nil,
            postedAt: Date(timeIntervalSince1970: 0),
            merchantName: "Starbucks",
            amount: Money(minorUnits: -900)
        )
        let checkingIncome = BudgetTransaction(
            id: "txn-income",
            accountID: "checking",
            categoryID: nil,
            postedAt: Date(timeIntervalSince1970: 0),
            merchantName: "Starbucks",
            amount: Money(minorUnits: 900)
        )

        let creditExpensesRule = rule(
            matchText: "starbucks",
            amountFilter: .expensesOnly,
            accountID: "credit"
        )

        XCTAssertTrue(creditExpensesRule.matches(creditExpense))
        XCTAssertFalse(creditExpensesRule.matches(checkingIncome))
    }

    func testPreviewIDsProtectManualAssignments() {
        let manual = BudgetTransaction(
            id: "txn-manual",
            accountID: "credit",
            categoryID: "cat-travel",
            categoryAssignmentSource: .manual,
            postedAt: Date(timeIntervalSince1970: 0),
            merchantName: "Starbucks",
            amount: Money(minorUnits: -900)
        )
        let plaid = BudgetTransaction(
            id: "txn-plaid",
            accountID: "credit",
            categoryID: "cat-travel",
            categoryAssignmentSource: .plaid,
            postedAt: Date(timeIntervalSince1970: 0),
            merchantName: "Starbucks",
            amount: Money(minorUnits: -1_200)
        )

        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [
                BudgetCategory(id: "cat-dining", name: "Dining"),
                BudgetCategory(id: "cat-travel", name: "Travel")
            ],
            transactions: [manual, plaid]
        )

        let ids = BudgetAssignmentRuleEngine.transactionIDsMatching(
            rule(matchText: "starbucks", categoryID: "cat-dining"),
            in: snapshot
        )

        XCTAssertEqual(ids, ["txn-plaid"])
    }

    private func rule(
        matchText: String,
        field: AssignmentRuleMatchField = .merchantName,
        textOperator: AssignmentRuleTextOperator = .contains,
        amountFilter: AssignmentRuleAmountFilter = .any,
        accountID: FinancialAccount.ID? = nil,
        categoryID: BudgetCategory.ID = "cat-dining"
    ) -> BudgetAssignmentRule {
        BudgetAssignmentRule(
            id: "rule-1",
            name: "Test rule",
            merchantContains: matchText,
            categoryID: categoryID,
            matchField: field,
            matchOperator: textOperator,
            amountFilter: amountFilter,
            accountID: accountID
        )
    }
}
