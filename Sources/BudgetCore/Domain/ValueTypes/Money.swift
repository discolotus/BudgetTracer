import Foundation

public struct Money: Hashable, Sendable {
    public var minorUnits: Int64
    public var currencyCode: String

    public init(minorUnits: Int64, currencyCode: String = "USD") {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
    }

    public static func dollars(_ amount: Decimal, currencyCode: String = "USD") -> Money {
        let decimal = NSDecimalNumber(decimal: amount * Decimal(100))
        return Money(minorUnits: decimal.rounding(accordingToBehavior: nil).int64Value, currencyCode: currencyCode)
    }

    public var absolute: Money {
        Money(minorUnits: Swift.abs(minorUnits), currencyCode: currencyCode)
    }

    public var isExpense: Bool {
        minorUnits < 0
    }

    public var isIncome: Bool {
        minorUnits > 0
    }

    public var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale.current

        let decimal = Decimal(minorUnits) / 100
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? "\(currencyCode) \(decimal)"
    }
}

public func + (lhs: Money, rhs: Money) -> Money {
    precondition(lhs.currencyCode == rhs.currencyCode, "Cannot add money values with different currencies.")
    return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currencyCode: lhs.currencyCode)
}

public func - (lhs: Money, rhs: Money) -> Money {
    precondition(lhs.currencyCode == rhs.currencyCode, "Cannot subtract money values with different currencies.")
    return Money(minorUnits: lhs.minorUnits - rhs.minorUnits, currencyCode: lhs.currencyCode)
}
