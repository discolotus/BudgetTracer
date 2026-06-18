import Foundation

public enum BudgetAssignmentRuleEngine {
    public static func transactionIDsMatching(
        _ rule: BudgetAssignmentRule,
        in snapshot: BudgetSnapshot,
        protectManualAssignments: Bool = true
    ) -> [BudgetTransaction.ID] {
        snapshot.transactions
            .filter { transaction in
                guard rule.matches(transaction) else {
                    return false
                }

                if protectManualAssignments, transaction.hasManualCategoryAssignment {
                    return false
                }

                return transaction.categoryID != rule.categoryID
                    || transaction.categoryAssignmentSource == .rule
                    || transaction.categoryAssignmentSource == .plaid
                    || transaction.categoryAssignmentSource == nil
            }
            .map(\.id)
    }

    public static func applying(
        _ rule: BudgetAssignmentRule,
        to snapshot: BudgetSnapshot,
        protectManualAssignments: Bool = true
    ) -> BudgetSnapshot {
        var updated = snapshot
        updated.transactions = snapshot.transactions.map { transaction in
            guard rule.matches(transaction) else {
                return transaction
            }

            if protectManualAssignments, transaction.hasManualCategoryAssignment {
                return transaction
            }

            var assigned = transaction
            assigned.categoryID = rule.categoryID
            assigned.categoryAssignmentSource = .rule
            assigned.categoryAssignmentRuleID = rule.id
            return assigned
        }

        if let index = updated.assignmentRules.firstIndex(where: { $0.id == rule.id }) {
            updated.assignmentRules[index] = rule
        } else {
            updated.assignmentRules.append(rule)
        }

        return updated
    }
}
