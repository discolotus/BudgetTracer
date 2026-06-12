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
        ScrollView {
            VStack(spacing: 0) {
                if transactionRows.isEmpty {
                    Text("No matching transactions.")
                        .font(.subheadline)
                        .foregroundStyle(BudgetTracerStyle.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    ForEach(transactionRows.indices, id: \.self) { index in
                        TransactionRowView(row: transactionRows[index])

                        if index < transactionRows.index(before: transactionRows.endIndex) {
                            ThemeRowDivider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
            .budgetTracerCard()
            .padding()
        }
        .background(BudgetTracerStyle.canvas)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var transactionLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.merchantName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.ink)
            Text(row.postedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
        }
    }

    private var amountText: some View {
        Text(row.amount.formatted)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(row.amount.isExpense ? BudgetTracerStyle.ink : BudgetTracerStyle.positive)
            .monospacedDigit()
    }
}
