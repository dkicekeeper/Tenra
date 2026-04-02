//
//  CategoryRuleEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData


public typealias CategoryRuleEntityCoreDataPropertiesSet = NSSet

extension CategoryRuleEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CategoryRuleEntity> {
        return NSFetchRequest<CategoryRuleEntity>(entityName: "CategoryRuleEntity")
    }

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var pattern: String?
    @NSManaged public nonisolated var category: String?
    @NSManaged public nonisolated var isEnabled: Bool

}

extension CategoryRuleEntity : Identifiable {

}
