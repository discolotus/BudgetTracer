import BudgetCore
import SwiftUI

/// A set of recurring transactions that share a merchant — e.g. every month's rent payment.
/// Collapsed into a single row in the regular-monthly list; expanded into full history on tap.
struct RecurringSeries: Identifiable {
    /// Normalized merchant name, also the grouping key.
    let id: String
    /// Display name, taken from the most recent occurrence.
    let merchantName: String
    /// All occurrences across all time, newest first.
    let transactions: [BudgetTransaction]

    var ids: [BudgetTransaction.ID] { transactions.map(\.id) }
    var occurrenceCount: Int { transactions.count }
    var mostRecentDate: Date { transactions.first?.postedAt ?? .distantPast }
    var representativeAmount: Money { transactions.first?.amount ?? Money(minorUnits: 0) }
    var representativeCategoryID: BudgetCategory.ID? { transactions.first?.categoryID }

    static func normalizedMerchant(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Builds series from the recurring transactions visible in the window, pulling each
    /// series' full all-time history from the complete transaction list.
    static func build(
        windowRecurring: [BudgetTransaction],
        allTransactions: [BudgetTransaction]
    ) -> [RecurringSeries] {
        let keys = Set(windowRecurring.map { normalizedMerchant($0.merchantName) })

        return keys.compactMap { key -> RecurringSeries? in
            let history = allTransactions
                .filter { normalizedMerchant($0.merchantName) == key }
                .sorted { $0.postedAt > $1.postedAt }

            guard let mostRecent = history.first else {
                return nil
            }

            return RecurringSeries(id: key, merchantName: mostRecent.merchantName, transactions: history)
        }
        .sorted { $0.mostRecentDate > $1.mostRecentDate }
    }
}

struct RecurringSeriesRow: View {
    var series: RecurringSeries
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.accent)
                    .frame(width: 28, height: 28)
                    .background(BudgetTracerStyle.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(series.merchantName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BudgetTracerStyle.ink)
                    Text("Monthly · \(series.occurrenceCount) occurrences")
                        .font(.caption)
                        .foregroundStyle(BudgetTracerStyle.inkMuted)
                }

                Spacer(minLength: 8)

                Text(series.representativeAmount.formatted)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(BudgetTracerStyle.ink)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.inkFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        ThemeRowDivider()
            .padding(.leading, 16)
    }
}

/// History + series-level controls for a collapsed recurring series.
struct RecurringSeriesDetailSheet: View {
    var series: RecurringSeries
    var snapshot: BudgetSnapshot
    var setRecurring: ([BudgetTransaction.ID], Bool) -> Void
    var setCategory: ([BudgetTransaction.ID], BudgetCategory.ID?) -> Void
    var dismiss: () -> Void

    private var isRecurring: Bool {
        series.ids.contains { snapshot.recurringTransactionIDs.contains($0) }
    }

    private var recurringBinding: Binding<Bool> {
        Binding(
            get: { isRecurring },
            set: { setRecurring(series.ids, $0) }
        )
    }

    private var categoryBinding: Binding<BudgetCategory.ID?> {
        Binding(
            get: { series.representativeCategoryID },
            set: { setCategory(series.ids, $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            handle

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    controlsCard
                    historyCard
                }
                .padding(20)
            }
        }
        .background(BudgetTracerStyle.canvas)
        #if os(macOS)
        .frame(width: 460, height: 560)
        #endif
    }

    private var handle: some View {
        HStack {
            EyebrowText("Recurring series")
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
            Text(series.merchantName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(BudgetTracerStyle.ink)
            Text("\(series.occurrenceCount) occurrences found")
                .font(.subheadline)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlsCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: recurringBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Regular monthly")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BudgetTracerStyle.ink)
                    Text("Applies to all \(series.occurrenceCount) occurrences")
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

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            EyebrowText("History")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(series.transactions.indices, id: \.self) { index in
                let transaction = series.transactions[index]
                HStack {
                    Text(transaction.postedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(BudgetTracerStyle.inkMuted)
                    Spacer()
                    Text(transaction.amount.formatted)
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(BudgetTracerStyle.ink)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                if index < series.transactions.count - 1 {
                    ThemeRowDivider().padding(.leading, 16)
                }
            }
        }
        .padding(.bottom, 6)
        .budgetTracerCard()
    }
}
