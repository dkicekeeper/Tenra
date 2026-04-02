//
//  RecurringOccurrenceEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created on 2026
//

import Foundation
import CoreData

extension RecurringOccurrenceEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RecurringOccurrenceEntity> {
        return NSFetchRequest<RecurringOccurrenceEntity>(entityName: "RecurringOccurrenceEntity")
    }

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var seriesId: String?
    @NSManaged public nonisolated var occurrenceDate: String?
    @NSManaged public nonisolated var transactionId: String?
    @NSManaged public nonisolated var series: RecurringSeriesEntity?

}

extension RecurringOccurrenceEntity : Identifiable {

}
