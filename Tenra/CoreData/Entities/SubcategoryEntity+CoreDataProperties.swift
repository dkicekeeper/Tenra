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

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var name: String?
    @NSManaged public nonisolated var iconName: String?
    @NSManaged public nonisolated var transactions: NSSet?

}

// MARK: Generated accessors for transactions
extension SubcategoryEntity {

    @objc(addTransactionsObject:)
    @NSManaged public nonisolated func addToTransactions(_ value: SubcategoryEntity)

    @objc(removeTransactionsObject:)
    @NSManaged public nonisolated func removeFromTransactions(_ value: SubcategoryEntity)

    @objc(addTransactions:)
    @NSManaged public nonisolated func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public nonisolated func removeFromTransactions(_ values: NSSet)

}

extension SubcategoryEntity : Identifiable {

}
