//
//  TransactionDayKeyTests.swift
//  TenraTests
//
//  A transaction's day must not depend on the time zone the phone is in now.
//  `date` is stored as the local midnight of the chosen day (an instant), and was
//  read back by formatting it in the current zone: after travelling west every
//  transaction showed a day earlier, and any re-save made that permanent.
//  The day now comes from `dateSectionKey`, written in the zone of the write that
//  set `date`, and a save that does not touch `date` keeps the key.
//
//  `.serialized` + `.sharedProcessState`: in-memory containers named "Tenra".
//

import Testing
import CoreData
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct TransactionDayKeyTests {

    private func makeContext() throws -> NSManagedObjectContext {
        let container = NSPersistentContainer(name: "Tenra")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = URL(string: "memory://\(UUID().uuidString)")
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let error = loadError { throw error }
        return container.viewContext
    }

    private func insert(day: String, in context: NSManagedObjectContext) throws -> TransactionEntity {
        let entity = TransactionEntity(context: context)
        entity.id = UUID().uuidString
        entity.date = DateFormatters.dateFormatter.date(from: day)
        entity.amount = 1000
        entity.currency = "KZT"
        entity.type = TransactionType.expense.rawValue
        entity.category = "Food"
        try context.save()
        return entity
    }

    @Test("Inserting keys the row by its day")
    func insertSetsTheKey() throws {
        let context = try makeContext()
        let entity = try insert(day: "2026-03-10", in: context)

        #expect(entity.dateSectionKey == "2026-03-10")
        #expect(entity.toTransaction().date == "2026-03-10")
    }

    @Test("A save that doesn't change the date keeps the day it was written under")
    func resaveKeepsTheWrittenDay() throws {
        let context = try makeContext()
        let entity = try insert(day: "2026-03-10", in: context)
        // As if the row had been written in a zone east of this one: the same instant is
        // the next calendar day there.
        entity.dateSectionKey = "2026-03-11"
        try context.save()

        entity.amount = 2500
        try context.save()

        #expect(entity.dateSectionKey == "2026-03-11")
        #expect(entity.toTransaction().date == "2026-03-11")
    }

    @Test("Changing the date re-keys the row")
    func dateChangeReKeys() throws {
        let context = try makeContext()
        let entity = try insert(day: "2026-03-10", in: context)

        entity.date = DateFormatters.dateFormatter.date(from: "2026-04-02")
        try context.save()

        #expect(entity.dateSectionKey == "2026-04-02")
        #expect(entity.toTransaction().date == "2026-04-02")
    }

    @Test("Only a well-formed key is used as the day")
    func storedDayValidation() {
        #expect(TransactionEntity.storedDay("2026-10-06") == "2026-10-06")
        #expect(TransactionEntity.storedDay(nil) == nil)
        #expect(TransactionEntity.storedDay("") == nil)
        #expect(TransactionEntity.storedDay("0000-00-00") == nil)
        #expect(TransactionEntity.storedDay("2026-13-01") == nil)
        #expect(TransactionEntity.storedDay("not-a-date") == nil)
    }
}
