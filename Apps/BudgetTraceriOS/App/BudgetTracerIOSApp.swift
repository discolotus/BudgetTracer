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
        BudgetTracerAppWorkspaceFactory.make()
    }
}
