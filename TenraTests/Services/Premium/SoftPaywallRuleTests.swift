//
//  SoftPaywallRuleTests.swift
//  TenraTests
//
//  Pins when Analytics offers Pro by itself (PremiumManager.softPaywallDue): a free person with
//  3 entries, at most 3 times, 14 days apart, and not within a day of the trial offer at the end
//  of onboarding (one unprompted paywall a day at most).
//

import Testing
import Foundation
@testable import Tenra

struct SoftPaywallRuleTests {

    private let now = Date(timeIntervalSince1970: 1_793_900_000)

    private func due(
        isPro: Bool = false,
        entries: Int = 3,
        shows: Int = 0,
        lastShown: Date? = nil,
        onboardingOffer: Date? = nil
    ) -> Bool {
        PremiumManager.softPaywallDue(
            isPro: isPro, transactionCount: entries, shows: shows,
            lastShown: lastShown, onboardingOfferShown: onboardingOffer, now: now
        )
    }

    @Test("Due from the third entry, not before")
    func dueFromThreeEntries() {
        #expect(!due(entries: 0))
        #expect(!due(entries: 2))
        #expect(due(entries: 3))
        #expect(due(entries: 40))
    }

    @Test("Never for Pro")
    func neverForPro() {
        #expect(!due(isPro: true, entries: 40))
    }

    @Test("At most three times, fourteen days apart")
    func capAndCooldown() {
        #expect(!due(shows: 3))
        #expect(!due(shows: 1, lastShown: now.addingTimeInterval(-13 * 86_400)))
        #expect(due(shows: 1, lastShown: now.addingTimeInterval(-15 * 86_400)))
    }

    @Test("Waits a day after the trial offer at the end of onboarding")
    func waitsAfterOnboardingOffer() {
        #expect(!due(onboardingOffer: now.addingTimeInterval(-3_600)))
        #expect(due(onboardingOffer: now.addingTimeInterval(-25 * 3_600)))
    }
}
