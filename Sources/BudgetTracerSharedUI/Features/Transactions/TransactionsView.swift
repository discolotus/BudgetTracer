import BudgetCore
import Foundation
import SwiftUI

@MainActor
struct TransactionsView: View {
    var snapshot: BudgetSnapshot
    var selectedAccountID: FinancialAccount.ID?
    var clearSelectedAccount: () -> Void = {}
    var setRecurring: (BudgetTransaction.ID, Bool) -> Void = { _, _ in }
    var setCategory: (BudgetTransaction.ID, BudgetCategory.ID?) -> Void = { _, _ in }
    var saveAssignmentRule: (BudgetAssignmentRule, Bool) -> Void = { _, _ in }

    @SceneStorage("BudgetTracer.transactions.searchText")
    private var searchText = ""

    @State private var selectedTransactionID: BudgetTransaction.ID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader

                if let selectedAccount {
                    AccountDetailSummaryView(
                        account: selectedAccount,
                        snapshot: snapshot,
                        transactionCount: transactions.count,
                        clear: clearSelectedAccount
                    )
                }

                VStack(spacing: 0) {
                    if transactions.isEmpty {
                        Text("No matching transactions.")
                            .font(.subheadline)
                            .foregroundStyle(BudgetTracerStyle.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else {
                        ForEach(transactions.indices, id: \.self) { index in
                            TransactionRowView(
                                transaction: transactions[index],
                                isRecurring: snapshot.recurringTransactionIDs.contains(transactions[index].id),
                                categoryName: categoryName(for: transactions[index]),
                                onTap: { selectedTransactionID = transactions[index].id }
                            )

                            if index < transactions.index(before: transactions.endIndex) {
                                ThemeRowDivider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
                .budgetTracerCard()
            }
            .padding()
        }
        .background(BudgetTracerStyle.canvas)
        .searchable(text: $searchText, placement: .automatic, prompt: searchPrompt)
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
    }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedAccount?.name ?? "Transactions")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("\(transactions.count) matching entries")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
            }

            Spacer()
        }
    }

    private var transactions: [BudgetTransaction] {
        TransactionListFilter.transactions(
            in: snapshot,
            searchText: searchText,
            selectedAccountID: selectedAccountID
        )
    }

    private var selectedAccount: FinancialAccount? {
        guard let selectedAccountID else {
            return nil
        }

        return snapshot.accounts.first { $0.id == selectedAccountID }
    }

    private var searchPrompt: String {
        selectedAccount == nil ? "Search merchant, budget, or date" : "Search this account"
    }

    private func categoryName(for transaction: BudgetTransaction) -> String? {
        transaction.categoryID.flatMap { categoryID in
            snapshot.categories.first { $0.id == categoryID }?.name
        }
    }

    /// Resolves the selected id back into a transaction for `.sheet(item:)`.
    private var selectedTransactionBinding: Binding<BudgetTransaction?> {
        Binding(
            get: {
                guard let selectedTransactionID else { return nil }
                return snapshot.transactions.first { $0.id == selectedTransactionID }
            },
            set: { newValue in selectedTransactionID = newValue?.id }
        )
    }
}

private struct TransactionRowView: View {
    var transaction: BudgetTransaction
    var isRecurring: Bool
    var categoryName: String?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    transactionLabel
                    Spacer()
                    amountText
                    chevron
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        transactionLabel
                        amountText
                    }
                    Spacer()
                    chevron
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var transactionLabel: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(transaction.amount.isIncome ? BudgetTracerStyle.positive : BudgetTracerStyle.accent, lineWidth: 1.6)
                .background(
                    Circle()
                        .fill((transaction.amount.isIncome ? BudgetTracerStyle.positive : BudgetTracerStyle.accent).opacity(0.08))
                )
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchantName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.ink)

                HStack(spacing: 6) {
                    Text(transaction.postedAt.formatted(date: .abbreviated, time: .omitted))
                    if let categoryName {
                        Text("·")
                        Text(categoryName)
                    }
                    if isRecurring {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .help("Regular monthly")
                    }
                    categorySourceIcon
                }
                .font(.caption)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
            }
        }
    }

    @ViewBuilder
    private var categorySourceIcon: some View {
        switch transaction.categoryAssignmentSource {
        case .rule:
            Image(systemName: "wand.and.stars")
                .help("Assigned by rule")
        case .plaid:
            Image(systemName: "tag")
                .help("Suggested by Plaid")
        case .manual, nil:
            EmptyView()
        }
    }

    private var amountText: some View {
        Text(transaction.amount.formatted)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(transaction.amount.isExpense ? BudgetTracerStyle.ink : BudgetTracerStyle.positive)
            .monospacedDigit()
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(BudgetTracerStyle.inkFaint)
    }
}
