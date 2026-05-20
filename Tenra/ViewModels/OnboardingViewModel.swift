//
//  OnboardingViewModel.swift
//  Tenra
//
//  Ephemeral state and commit pipeline for the first-launch onboarding flow.
//

import Foundation
import SwiftUI
import Observation
import os

/// One step in the data-collection portion of onboarding.
enum OnboardingStep: Hashable {
    case currency
    case account
    case categories
}

/// Draft for the first account being created during onboarding.
struct AccountDraft: Equatable {
    var name: String = ""
    var iconSource: IconSource = .sfSymbol("creditcard.fill")
    var balance: Double = 0
}

@Observable
@MainActor
final class OnboardingViewModel {
    // MARK: - Dependencies

    @ObservationIgnored private weak var coordinator: AppCoordinator?
    @ObservationIgnored private let logger = Logger(subsystem: "Tenra", category: "Onboarding")

    // MARK: - Step state

    var path: [OnboardingStep] = []

    /// Step 1: chosen base currency. Default `KZT` (matches `AppSettings.defaultCurrency`).
    var draftCurrency: String = AppSettings.defaultCurrency

    /// Step 2: account form draft.
    var draftAccount: AccountDraft = AccountDraft()

    /// Step 3: preset list with toggle state. All selected by default.
    var draftCategories: [SelectablePreset] = CategoryPreset.defaultExpense.map {
        $0.makeSelectable(isSelected: true)
    }

    /// True while the final commit pipeline is running (disables the Done button).
    var isFinishing: Bool = false

    // MARK: - Init

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Test-only convenience: builds a VM with no coordinator. The commit pipeline
    /// is a no-op in this mode (just toggles state). All draft logic still works.
    static func makeForTesting() -> OnboardingViewModel {
        OnboardingViewModel()
    }

    private init() {
        self.coordinator = nil
    }

    // MARK: - Derived UI helpers

    var selectedPresetCount: Int {
        draftCategories.lazy.filter { $0.isSelected }.count
    }

    var canAdvanceFromAccountStep: Bool {
        !draftAccount.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canFinish: Bool {
        selectedPresetCount > 0 && !isFinishing
    }

    // MARK: - Step navigation

    func startDataCollection() {
        // NavigationStack root is the welcome screen; push currency as the first data step.
        path = [.currency]
        logger.info("onboarding_started")
    }

    func advanceToAccountStep() async {
        guard let coordinator else { return }
        await coordinator.settingsViewModel.updateBaseCurrency(draftCurrency)
        path.append(.account)
        logger.info("onboarding_step_completed step=currency currency=\(self.draftCurrency, privacy: .public)")
    }

    func advanceToCategoriesStep() async {
        // No persistence here — the account is created in `finish()` so that
        // skipping at any later step creates nothing. We only navigate; the form
        // values live in `draftAccount` and survive back/forward navigation.
        path.append(.categories)
        logger.info("onboarding_step_completed step=account")
    }

    // MARK: - Skip

    /// User tapped the trailing «✕» button. Applies the currently selected
    /// base currency and completes onboarding immediately — no account, no
    /// categories. The user starts on an empty Home and can add everything
    /// later from the main UI.
    func skip() async {
        guard let coordinator, !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }

        await coordinator.settingsViewModel.updateBaseCurrency(draftCurrency)
        coordinator.completeOnboarding()
        logger.info("onboarding_skipped")
    }

    // MARK: - Final commit

    func finish() async {
        guard let coordinator, !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }

        // Account — deferred from Step 2 so that skipping any step creates nothing.
        // Only the final "Done" tap persists the drafted account.
        let trimmedName = draftAccount.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            await coordinator.accountsViewModel.addAccount(
                name: trimmedName,
                initialBalance: draftAccount.balance,
                currency: draftCurrency,
                iconSource: draftAccount.iconSource,
                shouldCalculateFromTransactions: false
            )
        }

        for selectable in draftCategories where selectable.isSelected {
            let preset = selectable.preset
            let category = CustomCategory(
                name: String(localized: String.LocalizationValue(preset.nameKey)),
                iconSource: preset.iconSource,
                colorHex: preset.colorHex,
                type: preset.type
            )
            coordinator.categoriesViewModel.addCategory(category)
        }

        coordinator.completeOnboarding()
        logger.info("onboarding_finished selectedCount=\(self.selectedPresetCount, privacy: .public)")
    }
}
