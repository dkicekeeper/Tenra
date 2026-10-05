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

    @Test("An inferred account is NOT recorded as a learned preference")
    func inferredAccountIsNotLearned() async throws {
        // Otherwise confirming a guess teaches the store that guess. Since the
        // learning store outranks history-based ranking, two confirmations lock
        // the original guess in permanently: a self-reinforcing loop that ends
        // with every transaction landing on whatever account was picked first.
        let harness = IntentTestHarness()
        var draft = makeDraft()
        draft.warnings = [.accountInferred]

        _ = try await TransactionDraftService.commit(
            draft,
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        #expect(harness.learningCalls.isEmpty)
    }

    @Test("An explicitly chosen account is still recorded")
    func chosenAccountIsLearned() async throws {
        let harness = IntentTestHarness()
        var draft = makeDraft()
        draft.warnings = [.categorySubstituted(original: "x")]

        _ = try await TransactionDraftService.commit(
            draft,
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        #expect(harness.learningCalls.count == 1)
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

    @Test("Before the full load, subcategories are linked without the in-memory list")
    func subcategoriesBeforeFullLoadBypassMemory() async throws {
        // In a process launched only for an intent the in-memory link list is
        // empty; saving it with the new link would delete every other link.
        let harness = IntentTestHarness()
        #expect(!harness.store.hasCompletedInitialLoad)
        var draft = makeDraft()
        draft.subcategoryIds = ["s-coffee"]

        let saved = try await TransactionDraftService.commit(
            draft,
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        #expect(harness.directLinkCalls.count == 1)
        #expect(harness.directLinkCalls.first?.transactionId == saved.id)
        #expect(harness.directLinkCalls.first?.subcategoryIds == ["s-coffee"])
        #expect(harness.categories.transactionSubcategoryLinks.isEmpty)
        #expect(harness.store.transactionSubcategoryLinks.isEmpty)
    }

    @Test("After the full load, subcategories go through the in-memory links")
    func subcategoriesAfterFullLoadUseMemory() async throws {
        let harness = IntentTestHarness()
        harness.store.hasCompletedInitialLoad = true
        var draft = makeDraft()
        draft.subcategoryIds = ["s-coffee"]

        let saved = try await TransactionDraftService.commit(
            draft,
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        #expect(harness.directLinkCalls.isEmpty)
        #expect(harness.categories.transactionSubcategoryLinks.contains {
            $0.transactionId == saved.id && $0.subcategoryId == "s-coffee"
        })
    }

    @Test("Without subcategories nothing is linked either way")
    func noSubcategoriesNoLinks() async throws {
        let harness = IntentTestHarness()
        _ = try await TransactionDraftService.commit(
            makeDraft(),
            store: harness.store,
            categoriesViewModel: harness.categories,
            hooks: harness.hooks
        )

        #expect(harness.directLinkCalls.isEmpty)
        #expect(harness.categories.transactionSubcategoryLinks.isEmpty)
    }
}
