//
//  SubcategoryLinkBatchTests.swift
//  TenraTests
//
//  Every link-table write rebuilds the subcategory usage stats over all transactions
//  (`rebuildSubcategoryUsageStats`). The add / edit / subscription flows linked a series'
//  occurrences one transaction at a time, so a back-dated series paid that rebuild once per
//  occurrence. They now link in one batch (`batchLinkSubcategoriesToTransaction`), and the
//  rebuild parses dates with FastDateParser instead of a DateFormatter. These tests pin that
//  the batch leaves the same links and counters as the per-transaction loop, and that the
//  counters match the old DateFormatter computation.
//
//  `.serialized` + `.sharedProcessState`: the add flow touches process-wide UserDefaults
//  (rating counter) like TransactionAddCoordinatorTests.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct SubcategoryLinkBatchTests {

    private static let dates = ["2026-01-05", "2026-02-05", "2026-03-05", "2026-04-05", "2026-05-05"]

    private static func seededGraph() async throws -> TransactionFlowTestGraph {
        let graph = await TransactionFlowTestGraph.make()
        for (index, date) in dates.enumerated() {
            _ = try await graph.store.add(Transaction(
                id: "t\(index)", date: date, description: "Gym", amount: 1000, currency: "KZT",
                type: .expense, category: "Food", accountId: "a1"
            ))
        }
        graph.store.addSubcategory(Subcategory(id: "s1", name: "Membership"))
        graph.store.addSubcategory(Subcategory(id: "s2", name: "Coach"))
        return graph
    }

    private struct Links: Equatable {
        let byTransaction: [String: [String]]
        let usage: [String: Int]
        let lastUsed: [String: Date]
        let rows: Set<String>
    }

    private static func links(_ graph: TransactionFlowTestGraph) -> Links {
        Links(
            byTransaction: graph.store.subcategoryIdsByTransactionId,
            usage: graph.store.subcategoryUsageCountById,
            lastUsed: graph.store.subcategoryLastUsedById,
            rows: Set(graph.store.transactionSubcategoryLinks.map { "\($0.transactionId)>\($0.subcategoryId)" })
        )
    }

    @Test func batchLinkMatchesLinkingOneTransactionAtATime() async throws {
        let perTransaction = try await Self.seededGraph()
        let batch = try await Self.seededGraph()
        let ids = ["t0", "t2", "t3", "t4"]

        for id in ids {
            perTransaction.categories.linkSubcategoriesToTransaction(transactionId: id, subcategoryIds: ["s1", "s2"])
        }
        var map: [String: [String]] = [:]
        for id in ids { map[id] = ["s1", "s2"] }
        batch.categories.batchLinkSubcategoriesToTransaction(map)

        #expect(Self.links(batch) == Self.links(perTransaction))
        #expect(batch.store.subcategoryUsageCountById["s1"] == 4)
        #expect(batch.store.subcategoryLastUsedById["s1"] == DateFormatters.dateFormatter.date(from: "2026-05-05"))
    }

    @Test func usageStatsMatchTheDateFormatterComputation() async throws {
        let graph = try await Self.seededGraph()
        graph.categories.batchLinkSubcategoriesToTransaction([
            "t0": ["s1"], "t1": ["s1", "s2"], "t3": ["s2"]
        ])

        // The computation the rebuild did before FastDateParser.
        var counts: [String: Int] = [:]
        var lastUsed: [String: Date] = [:]
        for tx in graph.store.transactions {
            guard let ids = graph.store.subcategoryIdsByTransactionId[tx.id], !ids.isEmpty else { continue }
            let date = DateFormatters.dateFormatter.date(from: tx.date) ?? Date()
            for id in ids {
                counts[id, default: 0] += 1
                if date > (lastUsed[id] ?? .distantPast) { lastUsed[id] = date }
            }
        }

        #expect(graph.store.subcategoryUsageCountById == counts)
        #expect(graph.store.subcategoryLastUsedById == lastUsed)
    }

    @Test func backDatedRecurringSeriesLinksEveryOccurrenceInOneWrite() async throws {
        let graph = await TransactionFlowTestGraph.make()
        graph.store.addSubcategory(Subcategory(id: "s1", name: "Coffee"))
        let add = TransactionAddCoordinator(
            category: "Food",
            type: .expense,
            currency: "KZT",
            transactionsViewModel: graph.transactions,
            categoriesViewModel: graph.categories,
            accountsViewModel: graph.accounts,
            transactionStore: graph.store
        )
        add.formData.amountText = "1500"
        add.formData.accountId = "a1"
        add.formData.subcategoryIds = ["s1"]
        add.formData.recurring = .frequency(.monthly)
        add.formData.selectedDate = Calendar.current.date(byAdding: .month, value: -5, to: Date())!
        let versionBefore = graph.store.subcategoriesMutationVersion

        let result = await add.save()

        #expect(result.isValid)
        let occurrences = graph.store.transactions.filter { $0.recurringSeriesId != nil }
        #expect(occurrences.count >= 6, "five past months, this one and the next")
        for tx in occurrences {
            #expect(graph.store.subcategoryIdsByTransactionId[tx.id] == ["s1"])
        }
        #expect(graph.store.subcategoryUsageCountById["s1"] == occurrences.count)
        // The category link and ONE transaction-link write, not one per occurrence.
        #expect(graph.store.subcategoriesMutationVersion - versionBefore <= 2)
    }
}
