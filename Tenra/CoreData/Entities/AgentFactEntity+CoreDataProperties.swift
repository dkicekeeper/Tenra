//
//  AgentFactEntity+CoreDataProperties.swift
//  Tenra
//

public import Foundation
public import CoreData

extension AgentFactEntity {

    @nonobjc public nonisolated class func fetchRequest() -> NSFetchRequest<AgentFactEntity> {
        return NSFetchRequest<AgentFactEntity>(entityName: "AgentFactEntity")
    }

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var text: String?
    @NSManaged public nonisolated var createdAt: Date?
    @NSManaged public nonisolated var updatedAt: Date?

}

extension AgentFactEntity : Identifiable {

}
