import SwiftUI

public struct BudgetTracerSettingsView: View {
    public init() {}

    public var body: some View {
        ScrollView {
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
            }
            .padding()
        }
        .background(BudgetTracerStyle.canvas)
        .navigationTitle("Settings")
        #if os(macOS)
        .frame(width: 460)
        #endif
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
