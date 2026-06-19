import BudgetCore
import SwiftUI
import UniformTypeIdentifiers

struct NormalizedMonthView: View {
    var snapshot: BudgetSnapshot
    var connectionState: PlaidConnectionState = .connected(institutionCount: 0, lastSyncedAt: nil)
    var setRecurring: (BudgetTransaction.ID, Bool) -> Void
    var setCategory: (BudgetTransaction.ID, BudgetCategory.ID?) -> Void = { _, _ in }
    var setRecurringSeries: ([BudgetTransaction.ID], Bool) -> Void = { _, _ in }
    var setCategorySeries: ([BudgetTransaction.ID], BudgetCategory.ID?) -> Void = { _, _ in }
    var setAccountKind: (FinancialAccount.ID, AccountKind) -> Void = { _, _ in }
    var setAccountAvailableCash: (FinancialAccount.ID, Bool) -> Void = { _, _ in }
    var setAccountOverride: (FinancialAccount.ID, AccountOverride?) -> Void = { _, _ in }
    var saveAssignmentRule: (BudgetAssignmentRule, Bool) -> Void = { _, _ in }

    @State private var didApplyLaunchState = false
    @State private var selectedTransactionID: BudgetTransaction.ID?
    @State private var selectedSeriesKey: String?

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

    @SceneStorage("BudgetTracer.normalizedMonth.plotAccountsExpanded")
    private var plotAccountsExpanded = true

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

    private var cashFlowFallbackCash: Money {
        cashFlowBalanceBasis == .accountBalances ? snapshot.availableCash : Money(minorUnits: 0)
    }

    private var cashFlowFallbackCardDebt: Money {
        cashFlowBalanceBasis == .accountBalances ? snapshot.creditDebt.absolute : Money(minorUnits: 0)
    }

    private var selectedTransactionBinding: Binding<BudgetTransaction?> {
        Binding(
            get: {
                guard let selectedTransactionID else { return nil }
                return snapshot.transactions.first { $0.id == selectedTransactionID }
            },
            set: { newValue in selectedTransactionID = newValue?.id }
        )
    }

    /// Recurring transactions in the window, collapsed to one series per merchant.
    private var recurringSeries: [RecurringSeries] {
        let windowRecurring = selectableTransactions.filter {
            snapshot.recurringTransactionIDs.contains($0.id)
        }

        return RecurringSeries.build(
            windowRecurring: windowRecurring,
            allTransactions: snapshot.transactions
        )
    }

    /// Non-recurring transactions stay as individual, markable rows.
    private var nonRecurringTransactions: [BudgetTransaction] {
        selectableTransactions.filter { !snapshot.recurringTransactionIDs.contains($0.id) }
    }

    private var hasRegularMonthlyContent: Bool {
        !recurringSeries.isEmpty || !nonRecurringTransactions.isEmpty
    }

    private var selectedSeriesBinding: Binding<RecurringSeries?> {
        Binding(
            get: {
                guard let selectedSeriesKey else { return nil }
                return recurringSeries.first { $0.id == selectedSeriesKey }
            },
            set: { newValue in selectedSeriesKey = newValue?.id }
        )
    }

    private var selectableTransactions: [BudgetTransaction] {
        snapshot.transactions
            .filter { transaction in
                transaction.amount.minorUnits != 0 && transactionDateInterval.contains(transaction.postedAt)
            }
            .filter { TransactionSearch.matches($0, query: transactionSearchText, in: snapshot) }
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

    private var cashFlowBalanceBasisBinding: Binding<CashFlowBalanceBasis> {
        Binding(
            get: { cashFlowBalanceBasis },
            set: { cashFlowBalanceBasisID = $0.rawValue }
        )
    }

    private var dateRangeBinding: Binding<BalanceDateRange> {
        Binding(
            get: { dateRange },
            set: { dateRangeID = $0.rawValue }
        )
    }

    private var cashFlowBalanceBasisPicker: some View {
        ThemePillPicker(
            options: CashFlowBalanceBasis.allCases,
            selection: cashFlowBalanceBasisBinding,
            label: { $0.displayName }
        )
        .frame(maxWidth: 240)
    }

    private var dateRangePicker: some View {
        ThemePillPicker(
            options: BalanceDateRange.allCases,
            selection: dateRangeBinding,
            label: { $0.displayName }
        )
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
                }

                CashFlowPlot(
                    points: points,
                    previousMonthPoints: previousMonthPoints,
                    monthInterval: analysisDateInterval,
                    previousMonthInterval: previousMonthInterval,
                    balanceBasis: cashFlowBalanceBasis,
                    showsPreviousPeriod: $showsPreviousPeriod,
                    showsCashBalance: showsCashBalanceSelection,
                    showsCreditCardDebt: showsCreditCardDebtSelection,
                    showsCardAdjustedBalance: showsCardAdjustedBalanceSelection,
                    previousPeriodIsAvailable: previousPeriodIsAvailable,
                    visibleBalanceSeriesCount: visibleBalanceSeriesCount
                )
                    .frame(height: 280)
                    .padding(18)
                    .budgetTracerCard(cornerRadius: 16)

                CashFlowAccountBreakdown(
                    snapshot: snapshot,
                    isExpanded: $plotAccountsExpanded,
                    setAccountKind: setAccountKind,
                    setAccountAvailableCash: setAccountAvailableCash,
                    setAccountOverride: setAccountOverride
                )
                    .padding(18)
                    .budgetTracerCard(cornerRadius: 16)

                DailySpendingPlot(
                    points: spendingPoints,
                    previousMonthPoints: previousMonthSpendingPoints,
                    monthInterval: analysisDateInterval,
                    previousMonthInterval: previousMonthInterval,
                    showsPreviousPeriod: $showsPreviousPeriod,
                    previousPeriodIsAvailable: previousPeriodIsAvailable
                )
                    .frame(height: 280)
                    .padding(18)
                    .budgetTracerCard(cornerRadius: 16)

                TransactionTimeSpendingPlot(
                    points: transactionTimelinePoints,
                    monthInterval: analysisDateInterval
                )
                .frame(height: 280)
                .padding(18)
                .budgetTracerCard(cornerRadius: 16)

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
                            SectionHeader("Regular monthly transactions")

                            Spacer()

                            TransactionSearchField(text: $transactionSearchText)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Regular monthly transactions")

                            TransactionSearchField(text: $transactionSearchText)
                        }
                    }

                    VStack(spacing: 0) {
                        if !hasRegularMonthlyContent {
                            Text(transactionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No transactions in this range." : "No matching transactions.")
                                .font(.subheadline)
                                .foregroundStyle(BudgetTracerStyle.inkMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        } else {
                            ForEach(recurringSeries) { series in
                                RecurringSeriesRow(
                                    series: series,
                                    onTap: { selectedSeriesKey = series.id }
                                )
                            }

                            ForEach<[BudgetTransaction], BudgetTransaction.ID, RecurringTransactionRow>(nonRecurringTransactions) { transaction in
                                RecurringTransactionRow(
                                    transaction: transaction,
                                    isRecurring: snapshot.recurringTransactionIDs.contains(transaction.id),
                                    setRecurring: setRecurring,
                                    onOpenDetail: { selectedTransactionID = transaction.id }
                                )
                            }
                        }
                    }
                    .budgetTracerCard(cornerRadius: 16)
                }
            }
            .padding()
        }
        .budgetTracerWorkspaceBackground()
        .sheet(item: selectedTransactionBinding) { transaction in
            TransactionDetailSheet(
                transaction: transaction,
                snapshot: snapshot,
                setRecurring: setRecurring,
                setCategory: setCategory,
                saveAssignmentRule: saveAssignmentRule,
                dismiss: { selectedTransactionID = nil }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: selectedSeriesBinding) { series in
            RecurringSeriesDetailSheet(
                series: series,
                snapshot: snapshot,
                setRecurring: setRecurringSeries,
                setCategory: setCategorySeries,
                dismiss: { selectedSeriesKey = nil }
            )
            .presentationDetents([.medium, .large])
        }
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
            .foregroundStyle(BudgetTracerStyle.inkMuted)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
        .background(BudgetTracerStyle.surfaceSunken, in: Capsule(style: .continuous))
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                    .frame(width: 26, height: 26)
                    .background(BudgetTracerStyle.surfaceSunken, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canMovePrevious)
            .opacity(canMovePrevious ? 1 : 0.4)
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                    .frame(width: 26, height: 26)
                    .background(BudgetTracerStyle.surfaceSunken, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canMoveNext)
            .opacity(canMoveNext ? 1 : 0.4)
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
            HStack(alignment: .firstTextBaseline) {
                Text("Transactions")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                Spacer()
                Text((points.last?.cumulativeSpending ?? Money(minorUnits: 0)).formatted)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(BudgetTracerStyle.ink)
                    .contentTransition(.numericText())
            }

            ChipFlowRow {
                LegendChip(color: BudgetTracerStyle.accent, title: "Transaction", isOn: true)
                LegendChip(color: BudgetTracerStyle.chartPurple, title: "Averaged transaction", isOn: true)
            }

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(BudgetTracerStyle.hairline)
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
                    .stroke(BudgetTracerStyle.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

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
                                .fill(BudgetTracerStyle.accent.opacity(0.8))
                                .frame(width: 5, height: 5)
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
            .foregroundStyle(BudgetTracerStyle.inkFaint)
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
    @Binding var showsPreviousPeriod: Bool
    var previousPeriodIsAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spending")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                Spacer()
                Text("\(totalCumulativeNormalizedSpending.formatted) / \(totalCumulativeNormalizedIncome.formatted)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(BudgetTracerStyle.ink)
                    .contentTransition(.numericText())
            }

            ChipFlowRow {
                LegendChip(color: BudgetTracerStyle.accent, title: "Cumulative spending", isOn: true)
                LegendChip(color: BudgetTracerStyle.positive, title: "Cumulative income", isOn: true)
                LegendChip(color: BudgetTracerStyle.chartPurple, title: "Averaged transaction", isOn: true)
                LegendChip(
                    color: BudgetTracerStyle.inkFaint,
                    title: "Previous period",
                    isOn: showsPreviousPeriod && previousPeriodIsAvailable,
                    isEnabled: previousPeriodIsAvailable,
                    toggle: { showsPreviousPeriod.toggle() }
                )
            }

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(BudgetTracerStyle.hairline)
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
                        UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 2, style: .continuous)
                            .fill(BudgetTracerStyle.accent.opacity(0.12))
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
                    .stroke(BudgetTracerStyle.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

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
                    .stroke(BudgetTracerStyle.positive, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

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

                    if let last = points.last {
                        ChartEndpointDot(color: BudgetTracerStyle.accent)
                            .position(
                                plotLocation(
                                    value: last.cumulativeNormalizedSpending.minorUnits,
                                    date: last.date,
                                    sourceMonthInterval: monthInterval,
                                    in: proxy.size
                                )
                            )
                        ChartEndpointDot(color: BudgetTracerStyle.positive)
                            .position(
                                plotLocation(
                                    value: last.cumulativeNormalizedIncome.minorUnits,
                                    date: last.date,
                                    sourceMonthInterval: monthInterval,
                                    in: proxy.size
                                )
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
            .foregroundStyle(BudgetTracerStyle.inkFaint)
        }
    }

    private var totalCumulativeNormalizedSpending: Money {
        points.last?.cumulativeNormalizedSpending ?? Money(minorUnits: 0)
    }

    private var totalCumulativeNormalizedIncome: Money {
        points.last?.cumulativeNormalizedIncome ?? Money(minorUnits: 0)
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
    @Binding var showsPreviousPeriod: Bool
    @Binding var showsCashBalance: Bool
    @Binding var showsCreditCardDebt: Bool
    @Binding var showsCardAdjustedBalance: Bool
    var previousPeriodIsAvailable: Bool
    var visibleBalanceSeriesCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(balanceBasis.chartTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                Spacer()
                if let last = points.last {
                    Text(last.runningCashMinusCreditDebt.formatted)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(BudgetTracerStyle.ink)
                        .contentTransition(.numericText())
                }
            }

            ChipFlowRow {
                LegendChip(
                    color: BalancePlotSeries.cash.color,
                    title: balanceBasis.cashLegendTitle,
                    isOn: showsCashBalance,
                    isEnabled: !(showsCashBalance && visibleBalanceSeriesCount <= 1),
                    toggle: { showsCashBalance.toggle() }
                )
                LegendChip(
                    color: BalancePlotSeries.creditCardDebt.color,
                    title: balanceBasis.cardDebtLegendTitle,
                    isOn: showsCreditCardDebt,
                    isEnabled: !(showsCreditCardDebt && visibleBalanceSeriesCount <= 1),
                    toggle: { showsCreditCardDebt.toggle() }
                )
                LegendChip(
                    color: BalancePlotSeries.cardAdjusted.color,
                    title: balanceBasis.cardAdjustedLegendTitle,
                    isOn: showsCardAdjustedBalance,
                    isEnabled: !(showsCardAdjustedBalance && visibleBalanceSeriesCount <= 1),
                    toggle: { showsCardAdjustedBalance.toggle() }
                )
                LegendChip(
                    color: BudgetTracerStyle.inkFaint,
                    title: "Previous period",
                    isOn: showsPreviousPeriod && previousPeriodIsAvailable,
                    isEnabled: previousPeriodIsAvailable,
                    toggle: { showsPreviousPeriod.toggle() }
                )
            }

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(BudgetTracerStyle.hairline)
                        .frame(height: 1)
                        .offset(y: proxy.size.height / -2)

                    if showsPreviousPeriod, let previousMonthInterval, !previousMonthPoints.isEmpty {
                        ForEach(visibleSeries) { series in
                            previousMonthPath(
                                series: series,
                                sourceMonthInterval: previousMonthInterval,
                                in: proxy.size
                            )
                            .stroke(series.color.opacity(0.35), style: previousMonthStyle.stroke)
                        }
                    }

                    if let fillSeries = visibleSeries.first {
                        areaPath(series: fillSeries, in: proxy.size)
                            .fill(
                                LinearGradient(
                                    colors: [fillSeries.color.opacity(0.14), fillSeries.color.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }

                    ForEach(visibleSeries) { series in
                        currentPath(series: series, in: proxy.size)
                            .stroke(series.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }

                    ForEach(visibleSeries) { series in
                        transactionMarkers(
                            series: series,
                            sourceMonthInterval: monthInterval,
                            in: proxy.size
                        )
                    }

                    ForEach(visibleSeries) { series in
                        if let last = points.last {
                            ChartEndpointDot(color: series.color)
                                .position(
                                    plotLocation(
                                        value: last[keyPath: series.keyPath].minorUnits,
                                        date: last.date,
                                        sourceMonthInterval: monthInterval,
                                        in: proxy.size
                                    )
                                )
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
            .foregroundStyle(BudgetTracerStyle.inkFaint)
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

    private func areaPath(series: BalancePlotSeries, in size: CGSize) -> Path {
        var path = currentPath(series: series, in: size)
        guard let last = points.last, let first = points.first else {
            return path
        }

        let lastX = plotLocation(
            value: last[keyPath: series.keyPath].minorUnits,
            date: last.date,
            sourceMonthInterval: monthInterval,
            in: size
        ).x
        let firstX = plotLocation(
            value: first[keyPath: series.keyPath].minorUnits,
            date: first.date,
            sourceMonthInterval: monthInterval,
            in: size
        ).x

        path.addLine(to: CGPoint(x: lastX, y: size.height))
        path.addLine(to: CGPoint(x: firstX, y: size.height))
        path.closeSubpath()
        return path
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
                    .fill(markerColor(for: point).opacity(0.75))
                    .frame(width: 4, height: 4)
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

private struct CashFlowAccountBreakdown: View {
    var snapshot: BudgetSnapshot
    @Binding var isExpanded: Bool
    var setAccountKind: (FinancialAccount.ID, AccountKind) -> Void
    var setAccountAvailableCash: (FinancialAccount.ID, Bool) -> Void
    var setAccountOverride: (FinancialAccount.ID, AccountOverride?) -> Void

    @State private var targetedGroup: PlotAccountGroup?

    private var cashAccounts: [FinancialAccount] {
        snapshot.accounts
            .filter { snapshot.includesInAvailableCash($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var cardAccounts: [FinancialAccount] {
        snapshot.accounts
            .filter { snapshot.includesInCreditCardDebt($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var excludedAccounts: [FinancialAccount] {
        snapshot.accounts
            .filter { account in
                !snapshot.includesInAvailableCash(account) && !snapshot.includesInCreditCardDebt(account)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(BudgetTracerStyle.spring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BudgetTracerStyle.inkMuted)
                        .frame(width: 14)

                    Text("Plot accounts")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BudgetTracerStyle.ink)

                    Spacer()

                    Text((snapshot.availableCash - snapshot.creditDebt).formatted)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(BudgetTracerStyle.ink)
                        .contentTransition(.numericText())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse Plot Accounts" : "Expand Plot Accounts")

            if isExpanded {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        accountGroup(.cash, accounts: cashAccounts, emptyText: "No cash accounts")
                        accountGroup(.cards, accounts: cardAccounts, emptyText: "No card accounts")
                        accountGroup(.excluded, accounts: excludedAccounts, emptyText: "None")
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        accountGroup(.cash, accounts: cashAccounts, emptyText: "No cash accounts")
                        accountGroup(.cards, accounts: cardAccounts, emptyText: "No card accounts")
                        accountGroup(.excluded, accounts: excludedAccounts, emptyText: "None")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func accountGroup(_ group: PlotAccountGroup, accounts: [FinancialAccount], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                Spacer()
                Text(accountsTotal(accounts).formatted)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
            }

            if accounts.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(BudgetTracerStyle.inkFaint)
            } else {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        accountRow(account, in: group)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 82, alignment: .topLeading)
        .background(
            targetedGroup == group ? BudgetTracerStyle.accentSoft : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    targetedGroup == group ? BudgetTracerStyle.accent.opacity(0.45) : BudgetTracerStyle.hairline,
                    lineWidth: 1
                )
        }
        .onDrop(
            of: AccountDragPayload.supportedContentTypes,
            isTargeted: dropTargetBinding(for: group),
            perform: { providers in
                acceptAccountDrop(providers, to: group)
            }
        )
    }

    private func accountRow(_ account: FinancialAccount, in group: PlotAccountGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BudgetTracerStyle.inkFaint)
                .frame(width: 10)
            Image(systemName: account.kind.plotSystemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BudgetTracerStyle.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.caption)
                    .foregroundStyle(BudgetTracerStyle.ink)
                    .lineLimit(1)
                Text(account.kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
            }
            Spacer(minLength: 8)
            Text(account.currentBalance.formatted)
                .font(.caption.monospacedDigit())
                .foregroundStyle(BudgetTracerStyle.ink)

            accountMoveMenu(account)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onDrag {
            AccountDragPayload.provider(accountID: account.id, suggestedName: account.name)
        } preview: {
            HStack(spacing: 8) {
                Image(systemName: account.kind.plotSystemImage)
                Text(account.name)
            }
            .font(.caption.weight(.medium))
            .padding(8)
            .background(BudgetTracerStyle.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .onDrop(
            of: AccountDragPayload.supportedContentTypes,
            isTargeted: dropTargetBinding(for: group),
            perform: { providers in
                acceptAccountDrop(providers, to: group)
            }
        )
        .help("Drag to move account between plot groups")
    }

    private func accountMoveMenu(_ account: FinancialAccount) -> some View {
        Menu {
            ForEach(PlotAccountGroup.allCases, id: \.self) { group in
                Button(group.title) {
                    moveAccount(account.id, to: group)
                }
                .disabled(PlotAccountMovePlanner.actions(for: account, destination: group, snapshot: snapshot).isEmpty)
            }
        } label: {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.caption)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
                .frame(width: 18, height: 18)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Move Account")
    }

    private func accountsTotal(_ accounts: [FinancialAccount]) -> Money {
        accounts
            .map(\.currentBalance)
            .reduce(Money(minorUnits: 0), +)
    }

    private func moveAccount(_ accountID: FinancialAccount.ID, to group: PlotAccountGroup) {
        guard let account = snapshot.accounts.first(where: { $0.id == accountID }) else {
            return
        }

        guard !PlotAccountMovePlanner.actions(for: account, destination: group, snapshot: snapshot).isEmpty else {
            return
        }

        setAccountOverride(
            accountID,
            PlotAccountMovePlanner.override(for: account, destination: group, snapshot: snapshot)
        )
    }

    private func dropTargetBinding(for group: PlotAccountGroup) -> Binding<Bool> {
        Binding {
            targetedGroup == group
        } set: { isTargeted in
            targetedGroup = isTargeted ? group : (targetedGroup == group ? nil : targetedGroup)
        }
    }

    private func acceptAccountDrop(_ providers: [NSItemProvider], to group: PlotAccountGroup) -> Bool {
        AccountDragPayload.loadAccountID(from: providers) { accountID in
            moveAccount(accountID, to: group)
        }
    }
}

enum PlotAccountGroup: String, CaseIterable, Hashable {
    case cash
    case cards
    case excluded

    var title: String {
        switch self {
        case .cash:
            return "Cash in plot"
        case .cards:
            return "Cards in plot"
        case .excluded:
            return "Excluded"
        }
    }
}

enum PlotAccountMoveAction: Equatable {
    case setKind(AccountKind)
    case setAvailableCash(Bool)
    case setCreditCardDebt(Bool)
}

enum PlotAccountMovePlanner {
    static func override(
        for account: FinancialAccount,
        destination: PlotAccountGroup,
        snapshot: BudgetSnapshot
    ) -> AccountOverride? {
        var override = snapshot.accountOverrides[account.id] ?? AccountOverride()

        for action in actions(for: account, destination: destination, snapshot: snapshot) {
            switch action {
            case .setKind(let kind):
                override.kind = kind
                if kind == .checking {
                    override.includesInAvailableCash = override.includesInAvailableCash ?? true
                } else {
                    override.includesInAvailableCash = false
                }
            case .setAvailableCash(let isAvailable):
                override.includesInAvailableCash = isAvailable
            case .setCreditCardDebt(let isIncluded):
                override.includesInCreditCardDebt = isIncluded
            }
        }

        return override.kind == nil
            && override.includesInAvailableCash == nil
            && override.includesInCreditCardDebt == nil ? nil : override
    }

    static func actions(
        for account: FinancialAccount,
        destination: PlotAccountGroup,
        snapshot: BudgetSnapshot
    ) -> [PlotAccountMoveAction] {
        switch destination {
        case .cash:
            if account.kind != .checking && account.kind != .savings {
                return [.setKind(.checking), .setAvailableCash(true)]
            }

            return snapshot.includesInAvailableCash(account) ? [] : [.setAvailableCash(true)]

        case .cards:
            var actions: [PlotAccountMoveAction] = []
            if account.kind != .creditCard {
                actions.append(.setKind(.creditCard))
            }
            if !snapshot.includesInCreditCardDebt(account) {
                actions.append(.setCreditCardDebt(true))
            }
            return actions

        case .excluded:
            if account.kind == .creditCard {
                return snapshot.includesInCreditCardDebt(account) ? [.setCreditCardDebt(false)] : []
            }

            return snapshot.includesInAvailableCash(account) ? [.setAvailableCash(false)] : []
        }
    }
}

private extension AccountKind {
    var plotSystemImage: String {
        switch self {
        case .checking:
            return "building.columns"
        case .savings:
            return "banknote"
        case .creditCard:
            return "creditcard"
        case .investment:
            return "chart.line.uptrend.xyaxis"
        case .loan:
            return "doc.text"
        case .other:
            return "wallet.pass"
        }
    }
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
            .foregroundStyle(BudgetTracerStyle.inkFaint)
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

private struct SummaryPill: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(BudgetTracerStyle.ink)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .budgetTracerCard(cornerRadius: 14)
    }
}

private struct RecurringTransactionRow: View {
    var transaction: BudgetTransaction
    var isRecurring: Bool
    var setRecurring: (BudgetTransaction.ID, Bool) -> Void
    var onOpenDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenDetail) {
                HStack(spacing: 12) {
                    transactionLabel
                    Spacer(minLength: 8)
                    transactionAmount
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("Regular monthly", isOn: binding)
                .labelsHidden()
                .budgetTracerRecurringToggleStyle()
                .tint(BudgetTracerStyle.accent)
                .help("Mark as regular monthly")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        ThemeRowDivider()
            .padding(.leading, 16)
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { isRecurring },
            set: { setRecurring(transaction.id, $0) }
        )
    }

    private var transactionLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.amount.isIncome ? "arrow.down" : "arrow.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(transaction.amount.isIncome ? BudgetTracerStyle.positive : BudgetTracerStyle.caution)
                .frame(width: 28, height: 28)
                .background(
                    (transaction.amount.isIncome ? BudgetTracerStyle.positive : BudgetTracerStyle.caution).opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchantName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BudgetTracerStyle.ink)
                Text(transaction.postedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
            }
        }
    }

    private var transactionAmount: some View {
        Text(transaction.amount.formatted)
            .font(.subheadline.weight(.medium).monospacedDigit())
            .foregroundStyle(BudgetTracerStyle.ink)
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
