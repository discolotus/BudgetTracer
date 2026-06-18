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
            VStack(alignment: .leading, spacing: 18) {
                OverviewHeroCard(
                    snapshot: snapshot,
                    connectionState: connectionState,
                    plaidLinkState: plaidLinkState,
                    preparePlaidLink: preparePlaidLink,
                    createSandboxItem: createSandboxItem,
                    refresh: refresh
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    MetricTile(title: "Income", value: snapshot.monthlyIncome.formatted, valueColor: BudgetTracerStyle.positive)
                    MetricTile(title: "Spending", value: snapshot.monthlySpending.formatted, valueColor: BudgetTracerStyle.ink)
                }

                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader("Spending by category")

                    VStack(spacing: 14) {
                        ForEach(snapshot.spendingByCategory(), id: \.id) { spend in
                            CategorySpendRow(spend: spend, maxMinorUnits: maxCategorySpend)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .budgetTracerCard()
            }
            .padding()
        }
        .background(BudgetTracerStyle.canvas)
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
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                EyebrowText("Overview")

                Spacer()

                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BudgetTracerStyle.ink)
                        .frame(width: 34, height: 34)
                        .background(BudgetTracerStyle.surfaceSunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Refresh Financial Data")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Cash after cards")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(BudgetTracerStyle.ink)

                Text(netPosition.formatted)
                    .font(.system(size: 48, weight: .bold))
                    .minimumScaleFactor(0.72)
                    .monospacedDigit()
                    .foregroundStyle(BudgetTracerStyle.ink)
                    .contentTransition(.numericText())
                    .animation(BudgetTracerStyle.spring, value: netPosition.formatted)
            }

            HStack(spacing: 0) {
                HeroStat(title: "Checking cash", value: snapshot.availableCash.formatted)

                Rectangle()
                    .fill(BudgetTracerStyle.hairline)
                    .frame(width: 1, height: 32)

                HeroStat(title: "Card debt", value: snapshot.creditDebt.absolute.formatted)
                    .padding(.leading, 16)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .budgetTracerCard(cornerRadius: 16)
    }

    @ViewBuilder
    private var plaidControlButtons: some View {
        Button(action: preparePlaidLink) {
            Label("Connect Account", systemImage: "link.badge.plus")
        }
        .buttonStyle(.themeProminent)
        .disabled(isPlaidActionInProgress)
        .help("Connect Account")

        Button(action: createSandboxItem) {
            Label("Sandbox Bank", systemImage: "building.columns")
        }
        .buttonStyle(.themeTonal)
        .disabled(isPlaidActionInProgress)
        .help("Create Sandbox Bank")
    }

    private var showsPlaidControls: Bool {
        OverviewPlaidControlVisibility.showsControls(for: connectionState)
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
            return BudgetTracerStyle.caution
        case .succeeded:
            return BudgetTracerStyle.positive
        case .idle, .preparing, .ready, .exchanging:
            return BudgetTracerStyle.inkMuted
        }
    }
}

enum OverviewPlaidControlVisibility {
    static func showsControls(for connectionState: PlaidConnectionState) -> Bool {
        switch connectionState {
        case .notConnected, .connecting, .failed, .connected:
            return true
        }
    }
}

private struct HeroStat: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(BudgetTracerStyle.ink)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricTile: View {
    var title: String
    var value: String
    var valueColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(title)
            Text(value)
                .font(.title2.weight(.semibold))
                .minimumScaleFactor(0.82)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .budgetTracerCard(cornerRadius: 14)
    }
}

private struct CategorySpendRow: View {
    var spend: CategorySpend
    var maxMinorUnits: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(spend.categoryName)
                    .font(.subheadline)
                    .foregroundStyle(BudgetTracerStyle.ink)
                Spacer()
                Text(spend.spent.formatted)
                    .font(.subheadline)
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                Capsule(style: .continuous)
                    .fill(BudgetTracerStyle.accent)
                    .frame(width: max(proxy.size.width * widthRatio, 6))
                    .animation(BudgetTracerStyle.spring, value: widthRatio)
            }
            .frame(height: 6)
            .background(BudgetTracerStyle.surfaceSunken, in: Capsule(style: .continuous))
        }
    }

    private var widthRatio: Double {
        guard maxMinorUnits > 0 else { return 0 }
        return Double(spend.spent.minorUnits) / Double(maxMinorUnits)
    }
}
