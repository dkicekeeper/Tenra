//
//  RecurringOccurrenceEntity+CoreDataClass.swift
//  AIFinanceManager
//
//  Created on 2026
//

import Foundation
import CoreData

@objc(RecurringOccurrenceEntity)
public class RecurringOccurrenceEntity: NSManagedObject {

    /// Convert Core Data entity to domain model
    func toRecurringOccurrence() -> RecurringOccurrence {
        return RecurringOccurrence(
            id: self.id ?? UUID().uuidString,
            seriesId: self.seriesId ?? "",
            occurrenceDate: self.occurrenceDate ?? "",
            transactionId: self.transactionId ?? ""
        )
    }

    /// Create entity from domain model
    nonisolated static func from(_ occurrence: RecurringOccurrence, context: NSManagedObjectContext) -> RecurringOccurrenceEntity {
        let entity = RecurringOccurrenceEntity(context: context)
        entity.id = occurrence.id
        entity.seriesId = occurrence.seriesId
        entity.occurrenceDate = occurrence.occurrenceDate
        entity.transactionId = occurrence.transactionId
        return entity
    }
}
