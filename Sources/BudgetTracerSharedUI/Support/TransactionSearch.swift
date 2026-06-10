import BudgetCore
import Foundation

enum TransactionSearch {
    static func matches(_ transaction: BudgetTransaction, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return true
        }

        let searchableText = [
            transaction.merchantName,
            transaction.amount.formatted,
            transaction.postedAt.formatted(date: .abbreviated, time: .omitted),
            transaction.postedAt.formatted(.dateTime.month(.wide)),
            transaction.postedAt.formatted(.dateTime.month(.abbreviated)),
            String(Calendar.current.component(.year, from: transaction.postedAt))
        ]
        .joined(separator: " ")

        return searchableText.localizedCaseInsensitiveContains(normalizedQuery)
    }
}
