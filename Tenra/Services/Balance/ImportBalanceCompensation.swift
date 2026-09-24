//
//  ImportBalanceCompensation.swift
//  Tenra
//
//  An account's balance is `initialBalance + Σ realized transactions`, with no
//  cutoff at the account's creation. Onboarding and "add account" store the
//  user's REAL current balance as initialBalance, so importing last month's
//  statement used to subtract spending the entered balance already reflected
//  (e.g. real 150 000 ₸, shown 70 000 ₸).
//
//  Rows dated before the account's creation day are, by definition, already
//  baked into the balance the user typed when creating it. Importing them shifts
//  initialBalance by exactly their contribution, so the current balance stays
//  put. Rows on or after the creation day are genuinely new money movement and
//  still move the balance.
//

import Foundation

@MainActor
enum ImportBalanceCompensation {

    /// Σ `contribution(.currentBalance)` of `imported` rows that touch `account` and are
    /// dated strictly before the account's creation day. Rows ON the creation day are
    /// treated as new (the balance may have been entered before or after them).
    /// 0 when the account derives its balance from transactions, has no initialBalance,
    /// or has no createdDate.
    static func preCreationContribution(
        of imported: [Transaction],
        to account: Account,
        engine: BalanceCalculationEngine = BalanceCalculationEngine()
    ) -> Double {
        guard !account.shouldCalculateFromTransactions,
              account.initialBalance != nil,
              let created = account.createdDate else { return 0 }
        let creationDay = DateFormatters.dateFormatter.string(from: created)
        let balance = AccountBalance.from(account)
        var sum: Double = 0
        for tx in imported where tx.date < creationDay {
            sum += engine.contribution(of: tx, to: balance, policy: .currentBalance)
        }
        return sum
    }

    /// Shifts the initialBalance of every account touched by `saved` so rows that
    /// predate the account do not change its current balance. Persists through
    /// `BalanceCoordinator.persistInitialBalance` (saveAccounts never writes
    /// initialBalance) and keeps the in-memory Account model in step.
    static func apply(saved: [Transaction], store: TransactionStore, coordinator: BalanceCoordinator) async {
        let accountIds = Set(saved.compactMap(\.accountId))
        var changed = Set<String>()

        for accountId in accountIds {
            guard let account = store.accounts.first(where: { $0.id == accountId }) else { continue }
            let shift = preCreationContribution(of: saved, to: account)
            guard abs(shift) >= 0.005 else { continue }
            guard let oldInitial = await coordinator.getInitialBalance(for: accountId) else { continue }

            let newInitial = oldInitial - shift
            await coordinator.persistInitialBalance(newInitial, for: accountId)
            var updated = account
            updated.initialBalance = newInitial
            store.updateAccount(updated)
            changed.insert(accountId)
        }

        guard !changed.isEmpty else { return }
        await coordinator.recalculateAccounts(changed, accounts: store.accounts, transactions: store.transactions)
    }
}
