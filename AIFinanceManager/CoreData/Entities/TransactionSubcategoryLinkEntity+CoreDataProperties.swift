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

    @NSManaged nonisolated public var id: String?
    @NSManaged nonisolated public var transactionId: String?
    @NSManaged nonisolated public var subcategoryId: String?

}

extension TransactionSubcategoryLinkEntity : Identifiable {

}
