import BudgetCore
import SwiftUI

struct NormalizedMonthView: View {
    var snapshot: BudgetSnapshot
    var setRecurring: (BudgetTransaction.ID, Bool) -> Void

    @SceneStorage("BudgetTracer.normalizedMonth.selectedMonthTimestamp")
    private var selectedMonthTimestamp: Double = 0

    @SceneStorage("BudgetTracer.normalizedMonth.transactionSearchText")
    private var transactionSearchText = ""

    private var analysisDate: Date {
        selectedMonth ?? defaultAnalysisMonth
    }

    private var points: [NormalizedCashFlowPoint] {
        snapshot.normalizedMonthlyCashFlow(containing: analysisDate, through: currentMonthCutoff)
    }

    private var previousMonthPoints: [NormalizedCashFlowPoint] {
        guard let previousMonth else {
            return []
        }

        return snapshot.normalizedMonthlyCashFlow(containing: previousMonth)
    }

    private var spendingPoints: [NormalizedSpendingPoint] {
        snapshot.normalizedMonthlySpending(containing: analysisDate, through: currentMonthCutoff)
    }

    private var previousMonthSpendingPoints: [NormalizedSpendingPoint] {
        guard let previousMonth else {
            return []
        }

        return snapshot.normalizedMonthlySpending(containing: previousMonth)
    }

    private var transactionTimelinePoints: [CumulativeTransactionSpendingPoint] {
        snapshot.cumulativeTransactionSpending(containing: analysisDate, through: currentMonthCutoff)
    }

    private var analysisMonthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: analysisDate)
            ?? DateInterval(start: analysisDate, duration: 1)
    }

    private var previousMonth: Date? {
        guard let previous = Calendar.current.date(byAdding: .month, value: -1, to: analysisDate) else {
            return nil
        }

        return availableMonths.first { month in
            Calendar.current.isDate(month, equalTo: previous, toGranularity: .month)
        }
    }

    private var previousMonthInterval: DateInterval? {
        previousMonth.flatMap { Calendar.current.dateInterval(of: .month, for: $0) }
    }

    private var currentMonthCutoff: Date? {
        Calendar.current.isDate(analysisDate, equalTo: Date(), toGranularity: .month) ? Date() : nil
    }

    private var transactionDateInterval: DateInterval {
        guard let currentMonthCutoff,
              analysisMonthInterval.contains(currentMonthCutoff),
              let dayAfterCutoff = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: Calendar.current.startOfDay(for: currentMonthCutoff)
              ) else {
            return analysisMonthInterval
        }

        return DateInterval(start: analysisMonthInterval.start, end: min(dayAfterCutoff, analysisMonthInterval.end))
    }

    private var availableMonths: [Date] {
        snapshot.availableTransactionMonths()
    }

    private var defaultAnalysisMonth: Date {
        let date = snapshot.normalizedMonthlyAnalysisDate()
        return Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    private var selectedMonth: Date? {
        guard selectedMonthTimestamp > 0 else {
            return nil
        }

        let selectedDate = Date(timeIntervalSince1970: selectedMonthTimestamp)
        return availableMonths.first { month in
            Calendar.current.isDate(month, equalTo: selectedDate, toGranularity: .month)
        }
    }

    private var selectedMonthIndex: Int? {
        availableMonths.firstIndex { month in
            Calendar.current.isDate(month, equalTo: analysisDate, toGranularity: .month)
        }
    }

    private var selectableTransactions: [BudgetTransaction] {
        snapshot.transactions
            .filter { transaction in
                transaction.amount.minorUnits != 0 && transactionDateInterval.contains(transaction.postedAt)
            }
            .filter { TransactionSearch.matches($0, query: transactionSearchText) }
            .sorted { lhs, rhs in
                if lhs.postedAt != rhs.postedAt {
                    return lhs.postedAt < rhs.postedAt
                }

                if lhs.merchantName != rhs.merchantName {
                    return lhs.merchantName < rhs.merchantName
                }

                return lhs.id < rhs.id
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Normalized Cash Flow")
                            .font(.headline)

                        Spacer()

                        MonthSelector(
                            months: availableMonths,
                            selectedMonth: analysisDate,
                            selectMonth: selectMonth,
                            selectPreviousMonth: selectPreviousMonth,
                            selectNextMonth: selectNextMonth
                        )
                    }

                    Text("Showing \(analysisDate.formatted(.dateTime.month(.wide).year())). Selected regular transactions are averaged across every day of the month. Irregular transactions remain on the day they posted.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                CashFlowPlot(
                    points: points,
                    previousMonthPoints: previousMonthPoints,
                    monthInterval: analysisMonthInterval,
                    previousMonthInterval: previousMonthInterval
                )
                    .frame(height: 260)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                DailySpendingPlot(
                    points: spendingPoints,
                    previousMonthPoints: previousMonthSpendingPoints,
                    monthInterval: analysisMonthInterval,
                    previousMonthInterval: previousMonthInterval
                )
                    .frame(height: 260)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                TransactionTimeSpendingPlot(
                    points: transactionTimelinePoints,
                    monthInterval: analysisMonthInterval
                )
                .frame(height: 260)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 16) {
                    SummaryPill(title: "Regular items", value: "\(snapshot.recurringTransactionIDs.count)")
                    SummaryPill(title: "Ending cash", value: (points.last?.runningCashBalance ?? snapshot.totalCash).formatted)
                    SummaryPill(title: "Ending card debt", value: (points.last?.runningCreditDebt ?? snapshot.creditDebt).formatted)
                    SummaryPill(title: "Cash after cards", value: (points.last?.runningCashMinusCreditDebt ?? (snapshot.totalCash - snapshot.creditDebt)).formatted)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Regular Monthly Transactions")
                            .font(.headline)

                        Spacer()

                        TransactionSearchField(text: $transactionSearchText)
                    }

                    VStack(spacing: 0) {
                        if selectableTransactions.isEmpty {
                            Text(transactionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No transactions in this range." : "No matching transactions.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        } else {
                            ForEach<[BudgetTransaction], BudgetTransaction.ID, RecurringTransactionRow>(selectableTransactions) { transaction in
                                RecurringTransactionRow(
                                    transaction: transaction,
                                    isRecurring: snapshot.recurringTransactionIDs.contains(transaction.id),
                                    setRecurring: setRecurring
                                )
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
        .onAppear {
            if selectedMonthTimestamp == 0 {
                selectMonth(defaultAnalysisMonth)
            }
        }
        .onChange(of: availableMonths) { _, months in
            guard !months.isEmpty else {
                selectedMonthTimestamp = 0
                return
            }

            if selectedMonth == nil {
                selectMonth(defaultAnalysisMonth)
            }
        }
    }

    private var dailyAverage: Money {
        guard !points.isEmpty else {
            return Money(minorUnits: 0)
        }

        let total = points.map(\.dailyNet.minorUnits).reduce(Int64(0), +)
        return Money(minorUnits: total / Int64(points.count))
    }

    private func selectMonth(_ month: Date) {
        let monthStart = Calendar.current.dateInterval(of: .month, for: month)?.start ?? month
        selectedMonthTimestamp = monthStart.timeIntervalSince1970
    }

    private func selectPreviousMonth() {
        guard let index = selectedMonthIndex, index > availableMonths.startIndex else {
            return
        }

        selectMonth(availableMonths[index - 1])
    }

    private func selectNextMonth() {
        guard let index = selectedMonthIndex, index < availableMonths.index(before: availableMonths.endIndex) else {
            return
        }

        selectMonth(availableMonths[index + 1])
    }
}

private struct TransactionSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MonthSelector: View {
    var months: [Date]
    var selectedMonth: Date
    var selectMonth: (Date) -> Void
    var selectPreviousMonth: () -> Void
    var selectNextMonth: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: selectPreviousMonth) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!canMovePrevious)
            .help("Previous month")

            Picker("Month", selection: selection) {
                ForEach(months, id: \.self) { month in
                    Text(month.formatted(.dateTime.month(.abbreviated).year()))
                        .tag(month.timeIntervalSince1970)
                }
            }
            .labelsHidden()
            .frame(width: 128)

            Button(action: selectNextMonth) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveNext)
            .help("Next month")
        }
    }

    private var selection: Binding<Double> {
        Binding(
            get: { normalized(selectedMonth).timeIntervalSince1970 },
            set: { timestamp in selectMonth(Date(timeIntervalSince1970: timestamp)) }
        )
    }

    private var selectedIndex: Int? {
        months.firstIndex { month in
            Calendar.current.isDate(month, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    private var canMovePrevious: Bool {
        guard let selectedIndex else {
            return false
        }

        return selectedIndex > months.startIndex
    }

    private var canMoveNext: Bool {
        guard let selectedIndex else {
            return false
        }

        return selectedIndex < months.index(before: months.endIndex)
    }

    private func normalized(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }
}

private struct TransactionTimeSpendingPlot: View {
    var points: [CumulativeTransactionSpendingPoint]
    var monthInterval: DateInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cumulative Spending by Transaction Time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text((points.last?.cumulativeSpending ?? Money(minorUnits: 0)).formatted)
                    .font(.subheadline.monospacedDigit())
            }

            HStack(spacing: 14) {
                LegendItem(color: .orange, title: "Transaction")
                LegendItem(color: .pink, title: "Averaged transaction")
                Spacer()
            }

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                        .offset(y: proxy.size.height / -2)

                    Path { path in
                        for (index, point) in points.enumerated() {
                            let location = plotLocation(for: point, in: proxy.size)
                            if index == 0 {
                                path.move(to: location)
                            } else {
                                path.addLine(to: location)
                            }
                        }
                    }
                    .stroke(.orange, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))

                    ForEach(points) { point in
                        if point.isAveraged {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.pink)
                                .frame(width: 10, height: 10)
                                .rotationEffect(.degrees(45))
                                .position(plotLocation(for: point, in: proxy.size))
                                .help(helpText(for: point))
                        } else {
                            Circle()
                                .fill(.orange)
                                .frame(width: 6, height: 6)
                                .position(plotLocation(for: point, in: proxy.size))
                                .help(helpText(for: point))
                        }
                    }

                    SparseYAxisLabels(labels: yAxisLabels)
                        .padding(.trailing, 4)
                }
            }

            HStack {
                Text(monthInterval.start.formatted(.dateTime.month(.abbreviated).day()))
                Spacer()
                Text(monthInterval.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var spendingCeiling: Int64 {
        max(points.last?.cumulativeSpending.minorUnits ?? 1, 1)
    }

    private var yAxisLabels: [String] {
        [
            Money(minorUnits: spendingCeiling).formatted,
            Money(minorUnits: spendingCeiling / 2).formatted,
            Money(minorUnits: 0).formatted
        ]
    }

    private func plotLocation(for point: CumulativeTransactionSpendingPoint, in size: CGSize) -> CGPoint {
        let elapsed = point.occurredAt.timeIntervalSince(monthInterval.start)
        let xRatio = min(max(elapsed / monthInterval.duration, 0), 1)
        let yRatio = Double(point.cumulativeSpending.minorUnits) / Double(spendingCeiling)

        return CGPoint(
            x: size.width * CGFloat(xRatio),
            y: size.height - (size.height * CGFloat(yRatio))
        )
    }

    private func helpText(for point: CumulativeTransactionSpendingPoint) -> String {
        "\(point.merchantName)\n\(point.occurredAt.formatted(date: .abbreviated, time: .shortened))\n\(point.amount.formatted)"
    }
}

private struct DailySpendingPlot: View {
    var points: [NormalizedSpendingPoint]
    var previousMonthPoints: [NormalizedSpendingPoint]
    var monthInterval: DateInterval
    var previousMonthInterval: DateInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cumulative Normal Spending and Income")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(totalCumulativeNormalizedSpending.formatted) / \(totalCumulativeNormalizedIncome.formatted)")
                    .font(.subheadline.monospacedDigit())
            }

            HStack(spacing: 14) {
                LegendItem(color: .orange, title: "Cumulative spending")
                LegendItem(color: .green, title: "Cumulative income")
                LegendItem(color: .orange.opacity(0.45), title: "Previous month")
                LegendItem(color: .pink, title: "Averaged transaction")
                Spacer()
            }

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                        .offset(y: proxy.size.height / -2)

                    if let previousMonthInterval {
                        Path { path in
                            for index in previousMonthPoints.indices {
                                let location = plotLocation(
                                    value: previousMonthPoints[index].cumulativeNormalizedSpending.minorUnits,
                                    date: previousMonthPoints[index].date,
                                    sourceMonthInterval: previousMonthInterval,
                                    in: proxy.size
                                )
                                if index == 0 {
                                    path.move(to: location)
                                } else {
                                    path.addLine(to: location)
                                }
                            }
                        }
                        .stroke(
                            .orange.opacity(0.42),
                            style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [6, 5])
                        )
                    }

                    ForEach(points.indices, id: \.self) { index in
                        let point = points[index]
                        let height = barHeight(for: point.cumulativeNormalizedSpending.minorUnits, in: proxy.size)
                        let width = barWidth(in: proxy.size)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.orange.opacity(0.22))
                            .frame(width: width, height: height)
                            .position(
                                x: xLocation(for: point.date, in: proxy.size),
                                y: proxy.size.height - height / 2
                            )
                    }

                    Path { path in
                        for index in points.indices {
                            let location = plotLocation(
                                value: points[index].cumulativeNormalizedSpending.minorUnits,
                                date: points[index].date,
                                sourceMonthInterval: monthInterval,
                                in: proxy.size
                            )
                            if index == 0 {
                                path.move(to: location)
                            } else {
                                path.addLine(to: location)
                            }
                        }
                    }
                    .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineJoin: .round))

                    Path { path in
                        for index in points.indices {
                            let location = plotLocation(
                                value: points[index].cumulativeNormalizedIncome.minorUnits,
                                date: points[index].date,
                                sourceMonthInterval: monthInterval,
                                in: proxy.size
                            )
                            if index == 0 {
                                path.move(to: location)
                            } else {
                                path.addLine(to: location)
                            }
                        }
                    }
                    .stroke(.green, style: StrokeStyle(lineWidth: 3, lineJoin: .round))

                    ForEach(points.indices, id: \.self) { index in
                        let point = points[index]
                        if !point.averagedTransactionMarkers.isEmpty {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.pink)
                                .frame(width: 9, height: 9)
                                .rotationEffect(.degrees(45))
                                .position(
                                    plotLocation(
                                        value: point.cumulativeNormalizedSpending.minorUnits,
                                        date: point.date,
                                        sourceMonthInterval: monthInterval,
                                        in: proxy.size
                                    )
                                )
                                .help(markerHelp(for: point))
                        }
                    }

                    SparseYAxisLabels(labels: yAxisLabels)
                        .padding(.trailing, 4)
                }
            }

            HStack {
                Text(monthInterval.start.formatted(.dateTime.month(.abbreviated).day()))
                Spacer()
                Text(monthInterval.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var totalCumulativeNormalizedSpending: Money {
        points.last?.cumulativeNormalizedSpending ?? Money(minorUnits: 0)
    }

    private var totalCumulativeNormalizedIncome: Money {
        points.last?.cumulativeNormalizedIncome ?? Money(minorUnits: 0)
    }

    private var spendingCeiling: Int64 {
        let maxValue = (points + previousMonthPoints)
            .flatMap {
                [
                    $0.cumulativeNormalizedSpending.minorUnits,
                    $0.cumulativeNormalizedIncome.minorUnits
                ]
            }
            .max() ?? 1

        return max(maxValue, 1)
    }

    private var yAxisLabels: [String] {
        [
            Money(minorUnits: spendingCeiling).formatted,
            Money(minorUnits: spendingCeiling / 2).formatted,
            Money(minorUnits: 0).formatted
        ]
    }

    private func xLocation(for date: Date, in size: CGSize) -> CGFloat {
        let elapsed = date.timeIntervalSince(monthInterval.start)
        let xRatio = min(max(elapsed / monthInterval.duration, 0), 1)

        return size.width * CGFloat(xRatio)
    }

    private func barWidth(in size: CGSize) -> CGFloat {
        let dayCount = Calendar.current.dateComponents([.day], from: monthInterval.start, to: monthInterval.end).day ?? points.count
        guard dayCount > 0 else {
            return 0
        }

        return max(3, min(14, size.width / CGFloat(dayCount) * 0.55))
    }

    private func barHeight(for value: Int64, in size: CGSize) -> CGFloat {
        size.height * CGFloat(Double(value) / Double(spendingCeiling))
    }

    private func plotLocation(
        value: Int64,
        date: Date,
        sourceMonthInterval: DateInterval,
        in size: CGSize
    ) -> CGPoint {
        let x = xLocation(for: date, sourceMonthInterval: sourceMonthInterval, in: size)
        let ratio = Double(value) / Double(spendingCeiling)
        let y = size.height - (size.height * CGFloat(ratio))

        return CGPoint(x: x, y: y)
    }

    private func xLocation(for date: Date, sourceMonthInterval: DateInterval, in size: CGSize) -> CGFloat {
        let elapsed = date.timeIntervalSince(sourceMonthInterval.start)
        let xRatio = min(max(elapsed / sourceMonthInterval.duration, 0), 1)

        return size.width * CGFloat(xRatio)
    }

    private func markerHelp(for point: NormalizedSpendingPoint) -> String {
        point.averagedTransactionMarkers
            .map { "\($0.merchantName): \($0.amount.formatted)" }
            .joined(separator: "\n")
    }
}

private struct CashFlowPlot: View {
    var points: [NormalizedCashFlowPoint]
    var previousMonthPoints: [NormalizedCashFlowPoint]
    var monthInterval: DateInterval
    var previousMonthInterval: DateInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Projected Cash and Card-Adjusted Balance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = points.last {
                    Text(last.runningCashMinusCreditDebt.formatted)
                        .font(.subheadline.monospacedDigit())
                }
            }

            HStack(spacing: 14) {
                LegendItem(color: .blue, title: "Cash")
                LegendItem(color: .purple, title: "Cash minus card debt")
                LegendItem(color: .purple.opacity(0.45), title: "Previous month")
                Spacer()
            }

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                        .offset(y: proxy.size.height / -2)

                    if let previousMonthInterval {
                        Path { path in
                            for index in previousMonthPoints.indices {
                                let location = plotLocation(
                                    value: previousMonthPoints[index].runningCashMinusCreditDebt.minorUnits,
                                    date: previousMonthPoints[index].date,
                                    sourceMonthInterval: previousMonthInterval,
                                    in: proxy.size
                                )
                                if index == 0 {
                                    path.move(to: location)
                                } else {
                                    path.addLine(to: location)
                                }
                            }
                        }
                        .stroke(
                            .purple.opacity(0.42),
                            style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [6, 5])
                        )
                    }

                    Path { path in
                        for index in points.indices {
                            let location = plotLocation(
                                value: points[index].runningCashBalance.minorUnits,
                                date: points[index].date,
                                sourceMonthInterval: monthInterval,
                                in: proxy.size
                            )
                            if index == 0 {
                                path.move(to: location)
                            } else {
                                path.addLine(to: location)
                            }
                        }
                    }
                    .stroke(.blue, style: StrokeStyle(lineWidth: 3, lineJoin: .round))

                    Path { path in
                        for index in points.indices {
                            let location = plotLocation(
                                value: points[index].runningCashMinusCreditDebt.minorUnits,
                                date: points[index].date,
                                sourceMonthInterval: monthInterval,
                                in: proxy.size
                            )
                            if index == 0 {
                                path.move(to: location)
                            } else {
                                path.addLine(to: location)
                            }
                        }
                    }
                    .stroke(.purple, style: StrokeStyle(lineWidth: 3, lineJoin: .round))

                    ForEach(points.indices, id: \.self) { index in
                        let point = points[index]
                        let location = plotLocation(
                            value: point.runningCashMinusCreditDebt.minorUnits,
                            date: point.date,
                            sourceMonthInterval: monthInterval,
                            in: proxy.size
                        )

                        Circle()
                            .fill(point.dailyNet.isExpense ? Color.orange : Color.green)
                            .frame(width: 5, height: 5)
                            .position(location)
                    }

                    SparseYAxisLabels(labels: yAxisLabels)
                        .padding(.trailing, 4)
                }
            }

            HStack {
                Text(monthInterval.start.formatted(.dateTime.month(.abbreviated).day()))
                Spacer()
                Text(monthInterval.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var balanceRange: ClosedRange<Int64> {
        let balances = points.flatMap {
            [
                $0.runningCashBalance.minorUnits,
                $0.runningCashMinusCreditDebt.minorUnits
            ]
        } + previousMonthPoints.map(\.runningCashMinusCreditDebt.minorUnits)
        let minValue = balances.min() ?? 0
        let maxValue = balances.max() ?? 1

        if minValue == maxValue {
            return (minValue - 1)...(maxValue + 1)
        }

        return minValue...maxValue
    }

    private var yAxisLabels: [String] {
        let range = balanceRange
        let midpoint = range.lowerBound + ((range.upperBound - range.lowerBound) / 2)

        return [
            Money(minorUnits: range.upperBound).formatted,
            Money(minorUnits: midpoint).formatted,
            Money(minorUnits: range.lowerBound).formatted
        ]
    }

    private func plotLocation(
        value: Int64,
        date: Date,
        sourceMonthInterval: DateInterval,
        in size: CGSize
    ) -> CGPoint {
        let elapsed = date.timeIntervalSince(sourceMonthInterval.start)
        let xRatio = min(max(elapsed / sourceMonthInterval.duration, 0), 1)
        let x = size.width * CGFloat(xRatio)
        let range = balanceRange
        let denominator = Double(range.upperBound - range.lowerBound)
        let ratio = Double(value - range.lowerBound) / denominator
        let y = size.height - (size.height * CGFloat(ratio))

        return CGPoint(x: x, y: y)
    }
}

private struct SparseYAxisLabels: View {
    var labels: [String]

    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing) {
                ForEach(labels.indices, id: \.self) { index in
                    Text(labels[index])

                    if index < labels.index(before: labels.endIndex) {
                        Spacer()
                    }
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .allowsHitTesting(false)
    }
}

private struct LegendItem: View {
    var color: Color
    var title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct SummaryPill: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RecurringTransactionRow: View {
    var transaction: BudgetTransaction
    var isRecurring: Bool
    var setRecurring: (BudgetTransaction.ID, Bool) -> Void

    var body: some View {
        Toggle(isOn: binding) {
            HStack(spacing: 12) {
                Image(systemName: transaction.amount.isIncome ? "arrow.down.circle" : "arrow.up.circle")
                    .foregroundStyle(transaction.amount.isIncome ? Color.green : Color.orange)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.merchantName)
                    Text(transaction.postedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(transaction.amount.formatted)
                    .font(.body.monospacedDigit())
            }
        }
        .budgetTracerRecurringToggleStyle()
        .padding()
        Divider()
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { isRecurring },
            set: { setRecurring(transaction.id, $0) }
        )
    }
}

private extension View {
    @ViewBuilder
    func budgetTracerRecurringToggleStyle() -> some View {
        #if os(macOS)
        self.toggleStyle(.checkbox)
        #else
        self.toggleStyle(.switch)
        #endif
    }
}
