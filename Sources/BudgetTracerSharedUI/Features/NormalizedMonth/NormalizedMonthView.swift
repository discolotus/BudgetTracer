import BudgetCore
import SwiftUI

struct NormalizedMonthView: View {
    var snapshot: BudgetSnapshot
    var connectionState: PlaidConnectionState = .connected(institutionCount: 0, lastSyncedAt: nil)
    var setRecurring: (BudgetTransaction.ID, Bool) -> Void

    @State private var didApplyLaunchState = false

    @SceneStorage("BudgetTracer.normalizedMonth.selectedMonthTimestamp")
    private var selectedMonthTimestamp: Double = 0

    @SceneStorage("BudgetTracer.normalizedMonth.transactionSearchText")
    private var transactionSearchText = ""

    @SceneStorage("BudgetTracer.normalizedMonth.cashFlowBalanceBasis")
    private var cashFlowBalanceBasisID = CashFlowBalanceBasis.accountBalances.rawValue

    @SceneStorage("BudgetTracer.normalizedMonth.dateRange")
    private var dateRangeID = BalanceDateRange.oneMonth.rawValue

    @SceneStorage("BudgetTracer.normalizedMonth.showsPreviousPeriod")
    private var showsPreviousPeriod = true

    @SceneStorage("BudgetTracer.normalizedMonth.showsCashBalance")
    private var showsCashBalance = true

    @SceneStorage("BudgetTracer.normalizedMonth.showsCreditCardDebt")
    private var showsCreditCardDebt = true

    @SceneStorage("BudgetTracer.normalizedMonth.showsCardAdjustedBalance")
    private var showsCardAdjustedBalance = true

    private var analysisDate: Date {
        selectedMonth ?? defaultAnalysisMonth
    }

    private var points: [NormalizedCashFlowPoint] {
        snapshot.normalizedCashFlow(
            in: analysisDateInterval,
            balanceBasis: cashFlowBalanceBasis,
            balanceAnchorEnd: balanceAnchorEnd
        )
    }

    private var previousMonthPoints: [NormalizedCashFlowPoint] {
        guard let previousDateInterval else {
            return []
        }

        return snapshot.normalizedCashFlow(
            in: previousDateInterval,
            balanceBasis: cashFlowBalanceBasis,
            balanceAnchorEnd: balanceAnchorEnd
        )
    }

    private var spendingPoints: [NormalizedSpendingPoint] {
        snapshot.normalizedSpending(in: analysisDateInterval)
    }

    private var previousMonthSpendingPoints: [NormalizedSpendingPoint] {
        guard let previousDateInterval else {
            return []
        }

        return snapshot.normalizedSpending(in: previousDateInterval)
    }

    private var transactionTimelinePoints: [CumulativeTransactionSpendingPoint] {
        snapshot.cumulativeTransactionSpending(in: analysisDateInterval)
    }

    private var analysisMonthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: analysisDate)
            ?? DateInterval(start: analysisDate, duration: 1)
    }

    private var analysisWindow: BalanceAnalysisWindow {
        BalanceAnalysisWindow.make(
            analysisDate: analysisDate,
            requestedMonthCount: dateRange.monthCount,
            availableMonths: availableMonths
        )
    }

    private var analysisDateInterval: DateInterval {
        analysisWindow.interval
    }

    private var balanceAnchorEnd: Date {
        let anchorDate = snapshot.lastSuccessfulSyncAt ?? Date()
        let dayAfterAnchor = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: anchorDate)
        ) ?? anchorDate

        return max(analysisDateInterval.end, dayAfterAnchor)
    }

    private var previousDateInterval: DateInterval? {
        guard let interval = analysisWindow.previousInterval else {
            return nil
        }

        guard snapshot.transactions.contains(where: { transaction in
            interval.contains(transaction.postedAt) || interval.contains(transaction.occurredAt)
        }) else {
            return nil
        }

        return interval
    }

    private var previousMonthInterval: DateInterval? {
        previousDateInterval
    }

    private var transactionDateInterval: DateInterval {
        analysisDateInterval
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

    private var cashFlowBalanceBasis: CashFlowBalanceBasis {
        CashFlowBalanceBasis(rawValue: cashFlowBalanceBasisID) ?? .accountBalances
    }

    private var dateRange: BalanceDateRange {
        BalanceDateRange(rawValue: dateRangeID) ?? .oneMonth
    }

    private var dateRangeSelection: Binding<String> {
        Binding(
            get: { dateRange.rawValue },
            set: { dateRangeID = $0 }
        )
    }

    private var previousPeriodIsAvailable: Bool {
        previousMonthInterval != nil && (!previousMonthPoints.isEmpty || !previousMonthSpendingPoints.isEmpty)
    }

    private var visibleBalanceSeriesCount: Int {
        [showsCashBalance, showsCreditCardDebt, showsCardAdjustedBalance].filter { $0 }.count
    }

    private var showsCashBalanceSelection: Binding<Bool> {
        Binding(
            get: { showsCashBalance },
            set: { newValue in
                if newValue || visibleBalanceSeriesCount > 1 {
                    showsCashBalance = newValue
                }
            }
        )
    }

    private var showsCreditCardDebtSelection: Binding<Bool> {
        Binding(
            get: { showsCreditCardDebt },
            set: { newValue in
                if newValue || visibleBalanceSeriesCount > 1 {
                    showsCreditCardDebt = newValue
                }
            }
        )
    }

    private var showsCardAdjustedBalanceSelection: Binding<Bool> {
        Binding(
            get: { showsCardAdjustedBalance },
            set: { newValue in
                if newValue || visibleBalanceSeriesCount > 1 {
                    showsCardAdjustedBalance = newValue
                }
            }
        )
    }

    private var cashFlowBalanceBasisSelection: Binding<String> {
        Binding(
            get: { cashFlowBalanceBasis.rawValue },
            set: { cashFlowBalanceBasisID = $0 }
        )
    }

    private var cashFlowFallbackCash: Money {
        cashFlowBalanceBasis == .accountBalances ? snapshot.availableCash : Money(minorUnits: 0)
    }

    private var cashFlowFallbackCardDebt: Money {
        cashFlowBalanceBasis == .accountBalances ? snapshot.creditDebt.absolute : Money(minorUnits: 0)
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

    private var cashFlowBalanceBasisPicker: some View {
        Picker("Cash plot baseline", selection: cashFlowBalanceBasisSelection) {
            ForEach(CashFlowBalanceBasis.allCases, id: \.self) { basis in
                Text(basis.displayName)
                    .tag(basis.rawValue)
            }
        }
        .pickerStyle(.segmented)
    }

    private var dateRangePicker: some View {
        Picker("Date range", selection: dateRangeSelection) {
            ForEach(BalanceDateRange.allCases, id: \.self) { range in
                Text(range.displayName)
                    .tag(range.rawValue)
            }
        }
        .pickerStyle(.segmented)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 12) {
                            MonthSelector(
                                months: availableMonths,
                                selectedMonth: analysisDate,
                                selectMonth: selectMonth,
                                selectPreviousMonth: selectPreviousMonth,
                                selectNextMonth: selectNextMonth
                            )

                            Spacer()

                            dateRangePicker
                                .frame(maxWidth: 340)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            MonthSelector(
                                months: availableMonths,
                                selectedMonth: analysisDate,
                                selectMonth: selectMonth,
                                selectPreviousMonth: selectPreviousMonth,
                                selectNextMonth: selectNextMonth
                            )

                            dateRangePicker
                        }
                    }

                    cashFlowBalanceBasisPicker

                    BalanceDataStatusView(
                        connectionState: connectionState,
                        requestedRange: dateRange,
                        visibleMonthCount: analysisWindow.visibleMonthCount,
                        availableMonthCount: availableMonths.count
                    )

                    BalancePlotControls(
                        showsPreviousPeriod: $showsPreviousPeriod,
                        showsCashBalance: showsCashBalanceSelection,
                        showsCreditCardDebt: showsCreditCardDebtSelection,
                        showsCardAdjustedBalance: showsCardAdjustedBalanceSelection,
                        previousPeriodIsAvailable: previousPeriodIsAvailable,
                        visibleBalanceSeriesCount: visibleBalanceSeriesCount
                    )
                }

                CashFlowPlot(
                    points: points,
                    previousMonthPoints: previousMonthPoints,
                    monthInterval: analysisDateInterval,
                    previousMonthInterval: previousMonthInterval,
                    balanceBasis: cashFlowBalanceBasis,
                    showsPreviousPeriod: showsPreviousPeriod,
                    showsCashBalance: showsCashBalance,
                    showsCreditCardDebt: showsCreditCardDebt,
                    showsCardAdjustedBalance: showsCardAdjustedBalance
                )
                    .frame(height: 260)
                    .padding()
                    .budgetTracerCard(cornerRadius: 24)

                DailySpendingPlot(
                    points: spendingPoints,
                    previousMonthPoints: previousMonthSpendingPoints,
                    monthInterval: analysisDateInterval,
                    previousMonthInterval: previousMonthInterval,
                    showsPreviousPeriod: showsPreviousPeriod
                )
                    .frame(height: 260)
                    .padding()
                    .budgetTracerCard(cornerRadius: 24)

                TransactionTimeSpendingPlot(
                    points: transactionTimelinePoints,
                    monthInterval: analysisDateInterval
                )
                .frame(height: 260)
                .padding()
                .budgetTracerCard(cornerRadius: 24)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 16) {
                    SummaryPill(title: "Regular items", value: "\(snapshot.recurringTransactionIDs.count)")
                    SummaryPill(title: cashFlowBalanceBasis.cashSummaryTitle, value: (points.last?.runningCashBalance ?? cashFlowFallbackCash).formatted)
                    SummaryPill(title: cashFlowBalanceBasis.cardDebtSummaryTitle, value: (points.last?.runningCreditDebt ?? cashFlowFallbackCardDebt).formatted)
                    SummaryPill(
                        title: cashFlowBalanceBasis.cardAdjustedSummaryTitle,
                        value: (points.last?.runningCashMinusCreditDebt ?? (cashFlowFallbackCash - cashFlowFallbackCardDebt)).formatted
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Regular Monthly Transactions")
                                .font(.headline)

                            Spacer()

                            TransactionSearchField(text: $transactionSearchText)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Regular Monthly Transactions")
                                .font(.headline)

                            TransactionSearchField(text: $transactionSearchText)
                        }
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
                    .budgetTracerCard(cornerRadius: 24)
                }
            }
            .padding()
        }
        .background(BudgetTracerStyle.screenBackground)
        .onAppear {
            applyLaunchStateIfNeeded()
            ensureVisibleBalanceSeries()
        }
        .onChange(of: availableMonths) { _, months in
            guard !months.isEmpty else {
                selectedMonthTimestamp = 0
                return
            }

            applyLaunchStateIfNeeded()

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

    private func ensureVisibleBalanceSeries() {
        if visibleBalanceSeriesCount == 0 {
            showsCashBalance = true
        }
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

    private func applyLaunchStateIfNeeded() {
        guard !didApplyLaunchState else {
            return
        }

        didApplyLaunchState = true

        if let launchBasis = launchCashFlowBalanceBasis {
            cashFlowBalanceBasisID = launchBasis.rawValue
        }

        if let launchDateRange = launchDateRange {
            dateRangeID = launchDateRange.rawValue
        }

        if let launchMonth = launchMonth {
            selectMonth(launchMonth)
        } else if selectedMonthTimestamp == 0 {
            selectMonth(defaultAnalysisMonth)
        }
    }

    private var launchCashFlowBalanceBasis: CashFlowBalanceBasis? {
        guard let value = ProcessInfo.processInfo.environment["BUDGETTRACER_INITIAL_CASH_FLOW_BASIS"] else {
            return nil
        }

        switch value.lowercased() {
        case CashFlowBalanceBasis.accountBalances.rawValue.lowercased(), "balances", "accountbalances":
            return .accountBalances
        case CashFlowBalanceBasis.monthStartZero.rawValue.lowercased(), "fromzero", "zero", "monthstartzero":
            return .monthStartZero
        default:
            return nil
        }
    }

    private var launchDateRange: BalanceDateRange? {
        guard let value = ProcessInfo.processInfo.environment["BUDGETTRACER_INITIAL_DATE_RANGE"] else {
            return nil
        }

        return BalanceDateRange(rawValue: value.uppercased())
    }

    private var launchMonth: Date? {
        guard let value = ProcessInfo.processInfo.environment["BUDGETTRACER_INITIAL_MONTH"] else {
            return nil
        }

        let parts = value
            .split(separator: "-")
            .compactMap { Int($0) }
        guard parts.count >= 2 else {
            return nil
        }

        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: 1))
    }
}

private struct BalanceDataStatusView: View {
    var connectionState: PlaidConnectionState
    var requestedRange: BalanceDateRange
    var visibleMonthCount: Int
    var availableMonthCount: Int

    var body: some View {
        if hasStatus {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    statusContent
                }

                VStack(alignment: .leading, spacing: 8) {
                    statusContent
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(BudgetTracerStyle.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BudgetTracerStyle.cardBorder, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        connectionStatus
        rangeStatus
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch connectionState {
        case .connecting:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading latest data")
            }
        case .connected(_, let lastSyncedAt):
            if let lastSyncedAt {
                Label(
                    "Synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "checkmark.circle"
                )
            }
        case .failed(let message):
            Label("Refresh failed: \(message)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(BudgetTracerStyle.caution)
        case .notConnected:
            EmptyView()
        }
    }

    @ViewBuilder
    private var rangeStatus: some View {
        if visibleMonthCount < requestedRange.monthCount {
            Label(
                "Showing \(visibleMonthCount)M because \(availableMonthCount)M of transaction history is loaded",
                systemImage: "calendar.badge.exclamationmark"
            )
        }
    }

    private var hasStatus: Bool {
        switch connectionState {
        case .connecting, .failed:
            return true
        case .connected(_, let lastSyncedAt):
            return lastSyncedAt != nil || visibleMonthCount < requestedRange.monthCount
        case .notConnected:
            return visibleMonthCount < requestedRange.monthCount
        }
    }
}

private struct BalancePlotControls: View {
    @Binding var showsPreviousPeriod: Bool
    @Binding var showsCashBalance: Bool
    @Binding var showsCreditCardDebt: Bool
    @Binding var showsCardAdjustedBalance: Bool
    var previousPeriodIsAvailable: Bool
    var visibleBalanceSeriesCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                toggles
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
                toggles
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var toggles: some View {
        Toggle("Previous period", isOn: $showsPreviousPeriod)
            .disabled(!previousPeriodIsAvailable)
        Toggle("Cash", isOn: $showsCashBalance)
            .disabled(showsCashBalance && visibleBalanceSeriesCount <= 1)
        Toggle("Card debt", isOn: $showsCreditCardDebt)
            .disabled(showsCreditCardDebt && visibleBalanceSeriesCount <= 1)
        Toggle("Cash after cards", isOn: $showsCardAdjustedBalance)
            .disabled(showsCardAdjustedBalance && visibleBalanceSeriesCount <= 1)
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
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
        .background(BudgetTracerStyle.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BudgetTracerStyle.cardBorder, lineWidth: 1)
        }
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
                Text("Transactions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text((points.last?.cumulativeSpending ?? Money(minorUnits: 0)).formatted)
                    .font(.subheadline.monospacedDigit())
            }

            LegendRow(items: [
                LegendEntry(color: BudgetTracerStyle.accent, title: "Transaction"),
                LegendEntry(color: BudgetTracerStyle.chartPurple, title: "Averaged transaction")
            ])

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
                    .stroke(BudgetTracerStyle.accent, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))

                    ForEach(points) { point in
                        if point.isAveraged {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(BudgetTracerStyle.chartPurple)
                                .frame(width: 10, height: 10)
                                .rotationEffect(.degrees(45))
                                .position(plotLocation(for: point, in: proxy.size))
                                .help(helpText(for: point))
                        } else {
                            Circle()
                                .fill(BudgetTracerStyle.accent)
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
        ChartMoneyAxis.roundedCeiling(
            for: points.map(\.cumulativeSpending.minorUnits)
        )
    }

    private var yAxisLabels: [String] {
        ChartMoneyAxis.labels(for: 0...spendingCeiling)
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
    var showsPreviousPeriod: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spending")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(totalCumulativeNormalizedSpending.formatted) / \(totalCumulativeNormalizedIncome.formatted)")
                    .font(.subheadline.monospacedDigit())
            }

            LegendRow(items: [
                LegendEntry(color: BudgetTracerStyle.accent, title: "Cumulative spending"),
                LegendEntry(color: BudgetTracerStyle.positive, title: "Cumulative income"),
                LegendEntry(color: BudgetTracerStyle.chartPurple, title: "Averaged transaction")
            ] + previousPeriodLegend)

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                        .offset(y: proxy.size.height / -2)

                    if showsPreviousPeriod, let previousMonthInterval {
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
                            BudgetTracerStyle.accent.opacity(0.42),
                            style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [6, 5])
                        )
                    }

                    ForEach(points.indices, id: \.self) { index in
                        let point = points[index]
                        let height = barHeight(for: point.cumulativeNormalizedSpending.minorUnits, in: proxy.size)
                        let width = barWidth(in: proxy.size)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(BudgetTracerStyle.accent.opacity(0.18))
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
                    .stroke(BudgetTracerStyle.accent, style: StrokeStyle(lineWidth: 3, lineJoin: .round))

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
                    .stroke(BudgetTracerStyle.positive, style: StrokeStyle(lineWidth: 3, lineJoin: .round))

                    ForEach(points.indices, id: \.self) { index in
                        let point = points[index]
                        if !point.averagedTransactionMarkers.isEmpty {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(BudgetTracerStyle.chartPurple)
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

    private var previousPeriodLegend: [LegendEntry] {
        guard showsPreviousPeriod, previousMonthInterval != nil, !previousMonthPoints.isEmpty else {
            return []
        }

        return [LegendEntry(color: BudgetTracerStyle.accent.opacity(0.45), title: "Previous period")]
    }

    private var spendingCeiling: Int64 {
        let comparisonPoints = showsPreviousPeriod ? previousMonthPoints : []
        return ChartMoneyAxis.roundedCeiling(
            for: (points + comparisonPoints).flatMap {
                [
                    $0.cumulativeNormalizedSpending.minorUnits,
                    $0.cumulativeNormalizedIncome.minorUnits
                ]
            }
        )
    }

    private var yAxisLabels: [String] {
        ChartMoneyAxis.labels(for: 0...spendingCeiling)
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
    var balanceBasis: CashFlowBalanceBasis
    var showsPreviousPeriod: Bool
    var showsCashBalance: Bool
    var showsCreditCardDebt: Bool
    var showsCardAdjustedBalance: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(balanceBasis.chartTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = points.last {
                    Text(last.runningCashMinusCreditDebt.formatted)
                        .font(.subheadline.monospacedDigit())
                }
            }

            LegendRow(items: legendEntries)

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                        .offset(y: proxy.size.height / -2)

                    if showsPreviousPeriod, let previousMonthInterval, !previousMonthPoints.isEmpty {
                        ForEach(visibleSeries) { series in
                            previousMonthPath(
                                series: series,
                                sourceMonthInterval: previousMonthInterval,
                                in: proxy.size
                            )
                            .stroke(series.color.opacity(0.48), style: previousMonthStyle.stroke)
                        }
                    }

                    ForEach(visibleSeries) { series in
                        currentPath(series: series, in: proxy.size)
                            .stroke(series.color, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                    }

                    ForEach(visibleSeries) { series in
                        transactionMarkers(
                            series: series,
                            sourceMonthInterval: monthInterval,
                            in: proxy.size
                        )
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

    private var visibleSeries: [BalancePlotSeries] {
        BalancePlotSeries.allCases.filter { series in
            switch series {
            case .cash:
                return showsCashBalance
            case .creditCardDebt:
                return showsCreditCardDebt
            case .cardAdjusted:
                return showsCardAdjustedBalance
            }
        }
    }

    private var legendEntries: [LegendEntry] {
        let currentEntries = visibleSeries.map { series in
            LegendEntry(color: series.color, title: series.title(for: balanceBasis))
        }

        guard showsPreviousPeriod, previousMonthInterval != nil, !previousMonthPoints.isEmpty else {
            return currentEntries
        }

        return currentEntries + [LegendEntry(color: Color.secondary.opacity(0.55), title: "Previous period")]
    }

    private var balanceRange: ClosedRange<Int64> {
        var balances = visibleSeries.flatMap { series in
            points.map { point in
                point[keyPath: series.keyPath].minorUnits
            }
        }

        if showsPreviousPeriod {
            balances += visibleSeries.flatMap { series in
                previousMonthPoints.map { point in
                    point[keyPath: series.keyPath].minorUnits
                }
            }
        }

        return ChartMoneyAxis.roundedRange(
            for: balances,
            includeZero: balanceBasis == .monthStartZero
        )
    }

    private var yAxisLabels: [String] {
        ChartMoneyAxis.labels(for: balanceRange)
    }

    private var previousMonthStyle: PreviousMonthLineStyle {
        PreviousMonthLineStyle()
    }

    private func previousMonthPath(
        series: BalancePlotSeries,
        sourceMonthInterval: DateInterval,
        in size: CGSize
    ) -> Path {
        Path { path in
            for index in previousMonthPoints.indices {
                let point = previousMonthPoints[index]
                let location = plotLocation(
                    value: point[keyPath: series.keyPath].minorUnits,
                    date: point.date,
                    sourceMonthInterval: sourceMonthInterval,
                    in: size
                )
                if index == 0 {
                    path.move(to: location)
                } else {
                    path.addLine(to: location)
                }
            }
        }
    }

    private func currentPath(series: BalancePlotSeries, in size: CGSize) -> Path {
        Path { path in
            for index in points.indices {
                let location = plotLocation(
                    value: points[index][keyPath: series.keyPath].minorUnits,
                    date: points[index].date,
                    sourceMonthInterval: monthInterval,
                    in: size
                )
                if index == 0 {
                    path.move(to: location)
                } else {
                    path.addLine(to: location)
                }
            }
        }
    }

    private func transactionMarkers(
        series: BalancePlotSeries,
        sourceMonthInterval: DateInterval,
        in size: CGSize
    ) -> some View {
        ForEach(points.indices, id: \.self) { index in
            let point = points[index]
            if point[keyPath: series.markerKeyPath] {
                let location = plotLocation(
                    value: point[keyPath: series.keyPath].minorUnits,
                    date: point.date,
                    sourceMonthInterval: sourceMonthInterval,
                    in: size
                )

                Circle()
                    .fill(markerColor(for: point))
                    .frame(width: 5, height: 5)
                    .position(location)
            }
        }
    }

    private func markerColor(for point: NormalizedCashFlowPoint) -> Color {
        point.dailyNet.isExpense ? BudgetTracerStyle.caution : BudgetTracerStyle.positive
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

private struct PreviousMonthLineStyle {
    var stroke = StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [6, 5])
}

private enum BalancePlotSeries: CaseIterable, Identifiable {
    case cash
    case creditCardDebt
    case cardAdjusted

    var id: String {
        switch self {
        case .cash:
            return "cash"
        case .creditCardDebt:
            return "credit-card-debt"
        case .cardAdjusted:
            return "card-adjusted"
        }
    }

    var color: Color {
        switch self {
        case .cash:
            return BudgetTracerStyle.chartBlue
        case .creditCardDebt:
            return BudgetTracerStyle.caution
        case .cardAdjusted:
            return BudgetTracerStyle.chartPurple
        }
    }

    var keyPath: KeyPath<NormalizedCashFlowPoint, Money> {
        switch self {
        case .cash:
            return \.runningCashBalance
        case .creditCardDebt:
            return \.runningCreditDebt
        case .cardAdjusted:
            return \.runningCashMinusCreditDebt
        }
    }

    var markerKeyPath: KeyPath<NormalizedCashFlowPoint, Bool> {
        switch self {
        case .cash:
            return \.hasPostedCashTransactions
        case .creditCardDebt, .cardAdjusted:
            return \.hasPostedCardTransactions
        }
    }

    func title(for balanceBasis: CashFlowBalanceBasis) -> String {
        switch self {
        case .cash:
            return balanceBasis.cashLegendTitle
        case .creditCardDebt:
            return balanceBasis.cardDebtLegendTitle
        case .cardAdjusted:
            return balanceBasis.cardAdjustedLegendTitle
        }
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

private enum ChartMoneyAxis {
    static func roundedCeiling(for values: [Int64]) -> Int64 {
        max(roundedRange(for: values, includeZero: true).upperBound, 100)
    }

    static func roundedRange(for values: [Int64], includeZero: Bool) -> ClosedRange<Int64> {
        let sourceValues = values.isEmpty ? [Int64(0)] : values
        var minValue = sourceValues.min() ?? 0
        var maxValue = sourceValues.max() ?? 0

        if includeZero {
            minValue = min(minValue, 0)
            maxValue = max(maxValue, 0)
        }

        let minDollars = Double(minValue) / 100
        let maxDollars = Double(maxValue) / 100
        let rawSpan = max(maxDollars - minDollars, 1)
        let step = max(niceStep(for: rawSpan / 8), 100)
        let lowerDollars: Double
        let upperDollars: Double

        if includeZero, minValue >= 0 {
            lowerDollars = 0
            upperDollars = max(ceil(maxDollars / step) * step, step)
        } else if includeZero, maxValue <= 0 {
            lowerDollars = min(floor(minDollars / step) * step, -step)
            upperDollars = 0
        } else {
            lowerDollars = floor(minDollars / step) * step
            upperDollars = ceil(maxDollars / step) * step
        }

        if upperDollars <= lowerDollars {
            return minorUnits(for: lowerDollars - step)...minorUnits(for: upperDollars + step)
        }

        return minorUnits(for: lowerDollars)...minorUnits(for: upperDollars)
    }

    static func labels(for range: ClosedRange<Int64>) -> [String] {
        return [
            compactCurrency(for: range.upperBound),
            compactCurrency(for: range.lowerBound)
        ]
    }

    private static func niceStep(for value: Double) -> Double {
        guard value.isFinite, value > 0 else {
            return 1
        }

        let exponent = floor(log10(value))
        let magnitude = pow(10, exponent)
        let normalized = value / magnitude

        switch normalized {
        case ...1:
            return magnitude
        case ...2:
            return 2 * magnitude
        case ...5:
            return 5 * magnitude
        default:
            return 10 * magnitude
        }
    }

    private static func minorUnits(for dollars: Double) -> Int64 {
        Int64((dollars * 100).rounded())
    }

    private static func compactCurrency(for minorUnits: Int64) -> String {
        let sign = minorUnits < 0 ? "-" : ""
        let dollars = abs(minorUnits) / 100

        if dollars >= 1_000_000, dollars % 1_000_000 == 0 {
            return "\(sign)$\(dollars / 1_000_000)M"
        }

        if dollars >= 10_000, dollars % 1_000 == 0 {
            return "\(sign)$\(dollars / 1_000)k"
        }

        return "\(sign)$\(dollars.formatted(.number.grouping(.automatic)))"
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

private struct LegendEntry: Identifiable {
    var color: Color
    var title: String

    var id: String { title }
}

private struct LegendRow: View {
    var items: [LegendEntry]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                ForEach(items) { item in
                    LegendItem(color: item.color, title: item.title)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    LegendItem(color: item.color, title: item.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
        .budgetTracerCard(cornerRadius: 18)
    }
}

private struct RecurringTransactionRow: View {
    var transaction: BudgetTransaction
    var isRecurring: Bool
    var setRecurring: (BudgetTransaction.ID, Bool) -> Void

    var body: some View {
        Toggle(isOn: binding) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    transactionLabel
                    Spacer()
                    transactionAmount
                }

                VStack(alignment: .leading, spacing: 8) {
                    transactionLabel
                    transactionAmount
                }
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

    private var transactionLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.amount.isIncome ? "arrow.down.circle" : "arrow.up.circle")
                .foregroundStyle(transaction.amount.isIncome ? BudgetTracerStyle.positive : BudgetTracerStyle.caution)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchantName)
                Text(transaction.postedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transactionAmount: some View {
        Text(transaction.amount.formatted)
            .font(.body.monospacedDigit())
    }
}

private enum BalanceDateRange: String, CaseIterable, Hashable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case nineMonths = "9M"
    case oneYear = "1Y"

    var displayName: String {
        rawValue
    }

    var monthCount: Int {
        switch self {
        case .oneMonth:
            return 1
        case .threeMonths:
            return 3
        case .sixMonths:
            return 6
        case .nineMonths:
            return 9
        case .oneYear:
            return 12
        }
    }
}

private extension CashFlowBalanceBasis {
    var displayName: String {
        switch self {
        case .accountBalances:
            return "Balances"
        case .monthStartZero:
            return "From zero"
        }
    }

    var chartTitle: String {
        switch self {
        case .accountBalances:
            return "Cash"
        case .monthStartZero:
            return "Cash change"
        }
    }

    var cashLegendTitle: String {
        switch self {
        case .accountBalances:
            return "Checking cash"
        case .monthStartZero:
            return "Checking cash change"
        }
    }

    var cardAdjustedLegendTitle: String {
        switch self {
        case .accountBalances:
            return "Cash minus card debt"
        case .monthStartZero:
            return "Cash minus card debt change"
        }
    }

    var cardDebtLegendTitle: String {
        switch self {
        case .accountBalances:
            return "Card debt"
        case .monthStartZero:
            return "Card debt change"
        }
    }

    var cashSummaryTitle: String {
        switch self {
        case .accountBalances:
            return "Ending checking cash"
        case .monthStartZero:
            return "Checking cash change"
        }
    }

    var cardDebtSummaryTitle: String {
        switch self {
        case .accountBalances:
            return "Ending card debt"
        case .monthStartZero:
            return "Card debt change"
        }
    }

    var cardAdjustedSummaryTitle: String {
        switch self {
        case .accountBalances:
            return "Cash after cards"
        case .monthStartZero:
            return "Cash after cards change"
        }
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
