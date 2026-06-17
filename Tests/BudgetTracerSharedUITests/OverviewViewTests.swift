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

    func testPlaidControlsAreHiddenOnlyWhileWorkspaceIsConnecting() {
        XCTAssertFalse(OverviewPlaidControlVisibility.showsControls(for: .connecting))
    }
}
#endif
