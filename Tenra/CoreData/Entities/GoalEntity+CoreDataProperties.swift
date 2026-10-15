//
//  GoalEntity+CoreDataProperties.swift
//  Tenra
//

public import Foundation
public import CoreData

extension GoalEntity {

    @nonobjc public nonisolated class func fetchRequest() -> NSFetchRequest<GoalEntity> {
        return NSFetchRequest<GoalEntity>(entityName: "GoalEntity")
    }

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var name: String?
    @NSManaged public nonisolated var iconSourceData: Data?  // Stores IconSource as JSON
    @NSManaged public nonisolated var targetAmount: Double
    @NSManaged public nonisolated var currency: String?
    @NSManaged public nonisolated var deadline: Date?
    @NSManaged public nonisolated var linkedAccountId: String?
    @NSManaged public nonisolated var contributions: Data?  // [GoalContribution] as JSON
    @NSManaged public nonisolated var createdAt: Date?
    @NSManaged public nonisolated var reachedAt: Date?
    @NSManaged public nonisolated var order: Int32

}

extension GoalEntity : Identifiable {

}
