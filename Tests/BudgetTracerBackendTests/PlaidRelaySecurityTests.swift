@testable import BudgetTracerBackend
import BudgetPersistence
import BudgetPlaid
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

    func testRelayOnlyRouteModeRejectsDevelopmentRoutes() async throws {
        let router = try makeRouter(routeMode: .relayOnly)
        let request = try HTTPRequest(data: Data("""
        GET /snapshot HTTP/1.1\r
        Host: 127.0.0.1\r
        \r

        """.utf8))

        let response = try await router.route(request)

        XCTAssertEqual(response.status, .notFound)
    }

    func testBackendRouteModeParsesRelayOnlyEnvironment() {
        XCTAssertEqual(
            BackendRouteMode(environment: ["BUDGETTRACER_BACKEND_ROUTE_MODE": "relay-only"]),
            .relayOnly
        )
        XCTAssertEqual(
            BackendRouteMode(environment: ["BUDGETTRACER_RELAY_ONLY": "1"]),
            .relayOnly
        )
        XCTAssertEqual(BackendRouteMode(environment: [:]), .development)
    }

    private func makeRouter(routeMode: BackendRouteMode) throws -> BackendRouter {
        let database = try SQLiteDatabase(path: ":memory:")
        let repository = BudgetRepository(database: database)
        try repository.migrate()
        try repository.ensureUser(id: "local-user")

        let plaidClient = PlaidAPIClient(
            configuration: PlaidConfiguration(clientID: "client", secret: "secret")
        )
        return BackendRouter(
            repository: repository,
            plaidSyncService: PlaidSyncService(
                client: plaidClient,
                repository: repository,
                tokenVault: InMemoryPlaidTokenVault()
            ),
            plaidRelayClient: plaidClient,
            routeMode: routeMode,
            defaultUserID: "local-user"
        )
    }
}
