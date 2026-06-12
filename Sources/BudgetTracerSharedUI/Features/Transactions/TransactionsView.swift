import BudgetCore
import Foundation
import SwiftUI

private struct TransactionRow: Identifiable, Hashable {
    typealias ID = String

    var id: String
    var merchantName: String
    var postedAt: Date
    var amount: Money
}

@MainActor
struct TransactionsView: View {
    var snapshot: BudgetSnapshot

    @SceneStorage("BudgetTracer.transactions.searchText")
    private var searchText = ""

    var body: some View {
        List {
            ForEach<[TransactionRow], TransactionRow.ID, TransactionRowView>(transactionRows) { row in
                TransactionRowView(row: row)
            }
        }
        .scrollContentBackground(.hidden)
        .background(BudgetTracerStyle.screenBackground)
        .searchable(text: $searchText, placement: .automatic, prompt: "Search transactions")
    }

    private var transactionRows: [TransactionRow] {
        snapshot.transactions
            .filter { TransactionSearch.matches($0, query: searchText) }
            .sorted { $0.postedAt > $1.postedAt }
            .map {
                TransactionRow(
                    id: $0.id,
                    merchantName: $0.merchantName,
                    postedAt: $0.postedAt,
                    amount: $0.amount
                )
        }
    }
}

private struct TransactionRowView: View {
    var row: TransactionRow

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                transactionLabel
                Spacer()
                amountText
            }

            VStack(alignment: .leading, spacing: 8) {
                transactionLabel
                amountText
            }
        }
        .padding(.vertical, 4)
    }

    private var transactionLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.merchantName)
            Text(row.postedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var amountText: some View {
        Text(row.amount.formatted)
            .foregroundStyle(row.amount.isExpense ? Color.primary : BudgetTracerStyle.positive)
            .monospacedDigit()
    }
}
