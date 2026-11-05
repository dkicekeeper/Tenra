//
//  AppCoordinatorFormatsTests.swift
//  TenraTests
//
//  Settings › Formats wiring (AppCoordinator.formatsDidChange): a change in the coordinator's
//  FormatSettings reaches DesignKit's amounts at once, and marks the insight signals already
//  scheduled for a rewrite on the next pass.
//

import Testing
import Foundation
@testable import Tenra

// `.sharedProcessState`: writes `FormatSettings.snapshot`, `AmountDisplayConfiguration.shared`
// and `InsightSignalService.shared`, and restores them.
@MainActor
@Suite("AppCoordinator formats", .serialized, .sharedProcessState)
struct AppCoordinatorFormatsTests {

    private func makeCoordinator() -> AppCoordinator {
        let name = "AppCoordinatorFormatsTests.\(UUID().uuidString)"
        let repository = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: name + ".data")!)
        return AppCoordinator(repository: repository, formatDefaults: UserDefaults(suiteName: name)!)
    }

    @Test func formatChangeReachesDesignKit() {
        let saved = AmountDisplayConfiguration.shared
        defer {
            AmountDisplayConfiguration.shared = saved
            FormatSettings.resetSnapshot()
        }
        let coordinator = makeCoordinator()

        coordinator.formatSettings.set {
            $0.separators = .commaDot
            $0.symbol = .before
            $0.cents = .always
        }

        #expect(Formatting.formatCurrencySmart(1234.5, currency: "USD") == "$1,234.50")
        #expect(Formatting.formatCurrencySmart(1234, currency: "USD") == "$1,234.00")
        #expect(FormatSettings.snapshot == coordinator.formatSettings.resolved)
    }

    @Test func formatChangeRewritesPendingSignals() {
        let saved = AmountDisplayConfiguration.shared
        let signals = InsightSignalService.shared
        let savedFlag = signals.rewritesPendingOnNextPass
        defer {
            AmountDisplayConfiguration.shared = saved
            signals.rewritesPendingOnNextPass = savedFlag
            FormatSettings.resetSnapshot()
        }
        signals.rewritesPendingOnNextPass = false
        let coordinator = makeCoordinator()

        coordinator.formatSettings.set { $0.date = .iso }

        #expect(signals.rewritesPendingOnNextPass)
    }

    /// The weekly digest and the pending signals are rebuilt by the insights pass, so a format
    /// change recomputes even while Analytics is not on screen (`invalidateAndRecompute` alone
    /// waits for it to appear).
    @Test func formatChangeRecomputesInsightsWithoutAnalytics() async throws {
        let saved = AmountDisplayConfiguration.shared
        let signals = InsightSignalService.shared
        let savedFlag = signals.rewritesPendingOnNextPass
        defer {
            AmountDisplayConfiguration.shared = saved
            signals.rewritesPendingOnNextPass = savedFlag
            FormatSettings.resetSnapshot()
        }
        let coordinator = makeCoordinator()
        await coordinator.accountsViewModel.addAccount(name: "Card", initialBalance: 0, currency: "KZT")
        let account = try #require(coordinator.accountsViewModel.accounts.first)
        _ = try await coordinator.transactionStore.add(Transaction(
            id: "", date: "2026-11-02", description: "Salary",
            amount: 1_234.5, currency: "KZT",
            type: .income, category: "", accountId: account.id
        ))
        #expect(!coordinator.insightsViewModel.hasComputed)

        coordinator.formatSettings.set { $0.separators = .commaDot }

        for _ in 0..<1000 where !coordinator.insightsViewModel.hasComputed {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.insightsViewModel.hasComputed)
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

    /// Insight text is written when a pass computes it, so a format change recomputes: after a
    /// separators change the top category's value carries the new marks.
    @Test func formatChangeRewritesTheTopCategoryValue() async throws {
        let saved = AmountDisplayConfiguration.shared
        let signals = InsightSignalService.shared
        let savedFlag = signals.rewritesPendingOnNextPass
        defer {
            AmountDisplayConfiguration.shared = saved
            signals.rewritesPendingOnNextPass = savedFlag
            FormatSettings.resetSnapshot()
        }
        let coordinator = try await makeCoordinatorWithAnExpense(1_234.5)
        let insights = coordinator.insightsViewModel
        coordinator.formatSettings.set { $0.separators = .dotComma }
        await insights.refreshInsightsAndWait()
        let before = try #require(insights.precomputedInsight(id: "top_spending", granularity: .month))
        #expect(before.metric.formattedValue.contains("1.234,5"), "\(before.metric.formattedValue)")

        coordinator.formatSettings.set { $0.separators = .commaDot }

        for _ in 0..<1000 where !(insights.precomputedInsight(id: "top_spending", granularity: .month)?.metric.formattedValue.contains("1,234.5") ?? false) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let after = try #require(insights.precomputedInsight(id: "top_spending", granularity: .month))
        #expect(after.metric.formattedValue.contains("1,234.5"), "\(after.metric.formattedValue)")
    }

    /// The pass a format change waits for, cancelled by a data change while Analytics is hidden
    /// (`invalidateAndRecompute` then only marks the insights stale and waits for the tab): the
    /// wait asks again, so it still ends with a whole pass, the one that reschedules the weekly
    /// digest and hands the signals their text.
    @Test func waitingForInsightsOutlivesACancelledPass() async throws {
        let coordinator = try await makeCoordinatorWithAnExpense(500)
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

    @Test func sameChoiceChangesNothing() {
        let saved = AmountDisplayConfiguration.shared
        let signals = InsightSignalService.shared
        let savedFlag = signals.rewritesPendingOnNextPass
        defer {
            AmountDisplayConfiguration.shared = saved
            signals.rewritesPendingOnNextPass = savedFlag
            FormatSettings.resetSnapshot()
        }
        signals.rewritesPendingOnNextPass = false
        let coordinator = makeCoordinator()
        let version = coordinator.formatSettings.version

        // The region's own date style, chosen: what the app writes stays the same.
        coordinator.formatSettings.set { $0.date = coordinator.formatSettings.resolved.dateStyle }

        #expect(coordinator.formatSettings.version == version)
        #expect(!signals.rewritesPendingOnNextPass)
    }
}
