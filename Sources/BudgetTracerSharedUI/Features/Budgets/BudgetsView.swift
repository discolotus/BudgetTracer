import BudgetCore
import SwiftUI

struct BudgetsView: View {
    var snapshot: BudgetSnapshot

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(snapshot.categories.indices, id: \.self) { index in
                    let category = snapshot.categories[index]

                    BudgetCategoryRow(
                        category: category,
                        spend: spend(for: category)
                    )

                    if index < snapshot.categories.index(before: snapshot.categories.endIndex) {
                        ThemeRowDivider()
                            .padding(.leading, 16)
                    }
                }
            }
            .budgetTracerCard()
            .padding()
        }
        .background(BudgetTracerStyle.canvas)
    }

    private func spend(for category: BudgetCategory) -> CategorySpend? {
        snapshot.spendingByCategory().first { $0.categoryID == category.id }
    }
}

private struct BudgetCategoryRow: View {
    var category: BudgetCategory
    var spend: CategorySpend?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    categoryLabel
                    Spacer()
                    spendText
                }

                VStack(alignment: .leading, spacing: 8) {
                    categoryLabel
                    spendText
                }
            }

            if let progress {
                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(progress > 1 ? BudgetTracerStyle.caution : BudgetTracerStyle.accent)
                        .frame(width: max(proxy.size.width * min(progress, 1), 6))
                        .animation(BudgetTracerStyle.spring, value: progress)
                }
                .frame(height: 6)
                .background(BudgetTracerStyle.surfaceSunken, in: Capsule(style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var categoryLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(category.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.ink)
            Text(limitText)
                .font(.caption)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
        }
    }

    @ViewBuilder
    private var spendText: some View {
        if let spend {
            Text(spend.spent.formatted)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.ink)
                .monospacedDigit()
        }
    }

    private var limitText: String {
        if let monthlyLimit = category.monthlyLimit {
            return "Monthly limit \(monthlyLimit.formatted)"
        }

        return "No limit"
    }

    private var progress: Double? {
        guard
            let spend,
            let limit = category.monthlyLimit,
            limit.minorUnits > 0
        else {
            return nil
        }

        return Double(spend.spent.minorUnits) / Double(limit.minorUnits)
    }
}
