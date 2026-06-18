import BudgetCore
import SwiftUI

public struct BudgetTracerRootView: View {
    @StateObject private var workspace: BudgetWorkspace
    @StateObject private var appLockController: BudgetAppLockController
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("BudgetTracer.selectedSection") private var selectedSectionID = BudgetSection.overview.rawValue
    @SceneStorage("BudgetTracer.transactions.selectedAccountID") private var selectedTransactionAccountID = ""
    @State private var isShowingSettings = false
    @State private var plaidLinkToken: String?

    @MainActor
    public init() {
        _workspace = StateObject(wrappedValue: BudgetWorkspace())
        _appLockController = StateObject(wrappedValue: .disabled())
    }

    @MainActor
    public init(workspace: BudgetWorkspace) {
        _workspace = StateObject(wrappedValue: workspace)
        _appLockController = StateObject(
            wrappedValue: BudgetAppLockController(isEnabled: workspace.requiresAppLock)
        )
    }

    public var body: some View {
        ZStack {
            navigationShell

            if shouldShowPrivacyCover {
                AppLockPrivacyCover(controller: appLockController)
                    .zIndex(1)
            }
        }
            .tint(BudgetTracerStyle.accent)
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
            if appLockController.isEnabled {
                await appLockController.unlock()
            }
            guard !appLockController.isLocked else {
                return
            }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if appLockController.isLocked {
                    Task { await appLockController.unlock() }
                }
            } else {
                appLockController.lock()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .budgetTracerDeleteLocalDataRequested)) { _ in
            workspace.deleteLocalData()
        }
    }

    private var shouldShowPrivacyCover: Bool {
        appLockController.isLocked || (appLockController.isEnabled && scenePhase != .active)
    }

    @ViewBuilder
    private var navigationShell: some View {
        #if os(iOS)
        TabView(selection: selection) {
            ForEach(BudgetSection.allCases) { section in
                NavigationStack {
                    sectionView(for: section)
                        .navigationTitle(section.title)
                        .toolbar { primaryToolbarItems }
                        .toolbarBackground(BudgetTracerStyle.canvas, for: .navigationBar)
                        .background(BudgetTracerStyle.canvas.ignoresSafeArea())
                }
                .tabItem {
                    Label(section.title, systemImage: section.systemImage)
                }
                .tag(section.rawValue as String?)
            }
        }
        #else
        NavigationSplitView {
            AccountsRailView(
                snapshot: workspace.displaySnapshot,
                connectionState: workspace.connectionState,
                plaidLinkState: workspace.plaidLinkState,
                accountOverrides: workspace.accountOverrides,
                dataSourceLabel: workspace.dataSourceLabel,
                selectedAccountID: visibleAccountSelectionID,
                selectAccount: { accountID in
                    selectedTransactionAccountID = accountID
                    selectedSectionID = BudgetSection.transactions.rawValue
                },
                setAccountKind: { accountID, kind in
                    workspace.setAccount(accountID, kind: kind)
                },
                setAccountAvailableCash: { accountID, includesInAvailableCash in
                    workspace.setAccount(accountID, includesInAvailableCash: includesInAvailableCash)
                },
                resetAccountOverride: { accountID in
                    workspace.resetAccountOverride(accountID)
                },
                connect: {
                    Task { plaidLinkToken = await workspace.preparePlaidLink() }
                },
                connectIsDisabled: isPlaidLinkActionInProgress
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } detail: {
            VStack(spacing: 0) {
                macTopBar
                sectionView(for: selectedSection)
            }
            .background(BudgetTracerStyle.canvas.ignoresSafeArea())
            .toolbar { primaryToolbarItems }
            .frame(minWidth: 760, minHeight: 560)
        }
        #endif
    }

    #if os(macOS)
    private var macTopBar: some View {
        HStack {
            Spacer()
            ThemePillPicker(
                options: BudgetSection.topNavSections,
                selection: topNavSelection,
                label: { $0.title }
            )
            .frame(maxWidth: 460)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(BudgetTracerStyle.canvas)
    }

    private var topNavSelection: Binding<BudgetSection> {
        Binding(
            get: {
                let current = selectedSection
                return current == .accounts ? .overview : current
            },
            set: { selectedSectionID = $0.rawValue }
        )
    }
    #endif

    private var isRefreshing: Bool {
        if case .connecting = workspace.connectionState {
            return true
        }

        return false
    }

    private var isPlaidLinkActionInProgress: Bool {
        switch workspace.plaidLinkState {
        case .preparing, .exchanging:
            return true
        case .idle, .ready, .succeeded, .failed:
            return false
        }
    }

    private var selectedSection: BudgetSection {
        BudgetSection(rawValue: selectedSectionID) ?? .overview
    }

    private var transactionAccountFilterID: FinancialAccount.ID? {
        selectedTransactionAccountID.isEmpty ? nil : selectedTransactionAccountID
    }

    private var visibleAccountSelectionID: FinancialAccount.ID? {
        selectedSection == .transactions ? transactionAccountFilterID : nil
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
    private func sectionView(for section: BudgetSection) -> some View {
        switch section {
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
                connectionState: workspace.connectionState,
                setRecurring: { transactionID, isRecurring in
                    workspace.setRecurringForSeries(containing: transactionID, isRecurring: isRecurring)
                },
                setCategory: { transactionID, categoryID in
                    workspace.setCategory(transactionID, categoryID: categoryID)
                },
                setRecurringSeries: { transactionIDs, isRecurring in
                    workspace.setRecurring(transactionIDs, isRecurring: isRecurring)
                },
                setCategorySeries: { transactionIDs, categoryID in
                    workspace.setCategory(transactionIDs, categoryID: categoryID)
                },
                setAccountKind: { accountID, kind in
                    workspace.setAccount(accountID, kind: kind)
                },
                setAccountAvailableCash: { accountID, includesInAvailableCash in
                    workspace.setAccount(accountID, includesInAvailableCash: includesInAvailableCash)
                },
                setAccountOverride: { accountID, override in
                    workspace.setAccount(accountID, override: override)
                },
                saveAssignmentRule: { rule, applyToExisting in
                    workspace.saveAssignmentRule(rule, applyToExisting: applyToExisting)
                }
            )
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
            TransactionsView(
                snapshot: workspace.displaySnapshot,
                selectedAccountID: transactionAccountFilterID,
                clearSelectedAccount: { selectedTransactionAccountID = "" },
                setRecurring: { transactionID, isRecurring in
                    workspace.setRecurringForSeries(containing: transactionID, isRecurring: isRecurring)
                },
                setCategory: { transactionID, categoryID in
                    workspace.setCategory(transactionID, categoryID: categoryID)
                },
                saveAssignmentRule: { rule, applyToExisting in
                    workspace.saveAssignmentRule(rule, applyToExisting: applyToExisting)
                }
            )
        case .budgets:
            BudgetsView(
                snapshot: workspace.displaySnapshot,
                addCategory: { name, limit in workspace.addCategory(name: name, monthlyLimit: limit) },
                saveCategory: { category in workspace.saveCategory(category) },
                deleteCategory: { categoryID in workspace.deleteCategory(categoryID) }
            )
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
    static let budgetTracerDeleteLocalDataRequested = Notification.Name("BudgetTracerDeleteLocalDataRequested")
}

private enum BudgetSection: String, CaseIterable, Identifiable {
    case overview
    case normalizedMonth
    case accounts
    case transactions
    case budgets

    var id: String { rawValue }

    /// macOS top pill nav omits Accounts; the sidebar rail owns account management there.
    static var topNavSections: [BudgetSection] {
        [.overview, .normalizedMonth, .transactions, .budgets]
    }

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
            return "square.grid.2x2"
        case .normalizedMonth:
            return "chart.line.uptrend.xyaxis"
        case .accounts:
            return "building.columns"
        case .transactions:
            return "list.bullet"
        case .budgets:
            return "target"
        }
    }
}
