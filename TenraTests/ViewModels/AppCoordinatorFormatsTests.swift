//
//  AppCoordinatorFormatsTests.swift
//  TenraTests
//
//  Settings › Formats wiring (AppCoordinator.formatsDidChange): a change in the coordinator's
//  FormatSettings reaches DesignKit's amounts at once, and the insight signals already
//  scheduled take the text of the first pass that starts after it.
//

import Testing
import Foundation
@testable import Tenra

// `.sharedProcessState`: writes `FormatSettings.snapshot` and `AmountDisplayConfiguration.shared`,
// and restores them. Every test waits for the formats refresh it started (the coalesced rebuild
// writes Ten's inbox, the widget snapshot and the reminders) before it puts them back.
@MainActor
@Suite("AppCoordinator formats", .serialized, .sharedProcessState)
struct AppCoordinatorFormatsTests {

    private func makeCoordinator() -> AppCoordinator {
        let name = "AppCoordinatorFormatsTests.\(UUID().uuidString)"
        let repository = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: name + ".data")!)
        return AppCoordinator(repository: repository, formatDefaults: UserDefaults(suiteName: name)!)
    }

    /// A coordinator with one card and an expense today in "Food" (the top category).
    private func makeCoordinatorWithAnExpense(_ amount: Double) async throws -> AppCoordinator {
        let coordinator = makeCoordinator()
        await coordinator.accountsViewModel.addAccount(name: "Card", initialBalance: 0, currency: "KZT")
        let account = try #require(coordinator.accountsViewModel.accounts.first)
        coordinator.transactionStore.addCategory(
            CustomCategory(id: "food", name: "Food", colorHex: "#22c55e", type: .expense)
        )
        _ = try await coordinator.transactionStore.add(Transaction(
            id: "", date: FastDateParser.string(from: Date()), description: "Lunch",
            amount: amount, currency: "KZT",
            type: .expense, category: "Food", accountId: account.id
        ))
        return coordinator
    }

    /// Runs `body` on the coordinator `make` builds, then waits for the formats refresh it
    /// started and puts the process-wide formats back, whether `body` threw or not.
    private func withCoordinator(
        _ make: () async throws -> AppCoordinator,
        _ body: (AppCoordinator) async throws -> Void
    ) async throws {
        let savedAmounts = AmountDisplayConfiguration.shared
        var coordinator: AppCoordinator?
        var failure: Error?
        do {
            let made = try await make()
            coordinator = made
            try await body(made)
        } catch {
            failure = error
        }
        await coordinator?.waitUntilFormatsRefreshIdle()
        AmountDisplayConfiguration.shared = savedAmounts
        FormatSettings.resetSnapshot()
        if let failure { throw failure }
    }

    private func withCoordinator(_ body: (AppCoordinator) async throws -> Void) async throws {
        try await withCoordinator({ makeCoordinator() }, body)
    }

    @Test func formatChangeReachesDesignKit() async throws {
        try await withCoordinator { coordinator in
            coordinator.formatSettings.set {
                $0.separators = .commaDot
                $0.symbol = .before
                $0.cents = .always
            }

            #expect(Formatting.formatCurrencySmart(1234.5, currency: "USD") == "$1,234.50")
            #expect(Formatting.formatCurrencySmart(1234, currency: "USD") == "$1,234.00")
            #expect(FormatSettings.snapshot == coordinator.formatSettings.resolved)
        }
    }

    /// Only a pass that starts after the change rewrites the signals already scheduled: one
    /// already running computed its text in the old format.
    @Test func onlyAPassStartedAfterTheChangeRewritesPendingSignals() async throws {
        try await withCoordinator { coordinator in
            let insights = coordinator.insightsViewModel
            let running = insights.computeGeneration

            coordinator.formatSettings.set { $0.date = .iso }

            #expect(!insights.takesPendingSignalRewrite(generation: running))
            #expect(insights.takesPendingSignalRewrite(generation: running + 1))
            // Once: the passes after it schedule with their own text anyway.
            #expect(!insights.takesPendingSignalRewrite(generation: running + 2))
        }
    }

    /// A second change while the first one's pass runs: that pass carries the first change's
    /// text, so only the one after it rewrites.
    @Test func aChangeDuringAPassMovesTheRewriteToTheNextPass() async throws {
        try await withCoordinator { coordinator in
            let insights = coordinator.insightsViewModel
            let first = insights.computeGeneration

            coordinator.formatSettings.set { $0.date = .iso }
            coordinator.formatSettings.set { $0.date = .dots }

            #expect(!insights.takesPendingSignalRewrite(generation: first))
            #expect(insights.takesPendingSignalRewrite(generation: first + 1))
        }
    }

    /// The weekly digest and the pending signals are rebuilt by the insights pass, so a format
    /// change recomputes even while Analytics is not on screen (`invalidateAndRecompute` alone
    /// waits for it to appear). The refresh is over once `waitUntilFormatsRefreshIdle` returns.
    @Test func formatChangeRecomputesInsightsWithoutAnalytics() async throws {
        try await withCoordinator { coordinator in
            await coordinator.accountsViewModel.addAccount(name: "Card", initialBalance: 0, currency: "KZT")
            let account = try #require(coordinator.accountsViewModel.accounts.first)
            _ = try await coordinator.transactionStore.add(Transaction(
                id: "", date: "2026-11-02", description: "Salary",
                amount: 1_234.5, currency: "KZT",
                type: .income, category: "", accountId: account.id
            ))
            #expect(!coordinator.insightsViewModel.hasComputed)

            coordinator.formatSettings.set { $0.separators = .commaDot }
            await coordinator.waitUntilFormatsRefreshIdle()

            #expect(coordinator.insightsViewModel.hasComputed)
        }
    }

    /// Insight text is written when a pass computes it, so a format change recomputes: after a
    /// separators change the top category's value carries the new marks.
    @Test func formatChangeRewritesTheTopCategoryValue() async throws {
        try await withCoordinator({ try await makeCoordinatorWithAnExpense(1_234.5) }) { coordinator in
            let insights = coordinator.insightsViewModel
            coordinator.formatSettings.set { $0.separators = .dotComma }
            await coordinator.waitUntilFormatsRefreshIdle()
            let before = try #require(insights.precomputedInsight(id: "top_spending", granularity: .month))
            #expect(before.metric.formattedValue.contains("1.234,5"), "\(before.metric.formattedValue)")

            coordinator.formatSettings.set { $0.separators = .commaDot }
            await coordinator.waitUntilFormatsRefreshIdle()

            let after = try #require(insights.precomputedInsight(id: "top_spending", granularity: .month))
            #expect(after.metric.formattedValue.contains("1,234.5"), "\(after.metric.formattedValue)")
        }
    }

    /// The pass a format change waits for, cancelled by a data change while Analytics is hidden
    /// (`invalidateAndRecompute` then only marks the insights stale and waits for the tab): the
    /// wait asks again, so it still ends with a whole pass, the one that reschedules the weekly
    /// digest and hands the signals their text.
    @Test func waitingForInsightsOutlivesACancelledPass() async throws {
        try await withCoordinator({ try await makeCoordinatorWithAnExpense(500) }) { coordinator in
            let insights = coordinator.insightsViewModel

            let waiting = Task { await insights.refreshInsightsAndWait() }
            var polls = 0
            while !insights.isLoading, polls < 1000 {
                await Task.yield()
                polls += 1
            }
            #expect(insights.isLoading)
            insights.invalidateAndRecompute()
            await waiting.value

            #expect(!insights.isStale)
            // The last write of a whole pass: every granularity, the week the digest is built from.
            #expect(insights.precomputedInsight(id: "top_spending", granularity: .week) != nil)
            #expect(insights.precomputedInsight(id: "top_spending", granularity: .month) != nil)
        }
    }

    @Test func sameChoiceChangesNothing() async throws {
        try await withCoordinator { coordinator in
            let insights = coordinator.insightsViewModel
            let version = coordinator.formatSettings.version

            // The region's own date style, chosen: what the app writes stays the same.
            coordinator.formatSettings.set { $0.date = coordinator.formatSettings.resolved.dateStyle }

            #expect(coordinator.formatSettings.version == version)
            #expect(!insights.takesPendingSignalRewrite(generation: insights.computeGeneration + 1))
        }
    }
}
