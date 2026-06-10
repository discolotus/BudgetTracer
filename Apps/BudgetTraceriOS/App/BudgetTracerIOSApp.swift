import BudgetCore
import BudgetTracerSharedUI
import SwiftUI

@main
struct BudgetTracerIOSApp: App {
    var body: some Scene {
        WindowGroup {
            BudgetTracerRootView(workspace: workspace)
        }
    }

    @MainActor
    private var workspace: BudgetWorkspace {
        if usesBackend {
            return BudgetWorkspace(
                connectionState: .connecting,
                dataProvider: BackendFinancialDataProvider(baseURL: backendURL)
            )
        }

        return BudgetWorkspace(
            connectionState: .connected(institutionCount: SampleBudgetData.snapshot.institutions.count, lastSyncedAt: nil),
            dataProvider: SampleFinancialDataProvider()
        )
    }

    private var usesBackend: Bool {
        ProcessInfo.processInfo.environment["BUDGETTRACER_USE_BACKEND"] == "1"
    }

    private var backendURL: URL {
        ProcessInfo.processInfo.environment["BUDGETTRACER_BACKEND_URL"].flatMap(URL.init(string:))
            ?? URL(string: "http://127.0.0.1:8790")!
    }
}
