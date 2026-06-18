import Foundation

public extension BudgetSnapshot {
    func accountBalanceHistory(
        for accountID: FinancialAccount.ID,
        calendar: Calendar = Calendar.current,
        anchorDate: Date? = nil
    ) -> [AccountBalancePoint] {
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            return []
        }

        let accountTransactions = transactions.filter { $0.accountID == accountID }
        let latestTransactionDate = accountTransactions.map(\.postedAt).max()
        let rawAnchorDate: Date
        if let anchorDate {
            rawAnchorDate = anchorDate
        } else if let lastSuccessfulSyncAt {
            rawAnchorDate = [lastSuccessfulSyncAt, latestTransactionDate]
                .compactMap { $0 }
                .max() ?? lastSuccessfulSyncAt
        } else {
            rawAnchorDate = latestTransactionDate ?? Date()
        }
        let anchorDay = calendar.startOfDay(for: rawAnchorDate)

        guard let earliestTransactionDate = accountTransactions.map(\.postedAt).min() else {
            return [
                AccountBalancePoint(
                    date: anchorDay,
                    balance: account.currentBalance,
                    dailyNet: Money(minorUnits: 0, currencyCode: account.currentBalance.currencyCode),
                    transactionCount: 0
                )
            ]
        }

        let startDay = calendar.startOfDay(for: min(earliestTransactionDate, anchorDay))
        var dailyActivity: [Date: AccountDailyBalanceActivity] = [:]

        for transaction in accountTransactions {
            let day = calendar.startOfDay(for: transaction.postedAt)
            let delta = accountBalanceDelta(for: transaction, account: account)
            var activity = dailyActivity[day] ?? AccountDailyBalanceActivity()
            activity.deltaMinorUnits += delta
            activity.transactionCount += 1
            dailyActivity[day] = activity
        }

        var reversedPoints: [AccountBalancePoint] = []
        var closingBalanceMinorUnits = account.currentBalance.minorUnits
        var cursor = anchorDay

        while cursor >= startDay {
            let activity = dailyActivity[cursor] ?? AccountDailyBalanceActivity()
            reversedPoints.append(
                AccountBalancePoint(
                    date: cursor,
                    balance: Money(
                        minorUnits: closingBalanceMinorUnits,
                        currencyCode: account.currentBalance.currencyCode
                    ),
                    dailyNet: Money(
                        minorUnits: activity.deltaMinorUnits,
                        currencyCode: account.currentBalance.currencyCode
                    ),
                    transactionCount: activity.transactionCount
                )
            )

            closingBalanceMinorUnits -= activity.deltaMinorUnits

            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }

        return reversedPoints.reversed()
    }
}

public struct AccountBalancePoint: Identifiable, Hashable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var balance: Money
    public var dailyNet: Money
    public var transactionCount: Int

    public var hasTransactions: Bool {
        transactionCount > 0
    }

    public init(date: Date, balance: Money, dailyNet: Money, transactionCount: Int) {
        self.date = date
        self.balance = balance
        self.dailyNet = dailyNet
        self.transactionCount = transactionCount
    }
}

private struct AccountDailyBalanceActivity {
    var deltaMinorUnits: Int64 = 0
    var transactionCount = 0
}

private extension BudgetSnapshot {
    func accountBalanceDelta(for transaction: BudgetTransaction, account: FinancialAccount) -> Int64 {
        let kind = accountOverrides[account.id]?.kind ?? account.kind

        switch kind {
        case .creditCard:
            return -transaction.amount.minorUnits
        case .checking, .savings, .investment, .loan, .other:
            return transaction.amount.minorUnits
        }
    }
}
