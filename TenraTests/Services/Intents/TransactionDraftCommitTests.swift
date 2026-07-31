//
//  TransactionDraftCommitTests.swift
//  TenraTests
//
//  Pins the side effects the manual add path performs, so an intent-created
//  transaction is indistinguishable from a hand-entered one. The rating counter
//  matters in particular: it lives in TransactionsViewModel.addTransaction,
//  which intents bypass entirely.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TransactionDraftCommitTests {

    private func makeDraft(accountId: String = "a1") -> TransactionDraft {
        TransactionDraft(
            type: .expense,
            amount: 3000,
            currency: "KZT",
            convertedAmount: nil,
            categoryName: "Food",
            subcategoryIds: [],
            accountId: accountId,
            date: Date(),
            note: "coffee",
            warnings: []
        )
    }

    @Test("Commit writes the transaction through the store")
    func commitWritesTransaction() async throws {
        let harness = IntentTestHarness()
        let saved = try await TransactionDraftService.commit(
            makeDraft(),
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        #expect(!saved.id.isEmpty)
        #expect(saved.amount == 3000)
        #expect(saved.category == "Food")
        #expect(saved.accountId == "a1")
    }

    @Test("Commit records the category-to-account pair for learning")
    func commitRecordsLearning() async throws {
        let harness = IntentTestHarness()
        _ = try await TransactionDraftService.commit(
            makeDraft(),
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        #expect(harness.learningCalls.count == 1)
        #expect(harness.learningCalls.first?.category == "Food")
        #expect(harness.learningCalls.first?.accountId == "a1")
    }

    @Test("Commit feeds the rating prompt counter")
    func commitRecordsRating() async throws {
        let harness = IntentTestHarness()
        _ = try await TransactionDraftService.commit(
            makeDraft(),
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        #expect(harness.ratingCallCount == 1)
    }
}
