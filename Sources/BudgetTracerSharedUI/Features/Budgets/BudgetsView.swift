import BudgetCore
import SwiftUI

struct BudgetsView: View {
    var snapshot: BudgetSnapshot

    var body: some View {
        List {
            ForEach(snapshot.categories, id: \.id) { category in
                ViewThatFits(in: .horizontal) {
                    HStack {
                        categoryLabel(for: category)
                        Spacer()
                        spendText(for: category)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        categoryLabel(for: category)
                        spendText(for: category)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollContentBackground(.hidden)
        .background(BudgetTracerStyle.screenBackground)
    }

    private func categoryLabel(for category: BudgetCategory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.name)
            Text(limitText(for: category))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func spendText(for category: BudgetCategory) -> some View {
        if let spend = spend(for: category) {
            Text(spend.spent.formatted)
                .monospacedDigit()
        }
    }

    private func limitText(for category: BudgetCategory) -> String {
        if let monthlyLimit = category.monthlyLimit {
            return "Monthly limit \(monthlyLimit.formatted)"
        }

        return "No limit"
    }

    private func spend(for category: BudgetCategory) -> CategorySpend? {
        snapshot.spendingByCategory().first { $0.categoryID == category.id }
    }
}
