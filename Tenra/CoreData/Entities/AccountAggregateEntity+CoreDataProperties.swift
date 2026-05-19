//
//  AccountAggregateEntity+CoreDataProperties.swift
//  Tenra
//
//  Properties for AccountAggregateEntity (Schema v9+).
//

public import Foundation
public import CoreData

extension AccountAggregateEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AccountAggregateEntity> {
        return NSFetchRequest<AccountAggregateEntity>(entityName: "AccountAggregateEntity")
    }

    @NSManaged public nonisolated var accountId: String?
    @NSManaged public nonisolated var currency: String?
    @NSManaged public nonisolated var lastUpdated: Date?
    @NSManaged public nonisolated var totalExpense: Double
    @NSManaged public nonisolated var totalIncome: Double
    @NSManaged public nonisolated var totalTransactions: Int32
}

extension AccountAggregateEntity: Identifiable {
}
