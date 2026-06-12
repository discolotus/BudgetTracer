import BudgetCore
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

public enum BudgetTracerAppWorkspaceFactory {
    @MainActor
    public static func make(environment: [String: String] = ProcessInfo.processInfo.environment) -> BudgetWorkspace {
        if usesBackend(environment: environment) {
            return BudgetWorkspace(
                connectionState: .connecting,
                dataProvider: BackendFinancialDataProvider(baseURL: backendURL(environment: environment))
            )
        }

        return BudgetWorkspace(
            connectionState: .connected(institutionCount: SampleBudgetData.snapshot.institutions.count, lastSyncedAt: nil),
            dataProvider: SampleFinancialDataProvider()
        )
    }

    public static func usesBackend(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["BUDGETTRACER_USE_BACKEND"] == "1"
    }

    public static func backendURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        environment["BUDGETTRACER_BACKEND_URL"].flatMap(URL.init(string:))
            ?? URL(string: "http://127.0.0.1:8790")!
    }
}

#if os(macOS)
@MainActor
public final class BudgetTracerMacAppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            BudgetTracerMacWindowCoordinator.shared.openMainWindowIfNeeded()
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        BudgetTracerMacWindowCoordinator.shared.openMainWindowIfNeeded()
        return true
    }
}

@MainActor
public final class BudgetTracerMacWindowCoordinator {
    public static let shared = BudgetTracerMacWindowCoordinator()

    private var fallbackWindow: NSWindow?

    private init() {}

    public func openMainWindowIfNeeded() {
        if NSApp.windows.contains(where: { $0.isVisible && !$0.isMiniaturized }) {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        NSApp.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
        if NSApp.windows.contains(where: { $0.isVisible && !$0.isMiniaturized }) {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        showFallbackWindow()
    }

    private func showFallbackWindow() {
        if let fallbackWindow {
            fallbackWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: BudgetTracerRootView(workspace: BudgetTracerAppWorkspaceFactory.make())
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "BudgetTracer"
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.setContentSize(NSSize(width: 1180, height: 860))
        window.minSize = NSSize(width: 900, height: 640)
        window.center()
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        fallbackWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
