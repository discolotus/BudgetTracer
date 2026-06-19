import BudgetCore
import SwiftUI

struct BudgetsView: View {
    var snapshot: BudgetSnapshot
    var addCategory: (String, Money?) -> Void = { _, _ in }
    var saveCategory: (BudgetCategory) -> Void = { _ in }
    var deleteCategory: (BudgetCategory.ID) -> Void = { _ in }

    @State private var editingCategoryID: BudgetCategory.ID?
    @State private var isAddingCategory = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader("Budgets")
                    Spacer()
                    Button {
                        isAddingCategory = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.themeTonal)
                    .help("Add budget category")
                }

                if snapshot.categories.isEmpty {
                    Text("No budgets yet. Add one to start tracking spending against a limit.")
                        .font(.subheadline)
                        .foregroundStyle(BudgetTracerStyle.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 16)
                        .budgetTracerCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(snapshot.categories.indices, id: \.self) { index in
                            let category = snapshot.categories[index]

                            BudgetCategoryRow(
                                category: category,
                                spend: spend(for: category),
                                onTap: { editingCategoryID = category.id }
                            )

                            if index < snapshot.categories.index(before: snapshot.categories.endIndex) {
                                ThemeRowDivider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .budgetTracerCard()
                }
            }
            .padding()
        }
        .budgetTracerWorkspaceBackground()
        .sheet(isPresented: $isAddingCategory) {
            CategoryEditorSheet(
                category: nil,
                onSave: { name, limit in addCategory(name, limit) },
                dismiss: { isAddingCategory = false }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: editingCategoryBinding) { category in
            CategoryEditorSheet(
                category: category,
                onSave: { name, limit in
                    saveCategory(BudgetCategory(id: category.id, name: name, monthlyLimit: limit))
                },
                onDelete: { id in deleteCategory(id) },
                dismiss: { editingCategoryID = nil }
            )
            .presentationDetents([.medium])
        }
    }

    private func spend(for category: BudgetCategory) -> CategorySpend? {
        snapshot.spendingByCategory().first { $0.categoryID == category.id }
    }

    private var editingCategoryBinding: Binding<BudgetCategory?> {
        Binding(
            get: {
                guard let editingCategoryID else { return nil }
                return snapshot.categories.first { $0.id == editingCategoryID }
            },
            set: { newValue in editingCategoryID = newValue?.id }
        )
    }
}

private struct BudgetCategoryRow: View {
    var category: BudgetCategory
    var spend: CategorySpend?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        categoryLabel
                        Spacer()
                        spendText
                        chevron
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            categoryLabel
                            spendText
                        }
                        Spacer()
                        chevron
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(BudgetTracerStyle.inkFaint)
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
