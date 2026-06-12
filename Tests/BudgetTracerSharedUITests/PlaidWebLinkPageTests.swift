#if os(macOS)
@testable import BudgetTracerSharedUI
import XCTest

final class PlaidWebLinkPageTests: XCTestCase {
    func testPlaidWebLinkPageLoadsPlaidScriptAndPostsNativeCallbacks() {
        let html = BudgetTracerPlaidWebLinkPage.html(linkToken: "link-token\"</script>")

        XCTAssertTrue(html.contains("https://cdn.plaid.com/link/v2/stable/link-initialize.js"))
        XCTAssertTrue(html.contains("Plaid.create"))
        XCTAssertTrue(html.contains("receivedRedirectUri"))
        XCTAssertTrue(html.contains("window.webkit.messageHandlers"))
        XCTAssertTrue(html.contains("plaidSuccess"))
        XCTAssertTrue(html.contains("plaidExit"))
        XCTAssertTrue(html.contains("plaidError"))
        XCTAssertTrue(html.contains("institution.institution_id"))
        XCTAssertTrue(html.contains("<\\/script>"))
    }

    func testPlaidWebLinkPageAddsReceivedRedirectUriWhenProvided() {
        let html = BudgetTracerPlaidWebLinkPage.html(
            linkToken: "link-token",
            receivedRedirectURI: "https://example.com/plaid/oauth?oauth_state_id=state-123"
        )

        XCTAssertTrue(html.contains("const receivedRedirectUri = \"https:\\/\\/example.com\\/plaid\\/oauth?oauth_state_id=state-123\";"))
        XCTAssertTrue(html.contains("plaidConfig.receivedRedirectUri = receivedRedirectUri"))
    }

    func testPlaidWebLinkPageDefinesInitializationBeforeLoadingPlaidScript() throws {
        let html = BudgetTracerPlaidWebLinkPage.html(linkToken: "link-token")

        let initializerRange = try XCTUnwrap(html.range(of: "function initializePlaid()"))
        let plaidScriptRange = try XCTUnwrap(html.range(of: "https://cdn.plaid.com/link/v2/stable/link-initialize.js"))

        XCTAssertLessThan(initializerRange.lowerBound, plaidScriptRange.lowerBound)
    }

    func testPlaidWebLinkPageUsesLocalHTTPSBaseURL() {
        XCTAssertEqual(BudgetTracerPlaidWebLinkPage.baseURL.absoluteString, "https://budgettracer.local/plaid/link")
    }

    func testPlaidOAuthRedirectMatcherDetectsReceivedRedirectUri() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/plaid/oauth?oauth_state_id=state-123"))

        XCTAssertEqual(
            BudgetTracerPlaidOAuthRedirect.receivedRedirectURI(from: url),
            "https://example.com/plaid/oauth?oauth_state_id=state-123"
        )
    }

    func testPlaidOAuthRedirectMatcherIgnoresNonPlaidRedirects() throws {
        let regularURL = try XCTUnwrap(URL(string: "https://bank.example.com/login?state=state-123"))
        let customSchemeURL = try XCTUnwrap(URL(string: "budgettracer://plaid/oauth?oauth_state_id=state-123"))

        XCTAssertNil(BudgetTracerPlaidOAuthRedirect.receivedRedirectURI(from: regularURL))
        XCTAssertNil(BudgetTracerPlaidOAuthRedirect.receivedRedirectURI(from: customSchemeURL))
    }
}
#endif
