import BudgetCore
@testable import BudgetTracerSharedUI
import XCTest

final class AccountDragPayloadTests: XCTestCase {
    func testProviderRoundTripsAccountIDThroughSharedPayload() {
        let provider = AccountDragPayload.provider(accountID: "card-1", suggestedName: "Travel Card")
        let expectation = expectation(description: "load account id")

        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(AccountDragPayload.contentType.identifier))
        XCTAssertTrue(provider.canLoadObject(ofClass: NSString.self))
        XCTAssertTrue(
            AccountDragPayload.loadAccountID(from: [provider]) { accountID in
                XCTAssertEqual(accountID, "card-1")
                expectation.fulfill()
            }
        )

        wait(for: [expectation], timeout: 1)
    }
}
