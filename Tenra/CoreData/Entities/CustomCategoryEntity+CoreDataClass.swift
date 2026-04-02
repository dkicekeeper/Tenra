//
//  CustomCategoryEntity+CoreDataClass.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData

public typealias CustomCategoryEntityCoreDataClassSet = NSSet


public class CustomCategoryEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension CustomCategoryEntity {
    /// Convert to domain model
    func toCustomCategory() -> CustomCategory {
        let transactionType = TransactionType(rawValue: type ?? "expense") ?? .expense

        // Parse budget period
        let budgetPeriodEnum = CustomCategory.BudgetPeriod(rawValue: budgetPeriod ?? "monthly") ?? .monthly

        // Convert budgetAmount (0.0 means nil)
        let budgetAmountValue = budgetAmount == 0.0 ? nil : budgetAmount

        // Migrate from old iconName field to iconSource
        let iconSource: IconSource
        if let iconName = iconName, !iconName.isEmpty {
            iconSource = .sfSymbol(iconName)
        } else {
            iconSource = .sfSymbol("questionmark.circle")
        }

        return CustomCategory(
            id: id ?? UUID().uuidString,
            name: name ?? "",
            iconSource: iconSource,
            colorHex: colorHex ?? "#000000",
            type: transactionType,
            budgetAmount: budgetAmountValue,
            budgetPeriod: budgetPeriodEnum,
            budgetResetDay: Int(budgetResetDay)
        )
    }

    /// Create from domain model
    nonisolated static func from(_ category: CustomCategory, context: NSManagedObjectContext) -> CustomCategoryEntity {
        let entity = CustomCategoryEntity(context: context)
        entity.id = category.id
        entity.name = category.name
        entity.type = category.type.rawValue
        // Save iconSource as iconName string (backward compatible)
        if case .sfSymbol(let symbolName) = category.iconSource {
            entity.iconName = symbolName
        } else {
            entity.iconName = "questionmark.circle"
        }
        entity.colorHex = category.colorHex

        // Budget fields
        entity.budgetAmount = category.budgetAmount ?? 0.0
        entity.budgetPeriod = category.budgetPeriod.rawValue
        entity.budgetStartDate = category.budgetStartDate
        entity.budgetResetDay = Int64(category.budgetResetDay)

        return entity
    }
}
