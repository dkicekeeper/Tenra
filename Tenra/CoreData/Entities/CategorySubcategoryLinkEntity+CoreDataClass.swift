//
//  CategorySubcategoryLinkEntity+CoreDataClass.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData

public typealias CategorySubcategoryLinkEntityCoreDataClassSet = NSSet


public class CategorySubcategoryLinkEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension CategorySubcategoryLinkEntity {
    /// Convert to domain model
    func toCategorySubcategoryLink() -> CategorySubcategoryLink {
        return CategorySubcategoryLink(
            id: id ?? UUID().uuidString,
            categoryId: categoryId ?? "",
            subcategoryId: subcategoryId ?? ""
        )
    }
    
    /// Create from domain model
    nonisolated static func from(_ link: CategorySubcategoryLink, context: NSManagedObjectContext) -> CategorySubcategoryLinkEntity {
        let entity = CategorySubcategoryLinkEntity(context: context)
        entity.id = link.id
        entity.categoryId = link.categoryId
        entity.subcategoryId = link.subcategoryId
        return entity
    }
}
