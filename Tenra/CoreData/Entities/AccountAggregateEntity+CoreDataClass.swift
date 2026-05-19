//
//  AccountAggregateEntity+CoreDataClass.swift
//  Tenra
//
//  CoreData warm-start snapshot for `TransactionStore.accountAggregatesByAccountId`.
//  Each row stores totals in the account's OWN currency (not base) — see
//  docs/domains/accounts.md.
//

public import CoreData

public class AccountAggregateEntity: NSManagedObject {
}

// MARK: - Conversion

extension AccountAggregateEntity {
    /// Snapshot row paired with its primary key for in-memory re-keying.
    struct Snapshot: Sendable {
        let accountId: String
        let aggregate: AccountAggregates
    }

    func toSnapshot() -> Snapshot? {
        guard let aid = accountId, !aid.isEmpty else { return nil }
        return Snapshot(
            accountId: aid,
            aggregate: AccountAggregates(
                totalTransactions: Int(totalTransactions),
                totalIncome: totalIncome,
                totalExpense: totalExpense
            )
        )
    }

    nonisolated static func from(
        accountId: String,
        aggregate: AccountAggregates,
        currency: String,
        context: NSManagedObjectContext
    ) -> AccountAggregateEntity {
        let e = AccountAggregateEntity(context: context)
        e.accountId = accountId
        e.totalTransactions = Int32(aggregate.totalTransactions)
        e.totalIncome = aggregate.totalIncome
        e.totalExpense = aggregate.totalExpense
        e.currency = currency
        e.lastUpdated = Date()
        return e
    }
}
