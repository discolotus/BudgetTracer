#if os(iOS)
import LinkKit
import SwiftUI

struct BudgetTracerPlaidLinkSheet: View {
    var linkToken: String
    var onSuccess: (String, String?) -> Void
    var onExit: () -> Void
    var onFailure: (String) -> Void

    var body: some View {
        PlaidLinkView(token: linkToken) { linkSuccess in
            onSuccess(
                linkSuccess.publicToken,
                linkSuccess.metadata.institution.id
            )
        } onExit: { linkExit in
            if let error = linkExit.error {
                onFailure(error.displayMessage ?? String(describing: error))
            } else {
                onExit()
            }
        } onEvent: { _ in
        } errorView: { error in
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)

                Text("Plaid Link Failed")
                    .font(.headline)

                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Dismiss") {
                    onFailure(error.localizedDescription)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }
}
#endif
