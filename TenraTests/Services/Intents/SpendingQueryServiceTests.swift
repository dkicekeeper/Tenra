//
//  SpendingQueryServiceTests.swift
//  TenraTests
//
//  `.serialized` is required: Swift Testing runs tests in parallel by default,
//  and parallel in-memory containers sharing a name can share backing stores.
//  Mirrors TenraTests/CoreDataRoundTripTests.swift:22.
//
//  Dates are built through DateFormatters.dateFormatter (TimeZone.current),
//  exactly as TransactionRepository writes them, so the suite is independent of
//  the machine's time zone.
//

import Testing
import CoreData
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized)
struct SpendingQueryServiceTests {

    // MARK: - Fixtures

    /// Copied from CoreDataRoundTripTests.makeInMemoryContainer (lines 29-42).
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

    /// Mirrors TransactionRepository.swift:474 — the entity stores a real Date
    /// parsed from the canonical "yyyy-MM-dd" key, at local midnight.
    private func seedExpense(
        in context: NSManagedObjectContext,
        amount: Double,
        currency: String,
        dateKey: String
    ) throws {
        let entity = TransactionEntity(context: context)
        entity.id = UUID().uuidString
        entity.date = DateFormatters.dateFormatter.date(from: dateKey)
        entity.amount = amount
        entity.currency = currency
        entity.type = TransactionType.expense.rawValue
        entity.category = "Food"
        entity.accountId = "a1"
        try context.save()
    }

    /// Noon on 2026-07-31 in the current calendar, so period boundaries are
    /// deterministic wherever the suite runs.
    private var now: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 31
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    // MARK: - Tests

    @Test("An empty period totals zero, not nil")
    func emptyPeriod() throws {
        let context = try makeContext()
        let total = try SpendingQueryService.total(
            period: .today,
            baseCurrency: "KZT",
            context: context,
            now: now
        )
        #expect(total.amount == 0)
        #expect(total.transactionCount == 0)
        #expect(total.currency == "KZT")
    }

    @Test("Only expenses inside the period are counted")
    func periodBoundaries() throws {
        let context = try makeContext()
        try seedExpense(in: context, amount: 1000, currency: "KZT", dateKey: "2026-07-31")
        try seedExpense(in: context, amount: 500, currency: "KZT", dateKey: "2026-07-30")

        let today = try SpendingQueryService.total(
            period: .today,
            baseCurrency: "KZT",
            context: context,
            now: now
        )
        #expect(today.amount == 1000)
        #expect(today.transactionCount == 1)

        let month = try SpendingQueryService.total(
            period: .thisMonth,
            baseCurrency: "KZT",
            context: context,
            now: now
        )
        #expect(month.amount == 1500)
        #expect(month.transactionCount == 2)
    }

    @Test("Income is excluded from a spending total")
    func incomeExcluded() throws {
        let context = try makeContext()
        try seedExpense(in: context, amount: 1000, currency: "KZT", dateKey: "2026-07-31")

        let income = TransactionEntity(context: context)
        income.id = UUID().uuidString
        income.date = DateFormatters.dateFormatter.date(from: "2026-07-31")
        income.amount = 900_000
        income.currency = "KZT"
        income.type = TransactionType.income.rawValue
        income.category = "Salary"
        income.accountId = "a1"
        try context.save()

        let total = try SpendingQueryService.total(
            period: .today,
            baseCurrency: "KZT",
            context: context,
            now: now
        )
        #expect(total.amount == 1000)
        #expect(total.transactionCount == 1)
    }

    @Test("Multi-currency totals are expressed in the base currency")
    func multiCurrencyTotal() throws {
        // Guards CLAUDE.md red flag #6: summing Transaction.convertedAmount
        // across currencies produces "$20 + $100 = 120 KZT". This test fails if
        // anyone reintroduces that.
        let store = CurrencyRateStore.shared
        store.clearAll()
        store.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 540.0],
            date: Date(),
            providerName: "test-provider"
        ))
        defer { store.clearAll() }

        let context = try makeContext()
        try seedExpense(in: context, amount: 1000, currency: "KZT", dateKey: "2026-07-31")
        try seedExpense(in: context, amount: 10, currency: "USD", dateKey: "2026-07-31")

        let total = try SpendingQueryService.total(
            period: .today,
            baseCurrency: "KZT",
            context: context,
            now: now
        )
        // 1000 KZT + (10 USD × 540) = 6400 KZT, not 1010.
        #expect(total.amount == 6400)
    }
}
