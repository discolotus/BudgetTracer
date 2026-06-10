import Foundation

public struct PlaidLocalSecretsFile {
    public var path: String

    public init(path: String) {
        self.path = path
    }

    public func sandboxConfiguration(webhookURL: URL? = nil) throws -> PlaidConfiguration {
        let values = try readValues()
        guard let clientID = values["PLAID_CLIENT_ID"], !clientID.isEmpty else {
            throw PlaidLocalSecretsFileError.missingKey("PLAID_CLIENT_ID")
        }

        let secret = values["PLAID_SANDBOX_SECRET"] ?? values["PLAID_SECRET"]
        guard let secret, !secret.isEmpty else {
            throw PlaidLocalSecretsFileError.missingKey("PLAID_SANDBOX_SECRET")
        }

        return PlaidConfiguration(
            clientID: clientID,
            secret: secret,
            environment: .sandbox,
            webhookURL: webhookURL
        )
    }

    private func readValues() throws -> [String: String] {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        var values: [String: String] = [:]

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            let assignment = trimmed.hasPrefix("export ") ? String(trimmed.dropFirst("export ".count)) : trimmed
            guard let separator = assignment.firstIndex(of: "=") else {
                continue
            }

            let key = assignment[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = assignment[assignment.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = unquoted(rawValue)
        }

        return values
    }

    private func unquoted(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        let first = value.first
        let last = value.last
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }

        return value
    }
}

public enum PlaidLocalSecretsFileError: Error, LocalizedError {
    case missingKey(String)

    public var errorDescription: String? {
        switch self {
        case let .missingKey(key):
            return "Plaid local secrets file is missing \(key)."
        }
    }
}
