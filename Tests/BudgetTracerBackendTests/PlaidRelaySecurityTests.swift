@testable import BudgetTracerBackend
import Foundation
import XCTest

final class PlaidRelaySecurityTests: XCTestCase {
    func testBearerRelayIdentityVerifierRequiresAuthorizationHeader() async throws {
        let request = try HTTPRequest(data: Data("""
        POST /v1/plaid/link-token HTTP/1.1\r
        Host: 127.0.0.1\r
        Content-Length: 2\r
        \r
        {}
        """.utf8))

        do {
            _ = try await BearerRelayIdentityVerifier().verifiedSubject(from: request)
            XCTFail("Expected verifier to reject a missing authorization header.")
        } catch {
            XCTAssertEqual((error as? HTTPError)?.status, .unauthorized)
        }
    }

    func testSensitiveLogRedactorRemovesFinancialPayloadFields() {
        let payload = Data("""
        {
          "access_token": "access-secret",
          "accounts": [
            {
              "account_id": "account-1",
              "name": "Checking",
              "balances": {
                "current": 1000.25,
                "available": 900.10
              }
            }
          ],
          "transactions": [
            {
              "transaction_id": "txn-1",
              "merchant_name": "Coffee Shop",
              "amount": 12.50
            }
          ]
        }
        """.utf8)

        let redacted = SensitiveLogRedactor.redactJSON(payload)

        XCTAssertFalse(redacted.contains("access-secret"))
        XCTAssertFalse(redacted.contains("account-1"))
        XCTAssertFalse(redacted.contains("Coffee Shop"))
        XCTAssertFalse(redacted.contains("1000.25"))
        XCTAssertTrue(redacted.contains("<redacted>"))
    }
}
