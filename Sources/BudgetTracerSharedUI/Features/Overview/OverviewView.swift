import BudgetCore
import SwiftUI

struct OverviewView: View {
    var snapshot: BudgetSnapshot
    var connectionState: PlaidConnectionState
    var refresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                connectionBanner

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                    MetricTile(title: "Cash", value: snapshot.totalCash.formatted, systemImage: "banknote")
                    MetricTile(title: "Credit Debt", value: snapshot.creditDebt.absolute.formatted, systemImage: "creditcard")
                    MetricTile(title: "Income", value: snapshot.monthlyIncome.formatted, systemImage: "arrow.down.circle")
                    MetricTile(title: "Spending", value: snapshot.monthlySpending.formatted, systemImage: "arrow.up.circle")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Spending by Category")
                        .font(.headline)

                    ForEach(snapshot.spendingByCategory(), id: \.id) { spend in
                        CategorySpendRow(spend: spend, maxMinorUnits: maxCategorySpend)
                    }
                }
            }
            .padding()
        }
    }

    private var maxCategorySpend: Int64 {
        snapshot.spendingByCategory().map(\.spent.minorUnits).max() ?? 1
    }

    @ViewBuilder
    private var connectionBanner: some View {
        switch connectionState {
        case .notConnected:
            HStack(spacing: 12) {
                Image(systemName: "link.badge.plus")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plaid connection pending")
                        .font(.headline)
                    Text("The app is ready for a real financial data provider behind the shared sync boundary.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", action: refresh)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        case .connecting:
            ProgressView("Syncing financial data")
        case let .connected(institutionCount, lastSyncedAt):
            Label("Connected to \(institutionCount) institution\(institutionCount == 1 ? "" : "s")\(lastSyncedAt.map { " as of \($0.formatted(date: .omitted, time: .shortened))" } ?? "")", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

private struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CategorySpendRow: View {
    var spend: CategorySpend
    var maxMinorUnits: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(spend.categoryName)
                Spacer()
                Text(spend.spent.formatted)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    .fill(.blue)
                    .frame(width: proxy.size.width * widthRatio)
            }
            .frame(height: 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 4)
    }

    private var widthRatio: Double {
        guard maxMinorUnits > 0 else { return 0 }
        return Double(spend.spent.minorUnits) / Double(maxMinorUnits)
    }
}
