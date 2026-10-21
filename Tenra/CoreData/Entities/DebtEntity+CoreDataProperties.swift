//
//  DebtEntity+CoreDataProperties.swift
//  Tenra
//

public import Foundation
public import CoreData

extension DebtEntity {

    @nonobjc public nonisolated class func fetchRequest() -> NSFetchRequest<DebtEntity> {
        return NSFetchRequest<DebtEntity>(entityName: "DebtEntity")
    }

    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var direction: String?
    @NSManaged public nonisolated var person: String?
    @NSManaged public nonisolated var amount: Double
    @NSManaged public nonisolated var currency: String?
    @NSManaged public nonisolated var date: Date?
    @NSManaged public nonisolated var dueDate: Date?
    @NSManaged public nonisolated var note: String?
    @NSManaged public nonisolated var repayments: Data?  // [DebtRepayment] as JSON
    @NSManaged public nonisolated var settledAt: Date?
    /// The person's own place in the list (v16); nil keeps the list's default order.
    @NSManaged public nonisolated var order: NSNumber?

}

extension DebtEntity : Identifiable {

}
