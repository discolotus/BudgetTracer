import Foundation

public struct BudgetSnapshot: Hashable, Sendable {
    public var institutions: [Institution]
    public var accounts: [FinancialAccount]
    public var categories: [BudgetCategory]
    public var assignmentRules: [BudgetAssignmentRule]
    public var transactions: [BudgetTransaction]
    public var recurringTransactionIDs: Set<BudgetTransaction.ID>
    public var accountOverrides: [FinancialAccount.ID: AccountOverride]
    public var lastSuccessfulSyncAt: Date?

    public init(
        institutions: [Institution],
        accounts: [FinancialAccount],
        categories: [BudgetCategory],
        assignmentRules: [BudgetAssignmentRule] = [],
        transactions: [BudgetTransaction],
        recurringTransactionIDs: Set<BudgetTransaction.ID> = [],
        accountOverrides: [FinancialAccount.ID: AccountOverride] = [:],
        lastSuccessfulSyncAt: Date? = nil
    ) {
        self.institutions = institutions
        self.accounts = accounts
        self.categories = categories
        self.assignmentRules = assignmentRules
        self.transactions = transactions
        self.recurringTransactionIDs = recurringTransactionIDs
        self.accountOverrides = accountOverrides
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    }

    public var totalCash: Money {
        accounts
            .filter { $0.kind == .checking || $0.kind == .savings }
            .map(\.currentBalance)
            .reduce(Money(minorUnits: 0), +)
    }

    public var availableCash: Money {
        accounts
            .filter { isAvailableCashAccount($0, override: accountOverrides[$0.id]) }
            .map(\.currentBalance)
            .reduce(Money(minorUnits: 0), +)
    }

    public var creditDebt: Money {
        accounts
            .filter { isCreditCardDebtAccount($0, override: accountOverrides[$0.id]) }
            .map(\.currentBalance)
            .reduce(Money(minorUnits: 0), +)
    }

    public var monthlyIncome: Money {
        transactions
            .map(\.amount)
            .filter(\.isIncome)
            .reduce(Money(minorUnits: 0), +)
    }

    public var monthlySpending: Money {
        transactions
            .map(\.amount)
            .filter(\.isExpense)
            .map(\.absolute)
            .reduce(Money(minorUnits: 0), +)
    }

    public var netCashFlow: Money {
        monthlyIncome - monthlySpending
    }

    public func spendingByCategory() -> [CategorySpend] {
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let grouped = Dictionary(grouping: transactions.filter { $0.amount.isExpense }) { transaction in
            transaction.categoryID ?? "uncategorized"
        }

        return grouped.map { categoryID, transactions in
            let total = transactions
                .map(\.amount.absolute)
                .reduce(Money(minorUnits: 0), +)

            return CategorySpend(
                categoryID: categoryID,
                categoryName: categoryNames[categoryID] ?? "Uncategorized",
                spent: total
            )
        }
        .sorted { $0.spent.minorUnits > $1.spent.minorUnits }
    }

    public func applying(accountOverrides overrides: [FinancialAccount.ID: AccountOverride]) -> BudgetSnapshot {
        var snapshot = self
        var migratedOverrides: [FinancialAccount.ID: AccountOverride] = [:]
        for account in accounts {
            migratedOverrides[account.id] = Self.migratedAccountOverride(overrides[account.id], for: account)
        }
        snapshot.accountOverrides = migratedOverrides
        snapshot.accounts = accounts.map { account in
            guard let kind = migratedOverrides[account.id]?.kind else {
                return account
            }

            var adjustedAccount = account
            adjustedAccount.kind = kind
            return adjustedAccount
        }
        return snapshot
    }

    public func includesInAvailableCash(_ account: FinancialAccount) -> Bool {
        isAvailableCashAccount(account, override: accountOverrides[account.id])
    }

    public func includesInCreditCardDebt(_ account: FinancialAccount) -> Bool {
        isCreditCardDebtAccount(account, override: accountOverrides[account.id])
    }

    private static func migratedAccountOverride(
        _ override: AccountOverride?,
        for account: FinancialAccount
    ) -> AccountOverride? {
        guard var override else {
            return nil
        }

        if account.kind == .creditCard,
           override.kind == .other,
           override.includesInAvailableCash == false,
           override.includesInCreditCardDebt == nil {
            override.kind = nil
            override.includesInAvailableCash = nil
            override.includesInCreditCardDebt = false
        }

        return override
    }

    public func normalizedMonthlyCashFlow(
        containing date: Date? = nil,
        calendar: Calendar = Calendar.current,
        through cutoffDate: Date? = nil,
        balanceBasis: CashFlowBalanceBasis = .accountBalances,
        balanceAnchorEnd: Date? = nil
    ) -> [NormalizedCashFlowPoint] {
        let analysisDate = date ?? normalizedMonthlyAnalysisDate(calendar: calendar)
        guard let monthInterval = calendar.dateInterval(of: .month, for: analysisDate),
              let dayRange = calendar.range(of: .day, in: .month, for: analysisDate) else {
            return []
        }

        let daysInMonth = dayRange.count
        let renderedDayCount = renderedDayCount(
            in: monthInterval,
            daysInMonth: daysInMonth,
            through: cutoffDate,
            calendar: calendar
        )
        let transactionInterval = transactionInterval(for: monthInterval, through: cutoffDate, calendar: calendar)
        let monthTransactions = transactions.filter { transactionInterval.contains($0.postedAt) }
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let openingBalances = openingCashFlowBalances(
            startingAt: monthInterval.start,
            through: balanceAnchorEnd ?? (cutoffDate == nil ? nil : transactionInterval.end),
            accountsByID: accountsByID,
            balanceBasis: balanceBasis
        )
        var dailyNetMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
        var dailyCashMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
        var dailyCreditDebtMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
        var hasPostedCashTransactions = Array(repeating: false, count: daysInMonth)
        var hasPostedCardTransactions = Array(repeating: false, count: daysInMonth)

        let renderedOffsetArray = Array(0..<renderedDayCount)
        for transaction in monthTransactions {
            let account = accountsByID[transaction.accountID]
            let isRecurring = recurringTransactionIDs.contains(transaction.id)

            if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                hasPostedCashTransactions[dayIndex] = hasPostedCashTransactions[dayIndex]
                    || affectsCashBalance(transaction, account: account)
                hasPostedCardTransactions[dayIndex] = hasPostedCardTransactions[dayIndex]
                    || affectsCardBalance(transaction, account: account)
            }

            if isRecurring {
                distribute(transaction.amount.minorUnits, across: &dailyNetMinorUnits)
                distributeTransaction(
                    transaction,
                    account: account,
                    acrossOffsets: renderedOffsetArray,
                    cash: &dailyCashMinorUnits,
                    creditDebt: &dailyCreditDebtMinorUnits
                )
            } else if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                dailyNetMinorUnits[dayIndex] += transaction.amount.minorUnits
                applyTransaction(
                    transaction,
                    account: account,
                    cashDelta: &dailyCashMinorUnits[dayIndex],
                    creditDebtDelta: &dailyCreditDebtMinorUnits[dayIndex]
                )
            }
        }

        var runningCashBalance: Money
        var runningCreditDebt: Money
        switch balanceBasis {
        case .accountBalances:
            runningCashBalance = openingBalances.cashBalance
            runningCreditDebt = openingBalances.creditDebt
        case .monthStartZero:
            runningCashBalance = Money(minorUnits: 0)
            runningCreditDebt = Money(minorUnits: 0)
        }

        let points: [NormalizedCashFlowPoint] = dailyNetMinorUnits.prefix(renderedDayCount).enumerated().compactMap { offset, netMinorUnits in
            guard let day = calendar.date(byAdding: .day, value: offset, to: monthInterval.start) else {
                return nil
            }

            let dailyNet = Money(minorUnits: netMinorUnits)
            runningCashBalance = runningCashBalance + Money(minorUnits: dailyCashMinorUnits[offset])
            runningCreditDebt = runningCreditDebt + Money(minorUnits: dailyCreditDebtMinorUnits[offset])

            return NormalizedCashFlowPoint(
                date: day,
                dailyNet: dailyNet,
                runningCashBalance: runningCashBalance,
                runningCreditDebt: runningCreditDebt,
                hasPostedCashTransactions: hasPostedCashTransactions[offset],
                hasPostedCardTransactions: hasPostedCardTransactions[offset]
            )
        }

        guard balanceBasis == .monthStartZero else {
            return points
        }

        return points.rebasedToZeroStart()
    }

    public func normalizedCashFlow(
        in dateInterval: DateInterval,
        calendar: Calendar = Calendar.current,
        balanceBasis: CashFlowBalanceBasis = .accountBalances,
        balanceAnchorEnd: Date? = nil
    ) -> [NormalizedCashFlowPoint] {
        guard dateInterval.start < dateInterval.end else {
            return []
        }

        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let openingBalances = openingCashFlowBalances(
            startingAt: dateInterval.start,
            through: balanceAnchorEnd,
            accountsByID: accountsByID,
            balanceBasis: balanceBasis
        )
        var runningCashBalance: Money
        var runningCreditDebt: Money
        switch balanceBasis {
        case .accountBalances:
            runningCashBalance = openingBalances.cashBalance
            runningCreditDebt = openingBalances.creditDebt
        case .monthStartZero:
            runningCashBalance = Money(minorUnits: 0)
            runningCreditDebt = Money(minorUnits: 0)
        }

        var points: [NormalizedCashFlowPoint] = []

        for monthInterval in monthIntervals(intersecting: dateInterval, calendar: calendar) {
            guard let dayRange = calendar.range(of: .day, in: .month, for: monthInterval.start),
                  let transactionInterval = clampedInterval(monthInterval, to: dateInterval) else {
                continue
            }

            let daysInMonth = dayRange.count
            let renderedOffsets = renderedDayOffsets(
                in: monthInterval,
                daysInMonth: daysInMonth,
                clippedTo: dateInterval,
                calendar: calendar
            )
            guard !renderedOffsets.isEmpty else {
                continue
            }

            let monthTransactions = transactions.filter { transactionInterval.contains($0.postedAt) }
            let renderedOffsetArray = Array(renderedOffsets)
            var dailyNetMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
            var dailyCashMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
            var dailyCreditDebtMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
            var hasPostedCashTransactions = Array(repeating: false, count: daysInMonth)
            var hasPostedCardTransactions = Array(repeating: false, count: daysInMonth)

            for transaction in monthTransactions {
                let account = accountsByID[transaction.accountID]
                let isRecurring = recurringTransactionIDs.contains(transaction.id)

                if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                    hasPostedCashTransactions[dayIndex] = hasPostedCashTransactions[dayIndex]
                        || affectsCashBalance(transaction, account: account)
                    hasPostedCardTransactions[dayIndex] = hasPostedCardTransactions[dayIndex]
                        || affectsCardBalance(transaction, account: account)
                }

                if isRecurring {
                    distribute(transaction.amount.minorUnits, across: &dailyNetMinorUnits)
                    distributeTransaction(
                        transaction,
                        account: account,
                        acrossOffsets: renderedOffsetArray,
                        cash: &dailyCashMinorUnits,
                        creditDebt: &dailyCreditDebtMinorUnits
                    )
                } else if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                    dailyNetMinorUnits[dayIndex] += transaction.amount.minorUnits
                    applyTransaction(
                        transaction,
                        account: account,
                        cashDelta: &dailyCashMinorUnits[dayIndex],
                        creditDebtDelta: &dailyCreditDebtMinorUnits[dayIndex]
                    )
                }
            }

            for offset in renderedOffsets {
                guard let day = calendar.date(byAdding: .day, value: offset, to: monthInterval.start) else {
                    continue
                }

                let dailyNet = Money(minorUnits: dailyNetMinorUnits[offset])
                runningCashBalance = runningCashBalance + Money(minorUnits: dailyCashMinorUnits[offset])
                runningCreditDebt = runningCreditDebt + Money(minorUnits: dailyCreditDebtMinorUnits[offset])

                points.append(
                    NormalizedCashFlowPoint(
                        date: day,
                        dailyNet: dailyNet,
                        runningCashBalance: runningCashBalance,
                        runningCreditDebt: runningCreditDebt,
                        hasPostedCashTransactions: hasPostedCashTransactions[offset],
                        hasPostedCardTransactions: hasPostedCardTransactions[offset]
                    )
                )
            }
        }

        guard balanceBasis == .monthStartZero else {
            return points
        }

        return points.rebasedToZeroStart()
    }

    public func normalizedMonthlySpending(
        containing date: Date? = nil,
        calendar: Calendar = Calendar.current,
        through cutoffDate: Date? = nil
    ) -> [NormalizedSpendingPoint] {
        let analysisDate = date ?? normalizedMonthlyAnalysisDate(calendar: calendar)
        guard let monthInterval = calendar.dateInterval(of: .month, for: analysisDate),
              let dayRange = calendar.range(of: .day, in: .month, for: analysisDate) else {
            return []
        }

        let daysInMonth = dayRange.count
        let renderedDayCount = renderedDayCount(
            in: monthInterval,
            daysInMonth: daysInMonth,
            through: cutoffDate,
            calendar: calendar
        )
        let transactionInterval = transactionInterval(for: monthInterval, through: cutoffDate, calendar: calendar)
        let monthTransactions = transactions.filter { transactionInterval.contains($0.postedAt) }
        var actualSpendingMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
        var actualIncomeMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
        var normalizedSpendingMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
        var normalizedIncomeMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
        var averagedSpendingMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
        var averagedTransactionMarkers = Array(repeating: [AveragedTransactionMarker](), count: daysInMonth)

        for transaction in monthTransactions {
            if transaction.amount.isExpense {
                let spendingMinorUnits = transaction.amount.absolute.minorUnits

                if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                    actualSpendingMinorUnits[dayIndex] += spendingMinorUnits

                    if recurringTransactionIDs.contains(transaction.id) {
                        averagedTransactionMarkers[dayIndex].append(
                            AveragedTransactionMarker(
                                transactionID: transaction.id,
                                merchantName: transaction.merchantName,
                                amount: transaction.amount.absolute
                            )
                        )
                    }
                }

                if recurringTransactionIDs.contains(transaction.id) {
                    distribute(spendingMinorUnits, across: &normalizedSpendingMinorUnits)
                    distribute(spendingMinorUnits, across: &averagedSpendingMinorUnits)
                } else if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                    normalizedSpendingMinorUnits[dayIndex] += spendingMinorUnits
                }
            } else if transaction.amount.isIncome {
                let incomeMinorUnits = transaction.amount.minorUnits

                if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                    actualIncomeMinorUnits[dayIndex] += incomeMinorUnits
                }

                if recurringTransactionIDs.contains(transaction.id) {
                    distribute(incomeMinorUnits, across: &normalizedIncomeMinorUnits)
                } else if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                    normalizedIncomeMinorUnits[dayIndex] += incomeMinorUnits
                }
            }
        }

        var cumulativeNormalizedSpendingMinorUnits: Int64 = 0
        var cumulativeNormalizedIncomeMinorUnits: Int64 = 0

        return normalizedSpendingMinorUnits.prefix(renderedDayCount).indices.compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: monthInterval.start) else {
                return nil
            }
            cumulativeNormalizedSpendingMinorUnits += normalizedSpendingMinorUnits[offset]
            cumulativeNormalizedIncomeMinorUnits += normalizedIncomeMinorUnits[offset]

            return NormalizedSpendingPoint(
                date: day,
                actualSpending: Money(minorUnits: actualSpendingMinorUnits[offset]),
                actualIncome: Money(minorUnits: actualIncomeMinorUnits[offset]),
                normalizedSpending: Money(minorUnits: normalizedSpendingMinorUnits[offset]),
                normalizedIncome: Money(minorUnits: normalizedIncomeMinorUnits[offset]),
                cumulativeNormalizedSpending: Money(minorUnits: cumulativeNormalizedSpendingMinorUnits),
                cumulativeNormalizedIncome: Money(minorUnits: cumulativeNormalizedIncomeMinorUnits),
                averagedRecurringSpending: Money(minorUnits: averagedSpendingMinorUnits[offset]),
                averagedTransactionMarkers: averagedTransactionMarkers[offset]
            )
        }
    }

    public func normalizedSpending(
        in dateInterval: DateInterval,
        calendar: Calendar = Calendar.current
    ) -> [NormalizedSpendingPoint] {
        guard dateInterval.start < dateInterval.end else {
            return []
        }

        var points: [NormalizedSpendingPoint] = []
        var cumulativeNormalizedSpendingMinorUnits: Int64 = 0
        var cumulativeNormalizedIncomeMinorUnits: Int64 = 0

        for monthInterval in monthIntervals(intersecting: dateInterval, calendar: calendar) {
            guard let dayRange = calendar.range(of: .day, in: .month, for: monthInterval.start),
                  let transactionInterval = clampedInterval(monthInterval, to: dateInterval) else {
                continue
            }

            let daysInMonth = dayRange.count
            let renderedOffsets = renderedDayOffsets(
                in: monthInterval,
                daysInMonth: daysInMonth,
                clippedTo: dateInterval,
                calendar: calendar
            )
            guard !renderedOffsets.isEmpty else {
                continue
            }

            let monthTransactions = transactions.filter { transactionInterval.contains($0.postedAt) }
            var actualSpendingMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
            var actualIncomeMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
            var normalizedSpendingMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
            var normalizedIncomeMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
            var averagedSpendingMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
            var averagedTransactionMarkers = Array(repeating: [AveragedTransactionMarker](), count: daysInMonth)

            for transaction in monthTransactions {
                if transaction.amount.isExpense {
                    let spendingMinorUnits = transaction.amount.absolute.minorUnits

                    if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                        actualSpendingMinorUnits[dayIndex] += spendingMinorUnits

                        if recurringTransactionIDs.contains(transaction.id) {
                            averagedTransactionMarkers[dayIndex].append(
                                AveragedTransactionMarker(
                                    transactionID: transaction.id,
                                    merchantName: transaction.merchantName,
                                    amount: transaction.amount.absolute
                                )
                            )
                        }
                    }

                    if recurringTransactionIDs.contains(transaction.id) {
                        distribute(spendingMinorUnits, across: &normalizedSpendingMinorUnits)
                        distribute(spendingMinorUnits, across: &averagedSpendingMinorUnits)
                    } else if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                        normalizedSpendingMinorUnits[dayIndex] += spendingMinorUnits
                    }
                } else if transaction.amount.isIncome {
                    let incomeMinorUnits = transaction.amount.minorUnits

                    if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                        actualIncomeMinorUnits[dayIndex] += incomeMinorUnits
                    }

                    if recurringTransactionIDs.contains(transaction.id) {
                        distribute(incomeMinorUnits, across: &normalizedIncomeMinorUnits)
                    } else if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                        normalizedIncomeMinorUnits[dayIndex] += incomeMinorUnits
                    }
                }
            }

            for offset in renderedOffsets {
                guard let day = calendar.date(byAdding: .day, value: offset, to: monthInterval.start) else {
                    continue
                }

                cumulativeNormalizedSpendingMinorUnits += normalizedSpendingMinorUnits[offset]
                cumulativeNormalizedIncomeMinorUnits += normalizedIncomeMinorUnits[offset]

                points.append(
                    NormalizedSpendingPoint(
                        date: day,
                        actualSpending: Money(minorUnits: actualSpendingMinorUnits[offset]),
                        actualIncome: Money(minorUnits: actualIncomeMinorUnits[offset]),
                        normalizedSpending: Money(minorUnits: normalizedSpendingMinorUnits[offset]),
                        normalizedIncome: Money(minorUnits: normalizedIncomeMinorUnits[offset]),
                        cumulativeNormalizedSpending: Money(minorUnits: cumulativeNormalizedSpendingMinorUnits),
                        cumulativeNormalizedIncome: Money(minorUnits: cumulativeNormalizedIncomeMinorUnits),
                        averagedRecurringSpending: Money(minorUnits: averagedSpendingMinorUnits[offset]),
                        averagedTransactionMarkers: averagedTransactionMarkers[offset]
                    )
                )
            }
        }

        return points
    }

    public func cumulativeTransactionSpending(
        containing date: Date? = nil,
        calendar: Calendar = Calendar.current,
        through cutoffDate: Date? = nil
    ) -> [CumulativeTransactionSpendingPoint] {
        let analysisDate = date ?? normalizedMonthlyAnalysisDate(calendar: calendar)
        guard let monthInterval = calendar.dateInterval(of: .month, for: analysisDate) else {
            return []
        }
        let transactionInterval = transactionInterval(for: monthInterval, through: cutoffDate, calendar: calendar)

        let monthTransactions = transactions
            .filter { $0.amount.isExpense && transactionInterval.contains($0.occurredAt) }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt < $1.occurredAt
                }

                return $0.id < $1.id
            }

        var cumulativeSpending = Money(minorUnits: 0)

        return monthTransactions.map { transaction in
            cumulativeSpending = cumulativeSpending + transaction.amount.absolute
            return CumulativeTransactionSpendingPoint(
                transactionID: transaction.id,
                occurredAt: transaction.occurredAt,
                merchantName: transaction.merchantName,
                amount: transaction.amount.absolute,
                cumulativeSpending: cumulativeSpending,
                isAveraged: recurringTransactionIDs.contains(transaction.id)
            )
        }
    }

    public func cumulativeTransactionSpending(
        in dateInterval: DateInterval,
        calendar: Calendar = Calendar.current
    ) -> [CumulativeTransactionSpendingPoint] {
        guard dateInterval.start < dateInterval.end else {
            return []
        }

        let rangeTransactions = transactions
            .filter { $0.amount.isExpense && dateInterval.contains($0.occurredAt) }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt < $1.occurredAt
                }

                return $0.id < $1.id
            }

        var cumulativeSpending = Money(minorUnits: 0)

        return rangeTransactions.map { transaction in
            cumulativeSpending = cumulativeSpending + transaction.amount.absolute
            return CumulativeTransactionSpendingPoint(
                transactionID: transaction.id,
                occurredAt: transaction.occurredAt,
                merchantName: transaction.merchantName,
                amount: transaction.amount.absolute,
                cumulativeSpending: cumulativeSpending,
                isAveraged: recurringTransactionIDs.contains(transaction.id)
            )
        }
    }

    public func normalizedMonthlyAnalysisDate(calendar: Calendar = Calendar.current) -> Date {
        let groupedByMonth = Dictionary(grouping: transactions) { transaction in
            calendar.dateInterval(of: .month, for: transaction.postedAt)?.start ?? transaction.postedAt
        }

        return groupedByMonth
            .max { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count < rhs.value.count
                }

                return lhs.key < rhs.key
            }?
            .key
            ?? Date()
    }

    public func availableTransactionMonths(calendar: Calendar = Calendar.current) -> [Date] {
        Array(
            Set(
                transactions.compactMap { transaction in
                    calendar.dateInterval(of: .month, for: transaction.postedAt)?.start
                }
            )
        )
        .sorted()
    }

    private func monthIntervals(intersecting dateInterval: DateInterval, calendar: Calendar) -> [DateInterval] {
        guard let firstMonth = calendar.dateInterval(of: .month, for: dateInterval.start) else {
            return []
        }

        var intervals: [DateInterval] = []
        var cursor = firstMonth.start

        while cursor < dateInterval.end {
            guard let monthInterval = calendar.dateInterval(of: .month, for: cursor) else {
                break
            }

            if clampedInterval(monthInterval, to: dateInterval) != nil {
                intervals.append(monthInterval)
            }

            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }
            cursor = nextMonth
        }

        return intervals
    }

    private func clampedInterval(_ interval: DateInterval, to bounds: DateInterval) -> DateInterval? {
        let start = max(interval.start, bounds.start)
        let end = min(interval.end, bounds.end)

        guard start < end else {
            return nil
        }

        return DateInterval(start: start, end: end)
    }

    private func renderedDayOffsets(
        in monthInterval: DateInterval,
        daysInMonth: Int,
        clippedTo dateInterval: DateInterval,
        calendar: Calendar
    ) -> Range<Int> {
        guard let clippedInterval = clampedInterval(monthInterval, to: dateInterval) else {
            return 0..<0
        }

        let startOffset = dayOffset(
            for: calendar.startOfDay(for: clippedInterval.start),
            in: monthInterval,
            daysInMonth: daysInMonth,
            calendar: calendar
        )
        let endOffset = renderedEndOffset(
            for: clippedInterval.end,
            in: monthInterval,
            daysInMonth: daysInMonth,
            calendar: calendar
        )

        guard startOffset < endOffset else {
            return 0..<0
        }

        return startOffset..<endOffset
    }

    private func renderedEndOffset(
        for date: Date,
        in monthInterval: DateInterval,
        daysInMonth: Int,
        calendar: Calendar
    ) -> Int {
        let dayStart = calendar.startOfDay(for: date)
        let rawOffset = dayOffset(
            for: dayStart,
            in: monthInterval,
            daysInMonth: daysInMonth,
            calendar: calendar
        )

        if date == dayStart {
            return rawOffset
        }

        return min(daysInMonth, rawOffset + 1)
    }

    private func dayOffset(
        for date: Date,
        in monthInterval: DateInterval,
        daysInMonth: Int,
        calendar: Calendar
    ) -> Int {
        let offset = calendar.dateComponents([.day], from: monthInterval.start, to: date).day ?? 0
        return min(max(offset, 0), daysInMonth)
    }

    private func applyTransaction(
        _ transaction: BudgetTransaction,
        account: FinancialAccount?,
        cashDelta: inout Int64,
        creditDebtDelta: inout Int64
    ) {
        switch account.map({ effectiveKind(for: $0) }) {
        case .creditCard:
            if isCashFlowCreditCardAccount(account) {
                creditDebtDelta += -transaction.amount.minorUnits
            }
        case .checking, .savings:
            if isCashFlowCashAccount(account) {
                cashDelta += transaction.amount.minorUnits
            }
        case .investment, .loan, .other:
            return
        case .none:
            cashDelta += transaction.amount.minorUnits
        }
    }

    private func affectsCashBalance(_ transaction: BudgetTransaction, account: FinancialAccount?) -> Bool {
        guard transaction.amount.minorUnits != 0 else {
            return false
        }

        switch account.map({ effectiveKind(for: $0) }) {
        case .checking, .savings:
            return isCashFlowCashAccount(account)
        case .creditCard, .investment, .loan, .other:
            return false
        case .none:
            return true
        }
    }

    private func affectsCardBalance(_ transaction: BudgetTransaction, account: FinancialAccount?) -> Bool {
        guard transaction.amount.minorUnits != 0 else {
            return false
        }

        switch account.map({ effectiveKind(for: $0) }) {
        case .creditCard:
            return isCashFlowCreditCardAccount(account)
        case .checking, .savings, .investment, .loan, .other:
            return false
        case .none:
            return false
        }
    }

    private var cashFlowCashBalance: Money {
        availableCash
    }

    private func openingCashFlowBalances(
        startingAt start: Date,
        through balanceAnchorEnd: Date?,
        accountsByID: [FinancialAccount.ID: FinancialAccount],
        balanceBasis: CashFlowBalanceBasis
    ) -> CashFlowOpeningBalances {
        switch balanceBasis {
        case .monthStartZero:
            return CashFlowOpeningBalances(cashBalance: Money(minorUnits: 0), creditDebt: Money(minorUnits: 0))
        case .accountBalances:
            var cashDeltaSinceStart: Int64 = 0
            var creditDebtDeltaSinceStart: Int64 = 0

            for transaction in transactions where transaction.postedAt >= start {
                if let balanceAnchorEnd, transaction.postedAt >= balanceAnchorEnd {
                    continue
                }

                var cashDelta: Int64 = 0
                var creditDebtDelta: Int64 = 0
                applyTransaction(
                    transaction,
                    account: accountsByID[transaction.accountID],
                    cashDelta: &cashDelta,
                    creditDebtDelta: &creditDebtDelta
                )
                cashDeltaSinceStart += cashDelta
                creditDebtDeltaSinceStart += creditDebtDelta
            }

            return CashFlowOpeningBalances(
                cashBalance: Money(
                    minorUnits: cashFlowCashBalance.minorUnits - cashDeltaSinceStart,
                    currencyCode: cashFlowCashBalance.currencyCode
                ),
                creditDebt: Money(
                    minorUnits: creditDebt.absolute.minorUnits - creditDebtDeltaSinceStart,
                    currencyCode: creditDebt.currencyCode
                )
            )
        }
    }

    private func isCashFlowCashAccount(_ account: FinancialAccount?) -> Bool {
        guard let account else {
            return true
        }

        return isAvailableCashAccount(account)
    }

    private func isCashFlowCreditCardAccount(_ account: FinancialAccount?) -> Bool {
        guard let account else {
            return false
        }

        return isCreditCardDebtAccount(account, override: accountOverrides[account.id])
    }

    private func isAvailableCashAccount(_ account: FinancialAccount, override: AccountOverride? = nil) -> Bool {
        if override?.includesInAvailableCash == false {
            return false
        }

        let kind = override?.kind ?? account.kind
        guard kind == .checking || kind == .savings else {
            return false
        }

        if override?.includesInAvailableCash == true {
            return true
        }

        guard kind == .checking else {
            return false
        }

        let subtype = account.plaidSubtype?.lowercased()
        return subtype != "money market" && subtype != "cd"
    }

    private func isCreditCardDebtAccount(_ account: FinancialAccount, override: AccountOverride? = nil) -> Bool {
        if override?.includesInCreditCardDebt == false {
            return false
        }

        return (override?.kind ?? account.kind) == .creditCard
    }

    private func effectiveKind(for account: FinancialAccount) -> AccountKind {
        accountOverrides[account.id]?.kind ?? account.kind
    }

    /// Spreads a recurring transaction's cash / credit-debt impact evenly across the given
    /// rendered day offsets, so the balance trace trends smoothly instead of stepping on the
    /// posting date. Spreading over the rendered offsets (rather than the raw calendar month)
    /// keeps the window's closing balance anchored to the real account balance.
    private func distributeTransaction(
        _ transaction: BudgetTransaction,
        account: FinancialAccount?,
        acrossOffsets offsets: [Int],
        cash dailyCashMinorUnits: inout [Int64],
        creditDebt dailyCreditDebtMinorUnits: inout [Int64]
    ) {
        switch account.map({ effectiveKind(for: $0) }) {
        case .creditCard:
            if isCashFlowCreditCardAccount(account) {
                distribute(-transaction.amount.minorUnits, acrossOffsets: offsets, in: &dailyCreditDebtMinorUnits)
            }
        case .checking, .savings:
            if isCashFlowCashAccount(account) {
                distribute(transaction.amount.minorUnits, acrossOffsets: offsets, in: &dailyCashMinorUnits)
            }
        case .investment, .loan, .other:
            return
        case .none:
            distribute(transaction.amount.minorUnits, acrossOffsets: offsets, in: &dailyCashMinorUnits)
        }
    }

    private func distribute(_ minorUnits: Int64, acrossOffsets offsets: [Int], in array: inout [Int64]) {
        guard !offsets.isEmpty else {
            return
        }

        let count = Int64(offsets.count)
        let base = minorUnits / count
        let remainder = minorUnits % count

        for offset in offsets {
            array[offset] += base
        }

        guard remainder != 0 else {
            return
        }

        let adjustment = remainder > 0 ? Int64(1) : Int64(-1)
        for index in 0..<Int(Swift.abs(remainder)) {
            array[offsets[index]] += adjustment
        }
    }

    private func distribute(_ minorUnits: Int64, across dailyNetMinorUnits: inout [Int64]) {
        guard !dailyNetMinorUnits.isEmpty else {
            return
        }

        let dayCount = Int64(dailyNetMinorUnits.count)
        let base = minorUnits / dayCount
        let remainder = minorUnits % dayCount

        for index in dailyNetMinorUnits.indices {
            dailyNetMinorUnits[index] += base
        }

        guard remainder != 0 else {
            return
        }

        let adjustment = remainder > 0 ? Int64(1) : Int64(-1)
        for index in 0..<Int(Swift.abs(remainder)) {
            dailyNetMinorUnits[index] += adjustment
        }
    }

    private func dayIndex(for date: Date, in monthInterval: DateInterval, calendar: Calendar) -> Int? {
        let components = calendar.dateComponents([.day], from: monthInterval.start, to: date)

        guard let day = components.day, dailyIndexIsValid(day, in: monthInterval, calendar: calendar) else {
            return nil
        }

        return day
    }

    private func dailyIndexIsValid(_ index: Int, in monthInterval: DateInterval, calendar: Calendar) -> Bool {
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthInterval.start) else {
            return false
        }

        return index >= 0 && index < dayRange.count
    }

    private func renderedDayCount(
        in monthInterval: DateInterval,
        daysInMonth: Int,
        through cutoffDate: Date?,
        calendar: Calendar
    ) -> Int {
        guard let cutoffDate,
              monthInterval.contains(cutoffDate) else {
            return daysInMonth
        }

        let cutoffDay = calendar.startOfDay(for: cutoffDate)
        let components = calendar.dateComponents([.day], from: monthInterval.start, to: cutoffDay)
        let visibleDays = (components.day ?? 0) + 1

        return min(max(visibleDays, 0), daysInMonth)
    }

    private func transactionInterval(
        for monthInterval: DateInterval,
        through cutoffDate: Date?,
        calendar: Calendar
    ) -> DateInterval {
        guard let cutoffDate,
              monthInterval.contains(cutoffDate),
              let dayAfterCutoff = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cutoffDate)) else {
            return monthInterval
        }

        return DateInterval(start: monthInterval.start, end: min(dayAfterCutoff, monthInterval.end))
    }
}

private struct CashFlowOpeningBalances {
    var cashBalance: Money
    var creditDebt: Money
}

public struct CategorySpend: Identifiable, Hashable, Sendable {
    public var id: String { categoryID }
    public var categoryID: BudgetCategory.ID
    public var categoryName: String
    public var spent: Money

    public init(categoryID: BudgetCategory.ID, categoryName: String, spent: Money) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.spent = spent
    }
}

public struct NormalizedCashFlowPoint: Identifiable, Hashable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var dailyNet: Money
    public var runningCashBalance: Money
    public var runningCreditDebt: Money
    public var hasPostedCashTransactions: Bool
    public var hasPostedCardTransactions: Bool
    public var runningCashMinusCreditDebt: Money {
        runningCashBalance - runningCreditDebt
    }

    public init(
        date: Date,
        dailyNet: Money,
        runningCashBalance: Money,
        runningCreditDebt: Money = Money(minorUnits: 0),
        hasPostedCashTransactions: Bool = false,
        hasPostedCardTransactions: Bool = false
    ) {
        self.date = date
        self.dailyNet = dailyNet
        self.runningCashBalance = runningCashBalance
        self.runningCreditDebt = runningCreditDebt
        self.hasPostedCashTransactions = hasPostedCashTransactions
        self.hasPostedCardTransactions = hasPostedCardTransactions
    }
}

public enum CashFlowBalanceBasis: String, CaseIterable, Hashable, Sendable {
    case accountBalances
    case monthStartZero
}

private extension Array where Element == NormalizedCashFlowPoint {
    func rebasedToZeroStart() -> [NormalizedCashFlowPoint] {
        guard let first else {
            return []
        }

        let cashOffset = first.runningCashBalance
        let creditDebtOffset = first.runningCreditDebt

        return map { point in
            let runningCashBalance = point.runningCashBalance - cashOffset
            let runningCreditDebt = point.runningCreditDebt - creditDebtOffset
            return NormalizedCashFlowPoint(
                date: point.date,
                dailyNet: point.dailyNet,
                runningCashBalance: runningCashBalance,
                runningCreditDebt: runningCreditDebt,
                hasPostedCashTransactions: point.hasPostedCashTransactions,
                hasPostedCardTransactions: point.hasPostedCardTransactions
            )
        }
    }
}

public struct NormalizedSpendingPoint: Identifiable, Hashable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var actualSpending: Money
    public var actualIncome: Money
    public var normalizedSpending: Money
    public var normalizedIncome: Money
    public var cumulativeNormalizedSpending: Money
    public var cumulativeNormalizedIncome: Money
    public var averagedRecurringSpending: Money
    public var averagedTransactionMarkers: [AveragedTransactionMarker]

    public init(
        date: Date,
        actualSpending: Money,
        actualIncome: Money = Money(minorUnits: 0),
        normalizedSpending: Money,
        normalizedIncome: Money = Money(minorUnits: 0),
        cumulativeNormalizedSpending: Money,
        cumulativeNormalizedIncome: Money = Money(minorUnits: 0),
        averagedRecurringSpending: Money,
        averagedTransactionMarkers: [AveragedTransactionMarker]
    ) {
        self.date = date
        self.actualSpending = actualSpending
        self.actualIncome = actualIncome
        self.normalizedSpending = normalizedSpending
        self.normalizedIncome = normalizedIncome
        self.cumulativeNormalizedSpending = cumulativeNormalizedSpending
        self.cumulativeNormalizedIncome = cumulativeNormalizedIncome
        self.averagedRecurringSpending = averagedRecurringSpending
        self.averagedTransactionMarkers = averagedTransactionMarkers
    }
}

public struct AveragedTransactionMarker: Identifiable, Hashable, Sendable {
    public var id: BudgetTransaction.ID { transactionID }
    public var transactionID: BudgetTransaction.ID
    public var merchantName: String
    public var amount: Money

    public init(transactionID: BudgetTransaction.ID, merchantName: String, amount: Money) {
        self.transactionID = transactionID
        self.merchantName = merchantName
        self.amount = amount
    }
}

public struct CumulativeTransactionSpendingPoint: Identifiable, Hashable, Sendable {
    public var id: BudgetTransaction.ID { transactionID }
    public var transactionID: BudgetTransaction.ID
    public var occurredAt: Date
    public var merchantName: String
    public var amount: Money
    public var cumulativeSpending: Money
    public var isAveraged: Bool

    public init(
        transactionID: BudgetTransaction.ID,
        occurredAt: Date,
        merchantName: String,
        amount: Money,
        cumulativeSpending: Money,
        isAveraged: Bool
    ) {
        self.transactionID = transactionID
        self.occurredAt = occurredAt
        self.merchantName = merchantName
        self.amount = amount
        self.cumulativeSpending = cumulativeSpending
        self.isAveraged = isAveraged
    }
}
