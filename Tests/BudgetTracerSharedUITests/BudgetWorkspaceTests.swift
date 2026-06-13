import BudgetCore
@testable import BudgetTracerSharedUI
import XCTest

@MainActor
final class BudgetWorkspaceTests: XCTestCase {
    func testRefreshUsesSyncIfStaleAndPreservesProviderSyncTimestamp() async throws {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = RecordingFinancialDataProvider(snapshot: makeSnapshot(lastSuccessfulSyncAt: syncedAt))
        let workspace = BudgetWorkspace(
            connectionState: .connected(institutionCount: 0, lastSyncedAt: nil),
            dataProvider: provider,
            userDefaults: try makeUserDefaults()
        )

        await workspace.refresh()

        XCTAssertEqual(provider.requestedPolicies, [.syncIfStale(maxAge: 300)])
        guard case .connected(let institutionCount, let lastSyncedAt) = workspace.connectionState else {
            return XCTFail("Expected workspace to be connected after refresh.")
        }
        XCTAssertEqual(institutionCount, 1)
        XCTAssertEqual(lastSyncedAt, syncedAt)
    }

    func testForceRefreshRequestsForceSyncAndDoesNotInventSyncTimestamp() async throws {
        let provider = RecordingFinancialDataProvider(snapshot: makeSnapshot(lastSuccessfulSyncAt: nil))
        let workspace = BudgetWorkspace(
            connectionState: .connected(institutionCount: 0, lastSyncedAt: nil),
            dataProvider: provider,
            userDefaults: try makeUserDefaults()
        )

        await workspace.refresh(forceSync: true)

        XCTAssertEqual(provider.requestedPolicies, [.forceSync])
        guard case .connected(_, let lastSyncedAt) = workspace.connectionState else {
            return XCTFail("Expected workspace to be connected after refresh.")
        }
        XCTAssertNil(lastSyncedAt)
    }

    func testPreparePlaidLinkRequestsLinkToken() async throws {
        let provider = RecordingFinancialDataProvider(
            snapshot: makeSnapshot(lastSuccessfulSyncAt: nil),
            linkToken: "link-sandbox-test"
        )
        let workspace = BudgetWorkspace(
            connectionState: .connected(institutionCount: 0, lastSyncedAt: nil),
            dataProvider: provider,
            userDefaults: try makeUserDefaults()
        )

        let linkToken = await workspace.preparePlaidLink()

        XCTAssertEqual(linkToken, "link-sandbox-test")
        XCTAssertEqual(provider.linkTokenRequestCount, 1)
        XCTAssertEqual(workspace.plaidLinkState, .ready)
    }

    func testFinishPlaidLinkExchangesPublicTokenAndUpdatesConnectionState() async throws {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_123)
        let provider = RecordingFinancialDataProvider(
            snapshot: makeSnapshot(lastSuccessfulSyncAt: nil),
            exchangeSnapshot: makeSnapshot(lastSuccessfulSyncAt: syncedAt)
        )
        let workspace = BudgetWorkspace(
            connectionState: .connected(institutionCount: 0, lastSyncedAt: nil),
            dataProvider: provider,
            userDefaults: try makeUserDefaults()
        )

        await workspace.finishPlaidLink(publicToken: "public-sandbox-test", institutionID: "ins_test")

        XCTAssertEqual(
            provider.exchangeRequests,
            [PlaidExchangeRequest(publicToken: "public-sandbox-test", institutionID: "ins_test")]
        )
        XCTAssertEqual(workspace.plaidLinkState, .succeeded)
        guard case .connected(let institutionCount, let lastSyncedAt) = workspace.connectionState else {
            return XCTFail("Expected workspace to be connected after exchanging a public token.")
        }
        XCTAssertEqual(institutionCount, 1)
        XCTAssertEqual(lastSyncedAt, syncedAt)
    }

    func testCreateSandboxPlaidItemUpdatesSnapshotAndConnectionState() async throws {
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_456)
        let provider = RecordingFinancialDataProvider(
            snapshot: makeSnapshot(lastSuccessfulSyncAt: nil),
            sandboxSnapshot: makeSnapshot(lastSuccessfulSyncAt: syncedAt)
        )
        let workspace = BudgetWorkspace(
            connectionState: .connected(institutionCount: 0, lastSyncedAt: nil),
            dataProvider: provider,
            userDefaults: try makeUserDefaults()
        )

        await workspace.createSandboxPlaidItem(institutionID: "ins_109508")

        XCTAssertEqual(provider.sandboxInstitutionIDs, ["ins_109508"])
        XCTAssertEqual(workspace.plaidLinkState, .succeeded)
        guard case .connected(let institutionCount, let lastSyncedAt) = workspace.connectionState else {
            return XCTFail("Expected workspace to be connected after creating a sandbox item.")
        }
        XCTAssertEqual(institutionCount, 1)
        XCTAssertEqual(lastSyncedAt, syncedAt)
    }

    func testCancelPlaidLinkReturnsLinkStateToIdle() async throws {
        let provider = RecordingFinancialDataProvider(
            snapshot: makeSnapshot(lastSuccessfulSyncAt: nil),
            linkToken: "link-sandbox-test"
        )
        let workspace = BudgetWorkspace(
            connectionState: .connected(institutionCount: 0, lastSyncedAt: nil),
            dataProvider: provider,
            userDefaults: try makeUserDefaults()
        )
        await workspace.preparePlaidLink()

        workspace.cancelPlaidLink()

        XCTAssertEqual(workspace.plaidLinkState, .idle)
    }

    func testFailPlaidLinkStoresFailureMessage() async throws {
        let workspace = BudgetWorkspace(
            connectionState: .connected(institutionCount: 0, lastSyncedAt: nil),
            dataProvider: RecordingFinancialDataProvider(snapshot: makeSnapshot(lastSuccessfulSyncAt: nil)),
            userDefaults: try makeUserDefaults()
        )

        workspace.failPlaidLink(message: "Link token expired.")

        XCTAssertEqual(workspace.plaidLinkState, .failed(message: "Link token expired."))
    }

    func testProviderOwnedAccountOverridesDoNotWriteSensitiveAccountIDsToUserDefaults() throws {
        let userDefaults = try makeUserDefaults()
        let provider = ProviderOwnedOverrideDataProvider(snapshot: makeSnapshot(lastSuccessfulSyncAt: nil))
        let workspace = BudgetWorkspace(
            snapshot: makeSnapshot(lastSuccessfulSyncAt: nil),
            connectionState: .connected(institutionCount: 1, lastSyncedAt: nil),
            dataProvider: provider,
            userDefaults: userDefaults
        )

        workspace.setAccount("sensitive-account-id", kind: .checking)

        XCTAssertNil(userDefaults.data(forKey: "BudgetTracer.accountOverrides.v1"))
    }

    func testAppLockControllerUnlocksWithSuccessfulAuthenticator() async {
        let controller = BudgetAppLockController(
            isEnabled: true,
            authenticator: SucceedingUnlockAuthenticator()
        )

        XCTAssertTrue(controller.isLocked)

        await controller.unlock()

        XCTAssertFalse(controller.isLocked)
        XCTAssertNil(controller.lastErrorMessage)
    }

    func testMarkingRecurringSweepsEveryTransactionOfTheSameMerchant() {
        func market(_ id: String) -> BudgetTransaction {
            BudgetTransaction(id: id, accountID: "checking", categoryID: nil, postedAt: Date(), merchantName: "Neighborhood Market", amount: Money(minorUnits: -1_500))
        }
        let cafe = BudgetTransaction(id: "cafe", accountID: "checking", categoryID: nil, postedAt: Date(), merchantName: "Corner Cafe", amount: Money(minorUnits: -500))
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [],
            categories: [],
            transactions: [market("m1"), market("m2"), market("m3"), cafe]
        )
        let workspace = BudgetWorkspace(
            snapshot: snapshot,
            dataProvider: SampleFinancialDataProvider(snapshot: snapshot)
        )

        // Flagging one occurrence sweeps the whole merchant series, not just that id.
        workspace.setRecurringForSeries(containing: "m2", isRecurring: true)
        XCTAssertEqual(workspace.snapshot.recurringTransactionIDs, ["m1", "m2", "m3"])

        // Unflagging likewise clears the whole series and leaves other merchants untouched.
        workspace.setRecurringForSeries(containing: "m1", isRecurring: false)
        XCTAssertTrue(workspace.snapshot.recurringTransactionIDs.isEmpty)
    }

    private func makeSnapshot(lastSuccessfulSyncAt: Date?) -> BudgetSnapshot {
        BudgetSnapshot(
            institutions: [Institution(id: "bank", name: "Bank")],
            accounts: [],
            categories: [],
            transactions: [],
            lastSuccessfulSyncAt: lastSuccessfulSyncAt
        )
    }

    private func makeUserDefaults() throws -> UserDefaults {
        let suiteName = "BudgetWorkspaceTests.\(UUID().uuidString)"
        return try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }
}

private final class RecordingFinancialDataProvider: FinancialDataProvider, @unchecked Sendable {
    private let snapshot: BudgetSnapshot
    private let linkToken: String
    private let exchangeSnapshot: BudgetSnapshot?
    private let sandboxSnapshot: BudgetSnapshot?
    private(set) var requestedPolicies: [BudgetSnapshotFreshnessPolicy] = []
    private(set) var linkTokenRequestCount = 0
    private(set) var exchangeRequests: [PlaidExchangeRequest] = []
    private(set) var sandboxInstitutionIDs: [String?] = []

    init(
        snapshot: BudgetSnapshot,
        linkToken: String = "link-token",
        exchangeSnapshot: BudgetSnapshot? = nil,
        sandboxSnapshot: BudgetSnapshot? = nil
    ) {
        self.snapshot = snapshot
        self.linkToken = linkToken
        self.exchangeSnapshot = exchangeSnapshot
        self.sandboxSnapshot = sandboxSnapshot
    }

    func fetchBudgetSnapshot() async throws -> BudgetSnapshot {
        snapshot
    }

    func fetchBudgetSnapshot(freshnessPolicy: BudgetSnapshotFreshnessPolicy) async throws -> BudgetSnapshot {
        requestedPolicies.append(freshnessPolicy)
        return snapshot
    }

    func createPlaidLinkToken() async throws -> String {
        linkTokenRequestCount += 1
        return linkToken
    }

    func exchangePlaidPublicToken(_ publicToken: String, institutionID: String?) async throws -> BudgetSnapshot {
        exchangeRequests.append(PlaidExchangeRequest(publicToken: publicToken, institutionID: institutionID))
        return exchangeSnapshot ?? snapshot
    }

    func createSandboxPlaidItem(institutionID: String?) async throws -> BudgetSnapshot {
        sandboxInstitutionIDs.append(institutionID)
        return sandboxSnapshot ?? snapshot
    }
}

private final class ProviderOwnedOverrideDataProvider: FinancialDataProvider, @unchecked Sendable {
    var storesAccountOverrides: Bool { true }

    private var snapshot: BudgetSnapshot

    init(snapshot: BudgetSnapshot) {
        self.snapshot = snapshot
    }

    func fetchBudgetSnapshot() async throws -> BudgetSnapshot {
        snapshot
    }

    func setAccountOverride(accountID: FinancialAccount.ID, override: AccountOverride?) async throws -> BudgetSnapshot {
        snapshot.accountOverrides[accountID] = override
        return snapshot
    }
}

private struct SucceedingUnlockAuthenticator: AppUnlockAuthenticating {
    func unlock(reason: String) async throws {}
}

private struct PlaidExchangeRequest: Equatable {
    var publicToken: String
    var institutionID: String?
}
