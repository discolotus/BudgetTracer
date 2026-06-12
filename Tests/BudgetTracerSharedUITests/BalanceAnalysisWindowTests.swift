import XCTest
@testable import BudgetTracerSharedUI

final class BalanceAnalysisWindowTests: XCTestCase {
    func testRequestedRangeClampsToEarliestAvailableMonth() throws {
        let calendar = utcCalendar
        let analysisDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let currentDate = analysisDate
        let availableMonths = try [
            XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))),
            XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))),
            XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        ]

        let window = BalanceAnalysisWindow.make(
            analysisDate: analysisDate,
            requestedMonthCount: 6,
            availableMonths: availableMonths,
            currentDate: currentDate,
            calendar: calendar
        )

        XCTAssertEqual(window.interval.start, availableMonths[0])
        XCTAssertEqual(
            window.interval.end,
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11)))
        )
        XCTAssertEqual(window.visibleMonthCount, 3)
        XCTAssertEqual(
            window.previousInterval,
            DateInterval(
                start: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))),
                end: availableMonths[0]
            )
        )
    }

    func testRequestedRangeUsesFullSpanWhenAvailableDataCoversIt() throws {
        let calendar = utcCalendar
        let analysisDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let currentDate = analysisDate
        let availableMonths = try (1...6).map { month in
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: 1)))
        }

        let window = BalanceAnalysisWindow.make(
            analysisDate: analysisDate,
            requestedMonthCount: 6,
            availableMonths: availableMonths,
            currentDate: currentDate,
            calendar: calendar
        )

        XCTAssertEqual(
            window.interval,
            DateInterval(
                start: availableMonths[0],
                end: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11)))
            )
        )
        XCTAssertEqual(window.visibleMonthCount, 6)
    }

    func testLongRangesUseDistinctStartMonthsWhenAvailableDataCoversThem() throws {
        let calendar = utcCalendar
        let analysisDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let currentDate = analysisDate
        let availableMonths = try (1...12).map { month in
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2025 + (month >= 7 ? 0 : 1), month: month, day: 1)))
        }.sorted()

        let sixMonthWindow = BalanceAnalysisWindow.make(
            analysisDate: analysisDate,
            requestedMonthCount: 6,
            availableMonths: availableMonths,
            currentDate: currentDate,
            calendar: calendar
        )
        let nineMonthWindow = BalanceAnalysisWindow.make(
            analysisDate: analysisDate,
            requestedMonthCount: 9,
            availableMonths: availableMonths,
            currentDate: currentDate,
            calendar: calendar
        )
        let oneYearWindow = BalanceAnalysisWindow.make(
            analysisDate: analysisDate,
            requestedMonthCount: 12,
            availableMonths: availableMonths,
            currentDate: currentDate,
            calendar: calendar
        )

        XCTAssertEqual(sixMonthWindow.interval.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))))
        XCTAssertEqual(nineMonthWindow.interval.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 10, day: 1))))
        XCTAssertEqual(oneYearWindow.interval.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 7, day: 1))))
        XCTAssertEqual([sixMonthWindow.visibleMonthCount, nineMonthWindow.visibleMonthCount, oneYearWindow.visibleMonthCount], [6, 9, 12])
    }

    func testOneMonthRangeKeepsSelectedMonthWhenOlderDataExists() throws {
        let calendar = utcCalendar
        let analysisDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let currentDate = analysisDate
        let availableMonths = try [
            XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))),
            XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))),
            XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        ]

        let window = BalanceAnalysisWindow.make(
            analysisDate: analysisDate,
            requestedMonthCount: 1,
            availableMonths: availableMonths,
            currentDate: currentDate,
            calendar: calendar
        )

        XCTAssertEqual(
            window.interval,
            DateInterval(
                start: availableMonths[2],
                end: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11)))
            )
        )
        XCTAssertEqual(window.visibleMonthCount, 1)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
