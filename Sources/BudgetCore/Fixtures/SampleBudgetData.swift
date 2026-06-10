import Foundation

public enum SampleBudgetData {
    public static let snapshot: BudgetSnapshot = {
        let institution = Institution(id: "inst-main", name: "Sample Bank")

        let checking = FinancialAccount(
            id: "acct-checking",
            institutionID: institution.id,
            name: "Household Checking",
            kind: .checking,
            currentBalance: .dollars(4820.42)
        )
        let savings = FinancialAccount(
            id: "acct-savings",
            institutionID: institution.id,
            name: "Emergency Savings",
            kind: .savings,
            currentBalance: .dollars(14550.00)
        )
        let credit = FinancialAccount(
            id: "acct-credit",
            institutionID: institution.id,
            name: "Rewards Card",
            kind: .creditCard,
            currentBalance: .dollars(-1230.15)
        )

        let groceries = BudgetCategory(id: "cat-groceries", name: "Groceries", monthlyLimit: .dollars(900))
        let dining = BudgetCategory(id: "cat-dining", name: "Dining", monthlyLimit: .dollars(450))
        let home = BudgetCategory(id: "cat-home", name: "Home", monthlyLimit: .dollars(700))
        let housing = BudgetCategory(id: "cat-housing", name: "Housing")
        let utilities = BudgetCategory(id: "cat-utilities", name: "Utilities", monthlyLimit: .dollars(450))
        let income = BudgetCategory(id: "cat-income", name: "Income")

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let paycheckDate = calendar.date(byAdding: .day, value: 4, to: monthStart) ?? now
        let rentDate = calendar.date(byAdding: .day, value: 0, to: monthStart) ?? now
        let utilityDate = calendar.date(byAdding: .day, value: 12, to: monthStart) ?? now

        return BudgetSnapshot(
            institutions: [institution],
            accounts: [checking, savings, credit],
            categories: [groceries, dining, home, housing, utilities, income],
            transactions: [
                BudgetTransaction(
                    id: "txn-paycheck",
                    accountID: checking.id,
                    categoryID: income.id,
                    postedAt: paycheckDate,
                    merchantName: "Payroll",
                    amount: .dollars(5200)
                ),
                BudgetTransaction(
                    id: "txn-rent",
                    accountID: checking.id,
                    categoryID: housing.id,
                    postedAt: rentDate,
                    merchantName: "Rent",
                    amount: .dollars(-2650)
                ),
                BudgetTransaction(
                    id: "txn-utilities",
                    accountID: checking.id,
                    categoryID: utilities.id,
                    postedAt: utilityDate,
                    merchantName: "Utility Provider",
                    amount: .dollars(-310.45)
                ),
                BudgetTransaction(
                    id: "txn-market",
                    accountID: credit.id,
                    categoryID: groceries.id,
                    postedAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
                    merchantName: "Neighborhood Market",
                    amount: .dollars(-184.23)
                ),
                BudgetTransaction(
                    id: "txn-cafe",
                    accountID: credit.id,
                    categoryID: dining.id,
                    postedAt: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                    merchantName: "Corner Cafe",
                    amount: .dollars(-36.75)
                ),
                BudgetTransaction(
                    id: "txn-hardware",
                    accountID: checking.id,
                    categoryID: home.id,
                    postedAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                    merchantName: "Hardware Supply",
                    amount: .dollars(-92.10)
                )
            ],
            recurringTransactionIDs: ["txn-paycheck", "txn-rent", "txn-utilities"]
        )
    }()
}
