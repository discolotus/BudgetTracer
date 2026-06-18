import BudgetCore
import SwiftUI

#if os(macOS)

/// macOS sidebar: connected accounts grouped by kind, sync status, and connection
/// actions. Replaces section navigation, which lives in the top pill bar.
struct AccountsRailView: View {
    var snapshot: BudgetSnapshot
    var connectionState: PlaidConnectionState
    var plaidLinkState: PlaidLinkState = .idle
    var accountOverrides: [FinancialAccount.ID: AccountOverride] = [:]
    var dataSourceLabel = "Demo data"
    var selectedAccountID: FinancialAccount.ID?
    var selectAccount: (FinancialAccount.ID) -> Void = { _ in }
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
                VStack(alignment: .leading, spacing: 20) {
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
        .background(BudgetTracerStyle.sidebar)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "wallet.pass.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(BudgetTracerStyle.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("BudgetTracer")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BudgetTracerStyle.ink)
                    Text("Financial workspace")
                        .font(.caption)
                        .foregroundStyle(BudgetTracerStyle.inkMuted)
                }
            }

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
            .font(.caption.weight(.medium))
            .foregroundStyle(BudgetTracerStyle.inkMuted)
        case .connected(_, let lastSyncedAt):
            if let lastSyncedAt {
                Label(
                    "Synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "checkmark.circle"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.inkMuted)
            } else {
                Text(dataSourceLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.caution)
                .lineLimit(2)
        case .notConnected:
            Text("Not connected")
                .font(.caption.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.inkMuted)
        }
    }

    private func accountGroup(_ group: AccountGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
                Spacer()
                Text(group.total.formatted)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)

            VStack(spacing: 2) {
                ForEach(group.accounts, id: \.id) { account in
                    AccountRailRow(
                        account: account,
                        isSelected: account.id == selectedAccountID,
                        includesInAvailableCash: snapshot.includesInAvailableCash(account),
                        hasOverride: accountOverrides[account.id] != nil,
                        select: { selectAccount(account.id) },
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

            if let status = AccountsRailPlaidStatus.status(for: plaidLinkState) {
                HStack(spacing: 6) {
                    if status.showsProgress {
                        ProgressView()
                            .controlSize(.mini)
                    } else if let systemImage = status.systemImage {
                        Image(systemName: systemImage)
                            .font(.caption)
                    }

                    Text(status.message)
                        .font(.caption)
                        .foregroundStyle(status.color)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
            }

            Button(action: connect) {
                HStack {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                    Text("Connect account")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(BudgetTracerStyle.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(connectIsDisabled)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .help("Connect Account")
        }
        .background(BudgetTracerStyle.sidebar)
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

enum AccountsRailPlaidStatus {
    struct Status {
        var message: String
        var color: Color
        var systemImage: String?
        var showsProgress = false
    }

    static func status(for plaidLinkState: PlaidLinkState) -> Status? {
        switch plaidLinkState {
        case .idle:
            return nil
        case .preparing:
            return Status(
                message: "Preparing Plaid Link...",
                color: BudgetTracerStyle.inkMuted,
                systemImage: nil,
                showsProgress: true
            )
        case .ready:
            return Status(
                message: "Plaid Link is ready.",
                color: BudgetTracerStyle.inkMuted,
                systemImage: "link"
            )
        case .exchanging:
            return Status(
                message: "Connecting account...",
                color: BudgetTracerStyle.inkMuted,
                systemImage: nil,
                showsProgress: true
            )
        case .succeeded:
            return Status(
                message: "Account connected. Balances are syncing.",
                color: BudgetTracerStyle.positive,
                systemImage: "checkmark.circle"
            )
        case .failed(let message):
            return Status(
                message: "Connection failed: \(message)",
                color: BudgetTracerStyle.caution,
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}

private struct AccountRailRow: View {
    var account: FinancialAccount
    var isSelected: Bool
    var includesInAvailableCash: Bool
    var hasOverride: Bool
    var select: () -> Void
    var setAccountKind: (FinancialAccount.ID, AccountKind) -> Void
    var setAccountAvailableCash: (FinancialAccount.ID, Bool) -> Void
    var resetAccountOverride: (FinancialAccount.ID) -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            rowContent
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    rowBackground,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(alignment: .leading) {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(BudgetTracerStyle.accent)
                            .frame(width: 3)
                            .padding(.vertical, 7)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
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
        .onDrag {
            AccountDragPayload.provider(accountID: account.id, suggestedName: account.name)
        } preview: {
            HStack(spacing: 8) {
                Image(systemName: account.kind.iconName)
                Text(account.name)
            }
            .font(.caption.weight(.medium))
            .padding(8)
            .background(BudgetTracerStyle.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .help("Open transactions. Right-click to reclassify.")
        .accessibilityLabel("\(account.name), \(account.currentBalance.formatted)")
        .accessibilityHint("Opens transactions for this account")
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            Image(systemName: account.kind.iconName)
                .font(.caption.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.accent)
                .frame(width: 26, height: 26)
                .background(isSelected ? BudgetTracerStyle.surfaceRaised : BudgetTracerStyle.accentSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

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
    }

    private var rowBackground: Color {
        if isSelected {
            return BudgetTracerStyle.surfaceRaised
        }

        if isHovering {
            return BudgetTracerStyle.surfaceSunken
        }

        return Color.clear
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
