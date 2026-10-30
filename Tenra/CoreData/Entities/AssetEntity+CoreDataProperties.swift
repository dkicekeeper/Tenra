//
//  AssetEntity+CoreDataProperties.swift
//  Tenra
//

public import Foundation
public import CoreData

extension AssetEntity {

    @nonobjc public nonisolated class func fetchRequest() -> NSFetchRequest<AssetEntity> {
        return NSFetchRequest<AssetEntity>(entityName: "AssetEntity")
    }

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var name: String?
    @NSManaged public nonisolated var kind: String?  // AssetKind raw value
    @NSManaged public nonisolated var iconSourceData: Data?  // Stores IconSource as JSON
    @NSManaged public nonisolated var currency: String?
    @NSManaged public nonisolated var purchaseDate: Date?
    @NSManaged public nonisolated var purchasePrice: NSNumber?  // Double; nil when unknown
    @NSManaged public nonisolated var valuations: Data?  // [AssetValuation] as JSON
    @NSManaged public nonisolated var depreciationPerYear: NSNumber?  // Double; nil keeps the last valuation
    @NSManaged public nonisolated var ownershipShare: Double
    @NSManaged public nonisolated var linkedLoanAccountId: String?
    @NSManaged public nonisolated var incomeLinkData: Data?  // AssetCategoryLink as JSON
    @NSManaged public nonisolated var expenseLinkData: Data?  // AssetCategoryLink as JSON
    @NSManaged public nonisolated var includeInNetWorth: Bool
    @NSManaged public nonisolated var soldAt: Date?
    @NSManaged public nonisolated var note: String?
    @NSManaged public nonisolated var order: Int32
    @NSManaged public nonisolated var createdAt: Date?

}

extension AssetEntity : Identifiable {

}
