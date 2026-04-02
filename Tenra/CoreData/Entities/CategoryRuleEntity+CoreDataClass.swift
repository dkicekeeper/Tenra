//
//  CategoryRuleEntity+CoreDataClass.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData

public typealias CategoryRuleEntityCoreDataClassSet = NSSet


public class CategoryRuleEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension CategoryRuleEntity {
    /// Convert to domain model
    func toCategoryRule() -> CategoryRule {
        return CategoryRule(
            description: pattern ?? "",
            category: category ?? "",
            subcategory: nil
        )
    }
    
    /// Create from domain model
    nonisolated static func from(_ rule: CategoryRule, context: NSManagedObjectContext) -> CategoryRuleEntity {
        let entity = CategoryRuleEntity(context: context)
        // Generate ID from pattern hash for uniqueness
        entity.id = "\(rule.description)_\(rule.category)".hash.description
        entity.pattern = rule.description
        entity.category = rule.category
        entity.isEnabled = true
        return entity
    }
}
