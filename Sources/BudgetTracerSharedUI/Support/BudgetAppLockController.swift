import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
public protocol AppUnlockAuthenticating: Sendable {
    func unlock(reason: String) async throws
}

public struct LocalAuthenticationUnlockAuthenticator: AppUnlockAuthenticating {
    public init() {}

    public func unlock(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error {
                throw error
            }
            throw AppLockError.authenticationUnavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? AppLockError.authenticationFailed)
                }
            }
        }
    }
}

public enum AppLockError: Error, LocalizedError, Sendable {
    case authenticationUnavailable
    case authenticationFailed

    public var errorDescription: String? {
        switch self {
        case .authenticationUnavailable:
            return "Device owner authentication is not available."
        case .authenticationFailed:
            return "Device owner authentication failed."
        }
    }
}

@MainActor
public final class BudgetAppLockController: ObservableObject {
    @Published public private(set) var isLocked: Bool
    @Published public private(set) var lastErrorMessage: String?

    public let isEnabled: Bool
    private let authenticator: AppUnlockAuthenticating

    public convenience init(isEnabled: Bool) {
        self.init(isEnabled: isEnabled, authenticator: LocalAuthenticationUnlockAuthenticator())
    }

    public init(isEnabled: Bool, authenticator: AppUnlockAuthenticating) {
        self.isEnabled = isEnabled
        self.authenticator = authenticator
        self.isLocked = isEnabled
    }

    public static func disabled() -> BudgetAppLockController {
        BudgetAppLockController(isEnabled: false)
    }

    public func lock() {
        guard isEnabled else {
            return
        }

        isLocked = true
    }

    public func unlock() async {
        guard isEnabled, isLocked else {
            return
        }

        do {
            try await authenticator.unlock(reason: "Unlock BudgetTracer to view your financial data.")
            lastErrorMessage = nil
            isLocked = false
        } catch {
            lastErrorMessage = error.localizedDescription
            isLocked = true
        }
    }
}

struct AppLockPrivacyCover: View {
    @ObservedObject var controller: BudgetAppLockController

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(BudgetTracerStyle.accent)

            VStack(spacing: 6) {
                Text("BudgetTracer Locked")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                Text("Unlock to view local financial data.")
                    .font(.subheadline)
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
            }

            if let message = controller.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(BudgetTracerStyle.caution)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await controller.unlock() }
            } label: {
                Label("Unlock", systemImage: "faceid")
            }
            .buttonStyle(.themeProminent)
        }
        .padding(28)
        .frame(maxWidth: 360)
        .budgetTracerCard(cornerRadius: 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BudgetTracerStyle.canvas.ignoresSafeArea())
    }
}
