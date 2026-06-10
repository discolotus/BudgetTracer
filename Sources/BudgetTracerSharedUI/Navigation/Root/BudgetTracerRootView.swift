import BudgetCore
import SwiftUI

public struct BudgetTracerRootView: View {
    @StateObject private var workspace: BudgetWorkspace
    @SceneStorage("BudgetTracer.selectedSection") private var selectedSectionID = BudgetSection.overview.rawValue

    @MainActor
    public init() {
        _workspace = StateObject(wrappedValue: BudgetWorkspace())
    }

    @MainActor
    public init(workspace: BudgetWorkspace) {
        _workspace = StateObject(wrappedValue: workspace)
    }

    public var body: some View {
        NavigationSplitView {
            List(BudgetSection.allCases, selection: selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section.rawValue)
            }
            .navigationTitle("BudgetTracer")
        } detail: {
            detailView
                .navigationTitle(selectedSection.title)
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 520)
                #endif
        }
        .task {
            if case .notConnected = workspace.connectionState {
                return
            }
            await workspace.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .budgetTracerRefreshRequested)) { _ in
            Task { await workspace.refresh() }
        }
        .onAppear {
            if let initialSectionID = ProcessInfo.processInfo.environment["BUDGETTRACER_INITIAL_SECTION"],
               BudgetSection(rawValue: initialSectionID) != nil {
                selectedSectionID = initialSectionID
            }
        }
    }

    private var selectedSection: BudgetSection {
        BudgetSection(rawValue: selectedSectionID) ?? .overview
    }

    private var selection: Binding<String?> {
        Binding(
            get: { selectedSectionID },
            set: { selectedSectionID = $0 ?? BudgetSection.overview.rawValue }
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .overview:
            OverviewView(snapshot: workspace.snapshot, connectionState: workspace.connectionState) {
                Task { await workspace.refresh() }
            }
        case .normalizedMonth:
            NormalizedMonthView(snapshot: workspace.snapshot) { transactionID, isRecurring in
                workspace.setTransaction(transactionID, isRecurring: isRecurring)
            }
        case .accounts:
            AccountsView(snapshot: workspace.snapshot)
        case .transactions:
            TransactionsView(snapshot: workspace.snapshot)
        case .budgets:
            BudgetsView(snapshot: workspace.snapshot)
        }
    }
}

public extension Notification.Name {
    static let budgetTracerRefreshRequested = Notification.Name("BudgetTracerRefreshRequested")
}

private enum BudgetSection: String, CaseIterable, Identifiable {
    case overview
    case normalizedMonth
    case accounts
    case transactions
    case budgets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .normalizedMonth:
            return "Normalized Month"
        case .accounts:
            return "Accounts"
        case .transactions:
            return "Transactions"
        case .budgets:
            return "Budgets"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "chart.pie"
        case .normalizedMonth:
            return "waveform.path.ecg"
        case .accounts:
            return "building.columns"
        case .transactions:
            return "list.bullet.rectangle"
        case .budgets:
            return "target"
        }
    }
}
