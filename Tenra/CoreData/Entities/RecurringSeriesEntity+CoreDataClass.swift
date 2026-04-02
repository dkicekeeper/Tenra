//
//  RecurringSeriesEntity+CoreDataClass.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData

public typealias RecurringSeriesEntityCoreDataClassSet = NSSet


public class RecurringSeriesEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension RecurringSeriesEntity {
    /// Convert to domain model
    func toRecurringSeries() -> RecurringSeries {
        let frequency = RecurringFrequency(rawValue: self.frequency ?? "monthly") ?? .monthly
        let kind = RecurringSeriesKind(rawValue: self.kind ?? "generic") ?? .generic
        let status = self.status.flatMap { SubscriptionStatus(rawValue: $0) }

        // Reconstruct iconSource from stored brandLogo/brandId fields.
        // brandId may carry an "sf:" prefix for sfSymbol icons — decode via IconSource.from(displayIdentifier:).
        // Legacy brandId values without a recognised prefix fall back to .brandService.
        let iconSource: IconSource?
        if let brandId = brandId, !brandId.isEmpty {
            iconSource = IconSource.from(displayIdentifier: brandId) ?? .brandService(brandId)
        } else {
            iconSource = nil
        }

        return RecurringSeries(
            id: id ?? UUID().uuidString,
            isActive: isActive,
            amount: amount as? Decimal ?? 0,
            currency: currency ?? "KZT",
            category: category ?? "",
            subcategory: subcategory,
            description: descriptionText ?? "",
            accountId: account?.id,
            targetAccountId: nil, // Not stored in Entity yet
            frequency: frequency,
            startDate: startDate.map { DateFormatters.dateFormatter.string(from: $0) } ?? "",
            lastGeneratedDate: lastGeneratedDate.map { DateFormatters.dateFormatter.string(from: $0) },
            kind: kind,
            iconSource: iconSource,
            reminderOffsets: nil, // Not stored in Entity yet
            status: status
        )
    }

    /// Create from domain model
    nonisolated static func from(_ series: RecurringSeries, context: NSManagedObjectContext) -> RecurringSeriesEntity {
        let entity = RecurringSeriesEntity(context: context)
        entity.id = series.id
        entity.isActive = series.isActive
        entity.amount = NSDecimalNumber(decimal: series.amount)
        entity.currency = series.currency
        entity.category = series.category
        entity.subcategory = series.subcategory
        entity.descriptionText = series.description
        entity.frequency = series.frequency.rawValue
        entity.startDate = DateFormatters.dateFormatter.date(from: series.startDate)
        entity.lastGeneratedDate = series.lastGeneratedDate.flatMap { DateFormatters.dateFormatter.date(from: $0) }
        entity.kind = series.kind.rawValue
        // Persist iconSource to brandLogo/brandId string columns.
        // sfSymbol uses the "sf:<name>" prefix in brandId so the name survives a CoreData round-trip.
        if let iconSource = series.iconSource {
            switch iconSource {
            case .brandService(let brandId):
                entity.brandLogo = nil
                entity.brandId = brandId
            case .sfSymbol(let name):
                entity.brandLogo = nil
                entity.brandId = "sf:\(name)"
            }
        } else {
            entity.brandLogo = nil
            entity.brandId = nil
        }
        entity.status = series.status?.rawValue
        // account relationship will be set separately
        return entity
    }
}
