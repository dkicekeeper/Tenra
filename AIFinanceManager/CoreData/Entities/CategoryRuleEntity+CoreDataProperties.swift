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

    @NSManaged nonisolated public var id: String?
    @NSManaged nonisolated public var pattern: String?
    @NSManaged nonisolated public var category: String?
    @NSManaged nonisolated public var isEnabled: Bool

}

extension CategoryRuleEntity : Identifiable {

}
