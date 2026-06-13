import BudgetCore
@testable import BudgetTracerSharedUI
import XCTest

final class RecurringSeriesTests: XCTestCase {
    private func transaction(id: String, merchant: String, day: Int, amount: Int64) -> BudgetTransaction {
        BudgetTransaction(
            id: id,
            accountID: "acct",
            categoryID: nil,
            postedAt: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
            merchantName: merchant,
            amount: Money(minorUnits: amount)
        )
    }

    func testCollapsesDuplicateMerchantsIntoOneSeriesWithAllTimeHistory() {
        let all = [
            transaction(id: "rent-1", merchant: "Rent", day: 10, amount: -265_000),
            transaction(id: "rent-2", merchant: "Rent", day: 40, amount: -265_000),
            transaction(id: "rent-3", merchant: "Rent", day: 70, amount: -265_000),
            transaction(id: "cafe-1", merchant: "Corner Cafe", day: 41, amount: -1_200)
        ]
        // Window shows only the two most recent rent occurrences.
        let windowRecurring = [all[1], all[2]]

        let series = RecurringSeries.build(windowRecurring: windowRecurring, allTransactions: all)

        XCTAssertEqual(series.count, 1)
        let rent = try? XCTUnwrap(series.first)
        XCTAssertEqual(rent?.merchantName, "Rent")
        // Full all-time history, newest first, even though the window had only two.
        XCTAssertEqual(rent?.transactions.map(\.id), ["rent-3", "rent-2", "rent-1"])
        XCTAssertEqual(rent?.occurrenceCount, 3)
        XCTAssertEqual(Set(rent?.ids ?? []), ["rent-1", "rent-2", "rent-3"])
    }

    func testGroupsCaseAndWhitespaceInsensitively() {
        let all = [
            transaction(id: "a", merchant: "Utility Provider", day: 10, amount: -100),
            transaction(id: "b", merchant: "  utility provider ", day: 40, amount: -110)
        ]

        let series = RecurringSeries.build(windowRecurring: all, allTransactions: all)

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series.first?.occurrenceCount, 2)
    }
}
