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
        var transactions: [BudgetTransaction] = []
        var recurringTransactionIDs: Set<BudgetTransaction.ID> = []

        func date(day: Int, in monthStart: Date) -> Date {
            calendar.date(byAdding: .day, value: max(day - 1, 0), to: monthStart) ?? monthStart
        }

        for (index, monthOffset) in (-11...0).enumerated() {
            let transactionPrefix = monthOffset == 0 ? "current" : "\(abs(monthOffset))mo"
            let transactionMonthStart = calendar.date(byAdding: .month, value: monthOffset, to: monthStart) ?? monthStart
            let paycheck = BudgetTransaction(
                id: "txn-\(transactionPrefix)-paycheck",
                accountID: checking.id,
                categoryID: income.id,
                postedAt: date(day: 5, in: transactionMonthStart),
                merchantName: "Payroll",
                amount: Money(minorUnits: 500_000 + Int64(index * 2_500))
            )
            let rent = BudgetTransaction(
                id: "txn-\(transactionPrefix)-rent",
                accountID: checking.id,
                categoryID: housing.id,
                postedAt: transactionMonthStart,
                merchantName: "Rent",
                amount: .dollars(-2650)
            )
            let utilities = BudgetTransaction(
                id: "txn-\(transactionPrefix)-utilities",
                accountID: checking.id,
                categoryID: utilities.id,
                postedAt: date(day: 12 + index % 3, in: transactionMonthStart),
                merchantName: "Utility Provider",
                amount: Money(minorUnits: -(28_000 + Int64(index % 5) * 750))
            )
            let market = BudgetTransaction(
                id: "txn-\(transactionPrefix)-market",
                accountID: credit.id,
                categoryID: groceries.id,
                postedAt: date(day: 8 + index % 4, in: transactionMonthStart),
                merchantName: "Neighborhood Market",
                amount: Money(minorUnits: -(15_000 + Int64(index % 6) * 850))
            )
            let cafe = BudgetTransaction(
                id: "txn-\(transactionPrefix)-cafe",
                accountID: credit.id,
                categoryID: dining.id,
                postedAt: date(day: 18 + index % 3, in: transactionMonthStart),
                merchantName: "Corner Cafe",
                amount: Money(minorUnits: -(3_500 + Int64(index % 4) * 425))
            )
            let hardware = BudgetTransaction(
                id: "txn-\(transactionPrefix)-hardware",
                accountID: checking.id,
                categoryID: home.id,
                postedAt: date(day: 24 + index % 4, in: transactionMonthStart),
                merchantName: "Hardware Supply",
                amount: Money(minorUnits: -(7_500 + Int64(index % 7) * 700))
            )

            transactions.append(contentsOf: [paycheck, rent, utilities, market, cafe, hardware])
            recurringTransactionIDs.formUnion([paycheck.id, rent.id, utilities.id])
        }

        return BudgetSnapshot(
            institutions: [institution],
            accounts: [checking, savings, credit],
            categories: [groceries, dining, home, housing, utilities, income],
            transactions: transactions,
            recurringTransactionIDs: recurringTransactionIDs
        )
    }()
}
