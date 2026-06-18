import BudgetCore
@testable import BudgetTracerSharedUI
import XCTest

final class PlotAccountMovePlannerTests: XCTestCase {
    func testMovingInvestmentToCashSetsCheckingAndIncludesIt() {
        let account = FinancialAccount(
            id: "brokerage",
            institutionID: "bank",
            name: "Brokerage",
            kind: .investment,
            currentBalance: .dollars(100)
        )
        let snapshot = BudgetSnapshot(institutions: [], accounts: [account], categories: [], transactions: [])

        XCTAssertEqual(
            PlotAccountMovePlanner.actions(for: account, destination: .cash, snapshot: snapshot),
            [.setKind(.checking), .setAvailableCash(true)]
        )
    }

    func testMovingExcludedSavingsToCashIncludesItWithoutChangingKind() {
        let account = FinancialAccount(
            id: "money-market",
            institutionID: "bank",
            name: "Money Market",
            kind: .savings,
            plaidSubtype: "money market",
            currentBalance: .dollars(100)
        )
        let snapshot = BudgetSnapshot(institutions: [], accounts: [account], categories: [], transactions: [])

        XCTAssertEqual(
            PlotAccountMovePlanner.actions(for: account, destination: .cash, snapshot: snapshot),
            [.setAvailableCash(true)]
        )
    }

    func testMovingCheckingToExcludedRemovesItFromCash() {
        let account = FinancialAccount(
            id: "checking",
            institutionID: "bank",
            name: "Checking",
            kind: .checking,
            currentBalance: .dollars(100)
        )
        let snapshot = BudgetSnapshot(institutions: [], accounts: [account], categories: [], transactions: [])

        XCTAssertEqual(
            PlotAccountMovePlanner.actions(for: account, destination: .excluded, snapshot: snapshot),
            [.setAvailableCash(false)]
        )
    }

    func testMovingCardToExcludedChangesItsKind() {
        let account = FinancialAccount(
            id: "card",
            institutionID: "bank",
            name: "Card",
            kind: .creditCard,
            currentBalance: .dollars(100)
        )
        let snapshot = BudgetSnapshot(institutions: [], accounts: [account], categories: [], transactions: [])

        XCTAssertEqual(
            PlotAccountMovePlanner.actions(for: account, destination: .excluded, snapshot: snapshot),
            [.setCreditCardDebt(false)]
        )
        XCTAssertEqual(
            PlotAccountMovePlanner.override(for: account, destination: .excluded, snapshot: snapshot),
            AccountOverride(includesInCreditCardDebt: false)
        )
    }

    func testMovingAccountToCardsSetsCreditCardKind() {
        let account = FinancialAccount(
            id: "checking",
            institutionID: "bank",
            name: "Checking",
            kind: .checking,
            currentBalance: .dollars(100)
        )
        let snapshot = BudgetSnapshot(institutions: [], accounts: [account], categories: [], transactions: [])

        XCTAssertEqual(
            PlotAccountMovePlanner.actions(for: account, destination: .cards, snapshot: snapshot),
            [.setKind(.creditCard), .setCreditCardDebt(true)]
        )
    }

    func testMovingExcludedCreditCardToCardsIncludesItInCardDebtWithoutChangingKind() {
        let account = FinancialAccount(
            id: "card",
            institutionID: "bank",
            name: "Card",
            kind: .creditCard,
            currentBalance: .dollars(100)
        )
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [account],
            categories: [],
            transactions: [],
            accountOverrides: [
                account.id: AccountOverride(includesInCreditCardDebt: false)
            ]
        )

        XCTAssertEqual(
            PlotAccountMovePlanner.actions(for: account, destination: .cards, snapshot: snapshot),
            [.setCreditCardDebt(true)]
        )
        XCTAssertEqual(
            PlotAccountMovePlanner.override(for: account, destination: .cards, snapshot: snapshot),
            AccountOverride(includesInCreditCardDebt: true)
        )
    }

    func testMovingOverriddenOtherAccountToCashBuildsSingleIncludingOverride() {
        let account = FinancialAccount(
            id: "cash-management",
            institutionID: "bank",
            name: "Cash Management",
            kind: .other,
            currentBalance: .dollars(100)
        )
        let snapshot = BudgetSnapshot(
            institutions: [],
            accounts: [account],
            categories: [],
            transactions: [],
            accountOverrides: [
                account.id: AccountOverride(kind: .other, includesInAvailableCash: false)
            ]
        )

        XCTAssertEqual(
            PlotAccountMovePlanner.override(for: account, destination: .cash, snapshot: snapshot),
            AccountOverride(kind: .checking, includesInAvailableCash: true)
        )
    }

    func testMovingAccountToCardsBuildsSingleCardOverride() {
        let account = FinancialAccount(
            id: "cash-management",
            institutionID: "bank",
            name: "Cash Management",
            kind: .other,
            currentBalance: .dollars(100)
        )
        let snapshot = BudgetSnapshot(institutions: [], accounts: [account], categories: [], transactions: [])

        XCTAssertEqual(
            PlotAccountMovePlanner.override(for: account, destination: .cards, snapshot: snapshot),
            AccountOverride(kind: .creditCard, includesInAvailableCash: false, includesInCreditCardDebt: true)
        )
    }

    func testMovingCheckingToExcludedBuildsSingleExcludedOverride() {
        let account = FinancialAccount(
            id: "checking",
            institutionID: "bank",
            name: "Checking",
            kind: .checking,
            currentBalance: .dollars(100)
        )
        let snapshot = BudgetSnapshot(institutions: [], accounts: [account], categories: [], transactions: [])

        XCTAssertEqual(
            PlotAccountMovePlanner.override(for: account, destination: .excluded, snapshot: snapshot),
            AccountOverride(kind: nil, includesInAvailableCash: false)
        )
    }
}
