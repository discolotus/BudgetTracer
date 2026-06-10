import BudgetCore
import SwiftUI

struct BudgetsView: View {
    var snapshot: BudgetSnapshot

    var body: some View {
        List {
            ForEach(snapshot.categories, id: \.id) { category in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name)
                        Text(limitText(for: category))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let spend = spend(for: category) {
                        Text(spend.spent.formatted)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 4)
            }
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
