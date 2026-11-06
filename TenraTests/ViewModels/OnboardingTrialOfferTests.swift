//
//  OnboardingTrialOfferTests.swift
//  TenraTests
//
//  Pins the trial offer at the end of onboarding (docs/promotion-plan.md §2, decision of
//  2026-11-06): "Start" saves everything first, then the paywall comes up when the App Store has
//  something to sell and the person is not Pro, and onboarding ends once it is closed; without an
//  offer it ends at once; a second tap while the offer is up saves nothing twice.
//

import Testing
import Foundation
@testable import Tenra

// `.sharedProcessState`: reads and writes the process-wide onboarding flag (UserDefaults
// standard), put back after each test.
@MainActor
@Suite("Onboarding trial offer", .serialized, .sharedProcessState)
struct OnboardingTrialOfferTests {

    /// Runs `body` on a coordinator that still needs onboarding, then puts the flag back.
    private func withFreshOnboarding(_ body: (AppCoordinator) async throws -> Void) async rethrows {
        let wasCompleted = OnboardingState.isCompleted
        OnboardingState.reset()
        defer { if wasCompleted { OnboardingState.markCompleted() } else { OnboardingState.reset() } }
        let name = "OnboardingTrialOfferTests.\(UUID().uuidString)"
        let repository = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: name + ".data")!)
        let coordinator = AppCoordinator(repository: repository, formatDefaults: UserDefaults(suiteName: name)!)
        try await body(coordinator)
    }

    private func model(_ coordinator: AppCoordinator, offers: Bool) -> OnboardingViewModel {
        let vm = OnboardingViewModel(coordinator: coordinator, offersTrial: { offers })
        vm.draftAccount.name = "Card"
        return vm
    }

    @Test("Offered to a free person when the App Store has something to sell")
    func offerRule() {
        #expect(PremiumManager.onboardingOfferDue(isPro: false, canSell: true))
        #expect(!PremiumManager.onboardingOfferDue(isPro: true, canSell: true))
        #expect(!PremiumManager.onboardingOfferDue(isPro: false, canSell: false))
    }

    @Test("With an offer, onboarding ends when the paywall closes")
    func waitsForTheOffer() async {
        await withFreshOnboarding { coordinator in
            let vm = model(coordinator, offers: true)
            await vm.finish()
            #expect(vm.showingTrialOffer)
            #expect(coordinator.needsOnboarding)
            #expect(coordinator.accountsViewModel.accounts.count == 1)
            vm.trialOfferClosed()
            #expect(!vm.showingTrialOffer)
            #expect(!coordinator.needsOnboarding)
        }
    }

    @Test("Without an offer, onboarding ends at once")
    func endsAtOnceWithoutOffer() async {
        await withFreshOnboarding { coordinator in
            let vm = model(coordinator, offers: false)
            await vm.finish()
            #expect(!vm.showingTrialOffer)
            #expect(!coordinator.needsOnboarding)
        }
    }

    @Test("A second tap while the offer is up saves nothing twice")
    func secondTapSavesOnce() async {
        await withFreshOnboarding { coordinator in
            let vm = model(coordinator, offers: true)
            await vm.finish()
            await vm.finish()
            #expect(coordinator.accountsViewModel.accounts.count == 1)
            vm.trialOfferClosed()
            vm.trialOfferClosed()
            #expect(!coordinator.needsOnboarding)
        }
    }
}
