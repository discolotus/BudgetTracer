import BudgetCore
import SwiftUI

#if os(macOS)

/// macOS sidebar: connected accounts grouped by kind, sync status, and connection
/// actions. Replaces section navigation, which lives in the top pill bar.
struct AccountsRailView: View {
    var snapshot: BudgetSnapshot
    var connectionState: PlaidConnectionState
    var accountOverrides: [FinancialAccount.ID: AccountOverride] = [:]
    var setAccountKind: (FinancialAccount.ID, AccountKind) -> Void = { _, _ in }
    var setAccountAvailableCash: (FinancialAccount.ID, Bool) -> Void = { _, _ in }
    var resetAccountOverride: (FinancialAccount.ID) -> Void = { _ in }
    var connect: () -> Void = {}
    var connectIsDisabled = false

    private static let groupOrder: [AccountKind] = [
        .checking, .savings, .creditCard, .investment, .loan, .other
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    ForEach(groups, id: \.kind) { group in
                        accountGroup(group)
                    }

                    if snapshot.accounts.isEmpty {
                        Text("No accounts connected yet.")
                            .font(.caption)
                            .foregroundStyle(BudgetTracerStyle.inkMuted)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer
        }
        .background(BudgetTracerStyle.canvas)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowText("Accounts")
            syncStatus
        }
    }

    @ViewBuilder
    private var syncStatus: some View {
        switch connectionState {
        case .connecting:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Syncing…")
            }
            .font(.caption)
            .foregroundStyle(BudgetTracerStyle.inkMuted)
        case .connected(_, let lastSyncedAt):
            if let lastSyncedAt {
                Label(
                    "Synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
            } else {
                Text("Demo data")
                    .font(.caption)
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(BudgetTracerStyle.caution)
                .lineLimit(2)
        case .notConnected:
            Text("Not connected")
                .font(.caption)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
        }
    }

    private func accountGroup(_ group: AccountGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
                Spacer()
                Text(group.total.formatted)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)

            VStack(spacing: 1) {
                ForEach(group.accounts, id: \.id) { account in
                    AccountRailRow(
                        account: account,
                        includesInAvailableCash: snapshot.includesInAvailableCash(account),
                        hasOverride: accountOverrides[account.id] != nil,
                        setAccountKind: setAccountKind,
                        setAccountAvailableCash: setAccountAvailableCash,
                        resetAccountOverride: resetAccountOverride
                    )
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            ThemeRowDivider()

            Button(action: connect) {
                Label("Connect account", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.themeTonal)
            .disabled(connectIsDisabled)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .help("Connect Account")
        }
        .background(BudgetTracerStyle.canvas)
    }

    // MARK: Grouping

    private struct AccountGroup {
        var kind: AccountKind
        var title: String
        var accounts: [FinancialAccount]
        var total: Money
    }

    private var groups: [AccountGroup] {
        Self.groupOrder.compactMap { kind in
            let accounts = snapshot.accounts
                .filter { $0.kind == kind }
                .sorted { $0.name < $1.name }

            guard !accounts.isEmpty else {
                return nil
            }

            return AccountGroup(
                kind: kind,
                title: groupTitle(for: kind),
                accounts: accounts,
                total: accounts.reduce(Money(minorUnits: 0)) { $0 + $1.currentBalance }
            )
        }
    }

    private func groupTitle(for kind: AccountKind) -> String {
        switch kind {
        case .checking:
            return "Cash"
        case .savings:
            return "Savings"
        case .creditCard:
            return "Cards"
        case .investment:
            return "Investments"
        case .loan:
            return "Loans"
        case .other:
            return "Other"
        }
    }
}

private struct AccountRailRow: View {
    var account: FinancialAccount
    var includesInAvailableCash: Bool
    var hasOverride: Bool
    var setAccountKind: (FinancialAccount.ID, AccountKind) -> Void
    var setAccountAvailableCash: (FinancialAccount.ID, Bool) -> Void
    var resetAccountOverride: (FinancialAccount.ID) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: account.kind.iconName)
                .font(.caption.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.accent)
                .frame(width: 26, height: 26)
                .background(BudgetTracerStyle.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(BudgetTracerStyle.ink)
                    .lineLimit(1)
                Text(account.currentBalance.formatted)
                    .font(.caption)
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
                    .monospacedDigit()
            }

            Spacer(minLength: 4)

            if hasOverride {
                Circle()
                    .fill(BudgetTracerStyle.accent.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .help("Classification customized")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isHovering ? BudgetTracerStyle.surfaceSunken : Color.clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Picker("Classification", selection: kindBinding) {
                ForEach(AccountKind.allCases, id: \.self) { kind in
                    Text(kind.displayName)
                        .tag(kind)
                }
            }

            Toggle("Available cash", isOn: availableCashBinding)
                .disabled(!cashToggleIsEnabled)

            if hasOverride {
                Divider()
                Button("Reset classification") {
                    resetAccountOverride(account.id)
                }
            }
        }
        .help("Right-click to reclassify")
    }

    private var kindBinding: Binding<AccountKind> {
        Binding(
            get: { account.kind },
            set: { setAccountKind(account.id, $0) }
        )
    }

    private var availableCashBinding: Binding<Bool> {
        Binding(
            get: { includesInAvailableCash },
            set: { setAccountAvailableCash(account.id, $0) }
        )
    }

    private var cashToggleIsEnabled: Bool {
        account.kind == .checking || account.kind == .savings
    }
}

#endif
