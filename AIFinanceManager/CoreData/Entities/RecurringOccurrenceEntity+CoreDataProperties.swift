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

    @NSManaged nonisolated public var id: String?
    @NSManaged nonisolated public var seriesId: String?
    @NSManaged nonisolated public var occurrenceDate: String?
    @NSManaged nonisolated public var transactionId: String?
    @NSManaged nonisolated public var series: RecurringSeriesEntity?

}

extension RecurringOccurrenceEntity : Identifiable {

}
