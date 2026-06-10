import BudgetCore
import SwiftUI

struct AccountsView: View {
    var snapshot: BudgetSnapshot

    var body: some View {
        List {
            ForEach(snapshot.accounts, id: \.id) { account in
                HStack(spacing: 12) {
                    Image(systemName: iconName(for: account.kind))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.name)
                        Text(account.kind.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(account.currentBalance.formatted)
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func iconName(for kind: AccountKind) -> String {
        switch kind {
        case .checking:
            return "building.columns"
        case .savings:
            return "safe"
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
