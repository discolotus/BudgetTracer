import BudgetCore
import SwiftUI

public struct BudgetTracerRootView: View {
    @StateObject private var workspace: BudgetWorkspace
    @SceneStorage("BudgetTracer.selectedSection") private var selectedSectionID = BudgetSection.overview.rawValue
    @State private var isShowingSettings = false
    @State private var plaidLinkToken: String?

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
                .toolbar {
                    primaryToolbarItems
                }
                .background(BudgetTracerStyle.screenBackground.ignoresSafeArea())
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 520)
                #endif
        }
        .budgetTracerSettingsSheet(isPresented: $isShowingSettings)
        .budgetTracerPlaidLinkSheet(
            linkToken: $plaidLinkToken,
            onSuccess: { publicToken, institutionID in
                Task {
                    await workspace.finishPlaidLink(
                        publicToken: publicToken,
                        institutionID: institutionID
                    )
                }
            },
            onExit: {
                workspace.cancelPlaidLink()
            },
            onFailure: { message in
                workspace.failPlaidLink(message: message)
            }
        )
        .task {
            if case .notConnected = workspace.connectionState {
                return
            }
            await workspace.refresh(forceSync: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .budgetTracerRefreshRequested)) { _ in
            refreshWorkspace()
        }
        .onAppear {
            if let initialSectionID = ProcessInfo.processInfo.environment["BUDGETTRACER_INITIAL_SECTION"],
               BudgetSection(rawValue: initialSectionID) != nil {
                selectedSectionID = initialSectionID
            }
        }
    }

    private var isRefreshing: Bool {
        if case .connecting = workspace.connectionState {
            return true
        }

        return false
    }

    private var selectedSection: BudgetSection {
        BudgetSection(rawValue: selectedSectionID) ?? .overview
    }

    private func refreshWorkspace(forceSync: Bool = true) {
        Task { await workspace.refresh(forceSync: forceSync) }
    }

    @ToolbarContentBuilder
    private var primaryToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                refreshWorkspace()
            } label: {
                Label("Refresh Financial Data", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
            .keyboardShortcut("r", modifiers: [.command])
            .help("Refresh Financial Data")

            #if os(macOS)
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings")
            #else
            Button {
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            #endif
        }
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
            OverviewView(
                snapshot: workspace.displaySnapshot,
                connectionState: workspace.connectionState,
                plaidLinkState: workspace.plaidLinkState,
                preparePlaidLink: {
                    Task {
                        plaidLinkToken = await workspace.preparePlaidLink()
                    }
                },
                createSandboxItem: {
                    Task { await workspace.createSandboxPlaidItem() }
                },
                refresh: {
                    Task { await workspace.refresh(forceSync: true) }
                }
            )
        case .normalizedMonth:
            NormalizedMonthView(
                snapshot: workspace.displaySnapshot,
                connectionState: workspace.connectionState
            ) { transactionID, isRecurring in
                workspace.setTransaction(transactionID, isRecurring: isRecurring)
            }
        case .accounts:
            AccountsView(
                snapshot: workspace.displaySnapshot,
                accountOverrides: workspace.accountOverrides,
                setAccountKind: { accountID, kind in
                    workspace.setAccount(accountID, kind: kind)
                },
                setAccountAvailableCash: { accountID, includesInAvailableCash in
                    workspace.setAccount(accountID, includesInAvailableCash: includesInAvailableCash)
                },
                resetAccountOverride: { accountID in
                    workspace.resetAccountOverride(accountID)
                }
            )
        case .transactions:
            TransactionsView(snapshot: workspace.displaySnapshot)
        case .budgets:
            BudgetsView(snapshot: workspace.displaySnapshot)
        }
    }
}

private extension View {
    @ViewBuilder
    func budgetTracerSettingsSheet(isPresented: Binding<Bool>) -> some View {
        #if os(macOS)
        self
        #else
        self.sheet(isPresented: isPresented) {
            NavigationStack {
                BudgetTracerSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                isPresented.wrappedValue = false
                            }
                        }
                    }
            }
        }
        #endif
    }
}

private extension View {
    @ViewBuilder
    func budgetTracerPlaidLinkSheet(
        linkToken: Binding<String?>,
        onSuccess: @escaping (String, String?) -> Void,
        onExit: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) -> some View {
        #if os(iOS)
        self.sheet(
            isPresented: Binding(
                get: { linkToken.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented, linkToken.wrappedValue != nil {
                        linkToken.wrappedValue = nil
                        onExit()
                    }
                }
            )
        ) {
            if let token = linkToken.wrappedValue {
                BudgetTracerPlaidLinkSheet(
                    linkToken: token,
                    onSuccess: { publicToken, institutionID in
                        linkToken.wrappedValue = nil
                        onSuccess(publicToken, institutionID)
                    },
                    onExit: {
                        linkToken.wrappedValue = nil
                        onExit()
                    },
                    onFailure: { message in
                        linkToken.wrappedValue = nil
                        onFailure(message)
                    }
                )
            }
        }
        #elseif os(macOS)
        self.sheet(
            isPresented: Binding(
                get: { linkToken.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented, linkToken.wrappedValue != nil {
                        linkToken.wrappedValue = nil
                        onExit()
                    }
                }
            )
        ) {
            if let token = linkToken.wrappedValue {
                BudgetTracerPlaidWebLinkSheet(
                    linkToken: token,
                    onSuccess: { publicToken, institutionID in
                        linkToken.wrappedValue = nil
                        onSuccess(publicToken, institutionID)
                    },
                    onExit: {
                        linkToken.wrappedValue = nil
                        onExit()
                    },
                    onFailure: { message in
                        linkToken.wrappedValue = nil
                        onFailure(message)
                    }
                )
            }
        }
        #else
        self
        #endif
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
            return "Balances"
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
