import SwiftUI

public struct BudgetTracerSettingsView: View {
    @State private var isConfirmingDeleteLocalData = false

    public init() {}

    public var body: some View {
        ScrollView {
            BudgetTracerGlassContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard(
                        eyebrow: "Data mode",
                        icon: "chart.bar.doc.horizontal",
                        title: "Demo mode",
                        detail: "Sample data is used unless backend mode is enabled for local Plaid testing."
                    )

                    settingsCard(
                        eyebrow: "Local backend",
                        icon: "lock.shield",
                        title: "Plaid credentials stay behind the backend",
                        detail: "The Apple apps read budget snapshots from the backend boundary and do not store Plaid secrets."
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        EyebrowText("Privacy")
                        Text("Delete local data")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BudgetTracerStyle.ink)
                        Text("Removes the local ledger, Keychain secrets, cached sessions, and connected Plaid Items where available.")
                            .font(.subheadline)
                            .foregroundStyle(BudgetTracerStyle.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(role: .destructive) {
                            isConfirmingDeleteLocalData = true
                        } label: {
                            Label("Delete Local Data", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .budgetTracerCard(cornerRadius: 20)
                }
            }
            .padding()
        }
        .budgetTracerWorkspaceBackground()
        .navigationTitle("Settings")
        #if os(macOS)
        .frame(width: 460)
        #endif
        .alert("Delete Local Data?", isPresented: $isConfirmingDeleteLocalData) {
            Button("Delete", role: .destructive) {
                NotificationCenter.default.post(name: .budgetTracerDeleteLocalDataRequested, object: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes local financial data and secrets from this device. You will need to reconnect accounts.")
        }
    }

    private func settingsCard(eyebrow: String, icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowText(eyebrow)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(BudgetTracerStyle.accent)
                    .frame(width: 34, height: 34)
                    .background(BudgetTracerStyle.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BudgetTracerStyle.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(BudgetTracerStyle.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .budgetTracerCard(cornerRadius: 20)
    }
}
