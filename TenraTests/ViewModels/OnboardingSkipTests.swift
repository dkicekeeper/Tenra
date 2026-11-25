//
//  OnboardingSkipTests.swift
//  TenraTests
//
//  Pins the ✕ in onboarding (OnboardingViewModel.skip, docs/promotion-plan.md §6, 2026-11-25):
//  it ends onboarding on a ready app, as "Start" would save it: the typed account or a card with
//  no money in the chosen currency, the picked categories (all when none is picked) and the
//  income ones, without the trial offer; a person who already has accounts gets no new one.
//

import Testing
import Foundation
@testable import Tenra

// `.sharedProcessState`: reads and writes the process-wide onboarding flag (UserDefaults
// standard), put back after each test.
@MainActor
@Suite("Onboarding skip", .serialized, .sharedProcessState)
struct OnboardingSkipTests {

    private func withFreshOnboarding(_ body: (AppCoordinator) async throws -> Void) async rethrows {
        let wasCompleted = OnboardingState.isCompleted
        OnboardingState.reset()
        defer { if wasCompleted { OnboardingState.markCompleted() } else { OnboardingState.reset() } }
        let name = "OnboardingSkipTests.\(UUID().uuidString)"
        let repository = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: name + ".data")!)
        let coordinator = AppCoordinator(repository: repository, formatDefaults: UserDefaults(suiteName: name)!)
        try await body(coordinator)
    }

    private func model(_ coordinator: AppCoordinator) -> OnboardingViewModel {
        OnboardingViewModel(coordinator: coordinator, offersTrial: { true })
    }

    private var startingCategories: Int { CategoryPreset.defaultExpense.count + CategoryPreset.defaultIncome.count }

    @Test("The ✕ leaves a card with no money in the chosen currency and every starting category")
    func readyApp() async {
        await withFreshOnboarding { coordinator in
            let vm = model(coordinator)
            vm.draftCurrency = "USD"
            await vm.skip()
            #expect(!coordinator.needsOnboarding)
            #expect(!vm.showingTrialOffer)
            let accounts = coordinator.transactionStore.accounts
            #expect(accounts.count == 1)
            #expect(accounts.first?.name == String(localized: "onboarding.account.defaultName"))
            #expect(accounts.first?.currency == "USD")
            #expect(coordinator.transactionStore.categories.count == startingCategories)
        }
    }

    @Test("What was typed and picked is what is saved")
    func keepsTheDrafts() async {
        await withFreshOnboarding { coordinator in
            let vm = model(coordinator)
            vm.draftAccount.name = "  Kaspi Gold "
            for index in vm.draftCategories.indices.dropFirst(3) { vm.draftCategories[index].isSelected = false }
            await vm.skip()
            #expect(coordinator.transactionStore.accounts.map(\.name) == ["Kaspi Gold"])
            #expect(coordinator.transactionStore.categories.count == 3 + CategoryPreset.defaultIncome.count)
        }
    }

    @Test("None picked means all of them, and an existing account gets no company")
    func noneAndAgain() async {
        await withFreshOnboarding { coordinator in
            let first = model(coordinator)
            for index in first.draftCategories.indices { first.draftCategories[index].isSelected = false }
            await first.skip()
            #expect(coordinator.transactionStore.categories.count == startingCategories)
            // Onboarding run again (Settings → Diagnostics): the ✕ adds no second account.
            let again = model(coordinator)
            await again.skip()
            #expect(coordinator.transactionStore.accounts.count == 1)
            #expect(coordinator.transactionStore.categories.count == startingCategories)
        }
    }
}
