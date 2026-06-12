import Foundation

struct BalanceAnalysisWindow: Hashable {
    var interval: DateInterval
    var previousInterval: DateInterval?
    var visibleMonthCount: Int

    static func make(
        analysisDate: Date,
        requestedMonthCount: Int,
        availableMonths: [Date],
        currentDate: Date = Date(),
        calendar: Calendar = .current
    ) -> BalanceAnalysisWindow {
        guard let analysisMonthInterval = calendar.dateInterval(of: .month, for: analysisDate) else {
            let fallbackEnd = analysisDate.addingTimeInterval(1)
            return BalanceAnalysisWindow(
                interval: DateInterval(start: analysisDate, end: fallbackEnd),
                previousInterval: nil,
                visibleMonthCount: 1
            )
        }

        let safeRequestedMonthCount = max(requestedMonthCount, 1)
        let requestedStart = calendar.date(
            byAdding: .month,
            value: 1 - safeRequestedMonthCount,
            to: analysisMonthInterval.start
        ) ?? analysisMonthInterval.start
        let earliestAvailableMonth = availableMonths
            .compactMap { calendar.dateInterval(of: .month, for: $0)?.start }
            .min()
        let clampedEarliestMonth = earliestAvailableMonth.map { min($0, analysisMonthInterval.start) }
        let intervalStart = max(requestedStart, clampedEarliestMonth ?? requestedStart)
        let intervalEnd = analysisIntervalEnd(
            for: analysisMonthInterval,
            currentDate: currentDate,
            calendar: calendar
        )
        let interval = DateInterval(
            start: intervalStart,
            end: max(intervalEnd, intervalStart.addingTimeInterval(1))
        )
        let visibleMonthCount = max(
            1,
            min(
                safeRequestedMonthCount,
                (calendar.dateComponents([.month], from: intervalStart, to: analysisMonthInterval.start).month ?? 0) + 1
            )
        )
        let previousStart = calendar.date(byAdding: .month, value: -visibleMonthCount, to: intervalStart)
        let previousInterval = previousStart.map { DateInterval(start: $0, end: intervalStart) }

        return BalanceAnalysisWindow(
            interval: interval,
            previousInterval: previousInterval,
            visibleMonthCount: visibleMonthCount
        )
    }

    private static func analysisIntervalEnd(
        for analysisMonthInterval: DateInterval,
        currentDate: Date,
        calendar: Calendar
    ) -> Date {
        guard calendar.isDate(currentDate, equalTo: analysisMonthInterval.start, toGranularity: .month),
              let dayAfterCutoff = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: currentDate)
              ) else {
            return analysisMonthInterval.end
        }

        return min(dayAfterCutoff, analysisMonthInterval.end)
    }
}
