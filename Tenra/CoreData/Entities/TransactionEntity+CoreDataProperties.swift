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
    @NSManaged public nonisolated var dateSectionKey: String?
    @NSManaged public nonisolated var accountId: String?
    @NSManaged public nonisolated var amount: Double
    @NSManaged public nonisolated var category: String?
    @NSManaged public nonisolated var convertedAmount: Double
    @NSManaged public nonisolated var createdAt: Date?
    @NSManaged public nonisolated var currency: String?
    @NSManaged public nonisolated var date: Date?
    @NSManaged public nonisolated var descriptionText: String?
    @NSManaged public nonisolated var id: String?
    /// Stored series ID string — survives RecurringSeriesEntity deletion (mirrors accountId pattern).
    @NSManaged public nonisolated var recurringSeriesId: String?
    @NSManaged public nonisolated var subcategory: String?
    @NSManaged public nonisolated var targetAccountId: String?
    @NSManaged public nonisolated var targetAmount: Double
    @NSManaged public nonisolated var targetCurrency: String?
    @NSManaged public nonisolated var type: String?
    @NSManaged public nonisolated var accountName: String?
    @NSManaged public nonisolated var targetAccountName: String?
    @NSManaged public nonisolated var account: AccountEntity?
    @NSManaged public nonisolated var recurringSeries: RecurringSeriesEntity?
    @NSManaged public nonisolated var targetAccount: AccountEntity?

}

extension TransactionEntity : Identifiable {

}
