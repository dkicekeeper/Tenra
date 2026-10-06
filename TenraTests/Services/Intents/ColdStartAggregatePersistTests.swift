//
//  ColdStartAggregatePersistTests.swift
//  TenraTests
//
//  A process launched only for an App Intent (the Wallet automation, Siri) never runs
//  the full load, so its aggregate maps hold just the payment it added. The aggregate
//  saves replace whole tables and the next launch warm-starts from them: persisting
//  that map made every category total, budget "spent" and account total read as one
//  payment. Before the full load a flush must write nothing partial.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct ColdStartAggregatePersistTests {

    private func makeDraft() -> TransactionDraft {
        TransactionDraft(
            type: .expense,
            amount: 3000,
            currency: "KZT",
            convertedAmount: nil,
            categoryName: "Food",
            subcategoryIds: [],
            accountId: "a1",
            date: Date(),
            note: "Coffee House",
            warnings: []
        )
    }

    @Test("Before the full load, a flush writes empty tables, not one payment's buckets")
    func coldProcessPersistsNothingPartial() async throws {
        let harness = IntentTestHarness()
        #expect(!harness.store.hasCompletedInitialLoad)

        _ = try await TransactionDraftService.commit(
            makeDraft(),
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        // The payment is applied in memory...
        #expect(!harness.store.categoryAggregatesByKey.isEmpty)
        // ...but must not become the whole persisted table.
        #expect(harness.store.categoryAggregatesToPersist().isEmpty)
        #expect(harness.store.accountAggregatesToPersist().isEmpty)
    }

    @Test("After the full load, a flush writes the aggregates in memory")
    func loadedStorePersistsEverything() async throws {
        let harness = IntentTestHarness()
        harness.store.hasCompletedInitialLoad = true

        _ = try await TransactionDraftService.commit(
            makeDraft(),
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        let categoryRows = harness.store.categoryAggregatesToPersist()
        #expect(!categoryRows.isEmpty)
        #expect(categoryRows.count == harness.store.categoryAggregatesByKey.count)
        #expect(
            Set(harness.store.accountAggregatesToPersist().keys)
                == Set(harness.store.accountAggregatesByAccountId.keys)
        )
    }
}
