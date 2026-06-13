import BudgetCore
import SwiftUI

/// Tap-through detail for a single transaction: mark it regular-monthly and reassign it
/// to a budget category. Reads live state from the snapshot so edits reflect immediately.
struct TransactionDetailSheet: View {
    var transaction: BudgetTransaction
    var snapshot: BudgetSnapshot
    var setRecurring: (BudgetTransaction.ID, Bool) -> Void
    var setCategory: (BudgetTransaction.ID, BudgetCategory.ID?) -> Void
    var dismiss: () -> Void

    private var isRecurring: Bool {
        snapshot.recurringTransactionIDs.contains(transaction.id)
    }

    private var accountName: String? {
        snapshot.accounts.first { $0.id == transaction.accountID }?.name
    }

    private var amountColor: Color {
        transaction.amount.isIncome ? BudgetTracerStyle.positive : BudgetTracerStyle.ink
    }

    private var recurringBinding: Binding<Bool> {
        Binding(
            get: { isRecurring },
            set: { setRecurring(transaction.id, $0) }
        )
    }

    private var categoryBinding: Binding<BudgetCategory.ID?> {
        Binding(
            get: { transaction.categoryID },
            set: { setCategory(transaction.id, $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            handle

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    detailCard
                    controlsCard
                }
                .padding(20)
            }
        }
        .background(BudgetTracerStyle.canvas)
        .frame(idealWidth: 440, idealHeight: 520)
        #if os(macOS)
        .frame(width: 440, height: 540)
        #endif
    }

    private var handle: some View {
        HStack {
            EyebrowText("Transaction")
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
                    .frame(width: 30, height: 30)
                    .background(BudgetTracerStyle.surfaceSunken, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(transaction.merchantName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(BudgetTracerStyle.ink)

            Text(transaction.amount.formatted)
                .font(.system(size: 34, weight: .semibold))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            detailRow("Date", transaction.postedAt.formatted(date: .long, time: .omitted))

            if let accountName {
                ThemeRowDivider()
                detailRow("Account", accountName)
            }

            if let note = transaction.note, !note.isEmpty {
                ThemeRowDivider()
                detailRow("Note", note)
            }
        }
        .budgetTracerCard()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
            Spacer(minLength: 16)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var controlsCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: recurringBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Regular monthly")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BudgetTracerStyle.ink)
                    Text("Spread this amount evenly across the month")
                        .font(.caption)
                        .foregroundStyle(BudgetTracerStyle.inkMuted)
                }
            }
            .tint(BudgetTracerStyle.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            ThemeRowDivider()

            HStack {
                Text("Budget")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BudgetTracerStyle.ink)
                Spacer()
                Picker("Budget", selection: categoryBinding) {
                    Text("Uncategorized").tag(BudgetCategory.ID?.none)
                    ForEach(snapshot.categories, id: \.id) { category in
                        Text(category.name).tag(BudgetCategory.ID?.some(category.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(BudgetTracerStyle.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .budgetTracerCard()
    }
}
