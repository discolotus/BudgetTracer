import BudgetCore
import BudgetTracerSharedUI
import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct BudgetTracerMacApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            BudgetTracerRootView(workspace: workspace)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Financial Data") {
                    NotificationCenter.default.post(name: .budgetTracerRefreshRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            Form {
                Text("Demo mode uses sample data. Plaid credentials are only used by the local backend when backend mode is enabled.")
            }
            .padding()
            .frame(width: 420)
        }
    }

    @MainActor
    private var workspace: BudgetWorkspace {
        if Self.usesBackend {
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

    private static var usesBackend: Bool {
        ProcessInfo.processInfo.environment["BUDGETTRACER_USE_BACKEND"] == "1"
    }

    private var backendURL: URL {
        ProcessInfo.processInfo.environment["BUDGETTRACER_BACKEND_URL"].flatMap(URL.init(string:))
            ?? URL(string: "http://127.0.0.1:8790")!
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
