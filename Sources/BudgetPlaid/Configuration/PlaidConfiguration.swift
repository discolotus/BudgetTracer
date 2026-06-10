import Foundation

public struct PlaidConfiguration: Hashable, Sendable {
    public var clientID: String
    public var secret: String
    public var environment: PlaidEnvironment
    public var webhookURL: URL?
    public var clientName: String
    public var daysRequested: Int

    public init(
        clientID: String,
        secret: String,
        environment: PlaidEnvironment = .sandbox,
        webhookURL: URL? = nil,
        clientName: String = "BudgetTracer",
        daysRequested: Int = 730
    ) {
        self.clientID = clientID
        self.secret = secret
        self.environment = environment
        self.webhookURL = webhookURL
        self.clientName = clientName
        self.daysRequested = daysRequested
    }
}

public enum PlaidEnvironment: String, Hashable, Sendable {
    case sandbox
    case development
    case production

    public var baseURL: URL {
        switch self {
        case .sandbox:
            return URL(string: "https://sandbox.plaid.com")!
        case .development:
            return URL(string: "https://development.plaid.com")!
        case .production:
            return URL(string: "https://production.plaid.com")!
        }
    }
}
