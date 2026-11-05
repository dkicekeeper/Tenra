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
