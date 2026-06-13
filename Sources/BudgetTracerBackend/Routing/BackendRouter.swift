import BudgetCore
import BudgetPersistence
import BudgetPlaid
import CryptoKit
import Foundation

actor BackendRouter {
    private let repository: BudgetRepository
    private let plaidSyncService: PlaidSyncService
    private let defaultUserID: String
    private let clock: @Sendable () -> Date

    init(
        repository: BudgetRepository,
        plaidSyncService: PlaidSyncService,
        defaultUserID: String,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.plaidSyncService = plaidSyncService
        self.defaultUserID = defaultUserID
        self.clock = clock
    }

    func route(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                return try health()
            case ("GET", "/snapshot"):
                return try await snapshot(request)
            case ("POST", "/plaid/link-token"):
                return try await createLinkToken(request)
            case ("POST", "/plaid/exchange-public-token"):
                return try await exchangePublicToken(request)
            case ("POST", "/plaid/sandbox/create-item"):
                return try await createSandboxItem(request)
            case ("POST", "/plaid/sync"):
                return try await sync(request)
            case ("POST", "/plaid/webhook"):
                return try await webhook(request)
            case ("PATCH", "/transactions/regular-monthly"):
                return try updateRegularMonthly(request)
            case ("PATCH", "/transactions/category"):
                return try updateCategory(request)
            default:
                throw HTTPError.notFound("No route for \(request.method) \(request.path).")
            }
        } catch let error as HTTPError {
            return HTTPResponse.json(status: error.status, body: ErrorResponse(error: error.localizedDescription))
        }
    }

    private func health() throws -> HTTPResponse {
        let itemCount = try repository.plaidItemCount(userID: defaultUserID)
        return HTTPResponse.json(body: HealthResponse(status: "ok", userID: defaultUserID, plaidItemCount: itemCount))
    }

    private func snapshot(_ request: HTTPRequest) async throws -> HTTPResponse {
        let userID = request.query["user_id"] ?? defaultUserID
        let policy = try SnapshotFreshnessPolicy(query: request.query)
        let syncedItemIDs = try await syncItemsIfNeeded(userID: userID, policy: policy)
        let snapshot = try repository.fetchSnapshot(userID: userID)
        return HTTPResponse.json(
            body: SnapshotResponse(
                snapshot: snapshot,
                freshness: SnapshotFreshnessResponse(
                    policy: policy.responseValue,
                    syncedItemIDs: syncedItemIDs
                )
            )
        )
    }

    private func cachedSnapshot(userID: String) throws -> HTTPResponse {
        let snapshot = try repository.fetchSnapshot(userID: userID)
        return HTTPResponse.json(body: SnapshotResponse(snapshot: snapshot))
    }

    private func syncItemsIfNeeded(userID: String, policy: SnapshotFreshnessPolicy) async throws -> [String] {
        let itemIDs: [String]
        switch policy {
        case .cached:
            itemIDs = []
        case .syncIfStale(let maxAge):
            itemIDs = try repository
                .plaidItemsNeedingSync(userID: userID, maxAge: maxAge, asOf: clock())
                .map(\.id)
        case .forceSync:
            itemIDs = try repository.plaidItems(userID: userID).map(\.id)
        }

        var syncedItemIDs: [String] = []
        for itemID in itemIDs {
            _ = try await plaidSyncService.syncItem(id: itemID)
            syncedItemIDs.append(itemID)
        }

        return syncedItemIDs
    }

    private func createLinkToken(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body = try request.jsonBody(UserScopedRequest.self)
        let userID = body.userID ?? defaultUserID
        try repository.ensureUser(id: userID)

        let linkToken = try await plaidSyncService.createLinkToken(userID: userID)
        return HTTPResponse.json(body: LinkTokenResponse(linkToken: linkToken))
    }

    private func exchangePublicToken(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body = try request.jsonBody(ExchangePublicTokenRequest.self)
        let userID = body.userID ?? defaultUserID
        guard !body.publicToken.isEmpty else {
            throw HTTPError.badRequest("public_token is required.")
        }

        let item = try await plaidSyncService.exchangePublicToken(
            body.publicToken,
            userID: userID,
            institutionID: body.institutionID
        )
        let syncedSnapshot = try await plaidSyncService.syncItem(id: item.id)

        return HTTPResponse.json(
            body: ExchangePublicTokenResponse(
                itemID: item.id,
                plaidItemID: item.plaidItemID,
                snapshot: SnapshotResponse(snapshot: syncedSnapshot)
            )
        )
    }

    private func createSandboxItem(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body = try request.jsonBody(CreateSandboxItemRequest.self)
        let userID = body.userID ?? defaultUserID
        let institutionID = body.institutionID ?? "ins_109508"
        try repository.ensureUser(id: userID)

        let syncedSnapshot = try await plaidSyncService.createSandboxItemAndSync(
            userID: userID,
            institutionID: institutionID
        )

        return HTTPResponse.json(
            body: SandboxItemResponse(
                institutionID: institutionID,
                snapshot: SnapshotResponse(snapshot: syncedSnapshot)
            )
        )
    }

    private func sync(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body = try request.jsonBody(SyncRequest.self)
        let userID = body.userID ?? defaultUserID
        let itemIDs: [String]

        if let itemID = body.itemID {
            itemIDs = [itemID]
        } else {
            itemIDs = try repository.plaidItems(userID: userID).map(\.id)
        }

        var lastSnapshot = try repository.fetchSnapshot(userID: userID)
        for itemID in itemIDs {
            lastSnapshot = try await plaidSyncService.syncItem(id: itemID)
        }

        return HTTPResponse.json(body: SyncResponse(syncedItemIDs: itemIDs, snapshot: SnapshotResponse(snapshot: lastSnapshot)))
    }

    private func webhook(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body = try request.jsonBody(PlaidWebhookRequest.self)
        let payloadJSON = String(data: request.body, encoding: .utf8) ?? "{}"
        let eventID = [
            body.webhookType,
            body.webhookCode,
            body.itemID ?? "none",
            sha256Hex(request.body)
        ].joined(separator: ":")
        let event = PlaidWebhookEventRecord(
            id: eventID,
            plaidItemID: body.itemID,
            webhookType: body.webhookType,
            webhookCode: body.webhookCode,
            receivedAt: Date(),
            payloadJSON: payloadJSON
        )
        try repository.recordWebhookEvent(event)

        if try repository.isWebhookProcessed(id: eventID) {
            return HTTPResponse.json(status: .accepted, body: WebhookResponse(accepted: true, syncedItemID: nil))
        }

        var syncedItemID: String?
        if body.webhookCode == "SYNC_UPDATES_AVAILABLE",
           let plaidItemID = body.itemID,
           let item = try repository.plaidItem(plaidItemID: plaidItemID) {
            _ = try await plaidSyncService.syncItem(id: item.id)
            syncedItemID = item.id
        }

        try repository.markWebhookProcessed(id: eventID)
        return HTTPResponse.json(status: .accepted, body: WebhookResponse(accepted: true, syncedItemID: syncedItemID))
    }

    private func updateRegularMonthly(_ request: HTTPRequest) throws -> HTTPResponse {
        let body = try request.jsonBody(UpdateRegularMonthlyRequest.self)
        let userID = body.userID ?? defaultUserID

        guard !body.transactionID.isEmpty else {
            throw HTTPError.badRequest("transaction_id is required.")
        }

        try repository.setRegularMonthly(
            transactionID: body.transactionID,
            isRegularMonthly: body.isRegularMonthly,
            userID: userID
        )

        return try cachedSnapshot(userID: userID)
    }

    private func updateCategory(_ request: HTTPRequest) throws -> HTTPResponse {
        let body = try request.jsonBody(UpdateCategoryRequest.self)
        let userID = body.userID ?? defaultUserID

        guard !body.transactionID.isEmpty else {
            throw HTTPError.badRequest("transaction_id is required.")
        }

        try repository.setCategory(
            transactionID: body.transactionID,
            categoryID: body.categoryID,
            userID: userID
        )

        return try cachedSnapshot(userID: userID)
    }
}

private enum SnapshotFreshnessPolicy {
    static let defaultMaxAge: TimeInterval = 300

    case cached
    case syncIfStale(maxAge: TimeInterval)
    case forceSync

    init(query: [String: String]) throws {
        let value = (query["freshness"] ?? "cached").lowercased()
        switch value {
        case "cached":
            self = .cached
        case "sync_if_stale", "fresh":
            self = .syncIfStale(maxAge: try Self.maxAge(from: query))
        case "force_sync", "force":
            self = .forceSync
        default:
            throw HTTPError.badRequest("Unsupported freshness policy '\(value)'.")
        }
    }

    var responseValue: String {
        switch self {
        case .cached:
            return "cached"
        case .syncIfStale:
            return "sync_if_stale"
        case .forceSync:
            return "force_sync"
        }
    }

    private static func maxAge(from query: [String: String]) throws -> TimeInterval {
        guard let rawValue = query["max_age_seconds"], !rawValue.isEmpty else {
            return defaultMaxAge
        }

        guard let maxAge = TimeInterval(rawValue), maxAge >= 0 else {
            throw HTTPError.badRequest("max_age_seconds must be a non-negative number.")
        }

        return maxAge
    }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
