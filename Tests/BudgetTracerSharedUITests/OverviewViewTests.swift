#if canImport(SwiftUI)
@testable import BudgetTracerSharedUI
import BudgetCore
import XCTest

final class OverviewViewTests: XCTestCase {
    func testPlaidControlsStayVisibleAfterAnInstitutionIsConnected() {
        XCTAssertTrue(
            OverviewPlaidControlVisibility.showsControls(
                for: .connected(institutionCount: 1, lastSyncedAt: nil)
            )
        )
    }

    func testPlaidControlsAreVisibleForFirstRunAndFailureStates() {
        XCTAssertTrue(OverviewPlaidControlVisibility.showsControls(for: .notConnected))
        XCTAssertTrue(OverviewPlaidControlVisibility.showsControls(for: .failed(message: "Backend unavailable.")))
        XCTAssertTrue(
            OverviewPlaidControlVisibility.showsControls(
                for: .connected(institutionCount: 0, lastSyncedAt: nil)
            )
        )
    }

    func testPlaidControlsStayVisibleWhileWorkspaceIsRefreshing() {
        XCTAssertTrue(OverviewPlaidControlVisibility.showsControls(for: .connecting))
    }

    func testAccountsRailShowsPlaidLinkFailureStatus() throws {
        let status = try XCTUnwrap(
            AccountsRailPlaidStatus.status(
                for: .failed(message: "Plaid relay returned HTTP 401.")
            )
        )

        XCTAssertEqual(
            status.message,
            "Connection failed: Plaid relay returned HTTP 401."
        )
        XCTAssertEqual(status.systemImage, "exclamationmark.triangle")
        XCTAssertFalse(status.showsProgress)
    }

    func testAccountsRailShowsPlaidLinkProgressStatus() throws {
        let status = try XCTUnwrap(AccountsRailPlaidStatus.status(for: .preparing))

        XCTAssertEqual(status.message, "Preparing Plaid Link...")
        XCTAssertTrue(status.showsProgress)
    }
}
#endif
