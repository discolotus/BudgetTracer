import BudgetCore
import Foundation
import UniformTypeIdentifiers

enum AccountDragPayload {
    static let contentType = UTType(exportedAs: "com.budgettracer.account-id")
    static let supportedContentTypes: [UTType] = [contentType, .plainText, .text]

    static func provider(
        accountID: FinancialAccount.ID,
        suggestedName: String? = nil
    ) -> NSItemProvider {
        let provider = NSItemProvider(object: accountID as NSString)
        provider.suggestedName = suggestedName
        provider.registerDataRepresentation(
            forTypeIdentifier: contentType.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(Data(accountID.utf8), nil)
            return nil
        }
        return provider
    }

    static func loadAccountID(
        from providers: [NSItemProvider],
        completion: @escaping (FinancialAccount.ID) -> Void
    ) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(contentType.identifier) }) {
            provider.loadDataRepresentation(forTypeIdentifier: contentType.identifier) { data, _ in
                guard let data, let accountID = String(data: data, encoding: .utf8) else {
                    return
                }

                DispatchQueue.main.async {
                    completion(accountID)
                }
            }
            return true
        }

        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let accountID = object as? String ?? (object as? NSString).map(String.init) else {
                return
            }

            DispatchQueue.main.async {
                completion(accountID)
            }
        }
        return true
    }
}
