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

    @NSManaged nonisolated public var id: String?
    @NSManaged nonisolated public var isActive: Bool
    @NSManaged nonisolated public var amount: NSDecimalNumber?
    @NSManaged nonisolated public var currency: String?
    @NSManaged nonisolated public var category: String?
    @NSManaged nonisolated public var subcategory: String?
    @NSManaged nonisolated public var descriptionText: String?
    @NSManaged nonisolated public var frequency: String?
    @NSManaged nonisolated public var startDate: Date?
    @NSManaged nonisolated public var lastGeneratedDate: Date?
    @NSManaged nonisolated public var kind: String?
    @NSManaged nonisolated public var brandLogo: String?
    @NSManaged nonisolated public var brandId: String?
    @NSManaged nonisolated public var status: String?
    @NSManaged nonisolated public var account: AccountEntity?
    @NSManaged nonisolated public var transactions: NSSet?
    @NSManaged nonisolated public var occurrences: NSSet?

}

// MARK: Generated accessors for transactions
extension RecurringSeriesEntity {

    @objc(addTransactionsObject:)
    @NSManaged nonisolated public func addToTransactions(_ value: TransactionEntity)

    @objc(removeTransactionsObject:)
    @NSManaged nonisolated public func removeFromTransactions(_ value: TransactionEntity)

    @objc(addTransactions:)
    @NSManaged nonisolated public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged nonisolated public func removeFromTransactions(_ values: NSSet)

}

// MARK: Generated accessors for occurrences
extension RecurringSeriesEntity {

    @objc(addOccurrencesObject:)
    @NSManaged nonisolated public func addToOccurrences(_ value: RecurringOccurrenceEntity)

    @objc(removeOccurrencesObject:)
    @NSManaged nonisolated public func removeFromOccurrences(_ value: RecurringOccurrenceEntity)

    @objc(addOccurrences:)
    @NSManaged nonisolated public func addToOccurrences(_ values: NSSet)

    @objc(removeOccurrences:)
    @NSManaged nonisolated public func removeFromOccurrences(_ values: NSSet)

}

extension RecurringSeriesEntity : Identifiable {

}
