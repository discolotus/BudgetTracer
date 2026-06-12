import BudgetCore
import SwiftUI

struct AccountsView: View {
    var snapshot: BudgetSnapshot
    var accountOverrides: [FinancialAccount.ID: AccountOverride] = [:]
    var setAccountKind: (FinancialAccount.ID, AccountKind) -> Void = { _, _ in }
    var setAccountAvailableCash: (FinancialAccount.ID, Bool) -> Void = { _, _ in }
    var resetAccountOverride: (FinancialAccount.ID) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(snapshot.accounts.indices, id: \.self) { index in
                    let account = snapshot.accounts[index]

                    accountRow(for: account)

                    if index < snapshot.accounts.index(before: snapshot.accounts.endIndex) {
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

    private func accountRow(for account: FinancialAccount) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    accountLabel(for: account)
                    Spacer()
                    balanceText(for: account)
                }

                VStack(alignment: .leading, spacing: 8) {
                    accountLabel(for: account)
                    balanceText(for: account)
                }
            }

            accountControls(for: account)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func accountLabel(for account: FinancialAccount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: account.kind))
                .font(.subheadline)
                .foregroundStyle(BudgetTracerStyle.accent)
                .frame(width: 34, height: 34)
                .background(BudgetTracerStyle.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BudgetTracerStyle.ink)
                Text(account.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
            }
        }
    }

    private func balanceText(for account: FinancialAccount) -> some View {
        Text(account.currentBalance.formatted)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BudgetTracerStyle.ink)
            .monospacedDigit()
    }

    private func accountControls(for account: FinancialAccount) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                classificationPicker(for: account)
                availableCashToggle(for: account)
                resetButton(for: account)
            }

            VStack(alignment: .leading, spacing: 10) {
                classificationPicker(for: account)
                availableCashToggle(for: account)
                resetButton(for: account)
            }
        }
        .font(.subheadline)
        .tint(BudgetTracerStyle.accent)
    }

    private func classificationPicker(for account: FinancialAccount) -> some View {
        Picker("Classification", selection: kindBinding(for: account)) {
            ForEach(AccountKind.allCases, id: \.self) { kind in
                Text(kind.displayName)
                    .tag(kind)
            }
        }
        .pickerStyle(.menu)
    }

    private func availableCashToggle(for account: FinancialAccount) -> some View {
        Toggle("Available cash", isOn: availableCashBinding(for: account))
            .disabled(!cashToggleIsEnabled(for: account))
            .help("Counts toward Cash after cards")
    }

    @ViewBuilder
    private func resetButton(for account: FinancialAccount) -> some View {
        if accountOverrides[account.id] != nil {
            Button {
                resetAccountOverride(account.id)
            } label: {
                Label("Reset", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Reset account classification")
        }
    }

    private func kindBinding(for account: FinancialAccount) -> Binding<AccountKind> {
        Binding(
            get: { account.kind },
            set: { setAccountKind(account.id, $0) }
        )
    }

    private func availableCashBinding(for account: FinancialAccount) -> Binding<Bool> {
        Binding(
            get: { snapshot.includesInAvailableCash(account) },
            set: { setAccountAvailableCash(account.id, $0) }
        )
    }

    private func cashToggleIsEnabled(for account: FinancialAccount) -> Bool {
        account.kind == .checking || account.kind == .savings
    }

    private func iconName(for kind: AccountKind) -> String {
        switch kind {
        case .checking:
            return "building.columns"
        case .savings:
            return "banknote"
        case .creditCard:
            return "creditcard"
        case .investment:
            return "chart.line.uptrend.xyaxis"
        case .loan:
            return "doc.text"
        case .other:
            return "wallet.pass"
        }
    }
}

private extension AccountKind {
    var displayName: String {
        switch self {
        case .checking:
            return "Checking"
        case .savings:
            return "Savings"
        case .creditCard:
            return "Credit card"
        case .investment:
            return "Investment"
        case .loan:
            return "Loan"
        case .other:
            return "Other"
        }
    }
}
