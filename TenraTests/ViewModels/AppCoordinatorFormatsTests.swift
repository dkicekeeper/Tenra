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
        // The add's debounced sync invalidates the insights: let it run now, not in the middle
        // of the test (under a full run's load it landed after the format change's pass).
        await coordinator.transactionStore.waitForPendingSync()
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

    /// Separator options that each change what the host's region writes, in the order Settings ›
    /// Formats lists them, with the marks each one writes. The Simulator's region varies (CI runs
    /// en_US, where commaDot is the region's own and choosing it changes nothing).
    private func separatorsOtherThanTheRegion(
        _ settings: FormatSettings
    ) -> [(option: AmountSeparators, grouping: String, decimal: String)] {
        var seen = [settings.resolved]
        var picked: [(option: AmountSeparators, grouping: String, decimal: String)] = []
        for option in FormatPreferences.separatorOptions(region: settings.resolved) where option != .region {
            var choices = settings.choices
            choices.separators = option
            let resolved = FormatPreferences.resolve(choices, locale: settings.regionLocale)
            guard !seen.contains(where: { FormatPreferences.isEquivalent($0, resolved) }) else { continue }
            seen.append(resolved)
            picked.append((option, resolved.groupingSeparator, resolved.decimalSeparator))
        }
        return picked
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

    /// A second change while a pass started after the first one runs: that pass carries the
    /// first change's text, so the boundary moves and only the pass after it rewrites (were the
    /// first change to win, the running pass would take it).
    @Test func aChangeDuringAPassMovesTheRewriteToTheNextPass() async throws {
        try await withCoordinator({ try await makeCoordinatorWithAnExpense(500) }) { coordinator in
            let insights = coordinator.insightsViewModel
            let before = insights.computeGeneration

            coordinator.formatSettings.set { $0.date = .iso }
            // A pass starts in the first change's formats (Analytics on screen, say)...
            insights.refreshInsights()
            let running = insights.computeGeneration
            #expect(running == before + 1)
            // ...and the formats change again while it runs.
            coordinator.formatSettings.set { $0.date = .dots }

            #expect(!insights.takesPendingSignalRewrite(generation: running))
            #expect(insights.takesPendingSignalRewrite(generation: running + 1))
        }
    }

    /// A mutation's sync (TransactionStore's debounced `syncTransactionStoreToViewModels`) wipes
    /// the insights; `waitForPendingSync` returns only once it has run, so a test that adds data
    /// and then computes insights is never wiped afterwards by its own setup (the flake of
    /// 2026-11-05: the sync landed after the format change's pass under a full run's load).
    @Test func waitingForThePendingSyncLetsItRunFirst() async throws {
        try await withCoordinator({ try await makeCoordinatorWithAnExpense(700) }) { coordinator in
            let insights = coordinator.insightsViewModel
            await insights.refreshInsightsAndWait()
            #expect(insights.precomputedInsight(id: "top_spending", granularity: .month) != nil)

            let account = try #require(coordinator.accountsViewModel.accounts.first)
            _ = try await coordinator.transactionStore.add(Transaction(
                id: "", date: FastDateParser.string(from: Date()), description: "Dinner",
                amount: 300, currency: "KZT", type: .expense, category: "Food", accountId: account.id
            ))
            await coordinator.transactionStore.waitForPendingSync()
            #expect(insights.precomputedInsight(id: "top_spending", granularity: .month) == nil)
            #expect(insights.isStale)
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
            let other = try #require(separatorsOtherThanTheRegion(coordinator.formatSettings).first)

            coordinator.formatSettings.set { $0.separators = other.option }
            await coordinator.waitUntilFormatsRefreshIdle()

            #expect(coordinator.insightsViewModel.hasComputed)
        }
    }

    /// Insight text is written when a pass computes it, so a format change recomputes: after a
    /// separators change the top category's value carries the new marks.
    @Test func formatChangeRewritesTheTopCategoryValue() async throws {
        try await withCoordinator({ try await makeCoordinatorWithAnExpense(1_234.5) }) { coordinator in
            let insights = coordinator.insightsViewModel
            let options = separatorsOtherThanTheRegion(coordinator.formatSettings)
            try #require(options.count >= 2)
            let (first, second) = (options[0], options[1])
            coordinator.formatSettings.set { $0.separators = first.option }
            await coordinator.waitUntilFormatsRefreshIdle()
            let before = try #require(insights.precomputedInsight(id: "top_spending", granularity: .month))
            let firstText = "1" + first.grouping + "234" + first.decimal + "5"
            #expect(before.metric.formattedValue.contains(firstText), "\(before.metric.formattedValue)")

            coordinator.formatSettings.set { $0.separators = second.option }
            await coordinator.waitUntilFormatsRefreshIdle()

            let after = try #require(insights.precomputedInsight(id: "top_spending", granularity: .month))
            let secondText = "1" + second.grouping + "234" + second.decimal + "5"
            #expect(after.metric.formattedValue.contains(secondText), "\(after.metric.formattedValue)")
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
