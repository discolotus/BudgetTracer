#if canImport(AuthenticationServices)
import AuthenticationServices
import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
public final class SignInWithAppleIdentityTokenProvider: NSObject, AppleIdentityTokenProvider, @unchecked Sendable {
    private var continuation: CheckedContinuation<String, Error>?

    public override init() {
        super.init()
    }

    public func identityToken() async throws -> String {
        if continuation != nil {
            throw SignInWithAppleError.authorizationAlreadyInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        continuation.resume(with: result)
    }
}

extension SignInWithAppleIdentityTokenProvider: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              !token.isEmpty else {
            finish(.failure(AppleIdentityTokenError.missingToken))
            return
        }

        finish(.success(token))
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(.failure(error))
    }
}

extension SignInWithAppleIdentityTokenProvider: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
            ?? ASPresentationAnchor()
        #elseif os(macOS)
        return NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

public enum SignInWithAppleError: Error, LocalizedError, Sendable {
    case authorizationAlreadyInProgress

    public var errorDescription: String? {
        switch self {
        case .authorizationAlreadyInProgress:
            return "Sign in with Apple is already in progress."
        }
    }
}
#endif
