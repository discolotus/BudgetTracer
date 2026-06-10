import BudgetCore
import Foundation
import SwiftUI

@MainActor
public final class BudgetWorkspace: ObservableObject {
    @Published public private(set) var snapshot: BudgetSnapshot
    @Published public private(set) var connectionState: PlaidConnectionState

    private let dataProvider: FinancialDataProvider

    public init(
        snapshot: BudgetSnapshot = SampleBudgetData.snapshot,
        connectionState: PlaidConnectionState = .notConnected,
        dataProvider: FinancialDataProvider = PlaidDataProvider()
    ) {
        self.snapshot = snapshot
        self.connectionState = connectionState
        self.dataProvider = dataProvider
    }

    public func refresh() async {
        connectionState = .connecting

        do {
            snapshot = try await dataProvider.fetchBudgetSnapshot()
            connectionState = .connected(institutionCount: snapshot.institutions.count, lastSyncedAt: Date())
        } catch {
            connectionState = .failed(message: error.localizedDescription)
        }
    }

    public func setTransaction(_ transactionID: BudgetTransaction.ID, isRecurring: Bool) {
        if isRecurring {
            snapshot.recurringTransactionIDs.insert(transactionID)
        } else {
            snapshot.recurringTransactionIDs.remove(transactionID)
        }

        Task {
            do {
                snapshot = try await dataProvider.setRegularMonthly(
                    transactionID: transactionID,
                    isRegularMonthly: isRecurring
                )
                connectionState = .connected(institutionCount: snapshot.institutions.count, lastSyncedAt: Date())
            } catch {
                connectionState = .failed(message: error.localizedDescription)
            }
        }
    }
}
