import Foundation

@MainActor
public protocol AppleIdentityTokenProvider: Sendable {
    func identityToken() async throws -> String
}

public struct StaticAppleIdentityTokenProvider: AppleIdentityTokenProvider {
    private let token: String

    public init(token: String) {
        self.token = token
    }

    public func identityToken() async throws -> String {
        token
    }
}

@MainActor
public final class CachedAppleIdentityTokenProvider: AppleIdentityTokenProvider, @unchecked Sendable {
    private let upstream: any AppleIdentityTokenProvider
    private var cachedToken: String?

    public init(upstream: any AppleIdentityTokenProvider) {
        self.upstream = upstream
    }

    public func identityToken() async throws -> String {
        if let cachedToken {
            return cachedToken
        }

        let token = try await upstream.identityToken()
        cachedToken = token
        return token
    }

    public func clearCache() {
        cachedToken = nil
    }
}

public enum AppleIdentityTokenError: Error, LocalizedError, Sendable {
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Sign in with Apple did not return an identity token."
        }
    }
}
