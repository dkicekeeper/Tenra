//
//  SubcategoryEntity+CoreDataClass.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData

public typealias SubcategoryEntityCoreDataClassSet = NSSet


public class SubcategoryEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension SubcategoryEntity {
    /// Convert to domain model
    func toSubcategory() -> Subcategory {
        return Subcategory(
            id: id ?? UUID().uuidString,
            name: name ?? ""
        )
    }
    
    /// Create from domain model
    nonisolated static func from(_ subcategory: Subcategory, context: NSManagedObjectContext) -> SubcategoryEntity {
        let entity = SubcategoryEntity(context: context)
        entity.id = subcategory.id
        entity.name = subcategory.name
        entity.iconName = ""
        return entity
    }
}
