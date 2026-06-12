import BudgetTracerSharedUI
import SwiftUI

#if os(macOS)
import AppKit
#endif

// Keep this file mirrored across Apps/BudgetTracerMac and Sources/BudgetTracerMac.
// MacAppShellParityTests fails if the Xcode and SwiftPM macOS shells drift.
@main
struct BudgetTracerMacApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(BudgetTracerMacAppDelegate.self) private var appDelegate
    #endif

    #if os(macOS)
    init() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            BudgetTracerMacWindowCoordinator.shared.openMainWindowIfNeeded()
        }
    }
    #endif

    var body: some Scene {
        WindowGroup("BudgetTracer", id: "main") {
            BudgetTracerRootView(workspace: workspace)
        }
        .defaultSize(width: 1180, height: 860)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Financial Data") {
                    NotificationCenter.default.post(name: .budgetTracerRefreshRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            BudgetTracerSettingsView()
        }
    }

    @MainActor
    private var workspace: BudgetWorkspace {
        BudgetTracerAppWorkspaceFactory.make()
    }
}
