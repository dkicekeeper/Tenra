//
//  SubcategoryEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData


public typealias SubcategoryEntityCoreDataPropertiesSet = NSSet

extension SubcategoryEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SubcategoryEntity> {
        return NSFetchRequest<SubcategoryEntity>(entityName: "SubcategoryEntity")
    }

    @NSManaged nonisolated public var id: String?
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var iconName: String?
    @NSManaged nonisolated public var transactions: NSSet?

}

// MARK: Generated accessors for transactions
extension SubcategoryEntity {

    @objc(addTransactionsObject:)
    @NSManaged nonisolated public func addToTransactions(_ value: SubcategoryEntity)

    @objc(removeTransactionsObject:)
    @NSManaged nonisolated public func removeFromTransactions(_ value: SubcategoryEntity)

    @objc(addTransactions:)
    @NSManaged nonisolated public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged nonisolated public func removeFromTransactions(_ values: NSSet)

}

extension SubcategoryEntity : Identifiable {

}
