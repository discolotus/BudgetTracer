import BudgetCore
import SwiftUI

struct OverviewView: View {
    var snapshot: BudgetSnapshot
    var connectionState: PlaidConnectionState
    var plaidLinkState: PlaidLinkState
    var preparePlaidLink: () -> Void
    var createSandboxItem: () -> Void
    var refresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OverviewHeroCard(
                    snapshot: snapshot,
                    connectionState: connectionState,
                    plaidLinkState: plaidLinkState,
                    preparePlaidLink: preparePlaidLink,
                    createSandboxItem: createSandboxItem,
                    refresh: refresh
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
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
        .background(BudgetTracerStyle.screenBackground)
    }

    private var maxCategorySpend: Int64 {
        snapshot.spendingByCategory().map(\.spent.minorUnits).max() ?? 1
    }

}

private struct OverviewHeroCard: View {
    var snapshot: BudgetSnapshot
    var connectionState: PlaidConnectionState
    var plaidLinkState: PlaidLinkState
    var preparePlaidLink: () -> Void
    var createSandboxItem: () -> Void
    var refresh: () -> Void

    private var netPosition: Money {
        snapshot.availableCash - snapshot.creditDebt.absolute
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text("NET POSITION")
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(BudgetTracerStyle.subduedText)

                Spacer()

                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(BudgetTracerStyle.accent, in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("Refresh Financial Data")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Cash after cards")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(netPosition.formatted)
                    .font(.system(size: 42, weight: .semibold, design: .default))
                    .minimumScaleFactor(0.72)
                    .monospacedDigit()
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    BalanceChip(title: "Checking cash", value: snapshot.availableCash.formatted)
                    BalanceChip(title: "Card debt", value: snapshot.creditDebt.absolute.formatted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    BalanceChip(title: "Checking cash", value: snapshot.availableCash.formatted)
                    BalanceChip(title: "Card debt", value: snapshot.creditDebt.absolute.formatted)
                }
            }

            if showsPlaidControls || plaidLinkStatusText != nil {
                VStack(alignment: .leading, spacing: 10) {
                    if showsPlaidControls {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                plaidControlButtons
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                plaidControlButtons
                            }
                        }
                    }

                    if let plaidLinkStatusText {
                        Text(plaidLinkStatusText)
                            .font(.caption)
                            .foregroundStyle(plaidLinkStatusColor)
                            .lineLimit(2)
                    }
                }
            }

        }
        .padding(24)
        .budgetTracerCard(cornerRadius: 28)
    }

    @ViewBuilder
    private var plaidControlButtons: some View {
        Button(action: preparePlaidLink) {
            Label("Connect Account", systemImage: "link.badge.plus")
        }
        .buttonStyle(.borderedProminent)
        .disabled(isPlaidActionInProgress)
        .help("Connect Account")

        Button(action: createSandboxItem) {
            Label("Sandbox Bank", systemImage: "building.columns")
        }
        .buttonStyle(.bordered)
        .disabled(isPlaidActionInProgress)
        .help("Create Sandbox Bank")
    }

    private var showsPlaidControls: Bool {
        switch connectionState {
        case .notConnected, .failed:
            return true
        case .connected(let institutionCount, _):
            return institutionCount == 0
        case .connecting:
            return false
        }
    }

    private var isPlaidActionInProgress: Bool {
        switch plaidLinkState {
        case .preparing, .exchanging:
            return true
        case .idle, .ready, .succeeded, .failed:
            return false
        }
    }

    private var plaidLinkStatusText: String? {
        switch plaidLinkState {
        case .idle:
            return nil
        case .preparing:
            return "Preparing Plaid Link..."
        case .ready:
            return "Plaid Link is ready."
        case .exchanging:
            return "Connecting account..."
        case .succeeded:
            return "Account connected. Balances are syncing."
        case .failed(let message):
            return "Connection failed: \(message)"
        }
    }

    private var plaidLinkStatusColor: Color {
        switch plaidLinkState {
        case .failed:
            return .red
        case .succeeded:
            return .green
        case .idle, .preparing, .ready, .exchanging:
            return BudgetTracerStyle.subduedText
        }
    }
}

private struct BalanceChip: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(BudgetTracerStyle.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .minimumScaleFactor(0.82)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .budgetTracerCard(cornerRadius: 22)
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
                    .fill(BudgetTracerStyle.accent)
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
