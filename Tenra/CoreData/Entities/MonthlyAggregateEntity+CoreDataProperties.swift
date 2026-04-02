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
    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var year: Int16
    @NSManaged public nonisolated var month: Int16
    @NSManaged public nonisolated var currency: String?
    @NSManaged public nonisolated var totalIncome: Double
    @NSManaged public nonisolated var totalExpenses: Double
    @NSManaged public nonisolated var netFlow: Double
    @NSManaged public nonisolated var transactionCount: Int32
    @NSManaged public nonisolated var lastUpdated: Date?
}

extension MonthlyAggregateEntity: Identifiable {

}
