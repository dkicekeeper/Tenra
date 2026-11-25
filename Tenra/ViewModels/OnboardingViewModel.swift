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
    /// What fills Tenra without typing: the Wallet automation, bank notifications, a statement.
    case autoCapture
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
    /// Whether "Start" offers the trial (PremiumManager.onboardingOfferDue); tests pass their own.
    @ObservationIgnored private let offersTrial: @MainActor () -> Bool
    /// The account and categories are saved: a second "Start" saves nothing again.
    @ObservationIgnored private var hasCommitted = false
    /// Onboarding is over: closing the offer twice ends it once.
    @ObservationIgnored private var hasCompleted = false

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

    /// What onboarding opens once it is done, chosen on the auto-capture step.
    enum FollowUp: Hashable {
        /// Ten (or the import tab) with a statement to pick.
        case statement
    }

    /// Step 4: the follow-up picked, if any. One at a time: a second tap clears it.
    var afterFinish: FollowUp?

    /// iCloud Drive holds a backup of Tenra: the welcome screen offers to restore it.
    var hasCloudBackup = false

    /// The backups iCloud Drive holds, newest first, for the restore sheet.
    var cloudBackups: [BackupMetadata] = [] {
        didSet { hasCloudBackup = !cloudBackups.isEmpty }
    }

    /// The list of iCloud backups to restore from, over the welcome screen.
    var showingRestore = false

    /// Tenra Pro's paywall over the last step, after "Start" saved everything (the trial offer,
    /// promotion-plan §2, 2026-11-06). Onboarding ends once it closes (`trialOfferClosed`).
    var showingTrialOffer = false

    /// The step indicator's symbols: Tenra's three data steps and the auto-capture step.
    static let stepSymbols = OnboardingStepIndicator.tenraSymbols + ["wave.3.right"]

    /// Whether the auto-capture step offers bank notifications: iOS 27's notification trigger.
    static var offersBankNotifications: Bool { BankNotificationGuideView.isAvailable }

    // MARK: - Init

    init(
        coordinator: AppCoordinator,
        offersTrial: @escaping @MainActor () -> Bool = { PremiumManager.shared.onboardingOfferDue }
    ) {
        self.coordinator = coordinator
        self.offersTrial = offersTrial
    }

    /// Test-only convenience: builds a VM with no coordinator. The commit pipeline
    /// is a no-op in this mode (just toggles state). All draft logic still works.
    static func makeForTesting() -> OnboardingViewModel {
        OnboardingViewModel()
    }

    private init() {
        self.coordinator = nil
        self.offersTrial = { false }
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

    /// The welcome screen is up: the first step of the funnel (ActivationAttributes.noteOnboardingStep).
    func welcomeShown() {
        ActivationAttributes.noteOnboardingStep(.welcome)
    }

    func startDataCollection() {
        // NavigationStack root is the welcome screen; push currency as the first data step.
        path = [.currency]
        ActivationAttributes.noteOnboardingStep(.currency)
        logger.info("onboarding_started")
    }

    func advanceToAccountStep() async {
        guard let coordinator else { return }
        await coordinator.settingsViewModel.updateBaseCurrency(draftCurrency)
        path.append(.account)
        ActivationAttributes.noteOnboardingStep(.account)
        logger.info("onboarding_step_completed step=currency currency=\(self.draftCurrency, privacy: .public)")
    }

    func advanceToCategoriesStep() async {
        // No persistence here — the account is created in `finish()` so that
        // skipping at any later step creates nothing. We only navigate; the form
        // values live in `draftAccount` and survive back/forward navigation.
        path.append(.categories)
        ActivationAttributes.noteOnboardingStep(.categories)
        logger.info("onboarding_step_completed step=account")
    }

    func advanceToAutoCaptureStep() {
        // The categories stay drafts too: `finish()` on the next step saves everything.
        path.append(.autoCapture)
        ActivationAttributes.noteOnboardingStep(.capture)
        logger.info("onboarding_step_completed step=categories selectedCount=\(self.selectedPresetCount, privacy: .public)")
    }

    /// The backups' view model, for the restore sheet; nil in tests.
    var cloudSyncViewModel: CloudSyncViewModel? { coordinator?.cloudSyncViewModel }

    /// Looks for backups in iCloud Drive while the welcome screen shows (a new phone, a
    /// reinstall). Nothing without an iCloud account or a backup.
    func checkForCloudBackups() async {
        guard let coordinator else { return }
        cloudBackups = await coordinator.cloudSyncViewModel.iCloudBackupsForRestore()
    }

    /// Restores `backup` and ends onboarding on the restored data. On failure the sheet stays
    /// with the error, and onboarding goes on as before.
    func restore(_ backup: BackupMetadata) async {
        guard let coordinator, !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }
        guard await coordinator.cloudSyncViewModel.restoreFromOnboarding(backup) else { return }
        showingRestore = false
        coordinator.completeOnboarding(.restored)
        logger.info("onboarding_restored_backup")
    }

    func toggleAfterFinish(_ followUp: FollowUp) {
        afterFinish = afterFinish == followUp ? nil : followUp
    }

    // MARK: - Skip

    /// User tapped the trailing «✕» button. Applies the currently selected base currency and
    /// ends onboarding at once, on a ready app: the account drafted, or a card with no money in
    /// that currency, and the categories picked (all of them when none is), as "Start" would save
    /// them, without the trial offer. On an empty Home the first expense needed an account and
    /// categories made by hand: after the ✕ 10% recorded one, after "Start" 42% (11-24.11,
    /// docs/promotion-plan.md §6). A person who already has accounts (onboarding run again) gets
    /// no new one.
    func skip() async {
        guard let coordinator, !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }

        await coordinator.settingsViewModel.updateBaseCurrency(draftCurrency)
        if !hasCommitted {
            let hasAccounts = !coordinator.transactionStore.accounts.isEmpty
            let starter = starterData(fallbackAccount: !hasAccounts, allCategoriesIfNone: true)
            await commit(account: hasAccounts ? nil : starter.account, categories: starter.categories, coordinator: coordinator)
        }
        coordinator.completeOnboarding(.skipped)
        adoptICloudBackups(coordinator)
        logger.info("onboarding_skipped")
    }

    /// A new install keeps its backups in iCloud Drive (CloudSyncViewModel.adoptICloudForNewInstall),
    /// off the path to Home.
    private func adoptICloudBackups(_ coordinator: AppCoordinator) {
        Task { await coordinator.cloudSyncViewModel.adoptICloudForNewInstall() }
    }

    // MARK: - Final commit

    func finish() async {
        guard let coordinator, !isFinishing else { return }
        // Saved already, the offer up (or just closed): nothing to save again.
        if hasCommitted {
            if !showingTrialOffer { trialOfferClosed() }
            return
        }
        isFinishing = true
        defer { isFinishing = false }

        // The account is deferred from Step 2: only "Start" (or the ✕, `skip`) saves it.
        let starter = starterData(fallbackAccount: false, allCategoriesIfNone: false)
        await commit(account: starter.account, categories: starter.categories, coordinator: coordinator)

        // Everything is saved first, so a person who leaves on the paywall keeps it all.
        if offersTrial() {
            showingTrialOffer = true
            logger.info("onboarding_trial_offer")
            return
        }
        complete(coordinator)
    }

    /// What onboarding saves: the drafted account (built as AccountsViewModel.addAccount does)
    /// and the picked expense categories, with the income ones the grid does not offer, so the
    /// first income can be recorded at once. `fallbackAccount`: without a name typed, a card with
    /// no money in the chosen currency. `allCategoriesIfNone`: none picked means all of them.
    func starterData(fallbackAccount: Bool, allCategoriesIfNone: Bool) -> (account: Account?, categories: [CustomCategory]) {
        let typed = draftAccount.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typed.isEmpty && fallbackAccount ? String(localized: "onboarding.account.defaultName") : typed
        let account: Account? = name.isEmpty ? nil : Account(
            name: name,
            currency: draftCurrency,
            iconSource: draftAccount.iconSource,
            shouldCalculateFromTransactions: false,
            initialBalance: draftAccount.balance,
            includeInBalance: true
        )
        var picked = draftCategories.filter(\.isSelected).map(\.preset)
        if picked.isEmpty && allCategoriesIfNone { picked = draftCategories.map(\.preset) }
        // An existing category (onboarding run again) is skipped by the store's name + type dedupe.
        let categories = (picked + CategoryPreset.defaultIncome).map { preset in
            CustomCategory(
                name: String(localized: String.LocalizationValue(preset.nameKey)),
                iconSource: preset.iconSource,
                colorHex: preset.colorHex,
                type: preset.type
            )
        }
        return (account, categories)
    }

    /// One synchronous save for everything, finished before Home appears and the first full load
    /// reads CoreData (TransactionStore+Onboarding), then the account's balance.
    private func commit(account: Account?, categories: [CustomCategory], coordinator: AppCoordinator) async {
        do {
            try coordinator.transactionStore.commitOnboarding(account: account, categories: categories)
        } catch {
            logger.error("onboarding_commit_failed error=\(error.localizedDescription, privacy: .public)")
        }
        if let account {
            await coordinator.balanceCoordinator.registerAccounts([account])
            await coordinator.balanceCoordinator.setInitialBalance(account.initialBalance ?? 0, for: account.id)
        }
        hasCommitted = true
    }

    /// The trial offer closed (✕, a swipe, a purchase or a restore): onboarding ends. Once.
    func trialOfferClosed() {
        showingTrialOffer = false
        guard let coordinator, hasCommitted else { return }
        complete(coordinator)
    }

    private func complete(_ coordinator: AppCoordinator) {
        guard !hasCompleted else { return }
        hasCompleted = true
        // Asked for before Home appears, so the tab bar finds it on its first pass.
        if afterFinish == .statement { coordinator.pickStatement() }
        coordinator.completeOnboarding(.finished)
        adoptICloudBackups(coordinator)
        logger.info("onboarding_finished selectedCount=\(self.selectedPresetCount, privacy: .public)")
    }
}
