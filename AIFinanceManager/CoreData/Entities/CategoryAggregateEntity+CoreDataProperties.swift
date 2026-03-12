//
//  CategoryAggregateEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created on 2026
//
//

public import Foundation
public import CoreData


extension CategoryAggregateEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CategoryAggregateEntity> {
        return NSFetchRequest<CategoryAggregateEntity>(entityName: "CategoryAggregateEntity")
    }

    @NSManaged nonisolated public var id: String?
    @NSManaged nonisolated public var categoryName: String?
    @NSManaged nonisolated public var subcategoryName: String?
    @NSManaged nonisolated public var year: Int16
    @NSManaged nonisolated public var month: Int16
    @NSManaged nonisolated public var day: Int16
    @NSManaged nonisolated public var totalAmount: Double
    @NSManaged nonisolated public var transactionCount: Int32
    @NSManaged nonisolated public var currency: String?
    @NSManaged nonisolated public var lastUpdated: Date?
    @NSManaged nonisolated public var lastTransactionDate: Date?
}

extension CategoryAggregateEntity : Identifiable {

}
