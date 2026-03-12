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

    @NSManaged nonisolated public var id: String?
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var type: String?
    @NSManaged nonisolated public var iconName: String?
    @NSManaged nonisolated public var colorHex: String?
    @NSManaged nonisolated public var budgetAmount: Double
    @NSManaged nonisolated public var budgetPeriod: String?
    @NSManaged nonisolated public var budgetStartDate: Date?
    @NSManaged nonisolated public var budgetResetDay: Int64
    @NSManaged nonisolated public var transactions: NSSet?

    // MARK: - Phase 22: Budget Spending Cache
    /// Cached total spent in the current budget period (base currency).
    /// Invalidated whenever a transaction in this category changes.
    @NSManaged nonisolated public var cachedSpentAmount: Double
    @NSManaged nonisolated public var cachedSpentUpdatedAt: Date?
    @NSManaged nonisolated public var cachedSpentCurrency: String?

}

// MARK: Generated accessors for transactions
extension CustomCategoryEntity {

    @objc(addTransactionsObject:)
    @NSManaged nonisolated public func addToTransactions(_ value: CustomCategoryEntity)

    @objc(removeTransactionsObject:)
    @NSManaged nonisolated public func removeFromTransactions(_ value: CustomCategoryEntity)

    @objc(addTransactions:)
    @NSManaged nonisolated public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged nonisolated public func removeFromTransactions(_ values: NSSet)

}

extension CustomCategoryEntity : Identifiable {

}
