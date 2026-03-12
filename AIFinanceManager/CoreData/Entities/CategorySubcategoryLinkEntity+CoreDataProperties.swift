//
//  CategorySubcategoryLinkEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData


public typealias CategorySubcategoryLinkEntityCoreDataPropertiesSet = NSSet

extension CategorySubcategoryLinkEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CategorySubcategoryLinkEntity> {
        return NSFetchRequest<CategorySubcategoryLinkEntity>(entityName: "CategorySubcategoryLinkEntity")
    }

    @NSManaged nonisolated public var id: String?
    @NSManaged nonisolated public var categoryId: String?
    @NSManaged nonisolated public var subcategoryId: String?

}

extension CategorySubcategoryLinkEntity : Identifiable {

}
