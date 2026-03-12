//
//  MonthlyAggregateEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Phase 22: Properties for MonthlyAggregateEntity.
//

public import Foundation
public import CoreData

extension MonthlyAggregateEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MonthlyAggregateEntity> {
        return NSFetchRequest<MonthlyAggregateEntity>(entityName: "MonthlyAggregateEntity")
    }

    /// Unique key: "monthly_{year}_{month}_{currency}"
    @NSManaged nonisolated public var id: String?
    @NSManaged nonisolated public var year: Int16
    @NSManaged nonisolated public var month: Int16
    @NSManaged nonisolated public var currency: String?
    @NSManaged nonisolated public var totalIncome: Double
    @NSManaged nonisolated public var totalExpenses: Double
    @NSManaged nonisolated public var netFlow: Double
    @NSManaged nonisolated public var transactionCount: Int32
    @NSManaged nonisolated public var lastUpdated: Date?
}

extension MonthlyAggregateEntity: Identifiable {

}
