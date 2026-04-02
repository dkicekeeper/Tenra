//
//  TransactionSubcategoryLinkEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData


public typealias TransactionSubcategoryLinkEntityCoreDataPropertiesSet = NSSet

extension TransactionSubcategoryLinkEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TransactionSubcategoryLinkEntity> {
        return NSFetchRequest<TransactionSubcategoryLinkEntity>(entityName: "TransactionSubcategoryLinkEntity")
    }

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var transactionId: String?
    @NSManaged public nonisolated var subcategoryId: String?

}

extension TransactionSubcategoryLinkEntity : Identifiable {

}
