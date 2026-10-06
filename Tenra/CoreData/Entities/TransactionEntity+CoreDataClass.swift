//
//  TransactionEntity+CoreDataClass.swift
//  Tenra
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData

public typealias TransactionEntityCoreDataClassSet = NSSet


public class TransactionEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension TransactionEntity {
    /// Convert to domain model
    func toTransaction() -> Transaction {
        // Prefer stored String columns (survive entity deletion / relationship faults),
        // fall back to relationship traversal for pre-migration rows where the column is nil.
        let resolvedAccountId = accountId ?? account?.id
        let resolvedTargetAccountId = targetAccountId ?? targetAccount?.id
        // recurringSeriesId: stored String (v4+) survives RecurringSeriesEntity deletion;
        // relationship fallback handles pre-v4 rows that still have the entity intact.
        let resolvedRecurringSeriesId = recurringSeriesId ?? recurringSeries?.id

        let tx = Transaction(
            id: id ?? "",
            date: Self.storedDay(dateSectionKey) ?? DateFormatters.dateFormatter.string(from: date ?? Date()),
            description: descriptionText ?? "",
            amount: amount,
            currency: currency ?? "KZT",
            convertedAmount: convertedAmount == 0 ? nil : convertedAmount,
            type: TransactionType(rawValue: type ?? "expense") ?? .expense,
            category: category ?? "",
            subcategory: subcategory,
            accountId: resolvedAccountId,
            targetAccountId: resolvedTargetAccountId,
            accountName: accountName ?? account?.name,
            targetAccountName: targetAccountName ?? targetAccount?.name,
            targetCurrency: targetCurrency ?? targetAccount?.currency,
            targetAmount: targetAmount == 0 ? nil : targetAmount,
            recurringSeriesId: resolvedRecurringSeriesId,
            recurringOccurrenceId: nil,
            createdAt: createdAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        )
        return tx
    }
    
    /// The day the transaction was saved under: `dateSectionKey`, "yyyy-MM-dd" in the time
    /// zone of the write that set `date`. `date` itself is that day's local midnight as an
    /// instant, so formatting it in the CURRENT zone moved every transaction a day earlier
    /// after travelling west (Almaty midnight is 21:00 the day before in Istanbul), and any
    /// re-save made the shift permanent. nil for a missing or malformed key (rows from
    /// before the v3 backfill): the caller then formats `date` as before.
    nonisolated static func storedDay(_ key: String?) -> String? {
        guard let key, key != "0000-00-00", FastDateParser.date(from: key) != nil else { return nil }
        return key
    }

    /// Create from domain model
    nonisolated static func from(_ transaction: Transaction, context: NSManagedObjectContext) -> TransactionEntity {
        let entity = TransactionEntity(context: context)
        entity.id = transaction.id
        entity.date = DateFormatters.dateFormatter.date(from: transaction.date) ?? Date()
        entity.descriptionText = transaction.description
        entity.amount = transaction.amount
        entity.currency = transaction.currency
        entity.convertedAmount = transaction.convertedAmount ?? 0
        entity.type = transaction.type.rawValue
        entity.category = transaction.category
        entity.subcategory = transaction.subcategory
        entity.targetAmount = transaction.targetAmount ?? 0
        entity.targetCurrency = transaction.targetCurrency
        entity.createdAt = Date(timeIntervalSince1970: transaction.createdAt)
        entity.accountName = transaction.accountName
        entity.targetAccountName = transaction.targetAccountName
        // Store ID strings so they survive entity deletion / relationship faults (same pattern as accountId)
        entity.accountId = transaction.accountId
        entity.targetAccountId = transaction.targetAccountId
        entity.recurringSeriesId = transaction.recurringSeriesId
        // Relationships will be set separately by finding AccountEntity and RecurringSeriesEntity
        return entity
    }
}
