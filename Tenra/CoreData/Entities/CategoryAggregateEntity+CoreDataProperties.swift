//
//  CategoryAggregateEntity+CoreDataProperties.swift
//  Tenra
//
//  Created on 2026
//
//

public import Foundation
public import CoreData


extension CategoryAggregateEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CategoryAggregateEntity> {
        return NSFetchRequest<CategoryAggregateEntity>(entityName: "CategoryAggregateEntity")
    }

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var categoryName: String?
    @NSManaged public nonisolated var subcategoryName: String?
    @NSManaged public nonisolated var year: Int16
    @NSManaged public nonisolated var month: Int16
    @NSManaged public nonisolated var day: Int16
    @NSManaged public nonisolated var totalAmount: Double
    /// Expense-only total in base currency (v10). Budget "spent" reads this so a
    /// non-expense tx tagged to a budgeted expense category does not inflate it.
    @NSManaged public nonisolated var expenseAmount: Double
    /// True once `expenseAmount` has been written by the v10 code path. Legacy
    /// rows (pre-v10) default to false → `toAggregate()` falls back to totalAmount.
    @NSManaged public nonisolated var expenseAmountSet: Bool
    @NSManaged public nonisolated var transactionCount: Int32
    @NSManaged public nonisolated var currency: String?
    @NSManaged public nonisolated var lastUpdated: Date?
    @NSManaged public nonisolated var lastTransactionDate: Date?
}

extension CategoryAggregateEntity : Identifiable {

}
