import SwiftUI

public struct BudgetTracerSettingsView: View {
    public init() {}

    public var body: some View {
        Form {
            Section("Data Mode") {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Demo mode")
                            .font(.headline)
                        Text("Sample data is used unless backend mode is enabled for local Plaid testing.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "chart.bar.doc.horizontal")
                }
            }

            Section("Local Backend") {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Plaid credentials stay behind the backend")
                            .font(.headline)
                        Text("The Apple apps read budget snapshots from the backend boundary and do not store Plaid secrets.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "lock.shield")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BudgetTracerStyle.screenBackground)
        .navigationTitle("Settings")
        #if os(macOS)
        .padding()
        .frame(width: 460)
        #endif
    }
}
