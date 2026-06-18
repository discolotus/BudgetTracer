import BudgetCore
import XCTest

final class PlaidCategoryBudgetClassifierTests: XCTestCase {
    func testMapsPlaidCategoriesToDefaultBudgetCategoryIDs() {
        XCTAssertEqual(
            PlaidCategoryBudgetClassifier.categoryID(
                primary: "INCOME",
                detailed: "INCOME_WAGES",
                merchantName: "Payroll",
                amount: .dollars(3_200),
                categories: BudgetCategory.defaultSeed
            ),
            "default-income"
        )

        XCTAssertEqual(
            PlaidCategoryBudgetClassifier.categoryID(
                primary: "RENT_AND_UTILITIES",
                detailed: "RENT_AND_UTILITIES_RENT",
                merchantName: "Rent",
                amount: .dollars(-2_100),
                categories: BudgetCategory.defaultSeed
            ),
            "default-housing"
        )

        XCTAssertEqual(
            PlaidCategoryBudgetClassifier.categoryID(
                primary: "FOOD_AND_DRINK",
                detailed: "FOOD_AND_DRINK_GROCERIES",
                merchantName: "Neighborhood Market",
                amount: .dollars(-84),
                categories: BudgetCategory.defaultSeed
            ),
            "default-groceries"
        )
    }

    func testDoesNotClassifyTransfersOrCardPayments() {
        XCTAssertNil(
            PlaidCategoryBudgetClassifier.categoryID(
                primary: "TRANSFER_OUT",
                detailed: "TRANSFER_OUT_ACCOUNT_TRANSFER",
                merchantName: "Transfer",
                amount: .dollars(-500),
                categories: BudgetCategory.defaultSeed
            )
        )

        XCTAssertNil(
            PlaidCategoryBudgetClassifier.categoryID(
                primary: "LOAN_PAYMENTS",
                detailed: "LOAN_PAYMENTS_CREDIT_CARD_PAYMENT",
                merchantName: "Credit Card Payment",
                amount: .dollars(-300),
                categories: BudgetCategory.defaultSeed
            )
        )
    }
}
