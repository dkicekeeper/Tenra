//
//  TransactionSubcategoryLinkEntity+CoreDataClass.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData

public typealias TransactionSubcategoryLinkEntityCoreDataClassSet = NSSet


public class TransactionSubcategoryLinkEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension TransactionSubcategoryLinkEntity {
    /// Convert to domain model
    func toTransactionSubcategoryLink() -> TransactionSubcategoryLink {
        return TransactionSubcategoryLink(
            id: id ?? UUID().uuidString,
            transactionId: transactionId ?? "",
            subcategoryId: subcategoryId ?? ""
        )
    }
    
    /// Create from domain model
    nonisolated static func from(_ link: TransactionSubcategoryLink, context: NSManagedObjectContext) -> TransactionSubcategoryLinkEntity {
        let entity = TransactionSubcategoryLinkEntity(context: context)
        entity.id = link.id
        entity.transactionId = link.transactionId
        entity.subcategoryId = link.subcategoryId
        return entity
    }
}
