//
//  AgentThreadEntity+CoreDataProperties.swift
//  Tenra
//

public import Foundation
public import CoreData

extension AgentThreadEntity {

    @nonobjc public nonisolated class func fetchRequest() -> NSFetchRequest<AgentThreadEntity> {
        return NSFetchRequest<AgentThreadEntity>(entityName: "AgentThreadEntity")
    }

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var createdAt: Date?
    @NSManaged public nonisolated var updatedAt: Date?
    /// The first question, for a future list of threads.
    @NSManaged public nonisolated var title: String?
    /// `AgentThreadSnapshot.Body` as JSON.
    @NSManaged public nonisolated var payload: Data?

}

extension AgentThreadEntity : Identifiable {

}
