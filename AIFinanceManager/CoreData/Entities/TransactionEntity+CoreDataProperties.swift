//
//  TransactionEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData


public typealias TransactionEntityCoreDataPropertiesSet = NSSet

extension TransactionEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TransactionEntity> {
        return NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
    }

    /// Stored "YYYY-MM-DD" key used by NSFetchedResultsController for SQL-level section grouping.
    /// Set automatically via willSave() in TransactionEntity+SectionKey.swift.
    @NSManaged nonisolated public var dateSectionKey: String?
    @NSManaged nonisolated public var accountId: String?
    @NSManaged nonisolated public var amount: Double
    @NSManaged nonisolated public var category: String?
    @NSManaged nonisolated public var convertedAmount: Double
    @NSManaged nonisolated public var createdAt: Date?
    @NSManaged nonisolated public var currency: String?
    @NSManaged nonisolated public var date: Date?
    @NSManaged nonisolated public var descriptionText: String?
    @NSManaged nonisolated public var id: String?
    /// Stored series ID string — survives RecurringSeriesEntity deletion (mirrors accountId pattern).
    @NSManaged nonisolated public var recurringSeriesId: String?
    @NSManaged nonisolated public var subcategory: String?
    @NSManaged nonisolated public var targetAccountId: String?
    @NSManaged nonisolated public var targetAmount: Double
    @NSManaged nonisolated public var targetCurrency: String?
    @NSManaged nonisolated public var type: String?
    @NSManaged nonisolated public var accountName: String?
    @NSManaged nonisolated public var targetAccountName: String?
    @NSManaged nonisolated public var account: AccountEntity?
    @NSManaged nonisolated public var recurringSeries: RecurringSeriesEntity?
    @NSManaged nonisolated public var targetAccount: AccountEntity?

}

extension TransactionEntity : Identifiable {

}
