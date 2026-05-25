//
//  CategoryAggregateEntity+CoreDataClass.swift
//  Tenra
//
//  Created on 2026
//
//

public import CoreData

public class CategoryAggregateEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension CategoryAggregateEntity {
    /// Convert to domain model
    func toAggregate() -> CategoryAggregate {
        // `expenseAmount` is a v10 additive attribute; legacy rows decode it as 0.
        // Distinguish "never written" (legacy) from a genuine 0 via `expenseAmountSet`:
        // when unset, fall back to `totalAmount` (legacy expense-category buckets are
        // overwhelmingly expense), which `CategoryAggregate.init` does for a nil.
        return CategoryAggregate(
            categoryName: categoryName ?? "",
            subcategoryName: subcategoryName,
            year: year,
            month: month,
            day: day,
            totalAmount: totalAmount,
            expenseAmount: expenseAmountSet ? expenseAmount : nil,
            transactionCount: transactionCount,
            currency: currency ?? "KZT",
            lastUpdated: lastUpdated ?? Date(),
            lastTransactionDate: lastTransactionDate
        )
    }

    /// Create from domain model
    nonisolated static func from(_ aggregate: CategoryAggregate, context: NSManagedObjectContext) -> CategoryAggregateEntity {
        let entity = CategoryAggregateEntity(context: context)
        entity.id = aggregate.id
        entity.categoryName = aggregate.categoryName
        entity.subcategoryName = aggregate.subcategoryName
        entity.year = aggregate.year
        entity.month = aggregate.month
        entity.day = aggregate.day
        entity.totalAmount = aggregate.totalAmount
        entity.expenseAmount = aggregate.expenseAmount
        entity.expenseAmountSet = true
        entity.transactionCount = aggregate.transactionCount
        entity.currency = aggregate.currency
        entity.lastUpdated = aggregate.lastUpdated
        entity.lastTransactionDate = aggregate.lastTransactionDate
        return entity
    }
}
