//
//  SubscriptionCreationServiceTests.swift
//  TenraTests
//
//  Creating a subscription the way its screen does, now shared with the assistant: the series,
//  the subcategory named after it linked to its category and to every generated transaction
//  (red flag 5). A generic recurring payment gets the series alone.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
@Suite(.serialized)
struct SubscriptionCreationServiceTests {

    private static var todayKey: String { DateFormatters.dateFormatter.string(from: Date()) }

    @Test func aSubscriptionGetsItsSeriesAndItsSubcategory() async throws {
        let graph = await TransactionFlowTestGraph.make()
        let series = RecurringSeries(
            amount: 4_990, currency: "KZT", category: "Food", subcategory: "Netflix", description: "Netflix",
            accountId: "a1", frequency: .monthly, startDate: Self.todayKey, kind: .subscription, status: .active
        )

        try await SubscriptionCreationService.create(series, store: graph.store, categoriesViewModel: graph.categories)

        #expect(graph.store.recurringSeries.contains { $0.id == series.id })
        let netflix = try #require(graph.categories.subcategories.first { $0.name == "Netflix" })
        let foodId = try #require(graph.store.categories.first { $0.name == "Food" }?.id)
        #expect(graph.categories.categorySubcategoryLinks.contains { $0.subcategoryId == netflix.id && $0.categoryId == foodId })
        let generated = graph.store.transactionsBySeriesId[series.id] ?? []
        #expect(!generated.isEmpty)
        for transaction in generated {
            #expect(graph.categories.getSubcategoriesForTransaction(transaction.id).contains { $0.id == netflix.id })
        }
    }

    @Test func aRegularPaymentGetsTheSeriesAlone() async throws {
        let graph = await TransactionFlowTestGraph.make()
        let series = RecurringSeries(
            amount: 180_000, currency: "KZT", category: "Food", description: "Аренда",
            accountId: "a1", frequency: .monthly, startDate: Self.todayKey
        )

        try await SubscriptionCreationService.create(series, store: graph.store, categoriesViewModel: graph.categories)

        #expect(graph.store.recurringSeries.contains { $0.id == series.id })
        #expect(graph.categories.subcategories.isEmpty)
    }
}
