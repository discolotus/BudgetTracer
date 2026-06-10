import XCTest
@testable import BudgetCore

final class BudgetSnapshotTests: XCTestCase {
    func testSummaryCalculatesIncomeSpendingAndNetCashFlow() {
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [],
            transactions: [
                BudgetTransaction(
                    id: "income",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: Date(),
                    merchantName: "Payroll",
                    amount: .dollars(2500)
                ),
                BudgetTransaction(
                    id: "expense",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: Date(),
                    merchantName: "Market",
                    amount: .dollars(-175)
                )
            ],
            recurringTransactionIDs: []
        )

        XCTAssertEqual(snapshot.monthlyIncome, .dollars(2500))
        XCTAssertEqual(snapshot.monthlySpending, .dollars(175))
        XCTAssertEqual(snapshot.netCashFlow, .dollars(2325))
    }

    func testSpendingByCategorySortsLargestFirst() {
        let groceries = BudgetCategory(id: "groceries", name: "Groceries")
        let dining = BudgetCategory(id: "dining", name: "Dining")
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [groceries, dining],
            transactions: [
                BudgetTransaction(
                    id: "a",
                    accountID: "checking",
                    categoryID: groceries.id,
                    postedAt: Date(),
                    merchantName: "Market",
                    amount: .dollars(-125)
                ),
                BudgetTransaction(
                    id: "b",
                    accountID: "checking",
                    categoryID: dining.id,
                    postedAt: Date(),
                    merchantName: "Cafe",
                    amount: .dollars(-40)
                )
            ],
            recurringTransactionIDs: []
        )

        XCTAssertEqual(snapshot.spendingByCategory().map(\.categoryID), [groceries.id, dining.id])
    }

    func testNormalizedMonthlyCashFlowSpreadsSelectedRecurringTransactionsAcrossMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let paycheckDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5)))
        let marketDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [
                FinancialAccount(
                    id: "checking",
                    institutionID: "bank",
                    name: "Checking",
                    kind: .checking,
                    currentBalance: .dollars(1000)
                )
            ],
            categories: [],
            transactions: [
                BudgetTransaction(
                    id: "paycheck",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: paycheckDate,
                    merchantName: "Payroll",
                    amount: .dollars(3000)
                ),
                BudgetTransaction(
                    id: "market",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: marketDate,
                    merchantName: "Market",
                    amount: .dollars(-90)
                )
            ],
            recurringTransactionIDs: ["paycheck"]
        )

        let points = snapshot.normalizedMonthlyCashFlow(containing: month, calendar: calendar)

        XCTAssertEqual(points.count, 30)
        XCTAssertEqual(points.first?.dailyNet, .dollars(100))
        XCTAssertEqual(points[8].dailyNet, .dollars(100))
        XCTAssertEqual(points[9].dailyNet, .dollars(10))
        XCTAssertEqual(points.last?.runningCashBalance, .dollars(3910))
    }

    func testNormalizedMonthlyCashFlowExcludesInvestmentsAndMoneyMarketFromCashSeries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let spendDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 3)))
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [
                FinancialAccount(
                    id: "checking",
                    institutionID: "bank",
                    name: "Checking",
                    kind: .checking,
                    currentBalance: .dollars(1000)
                ),
                FinancialAccount(
                    id: "savings",
                    institutionID: "bank",
                    name: "Savings",
                    kind: .savings,
                    plaidType: "depository",
                    plaidSubtype: "savings",
                    currentBalance: .dollars(200)
                ),
                FinancialAccount(
                    id: "money-market",
                    institutionID: "bank",
                    name: "Money Market",
                    kind: .savings,
                    plaidType: "depository",
                    plaidSubtype: "money market",
                    currentBalance: .dollars(5000)
                ),
                FinancialAccount(
                    id: "investment",
                    institutionID: "bank",
                    name: "Investment",
                    kind: .investment,
                    currentBalance: .dollars(9000)
                ),
                FinancialAccount(
                    id: "credit",
                    institutionID: "bank",
                    name: "Credit",
                    kind: .creditCard,
                    currentBalance: .dollars(100)
                )
            ],
            categories: [],
            transactions: [
                BudgetTransaction(
                    id: "checking-spend",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: spendDate,
                    merchantName: "Market",
                    amount: .dollars(-10)
                ),
                BudgetTransaction(
                    id: "money-market-interest",
                    accountID: "money-market",
                    categoryID: nil,
                    postedAt: spendDate,
                    merchantName: "Money Market Interest",
                    amount: .dollars(100)
                ),
                BudgetTransaction(
                    id: "investment-income",
                    accountID: "investment",
                    categoryID: nil,
                    postedAt: spendDate,
                    merchantName: "Investment Income",
                    amount: .dollars(100)
                ),
                BudgetTransaction(
                    id: "credit-spend",
                    accountID: "credit",
                    categoryID: nil,
                    postedAt: spendDate,
                    merchantName: "Card Spend",
                    amount: .dollars(-20)
                )
            ]
        )

        let points = snapshot.normalizedMonthlyCashFlow(containing: month, calendar: calendar)

        XCTAssertEqual(points.first?.runningCashBalance, .dollars(1200))
        XCTAssertEqual(points[2].runningCashBalance, .dollars(1190))
        XCTAssertEqual(points[2].runningCreditDebt, .dollars(120))
        XCTAssertEqual(points[2].runningCashMinusCreditDebt, .dollars(1070))
    }

    func testNormalizedMonthlySpendingCumulatesRecurringExpensesAndMarksOriginalPostingDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let rentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 3)))
        let paycheckDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5)))
        let marketDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let interestDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [
                FinancialAccount(
                    id: "checking",
                    institutionID: "bank",
                    name: "Checking",
                    kind: .checking,
                    currentBalance: .dollars(1000)
                )
            ],
            categories: [],
            transactions: [
                BudgetTransaction(
                    id: "rent",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: rentDate,
                    merchantName: "Rent",
                    amount: .dollars(-3000)
                ),
                BudgetTransaction(
                    id: "paycheck",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: paycheckDate,
                    merchantName: "Payroll",
                    amount: .dollars(3000)
                ),
                BudgetTransaction(
                    id: "market",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: marketDate,
                    merchantName: "Market",
                    amount: .dollars(-90)
                ),
                BudgetTransaction(
                    id: "interest",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: interestDate,
                    merchantName: "Interest",
                    amount: .dollars(30)
                )
            ],
            recurringTransactionIDs: ["rent", "paycheck"]
        )

        let points = snapshot.normalizedMonthlySpending(containing: month, calendar: calendar)

        XCTAssertEqual(points.count, 30)
        XCTAssertEqual(points.first?.normalizedSpending, .dollars(100))
        XCTAssertEqual(points.first?.normalizedIncome, .dollars(100))
        XCTAssertEqual(points.first?.cumulativeNormalizedSpending, .dollars(100))
        XCTAssertEqual(points.first?.cumulativeNormalizedIncome, .dollars(100))
        XCTAssertEqual(points[2].actualSpending, .dollars(3000))
        XCTAssertEqual(points[2].averagedTransactionMarkers.map(\.merchantName), ["Rent"])
        XCTAssertEqual(points[9].normalizedSpending, .dollars(190))
        XCTAssertEqual(points[9].cumulativeNormalizedSpending, .dollars(1090))
        XCTAssertEqual(points[14].actualIncome, .dollars(30))
        XCTAssertEqual(points[14].normalizedIncome, .dollars(130))
        XCTAssertEqual(points[14].cumulativeNormalizedIncome, .dollars(1530))
        XCTAssertEqual(points.last?.cumulativeNormalizedSpending, .dollars(3090))
        XCTAssertEqual(points.last?.cumulativeNormalizedIncome, .dollars(3030))
    }

    func testCumulativeTransactionSpendingUsesTransactionDateTimesAndFlagsAveragedTransactions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4)))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9, minute: 30)))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 18, minute: 45)))
        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 8)))
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [
                FinancialAccount(
                    id: "checking",
                    institutionID: "bank",
                    name: "Checking",
                    kind: .checking,
                    currentBalance: .dollars(1000)
                )
            ],
            categories: [],
            transactions: [
                BudgetTransaction(
                    id: "evening",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: day,
                    occurredAt: evening,
                    merchantName: "Dinner",
                    amount: .dollars(-60)
                ),
                BudgetTransaction(
                    id: "morning",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: day,
                    occurredAt: morning,
                    merchantName: "Coffee",
                    amount: .dollars(-10)
                ),
                BudgetTransaction(
                    id: "rent",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: nextDay,
                    occurredAt: nextDay,
                    merchantName: "Rent",
                    amount: .dollars(-1000)
                )
            ],
            recurringTransactionIDs: ["rent"]
        )

        let points = snapshot.cumulativeTransactionSpending(containing: month, calendar: calendar)

        XCTAssertEqual(points.map(\.transactionID), ["morning", "evening", "rent"])
        XCTAssertEqual(points.map(\.cumulativeSpending), [.dollars(10), .dollars(70), .dollars(1070)])
        XCTAssertEqual(points.map(\.isAveraged), [false, false, true])
    }

    func testProjectionCutoffStopsCurrentMonthSeriesAndFutureTransactions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let cutoff = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 12)))
        let rentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 3)))
        let currentSpendDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 8)))
        let futureSpendDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 8)))
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [
                FinancialAccount(
                    id: "checking",
                    institutionID: "bank",
                    name: "Checking",
                    kind: .checking,
                    currentBalance: .dollars(1000)
                )
            ],
            categories: [],
            transactions: [
                BudgetTransaction(
                    id: "rent",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: rentDate,
                    occurredAt: rentDate,
                    merchantName: "Rent",
                    amount: .dollars(-3000)
                ),
                BudgetTransaction(
                    id: "current",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: currentSpendDate,
                    occurredAt: currentSpendDate,
                    merchantName: "Current",
                    amount: .dollars(-50)
                ),
                BudgetTransaction(
                    id: "future",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: futureSpendDate,
                    occurredAt: futureSpendDate,
                    merchantName: "Future",
                    amount: .dollars(-75)
                )
            ],
            recurringTransactionIDs: ["rent"]
        )

        let cashFlow = snapshot.normalizedMonthlyCashFlow(containing: month, calendar: calendar, through: cutoff)
        let spending = snapshot.normalizedMonthlySpending(containing: month, calendar: calendar, through: cutoff)
        let transactions = snapshot.cumulativeTransactionSpending(containing: month, calendar: calendar, through: cutoff)

        XCTAssertEqual(cashFlow.count, 10)
        XCTAssertEqual(spending.count, 10)
        XCTAssertEqual(spending.last?.date, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))))
        XCTAssertEqual(spending.last?.cumulativeNormalizedSpending, .dollars(1050))
        XCTAssertEqual(transactions.map(\.transactionID), ["rent", "current"])
    }

    func testAvailableTransactionMonthsAreUniqueAndSorted() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let march = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 13)))
        let may = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
        let june = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [],
            transactions: [
                BudgetTransaction(
                    id: "may-1",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: may,
                    merchantName: "May",
                    amount: .dollars(-10)
                ),
                BudgetTransaction(
                    id: "march",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: march,
                    merchantName: "March",
                    amount: .dollars(-10)
                ),
                BudgetTransaction(
                    id: "may-2",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: may,
                    merchantName: "May Again",
                    amount: .dollars(10)
                ),
                BudgetTransaction(
                    id: "june",
                    accountID: "checking",
                    categoryID: nil,
                    postedAt: june,
                    merchantName: "June",
                    amount: .dollars(-10)
                )
            ]
        )

        let months = snapshot.availableTransactionMonths(calendar: calendar)

        XCTAssertEqual(
            months,
            [
                try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))),
                try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))),
                try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
            ]
        )
    }
}
