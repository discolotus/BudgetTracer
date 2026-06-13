import BudgetCore
import SwiftUI

/// Create or edit a budget category: name and an optional monthly limit. In edit mode it
/// also offers delete (with confirmation).
struct CategoryEditorSheet: View {
    /// The category being edited, or `nil` when creating a new one.
    var category: BudgetCategory?
    var onSave: (String, Money?) -> Void
    var onDelete: ((BudgetCategory.ID) -> Void)?
    var dismiss: () -> Void

    @State private var name: String
    @State private var limitText: String
    @State private var isConfirmingDelete = false

    init(
        category: BudgetCategory?,
        onSave: @escaping (String, Money?) -> Void,
        onDelete: ((BudgetCategory.ID) -> Void)? = nil,
        dismiss: @escaping () -> Void
    ) {
        self.category = category
        self.onSave = onSave
        self.onDelete = onDelete
        self.dismiss = dismiss
        _name = State(initialValue: category?.name ?? "")
        _limitText = State(initialValue: category?.monthlyLimit.map { dollarsString(from: $0) } ?? "")
    }

    private var isEditing: Bool { category != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedLimit: Money? {
        let trimmed = limitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let amount = Decimal(string: trimmed) else {
            return nil
        }

        return Money.dollars(amount)
    }

    var body: some View {
        VStack(spacing: 0) {
            handle

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    field(title: "Name") {
                        TextField("e.g. Groceries", text: $name)
                            .textFieldStyle(.plain)
                            .font(.body)
                    }

                    field(title: "Monthly limit (optional)") {
                        HStack(spacing: 4) {
                            Text("$")
                                .foregroundStyle(BudgetTracerStyle.inkMuted)
                            TextField("0", text: $limitText)
                                .textFieldStyle(.plain)
                                .font(.body.monospacedDigit())
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                    }

                    Button(action: save) {
                        Text(isEditing ? "Save changes" : "Add category")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themeProminent)
                    .disabled(trimmedName.isEmpty)

                    if isEditing, let onDelete, let category {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Text("Delete category")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.themeTonal)
                        .tint(BudgetTracerStyle.caution)
                        .confirmationDialog(
                            "Delete \(category.name)? Its transactions become Uncategorized.",
                            isPresented: $isConfirmingDelete,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) {
                                onDelete(category.id)
                                dismiss()
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(BudgetTracerStyle.canvas)
        #if os(macOS)
        .frame(width: 420, height: 420)
        #endif
    }

    private var handle: some View {
        HStack {
            EyebrowText(isEditing ? "Edit budget" : "New budget")
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

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(title)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(BudgetTracerStyle.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName, parsedLimit)
        dismiss()
    }
}

private func dollarsString(from money: Money) -> String {
    let decimal = Decimal(money.minorUnits) / 100
    return NSDecimalNumber(decimal: decimal).stringValue
}
