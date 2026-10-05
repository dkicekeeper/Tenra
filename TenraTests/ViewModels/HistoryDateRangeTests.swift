//
//  HistoryDateRangeTests.swift
//  TenraTests
//
//  `TimeFilter` ranges are half-open `[start, end)`: `.lastMonth` on 5 Oct is
//  [1 Sep, 1 Oct). History built its CoreData predicate as `date <= end`, and a
//  stored date is local midnight, so every transaction dated the 1st of the next
//  period showed up as an extra "1 Oct" section. Pins the History fetch (the real
//  FRC over an in-memory store) and the custom-range normalisation.
//

import Testing
import Foundation
import CoreData
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct HistoryDateRangeTests {

    private let calendar = Calendar.current

    // MARK: - Fixture

    private func makeStack() throws -> CoreDataStack {
        let container = NSPersistentContainer(name: "Tenra")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        desc.url = URL(string: "memory://\(UUID().uuidString)")
        desc.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return CoreDataStack(container: container)
    }

    /// Stores one expense per day, dated the way the repository writes them
    /// ("yyyy-MM-dd" parsed to local midnight).
    private func seed(_ days: [Date], in stack: CoreDataStack) throws {
        let ctx = stack.viewContext
        // Resolve the entity from this store's model: the test host app has loaded its
        // own model too, so `TransactionEntity(context:)` can't pick a unique match.
        let description = try #require(NSEntityDescription.entity(forEntityName: "TransactionEntity", in: ctx))
        for day in days {
            let key = TransactionSectionKeyFormatter.string(from: day)
            let entity = TransactionEntity(entity: description, insertInto: ctx)
            entity.id = UUID().uuidString
            entity.date = try #require(DateFormatters.dateFormatter.date(from: key))
            entity.descriptionText = "tx \(key)"
            entity.amount = 10
            entity.currency = "KZT"
            entity.type = TransactionType.expense.rawValue
            entity.category = "Food"
            entity.createdAt = Date()
        }
        try ctx.save()
    }

    /// Section keys History shows for `filter`, resolved exactly like
    /// `HistoryView.applyFiltersToController`.
    private func historySectionKeys(for filter: TimeFilter, in stack: CoreDataStack) -> Set<String> {
        let controller = TransactionPaginationController(stack: stack)
        controller.setup()
        let range = filter.dateRange()
        controller.batchUpdateFilters(dateRange: .some((start: range.start, end: range.end)))
        return Set(controller.sections.map(\.id))
    }

    private func key(_ date: Date) -> String {
        TransactionSectionKeyFormatter.string(from: date)
    }

    private func day(_ offset: Int, from date: Date) throws -> Date {
        try #require(calendar.date(byAdding: .day, value: offset, to: date))
    }

    // MARK: - Presets

    @Test func lastMonthExcludesFirstOfThisMonth() throws {
        let filter = TimeFilter(preset: .lastMonth)
        let firstDay = filter.startDate
        let firstOfThisMonth = filter.endDate
        let lastDay = try day(-1, from: firstOfThisMonth)
        let dayBefore = try day(-1, from: firstDay)

        let stack = try makeStack()
        try seed([dayBefore, firstDay, lastDay, firstOfThisMonth], in: stack)

        let keys = historySectionKeys(for: filter, in: stack)
        #expect(keys == [key(firstDay), key(lastDay)])
        #expect(!keys.contains(key(firstOfThisMonth)))
    }

    @Test func thisMonthExcludesFirstOfNextMonth() throws {
        let filter = TimeFilter(preset: .thisMonth)
        let firstDay = filter.startDate
        let firstOfNextMonth = filter.endDate
        let lastDay = try day(-1, from: firstOfNextMonth)

        let stack = try makeStack()
        // The 1st of next month is a future-dated (planned/recurring) transaction.
        try seed([firstDay, lastDay, firstOfNextMonth], in: stack)

        let keys = historySectionKeys(for: filter, in: stack)
        #expect(keys == [key(firstDay), key(lastDay)])
        #expect(!keys.contains(key(firstOfNextMonth)))
    }

    // MARK: - Custom range

    @Test func customRangeIncludesWholeLastPickedDay() throws {
        let today = calendar.startOfDay(for: Date())
        let firstDay = try day(-10, from: today)
        let lastDay = try day(-3, from: today)
        // DatePicker values keep whatever time of day the binding carried.
        let firstPicked = firstDay.addingTimeInterval(14 * 3600)
        let lastPicked = lastDay.addingTimeInterval(9 * 3600)

        let filter = TimeFilter.customDays(from: firstPicked, through: lastPicked)
        #expect(filter.startDate == firstDay)
        #expect(filter.lastIncludedDay == lastDay)
        #expect(filter.contains(date: lastDay))
        #expect(!filter.contains(date: try day(1, from: lastDay)))

        let stack = try makeStack()
        try seed([try day(-1, from: firstDay), firstDay, lastDay, try day(1, from: lastDay)], in: stack)

        #expect(historySectionKeys(for: filter, in: stack) == [key(firstDay), key(lastDay)])
    }

    @Test func singleDayCustomRange() throws {
        let today = calendar.startOfDay(for: Date())
        let filter = TimeFilter.customDays(from: today, through: today)
        #expect(filter.lastIncludedDay == today)

        let stack = try makeStack()
        try seed([try day(-1, from: today), today, try day(1, from: today)], in: stack)

        #expect(historySectionKeys(for: filter, in: stack) == [key(today)])
    }
}
