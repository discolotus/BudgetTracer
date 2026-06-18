import BudgetCore
import Foundation

enum TransactionListFilter {
    static func transactions(
        in snapshot: BudgetSnapshot,
        searchText: String,
        selectedAccountID: FinancialAccount.ID?
    ) -> [BudgetTransaction] {
        snapshot.transactions
            .filter { transaction in
                if let selectedAccountID, transaction.accountID != selectedAccountID {
                    return false
                }

                return TransactionSearch.matches(transaction, query: searchText, in: snapshot)
            }
            .sorted { $0.postedAt > $1.postedAt }
    }
}
