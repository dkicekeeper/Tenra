//
//  CustomCategoryEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData


public typealias CustomCategoryEntityCoreDataPropertiesSet = NSSet

extension CustomCategoryEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CustomCategoryEntity> {
        return NSFetchRequest<CustomCategoryEntity>(entityName: "CustomCategoryEntity")
    }

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var name: String?
    @NSManaged public nonisolated var type: String?
    @NSManaged public nonisolated var iconName: String?
    @NSManaged public nonisolated var colorHex: String?
    @NSManaged public nonisolated var budgetAmount: Double
    @NSManaged public nonisolated var budgetPeriod: String?
    @NSManaged public nonisolated var budgetStartDate: Date?
    @NSManaged public nonisolated var budgetResetDay: Int64
    @NSManaged public nonisolated var transactions: NSSet?

    // MARK: - Phase 22: Budget Spending Cache
    /// Cached total spent in the current budget period (base currency).
    /// Invalidated whenever a transaction in this category changes.
    @NSManaged public nonisolated var cachedSpentAmount: Double
    @NSManaged public nonisolated var cachedSpentUpdatedAt: Date?
    @NSManaged public nonisolated var cachedSpentCurrency: String?

}

// MARK: Generated accessors for transactions
extension CustomCategoryEntity {

    @objc(addTransactionsObject:)
    @NSManaged public nonisolated func addToTransactions(_ value: CustomCategoryEntity)

    @objc(removeTransactionsObject:)
    @NSManaged public nonisolated func removeFromTransactions(_ value: CustomCategoryEntity)

    @objc(addTransactions:)
    @NSManaged public nonisolated func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public nonisolated func removeFromTransactions(_ values: NSSet)

}

extension CustomCategoryEntity : Identifiable {

}
