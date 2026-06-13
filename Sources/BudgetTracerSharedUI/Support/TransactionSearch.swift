import BudgetCore
import Foundation

enum TransactionSearch {
    static func matches(
        _ transaction: BudgetTransaction,
        query: String,
        categoryName: String? = nil
    ) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return true
        }

        let searchableText = [
            transaction.merchantName,
            categoryName,
            transaction.note,
            transaction.amount.formatted,
            transaction.postedAt.formatted(date: .abbreviated, time: .omitted),
            transaction.postedAt.formatted(.dateTime.month(.wide)),
            transaction.postedAt.formatted(.dateTime.month(.abbreviated)),
            String(Calendar.current.component(.year, from: transaction.postedAt))
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        return searchableText.localizedCaseInsensitiveContains(normalizedQuery)
    }

    /// Resolves the category name for a transaction from a snapshot, then matches.
    static func matches(
        _ transaction: BudgetTransaction,
        query: String,
        in snapshot: BudgetSnapshot
    ) -> Bool {
        let categoryName = transaction.categoryID.flatMap { categoryID in
            snapshot.categories.first { $0.id == categoryID }?.name
        }

        return matches(transaction, query: query, categoryName: categoryName)
    }
}
