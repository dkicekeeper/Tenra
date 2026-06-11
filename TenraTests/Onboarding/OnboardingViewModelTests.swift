//
//  OnboardingViewModelTests.swift
//  TenraTests
//
//  Rewritten (2026-06-11, Plan 004) against the current navigation model.
//  The old suite referenced `currentScreen`, `goForward`, `goBack`, and
//  `transitionDirection` — all removed during the onboarding redesign.
//
//  Construction: `OnboardingViewModel.makeForTesting()` (line 61 in
//  OnboardingViewModel.swift) — builds a VM with nil coordinator so commit
//  pipeline is a no-op; all draft logic still works.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct OnboardingViewModelTests {

    // MARK: - 1. draftCurrency defaults to AppSettings.defaultCurrency

    /// OnboardingViewModel.draftCurrency is initialised to AppSettings.defaultCurrency
    /// (currently "KZT"). Asserting against the constant (not a literal) so the
    /// test stays correct if the default ever changes.
    @Test("draftCurrency defaults to AppSettings.defaultCurrency")
    func draftCurrencyDefaults() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.draftCurrency == AppSettings.defaultCurrency)
    }

    // MARK: - 2. draftCategories mirrors CategoryPreset.defaultExpense; all selected

    /// OnboardingViewModel seeds draftCategories from CategoryPreset.defaultExpense
    /// (line 46), calling makeSelectable(isSelected: true) for each entry.
    /// Currently 15 presets; we compare count against the source-of-truth array.
    @Test("draftCategories count matches CategoryPreset.defaultExpense and all start selected")
    func draftCategoriesInitialState() {
        let vm = OnboardingViewModel.makeForTesting()

        #expect(vm.draftCategories.count == CategoryPreset.defaultExpense.count)
        #expect(vm.draftCategories.allSatisfy { $0.isSelected })
    }

    /// selectedPresetCount returns the number of selected presets.
    /// After construction all are selected → count equals total.
    @Test("selectedPresetCount equals total when all selected")
    func selectedPresetCountAllSelected() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.selectedPresetCount == CategoryPreset.defaultExpense.count)
    }

    // MARK: - 3. canAdvanceFromAccountStep gating

    /// canAdvanceFromAccountStep is false when draftAccount.name is empty
    /// (trimming: whitespace-only also counts as empty).
    @Test("canAdvanceFromAccountStep is false for empty name")
    func canAdvanceAccountStepFalseWhenNameEmpty() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.canAdvanceFromAccountStep == false)
    }

    /// After setting a non-empty name the gate opens.
    @Test("canAdvanceFromAccountStep becomes true after setting account name")
    func canAdvanceAccountStepTrueAfterName() {
        let vm = OnboardingViewModel.makeForTesting()
        vm.draftAccount.name = "Kaspi"
        #expect(vm.canAdvanceFromAccountStep == true)
    }

    /// Whitespace-only name is treated as empty.
    @Test("canAdvanceFromAccountStep is false for whitespace-only name")
    func canAdvanceAccountStepFalseForWhitespace() {
        let vm = OnboardingViewModel.makeForTesting()
        vm.draftAccount.name = "   "
        #expect(vm.canAdvanceFromAccountStep == false)
    }

    // MARK: - 4. canFinish gating

    /// canFinish is true initially (≥1 category selected, isFinishing=false).
    @Test("canFinish is true when categories are selected")
    func canFinishTrueInitially() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.canFinish == true)
    }

    /// canFinish is false when all categories are deselected.
    @Test("canFinish is false when no category is selected")
    func canFinishFalseWhenNoneSelected() {
        let vm = OnboardingViewModel.makeForTesting()
        for index in vm.draftCategories.indices {
            vm.draftCategories[index].isSelected = false
        }
        #expect(vm.canFinish == false)
    }

    // MARK: - 5. startDataCollection pushes currency step

    /// startDataCollection() sets path = [.currency] (NavigationStack root is
    /// the welcome screen; .currency is the first data-collection step).
    @Test("startDataCollection sets path to [.currency]")
    func startDataCollectionPushesFirstStep() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.path.isEmpty)

        vm.startDataCollection()

        #expect(vm.path == [.currency])
    }

    // MARK: - 6. advanceToCategoriesStep appends .categories

    /// advanceToCategoriesStep() appends .categories to whatever is currently
    /// in path. Because makeForTesting() has nil coordinator,
    /// advanceToAccountStep() is a no-op (guard coordinator exits immediately),
    /// so we pre-set the path to simulate having completed the account step,
    /// then call advanceToCategoriesStep() directly (which does NOT touch coordinator).
    @Test("advanceToCategoriesStep appends .categories to path")
    func advanceToCategoriesStepAppendsStep() async {
        let vm = OnboardingViewModel.makeForTesting()
        // Simulate that the currency and account steps are already in path.
        vm.startDataCollection()           // path = [.currency]
        vm.path.append(.account)           // path = [.currency, .account]

        await vm.advanceToCategoriesStep()

        #expect(vm.path.contains(.categories))
        #expect(vm.path.last == .categories)
    }

    // MARK: - 7. finish/skip are safe no-ops without a coordinator

    /// Both finish() and skip() guard on `coordinator != nil` and exit
    /// immediately in test mode. Calling them must not crash and must not
    /// mutate isFinishing to true permanently.
    @Test("finish() does not crash and leaves isFinishing false when no coordinator")
    func finishIsNoOpWithoutCoordinator() async {
        let vm = OnboardingViewModel.makeForTesting()
        await vm.finish()
        #expect(vm.isFinishing == false)
    }

    @Test("skip() does not crash and leaves isFinishing false when no coordinator")
    func skipIsNoOpWithoutCoordinator() async {
        let vm = OnboardingViewModel.makeForTesting()
        await vm.skip()
        #expect(vm.isFinishing == false)
    }
}
