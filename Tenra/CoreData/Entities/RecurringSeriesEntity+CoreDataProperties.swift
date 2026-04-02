//
//  RecurringSeriesEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData


public typealias RecurringSeriesEntityCoreDataPropertiesSet = NSSet

extension RecurringSeriesEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RecurringSeriesEntity> {
        return NSFetchRequest<RecurringSeriesEntity>(entityName: "RecurringSeriesEntity")
    }

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var isActive: Bool
    @NSManaged public nonisolated var amount: NSDecimalNumber?
    @NSManaged public nonisolated var currency: String?
    @NSManaged public nonisolated var category: String?
    @NSManaged public nonisolated var subcategory: String?
    @NSManaged public nonisolated var descriptionText: String?
    @NSManaged public nonisolated var frequency: String?
    @NSManaged public nonisolated var startDate: Date?
    @NSManaged public nonisolated var lastGeneratedDate: Date?
    @NSManaged public nonisolated var kind: String?
    @NSManaged public nonisolated var brandLogo: String?
    @NSManaged public nonisolated var brandId: String?
    @NSManaged public nonisolated var status: String?
    @NSManaged public nonisolated var account: AccountEntity?
    @NSManaged public nonisolated var transactions: NSSet?
    @NSManaged public nonisolated var occurrences: NSSet?

}

// MARK: Generated accessors for transactions
extension RecurringSeriesEntity {

    @objc(addTransactionsObject:)
    @NSManaged public nonisolated func addToTransactions(_ value: TransactionEntity)

    @objc(removeTransactionsObject:)
    @NSManaged public nonisolated func removeFromTransactions(_ value: TransactionEntity)

    @objc(addTransactions:)
    @NSManaged public nonisolated func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public nonisolated func removeFromTransactions(_ values: NSSet)

}

// MARK: Generated accessors for occurrences
extension RecurringSeriesEntity {

    @objc(addOccurrencesObject:)
    @NSManaged public nonisolated func addToOccurrences(_ value: RecurringOccurrenceEntity)

    @objc(removeOccurrencesObject:)
    @NSManaged public nonisolated func removeFromOccurrences(_ value: RecurringOccurrenceEntity)

    @objc(addOccurrences:)
    @NSManaged public nonisolated func addToOccurrences(_ values: NSSet)

    @objc(removeOccurrences:)
    @NSManaged public nonisolated func removeFromOccurrences(_ values: NSSet)

}

extension RecurringSeriesEntity : Identifiable {

}
