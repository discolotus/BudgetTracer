import Foundation

public enum PlaidCategoryBudgetClassifier {
    public static func categoryID(
        primary: String?,
        detailed: String?,
        merchantName: String,
        amount: Money,
        categories: [BudgetCategory]
    ) -> BudgetCategory.ID? {
        guard let bucket = bucket(
            primary: primary,
            detailed: detailed,
            merchantName: merchantName,
            amount: amount
        ) else {
            return nil
        }

        return categoryID(for: bucket, categories: categories)
    }

    private static func bucket(
        primary: String?,
        detailed: String?,
        merchantName: String,
        amount: Money
    ) -> DefaultBudgetBucket? {
        let primary = normalizedPlaidCategory(primary)
        let detailed = normalizedPlaidCategory(detailed)

        if isTransferOrPayment(primary: primary, detailed: detailed) {
            return nil
        }

        if primary == "INCOME" || (primary.isEmpty && amount.isIncome) {
            return .income
        }

        if primary == "RENT_AND_UTILITIES" || detailed.hasPrefix("RENT_AND_UTILITIES") {
            return .housing
        }

        if isGrocery(primary: primary, detailed: detailed, merchantName: merchantName) {
            return .groceries
        }

        guard !primary.isEmpty || !detailed.isEmpty else {
            return nil
        }

        return amount.isExpense ? .other : nil
    }

    private static func categoryID(
        for bucket: DefaultBudgetBucket,
        categories: [BudgetCategory]
    ) -> BudgetCategory.ID? {
        if categories.contains(where: { $0.id == bucket.defaultCategoryID }) {
            return bucket.defaultCategoryID
        }

        let targetName = normalizedName(bucket.displayName)
        return categories.first { normalizedName($0.name) == targetName }?.id
    }

    private static func isTransferOrPayment(primary: String, detailed: String) -> Bool {
        primary.hasPrefix("TRANSFER")
            || primary == "LOAN_PAYMENTS"
            || detailed.contains("CREDIT_CARD_PAYMENT")
    }

    private static func isGrocery(
        primary: String,
        detailed: String,
        merchantName: String
    ) -> Bool {
        if detailed.contains("GROCERY")
            || detailed.contains("GROCERIES")
            || detailed.contains("SUPERMARKET") {
            return true
        }

        guard primary == "FOOD_AND_DRINK" || primary == "GENERAL_MERCHANDISE" else {
            return false
        }

        let merchant = normalizedName(merchantName)
        return [
            "grocery",
            "groceries",
            "market",
            "supermarket",
            "trader joe",
            "whole foods",
            "safeway",
            "kroger",
            "costco"
        ].contains { merchant.contains($0) }
    }

    private static func normalizedPlaidCategory(_ value: String?) -> String {
        normalizedName(value ?? "")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}

private enum DefaultBudgetBucket {
    case income
    case housing
    case groceries
    case other

    var defaultCategoryID: BudgetCategory.ID {
        switch self {
        case .income:
            return "default-income"
        case .housing:
            return "default-housing"
        case .groceries:
            return "default-groceries"
        case .other:
            return "default-other"
        }
    }

    var displayName: String {
        switch self {
        case .income:
            return "Income"
        case .housing:
            return "Housing"
        case .groceries:
            return "Groceries"
        case .other:
            return "Other"
        }
    }
}
