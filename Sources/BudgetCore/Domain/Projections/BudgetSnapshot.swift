import Foundation

public struct BudgetSnapshot: Hashable, Sendable {
    public var institutions: [Institution]
    public var accounts: [FinancialAccount]
    public var categories: [BudgetCategory]
    public var transactions: [BudgetTransaction]
    public var recurringTransactionIDs: Set<BudgetTransaction.ID>

    public init(
        institutions: [Institution],
        accounts: [FinancialAccount],
        categories: [BudgetCategory],
        transactions: [BudgetTransaction],
        recurringTransactionIDs: Set<BudgetTransaction.ID> = []
    ) {
        self.institutions = institutions
        self.accounts = accounts
        self.categories = categories
        self.transactions = transactions
        self.recurringTransactionIDs = recurringTransactionIDs
    }

    public var totalCash: Money {
        accounts
            .filter { $0.kind == .checking || $0.kind == .savings }
            .map(\.currentBalance)
            .reduce(Money(minorUnits: 0), +)
    }

    public var creditDebt: Money {
        accounts
            .filter { $0.kind == .creditCard }
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

    public func normalizedMonthlyCashFlow(
        containing date: Date? = nil,
        calendar: Calendar = Calendar.current,
        through cutoffDate: Date? = nil
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
        var dailyNetMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
        var dailyCashMinorUnits = Array(repeating: Int64(0), count: daysInMonth)
        var dailyCreditDebtMinorUnits = Array(repeating: Int64(0), count: daysInMonth)

        for transaction in monthTransactions {
            if recurringTransactionIDs.contains(transaction.id) {
                distribute(transaction.amount.minorUnits, across: &dailyNetMinorUnits)
                distributeTransaction(
                    transaction,
                    account: accountsByID[transaction.accountID],
                    acrossCash: &dailyCashMinorUnits,
                    creditDebt: &dailyCreditDebtMinorUnits
                )
            } else if let dayIndex = dayIndex(for: transaction.postedAt, in: monthInterval, calendar: calendar) {
                dailyNetMinorUnits[dayIndex] += transaction.amount.minorUnits
                applyTransaction(
                    transaction,
                    account: accountsByID[transaction.accountID],
                    cashDelta: &dailyCashMinorUnits[dayIndex],
                    creditDebtDelta: &dailyCreditDebtMinorUnits[dayIndex]
                )
            }
        }

        var runningCashBalance = cashFlowCashBalance
        var runningCreditDebt = creditDebt

        return dailyNetMinorUnits.prefix(renderedDayCount).enumerated().compactMap { offset, netMinorUnits in
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
                runningCreditDebt: runningCreditDebt
            )
        }
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

    private func distributeTransaction(
        _ transaction: BudgetTransaction,
        account: FinancialAccount?,
        acrossCash dailyCashMinorUnits: inout [Int64],
        creditDebt dailyCreditDebtMinorUnits: inout [Int64]
    ) {
        switch account?.kind {
        case .creditCard:
            distribute(-transaction.amount.minorUnits, across: &dailyCreditDebtMinorUnits)
        case .checking, .savings:
            if isCashFlowCashAccount(account) {
                distribute(transaction.amount.minorUnits, across: &dailyCashMinorUnits)
            }
        case .investment, .loan, .other:
            return
        case .none:
            distribute(transaction.amount.minorUnits, across: &dailyCashMinorUnits)
        }
    }

    private func applyTransaction(
        _ transaction: BudgetTransaction,
        account: FinancialAccount?,
        cashDelta: inout Int64,
        creditDebtDelta: inout Int64
    ) {
        switch account?.kind {
        case .creditCard:
            creditDebtDelta += -transaction.amount.minorUnits
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

    private var cashFlowCashBalance: Money {
        accounts
            .filter { isCashFlowCashAccount($0) }
            .map(\.currentBalance)
            .reduce(Money(minorUnits: 0), +)
    }

    private func isCashFlowCashAccount(_ account: FinancialAccount?) -> Bool {
        guard let account else {
            return true
        }

        guard account.kind == .checking || account.kind == .savings else {
            return false
        }

        let subtype = account.plaidSubtype?.lowercased()
        return subtype != "money market"
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
    public var runningCashMinusCreditDebt: Money {
        runningCashBalance - runningCreditDebt
    }

    public init(
        date: Date,
        dailyNet: Money,
        runningCashBalance: Money,
        runningCreditDebt: Money = Money(minorUnits: 0)
    ) {
        self.date = date
        self.dailyNet = dailyNet
        self.runningCashBalance = runningCashBalance
        self.runningCreditDebt = runningCreditDebt
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
