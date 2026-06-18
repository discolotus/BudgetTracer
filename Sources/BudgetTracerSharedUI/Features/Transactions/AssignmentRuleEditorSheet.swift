import BudgetCore
import SwiftUI

struct AssignmentRuleEditorSheet: View {
    var transaction: BudgetTransaction
    var snapshot: BudgetSnapshot
    var existingRule: BudgetAssignmentRule?
    var initialCategoryID: BudgetCategory.ID
    var saveAssignmentRule: (BudgetAssignmentRule, Bool) -> Void
    var dismiss: () -> Void

    @State private var ruleName: String
    @State private var matchText: String
    @State private var matchField: AssignmentRuleMatchField
    @State private var matchOperator: AssignmentRuleTextOperator
    @State private var amountFilter: AssignmentRuleAmountFilter
    @State private var selectedAccountID: FinancialAccount.ID?
    @State private var selectedCategoryID: BudgetCategory.ID
    @State private var isEnabled: Bool
    @State private var applyToExisting: Bool

    init(
        transaction: BudgetTransaction,
        snapshot: BudgetSnapshot,
        existingRule: BudgetAssignmentRule? = nil,
        initialCategoryID: BudgetCategory.ID,
        saveAssignmentRule: @escaping (BudgetAssignmentRule, Bool) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.transaction = transaction
        self.snapshot = snapshot
        self.existingRule = existingRule
        self.initialCategoryID = initialCategoryID
        self.saveAssignmentRule = saveAssignmentRule
        self.dismiss = dismiss

        let categoryName = snapshot.categories.first { $0.id == initialCategoryID }?.name ?? "Budget"
        let defaultAmountFilter: AssignmentRuleAmountFilter = if transaction.amount.isExpense {
            .expensesOnly
        } else if transaction.amount.isIncome {
            .incomeOnly
        } else {
            .any
        }

        _ruleName = State(initialValue: existingRule?.name ?? "\(transaction.merchantName) -> \(categoryName)")
        _matchText = State(initialValue: existingRule?.merchantContains ?? transaction.merchantName)
        _matchField = State(initialValue: existingRule?.matchField ?? .merchantName)
        _matchOperator = State(initialValue: existingRule?.matchOperator ?? .contains)
        _amountFilter = State(initialValue: existingRule?.amountFilter ?? defaultAmountFilter)
        _selectedAccountID = State(initialValue: existingRule?.accountID)
        _selectedCategoryID = State(initialValue: existingRule?.categoryID ?? initialCategoryID)
        _isEnabled = State(initialValue: existingRule?.isEnabled ?? true)
        _applyToExisting = State(initialValue: true)
    }

    private var draftRule: BudgetAssignmentRule {
        BudgetAssignmentRule(
            id: existingRule?.id ?? UUID().uuidString,
            name: trimmedRuleName,
            merchantContains: trimmedMatchText,
            categoryID: selectedCategoryID,
            isEnabled: isEnabled,
            matchField: matchField,
            matchOperator: matchOperator,
            amountFilter: amountFilter,
            accountID: selectedAccountID
        )
    }

    private var trimmedRuleName: String {
        ruleName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedMatchText: String {
        matchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedRuleName.isEmpty
            && !trimmedMatchText.isEmpty
            && snapshot.categories.contains { $0.id == selectedCategoryID }
    }

    private var matchingTransactions: [BudgetTransaction] {
        snapshot.transactions
            .filter { draftRule.matches($0) }
            .sorted(by: transactionSort)
    }

    private var changedTransactions: [BudgetTransaction] {
        let ids = Set(BudgetAssignmentRuleEngine.transactionIDsMatching(draftRule, in: snapshot))
        return snapshot.transactions
            .filter { ids.contains($0.id) }
            .sorted(by: transactionSort)
    }

    private var previewTransactions: [BudgetTransaction] {
        applyToExisting ? changedTransactions : matchingTransactions
    }

    private var protectedManualCount: Int {
        matchingTransactions.filter(\.hasManualCategoryAssignment).count
    }

    private var targetCategoryName: String {
        categoryName(for: selectedCategoryID) ?? "Selected budget"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    matchCard
                    assignmentCard
                    previewCard
                }
                .padding(20)
            }
        }
        .background(BudgetTracerStyle.canvas)
        .frame(idealWidth: 620, idealHeight: 680)
        #if os(macOS)
        .frame(width: 620, height: 680)
        #endif
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.title3.weight(.semibold))
                .foregroundStyle(BudgetTracerStyle.accent)
                .frame(width: 34, height: 34)
                .background(BudgetTracerStyle.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                EyebrowText(existingRule == nil ? "New rule" : "Edit rule")
                Text("Assignment rule")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                Text("Configure how this rule matches transactions, then review the changes before saving.")
                    .font(.subheadline)
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
            }

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
        .padding(.bottom, 12)
    }

    private var matchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                icon: "line.3.horizontal.decrease.circle",
                title: "Match transactions",
                subtitle: "Choose which transaction data this rule reads."
            )

            VStack(spacing: 0) {
                labeledTextField("Rule name", text: $ruleName)

                ThemeRowDivider()

                labeledTextField("Match text", text: $matchText)

                ThemeRowDivider()

                pickerRow("Field", selection: $matchField) {
                    ForEach(AssignmentRuleMatchField.allCases, id: \.self) { field in
                        Text(field.displayName).tag(field)
                    }
                }

                ThemeRowDivider()

                pickerRow("Text match", selection: $matchOperator) {
                    ForEach(AssignmentRuleTextOperator.allCases, id: \.self) { textOperator in
                        Text(textOperator.displayName).tag(textOperator)
                    }
                }

                ThemeRowDivider()

                pickerRow("Amount", selection: $amountFilter) {
                    ForEach(AssignmentRuleAmountFilter.allCases, id: \.self) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }

                ThemeRowDivider()

                pickerRow("Account", selection: $selectedAccountID) {
                    Text("Any account").tag(FinancialAccount.ID?.none)
                    ForEach(snapshot.accounts, id: \.id) { account in
                        Text(account.name).tag(FinancialAccount.ID?.some(account.id))
                    }
                }
            }
            .background(BudgetTracerStyle.surfaceSunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(18)
        .budgetTracerCard(cornerRadius: 20)
    }

    private var assignmentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                icon: "tag",
                title: "Assign result",
                subtitle: "Rules never overwrite manually assigned categories."
            )

            VStack(spacing: 0) {
                pickerRow("Budget", selection: $selectedCategoryID) {
                    ForEach(snapshot.categories, id: \.id) { category in
                        Text(category.name).tag(category.id)
                    }
                }

                ThemeRowDivider()

                Toggle(isOn: $applyToExisting) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apply to existing transactions")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BudgetTracerStyle.ink)
                        Text("Turn off to save this for future Plaid imports only.")
                            .font(.caption)
                            .foregroundStyle(BudgetTracerStyle.inkMuted)
                    }
                }
                .tint(BudgetTracerStyle.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                ThemeRowDivider()

                Toggle(isOn: $isEnabled) {
                    Text("Rule enabled")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BudgetTracerStyle.ink)
                }
                .tint(BudgetTracerStyle.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(BudgetTracerStyle.surfaceSunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(18)
        .budgetTracerCard(cornerRadius: 20)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                sectionHeader(
                    icon: "tablecells",
                    title: "Preview",
                    subtitle: previewSubtitle
                )

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(previewCountText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(BudgetTracerStyle.ink)
                    Text("Manual protected: \(protectedManualCount)")
                        .font(.caption)
                        .foregroundStyle(BudgetTracerStyle.inkMuted)
                }
            }

            if previewTransactions.isEmpty {
                emptyPreview
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(previewTransactions.prefix(10).enumerated()), id: \.element.id) { index, transaction in
                        previewRow(transaction)

                        if index < min(previewTransactions.count, 10) - 1 {
                            ThemeRowDivider()
                                .padding(.leading, 14)
                        }
                    }

                    if previewTransactions.count > 10 {
                        ThemeRowDivider()
                            .padding(.leading, 14)

                        Text("\(previewTransactions.count - 10) more matching transactions")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BudgetTracerStyle.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                    }
                }
                .background(BudgetTracerStyle.surfaceSunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack {
                Button("Cancel", action: dismiss)
                    .buttonStyle(.themeTonal)

                Spacer()

                Button(existingRule == nil ? "Create rule" : "Save rule") {
                    saveAssignmentRule(draftRule, applyToExisting)
                    dismiss()
                }
                .buttonStyle(.themeProminent)
                .disabled(!canSave)
            }
        }
        .padding(18)
        .budgetTracerCard(cornerRadius: 20)
    }

    private var previewSubtitle: String {
        if !isEnabled {
            return "Disabled rules will not change existing or future transactions."
        }

        if applyToExisting {
            return "These existing transactions will be reassigned to \(targetCategoryName)."
        }

        return "Existing transactions will stay as-is; matching future imports will use this rule."
    }

    private var previewCountText: String {
        if applyToExisting {
            return "\(changedTransactions.count) changes"
        }

        return "\(matchingTransactions.count) matches"
    }

    private var emptyPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(applyToExisting ? "No transactions will change." : "No existing transactions match.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BudgetTracerStyle.ink)

            Text(emptyPreviewDetail)
                .font(.caption)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(BudgetTracerStyle.surfaceSunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyPreviewDetail: String {
        if !isEnabled {
            return "Enable the rule to preview matching transactions."
        }

        if trimmedMatchText.isEmpty {
            return "Add match text to see a preview."
        }

        return "Try broadening the text match, amount filter, or account scope."
    }

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BudgetTracerStyle.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func labeledTextField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.ink)
                .frame(width: 96, alignment: .leading)

            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func pickerRow<Selection: Hashable, Content: View>(
        _ label: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.ink)
                .frame(width: 96, alignment: .leading)

            Spacer(minLength: 12)

            Picker(label, selection: selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(BudgetTracerStyle.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func previewRow(_ transaction: BudgetTransaction) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchantName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                    .lineLimit(1)

                Text(previewDetailText(for: transaction))
                    .font(.caption)
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(transaction.amount.formatted)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(transaction.amount.isIncome ? BudgetTracerStyle.positive : BudgetTracerStyle.ink)

                categoryChangeLabel(for: transaction)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func previewDetailText(for transaction: BudgetTransaction) -> String {
        let date = transaction.postedAt.formatted(date: .abbreviated, time: .omitted)
        let account = accountName(for: transaction.accountID) ?? "Unknown account"

        if !applyToExisting {
            return "\(date) - \(account) - no existing change on save"
        }

        if transaction.hasManualCategoryAssignment {
            return "\(date) - \(account) - manual category is protected"
        }

        return "\(date) - \(account)"
    }

    private func categoryChangeLabel(for transaction: BudgetTransaction) -> some View {
        HStack(spacing: 6) {
            Text(categoryName(for: transaction.categoryID) ?? "Uncategorized")
                .lineLimit(1)

            Image(systemName: applyToExisting ? "arrow.right" : "clock")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BudgetTracerStyle.inkFaint)

            Text(applyToExisting ? targetCategoryName : "Future only")
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(BudgetTracerStyle.inkMuted)
    }

    private func transactionSort(_ lhs: BudgetTransaction, _ rhs: BudgetTransaction) -> Bool {
        if lhs.postedAt == rhs.postedAt {
            return lhs.merchantName < rhs.merchantName
        }

        return lhs.postedAt > rhs.postedAt
    }

    private func categoryName(for categoryID: BudgetCategory.ID?) -> String? {
        categoryID.flatMap { id in
            snapshot.categories.first { $0.id == id }?.name
        }
    }

    private func accountName(for accountID: FinancialAccount.ID) -> String? {
        snapshot.accounts.first { $0.id == accountID }?.name
    }
}

private extension AssignmentRuleMatchField {
    var displayName: String {
        switch self {
        case .merchantName:
            return "Merchant name"
        case .note:
            return "Note"
        }
    }
}

private extension AssignmentRuleTextOperator {
    var displayName: String {
        switch self {
        case .contains:
            return "Contains"
        case .equals:
            return "Equals"
        case .beginsWith:
            return "Begins with"
        }
    }
}

private extension AssignmentRuleAmountFilter {
    var displayName: String {
        switch self {
        case .any:
            return "Any amount"
        case .expensesOnly:
            return "Expenses only"
        case .incomeOnly:
            return "Income only"
        }
    }
}

#Preview("Assignment Rule Editor") {
    AssignmentRuleEditorSheet(
        transaction: AssignmentRuleEditorSheetPreviewData.currentTransaction,
        snapshot: AssignmentRuleEditorSheetPreviewData.snapshot,
        initialCategoryID: "cat-dining",
        saveAssignmentRule: { _, _ in },
        dismiss: {}
    )
}

private enum AssignmentRuleEditorSheetPreviewData {
    static let categories = [
        BudgetCategory(id: "cat-dining", name: "Dining"),
        BudgetCategory(id: "cat-groceries", name: "Groceries"),
        BudgetCategory(id: "cat-travel", name: "Travel"),
        BudgetCategory(id: "cat-income", name: "Income")
    ]

    static let accounts = [
        FinancialAccount(
            id: "checking",
            institutionID: "plaid",
            name: "Plaid Checking",
            kind: .checking,
            currentBalance: Money(minorUnits: 2_450_00)
        ),
        FinancialAccount(
            id: "credit",
            institutionID: "plaid",
            name: "Plaid Credit Card",
            kind: .creditCard,
            currentBalance: Money(minorUnits: -820_00)
        )
    ]

    static let currentTransaction = BudgetTransaction(
        id: "txn-current",
        accountID: "credit",
        categoryID: "cat-dining",
        categoryAssignmentSource: .manual,
        postedAt: day(12),
        merchantName: "Starbucks",
        amount: Money(minorUnits: -5_85)
    )

    static let snapshot = BudgetSnapshot(
        institutions: [Institution(id: "plaid", name: "Plaid Sandbox")],
        accounts: accounts,
        categories: categories,
        transactions: [
            currentTransaction,
            BudgetTransaction(
                id: "txn-reserve",
                accountID: "credit",
                categoryID: "cat-travel",
                categoryAssignmentSource: .plaid,
                postedAt: day(10),
                merchantName: "Starbucks Reserve",
                amount: Money(minorUnits: -18_42)
            ),
            BudgetTransaction(
                id: "txn-downtown",
                accountID: "checking",
                categoryID: nil,
                postedAt: day(8),
                merchantName: "Starbucks Downtown",
                amount: Money(minorUnits: -6_20)
            ),
            BudgetTransaction(
                id: "txn-reward",
                accountID: "checking",
                categoryID: "cat-income",
                categoryAssignmentSource: .plaid,
                postedAt: day(7),
                merchantName: "Starbucks Rewards",
                amount: Money(minorUnits: 25_00)
            ),
            BudgetTransaction(
                id: "txn-market",
                accountID: "checking",
                categoryID: "cat-groceries",
                categoryAssignmentSource: .plaid,
                postedAt: day(6),
                merchantName: "Neighborhood Market",
                amount: Money(minorUnits: -42_00)
            )
        ]
    )

    private static func day(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: day)) ?? Date()
    }
}
