import Foundation

public struct PlaidEnvironmentVariables {
    public var values: [String: String]

    public init(values: [String: String] = ProcessInfo.processInfo.environment) {
        self.values = values
    }

    public func configuration(
        plaidEnvironment: PlaidEnvironment,
        webhookURL: URL? = nil,
        redirectURI: URL? = nil
    ) throws -> PlaidConfiguration {
        guard let clientID = values["PLAID_CLIENT_ID"], !clientID.isEmpty else {
            throw PlaidEnvironmentVariablesError.missingKey("PLAID_CLIENT_ID")
        }

        guard let secret = Self.secret(in: values, for: plaidEnvironment), !secret.isEmpty else {
            throw PlaidEnvironmentVariablesError.missingKey(plaidEnvironment.secretEnvironmentKey)
        }

        return PlaidConfiguration(
            clientID: clientID,
            secret: secret,
            environment: plaidEnvironment,
            webhookURL: webhookURL,
            redirectURI: redirectURI ?? values["PLAID_REDIRECT_URI"].flatMap(URL.init(string:)),
            daysRequested: Self.daysRequested(in: values)
        )
    }

    static func secret(in values: [String: String], for plaidEnvironment: PlaidEnvironment) -> String? {
        values[plaidEnvironment.secretEnvironmentKey] ?? values["PLAID_SECRET"]
    }

    private static func daysRequested(in values: [String: String]) -> Int {
        values["PLAID_TRANSACTIONS_DAYS_REQUESTED"].flatMap(Int.init) ?? 730
    }
}

public enum PlaidEnvironmentVariablesError: Error, LocalizedError {
    case missingKey(String)

    public var errorDescription: String? {
        switch self {
        case let .missingKey(key):
            return "Plaid environment configuration is missing \(key)."
        }
    }
}
