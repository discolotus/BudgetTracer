import CryptoKit
import Foundation

actor AppleIdentityRelayVerifier: RelayIdentityVerifying {
    private let audience: String
    private let keysURL: URL
    private let session: URLSession
    private let clock: @Sendable () -> Date
    private let keyCacheLifetime: TimeInterval
    private var cachedKeys: [String: P256.Signing.PublicKey] = [:]
    private var keysLoadedAt: Date?

    init(
        audience: String,
        keysURL: URL = URL(string: "https://appleid.apple.com/auth/keys")!,
        session: URLSession = .shared,
        clock: @escaping @Sendable () -> Date = { Date() },
        keyCacheLifetime: TimeInterval = 21_600
    ) {
        self.audience = audience
        self.keysURL = keysURL
        self.session = session
        self.clock = clock
        self.keyCacheLifetime = keyCacheLifetime
    }

    func verifiedSubject(from request: HTTPRequest) async throws -> String {
        let token = try RelayBearerToken.token(from: request)
        let jwt = try ParsedJWT(token)
        let header = try JSONDecoder().decode(JWTHeader.self, from: Self.base64URLDecoded(jwt.header))

        guard header.alg == "ES256", let kid = header.kid, !kid.isEmpty else {
            throw HTTPError.unauthorized("The Sign in with Apple token header is invalid.")
        }

        let publicKey = try await publicKey(kid: kid)
        let signatureData = try Self.base64URLDecoded(jwt.signature)
        guard signatureData.count == 64 else {
            throw HTTPError.unauthorized("The Sign in with Apple token signature is invalid.")
        }

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        guard publicKey.isValidSignature(signature, for: Data(jwt.signingInput.utf8)) else {
            throw HTTPError.unauthorized("The Sign in with Apple token signature is invalid.")
        }

        let claims = try JSONDecoder().decode(
            AppleIdentityClaims.self,
            from: Self.base64URLDecoded(jwt.payload)
        )
        try claims.validate(audience: audience, now: clock())
        return claims.sub
    }

    private func publicKey(kid: String) async throws -> P256.Signing.PublicKey {
        if let loadedAt = keysLoadedAt,
           clock().timeIntervalSince(loadedAt) < keyCacheLifetime,
           let key = cachedKeys[kid] {
            return key
        }

        try await refreshKeys()

        guard let key = cachedKeys[kid] else {
            throw HTTPError.unauthorized("No Apple public key matched the Sign in with Apple token.")
        }
        return key
    }

    private func refreshKeys() async throws {
        let (data, response) = try await session.data(from: keysURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw HTTPError.unauthorized("Could not load Apple public keys.")
        }

        let jwks = try JSONDecoder().decode(AppleJWKS.self, from: data)
        cachedKeys = jwks.keys.reduce(into: [String: P256.Signing.PublicKey]()) { result, key in
            guard key.kty == "EC",
                  key.crv == "P-256",
                  key.alg == "ES256",
                  let x = try? Self.base64URLDecoded(key.x),
                  let y = try? Self.base64URLDecoded(key.y),
                  x.count == 32,
                  y.count == 32 else {
                return
            }

            var representation = Data([0x04])
            representation.append(x)
            representation.append(y)
            if let publicKey = try? P256.Signing.PublicKey(x963Representation: representation) {
                result[key.kid] = publicKey
            }
        }
        keysLoadedAt = clock()
    }

    private static func base64URLDecoded(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: base64) else {
            throw HTTPError.unauthorized("The Sign in with Apple token is not valid base64url.")
        }
        return data
    }
}

enum RelayBearerToken {
    static func token(from request: HTTPRequest) throws -> String {
        guard let authorization = request.headers["authorization"],
              authorization.lowercased().hasPrefix("bearer ") else {
            throw HTTPError.unauthorized("A Sign in with Apple bearer token is required.")
        }

        let token = authorization.dropFirst("Bearer ".count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw HTTPError.unauthorized("The bearer token is invalid.")
        }
        return token
    }
}

private struct ParsedJWT {
    var header: String
    var payload: String
    var signature: String

    var signingInput: String {
        "\(header).\(payload)"
    }

    init(_ token: String) throws {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              !parts[0].isEmpty,
              !parts[1].isEmpty,
              !parts[2].isEmpty else {
            throw HTTPError.unauthorized("The Sign in with Apple token is malformed.")
        }

        header = parts[0]
        payload = parts[1]
        signature = parts[2]
    }
}

private struct JWTHeader: Decodable {
    var alg: String
    var kid: String?
}

private struct AppleJWKS: Decodable {
    var keys: [AppleJWK]
}

private struct AppleJWK: Decodable {
    var kty: String
    var kid: String
    var alg: String
    var crv: String
    var x: String
    var y: String
}

private struct AppleIdentityClaims: Decodable {
    var iss: String
    var sub: String
    var aud: AudienceClaim
    var exp: TimeInterval
    var iat: TimeInterval?

    func validate(audience: String, now: Date) throws {
        let nowTimestamp = now.timeIntervalSince1970
        let clockSkew: TimeInterval = 60

        guard iss == "https://appleid.apple.com" else {
            throw HTTPError.unauthorized("The Sign in with Apple token issuer is invalid.")
        }

        guard aud.contains(audience) else {
            throw HTTPError.unauthorized("The Sign in with Apple token audience is invalid.")
        }

        guard exp + clockSkew > nowTimestamp else {
            throw HTTPError.unauthorized("The Sign in with Apple token is expired.")
        }

        if let iat, iat - clockSkew > nowTimestamp {
            throw HTTPError.unauthorized("The Sign in with Apple token was issued in the future.")
        }
    }
}

private enum AudienceClaim: Decodable {
    case single(String)
    case multiple([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .single(value)
            return
        }

        self = .multiple(try container.decode([String].self))
    }

    func contains(_ audience: String) -> Bool {
        switch self {
        case .single(let value):
            return value == audience
        case .multiple(let values):
            return values.contains(audience)
        }
    }
}
