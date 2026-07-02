//
//  PremiumManager.swift
//  Tenra
//
//  Single source of truth for "is this user Pro?".
//  THE ONLY file in the app that imports RevenueCat — every feature gate and
//  paywall trigger depends only on `PremiumManager.isPro`, so the SDK surface
//  stays contained here.
//
//  isPro = isFounder (grandfathered existing user)  ||  active `pro` entitlement.
//
//  Grandfathering (see docs/MONETIZATION_STRATEGY.md §7): users who already
//  completed onboarding BEFORE the first launch of the Pro build are marked
//  "Founding Users" and keep Pro for free, permanently. This converts goodwill
//  into reviews/referrals and avoids yanking features from the live base.
//

import Foundation
import Observation
import os
import RevenueCat

@MainActor
@Observable
final class PremiumManager {

    static let shared = PremiumManager()

    // MARK: - Observable state

    /// True when RevenueCat reports an active `pro` entitlement (paid subscriber
    /// or lifetime buyer). Drives the UI together with `isFounder`.
    private(set) var isSubscriber = false

    /// True for grandfathered existing users. Read from UserDefaults (decided once
    /// at first Pro-build launch); exposed so the paywall can show a "Founding User"
    /// state instead of pricing.
    var isFounder: Bool { defaults.bool(forKey: Key.isFounder) }

    /// THE gate every feature checks.
    var isPro: Bool { isFounder || isSubscriber }

    /// True once RevenueCat has been configured this session. While false the app
    /// treats everyone as free (safe default before the API key / package is set up).
    private(set) var isConfigured = false

    // MARK: - Internals

    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "Tenra", category: "Premium")
    private var customerInfoTask: Task<Void, Never>?

    private enum Key {
        static let grandfatherEvaluated = "tenra.premium.grandfatherEvaluated.v1"
        static let isFounder            = "tenra.premium.isFounder.v1"
        static let softPaywallCount     = "tenra.premium.softPaywallCount.v1"
        static let softPaywallLastShown = "tenra.premium.softPaywallLastShown.v1"
    }

    // MARK: - Soft paywall (aha-moment trigger)

    /// Tuning knobs for the dismissible paywall shown on the Insights tab —
    /// the "aha moment" where users see where their money goes (strategy §5).
    private static let softPaywallMinTransactions = 10
    private static let softPaywallMaxShows = 3
    private static let softPaywallCooldown: TimeInterval = 14 * 86_400

    /// True when the aha-moment paywall should be offered: non-Pro user who has
    /// logged enough transactions to have felt the product's value, capped at
    /// 3 lifetime shows with a 14-day cooldown so it never feels like nagging
    /// (the contextual feature gates keep selling in between).
    func shouldShowSoftPaywall(transactionCount: Int) -> Bool {
        guard !isPro else { return false }
        guard transactionCount >= Self.softPaywallMinTransactions else { return false }
        guard defaults.integer(forKey: Key.softPaywallCount) < Self.softPaywallMaxShows else { return false }
        if let last = defaults.object(forKey: Key.softPaywallLastShown) as? Date,
           Date().timeIntervalSince(last) < Self.softPaywallCooldown {
            return false
        }
        return true
    }

    /// Record a soft-paywall impression (call when it is actually presented).
    func markSoftPaywallShown() {
        defaults.set(defaults.integer(forKey: Key.softPaywallCount) + 1, forKey: Key.softPaywallCount)
        defaults.set(Date(), forKey: Key.softPaywallLastShown)
    }

    private init() {}

    // MARK: - Configuration

    /// Call ONCE, as early as possible (AppDelegate.didFinishLaunching). Safe to
    /// call before onboarding completes — grandfathering reads the onboarding flag's
    /// value AS IT WAS at launch (existing user = already completed; fresh install =
    /// not yet completed), which is exactly the discriminator we want.
    func configure() {
        evaluateGrandfatheringOnce()

        guard !PremiumConfig.revenueCatAPIKey.isEmpty else {
            log.notice("RevenueCat API key not set — Premium runs in free-only mode. isFounder=\(self.isFounder, privacy: .public)")
            return
        }
        guard !isConfigured else { return }

        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: PremiumConfig.revenueCatAPIKey)
        isConfigured = true

        observeCustomerInfo()
        log.info("RevenueCat configured. isFounder=\(self.isFounder, privacy: .public)")
    }

    /// Stream entitlement changes so the UI reacts to purchases, restores, expiries,
    /// and cross-device sync without manual refreshes.
    private func observeCustomerInfo() {
        customerInfoTask?.cancel()
        customerInfoTask = Task { [weak self] in
            guard let self else { return }
            // Initial snapshot.
            if let info = try? await Purchases.shared.customerInfo() {
                self.apply(info)
            }
            // Live updates.
            for await info in Purchases.shared.customerInfoStream {
                self.apply(info)
            }
        }
    }

    private func apply(_ info: CustomerInfo) {
        let active = info.entitlements[PremiumConfig.entitlementID]?.isActive == true
        guard active != isSubscriber else { return }
        isSubscriber = active
        log.info("pro entitlement active=\(active, privacy: .public)")
    }

    // MARK: - Purchases / restore (used by custom flows; RevenueCatUI handles its own)

    /// Restore previous purchases (App Store "Restore" requirement). RevenueCatUI's
    /// PaywallView exposes its own restore button; this is for any custom entry point.
    func restorePurchases() async throws {
        guard isConfigured else { return }
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
    }

    // MARK: - Grandfathering

    /// Decide founder status exactly once, the first time the Pro build runs.
    private func evaluateGrandfatheringOnce() {
        guard !defaults.bool(forKey: Key.grandfatherEvaluated) else { return }
        defaults.set(true, forKey: Key.grandfatherEvaluated)

        // Existing user = already finished onboarding before this build first ran.
        // A brand-new install has not completed onboarding at this point, so it is
        // correctly treated as a normal free user.
        if OnboardingState.isCompleted {
            defaults.set(true, forKey: Key.isFounder)
            log.info("grandfathered existing user as Founding User")
        }
    }

#if DEBUG
    /// Test/QA helper: clear the founder flag so the paywall can be exercised.
    func _debugClearFounder() {
        defaults.removeObject(forKey: Key.isFounder)
        defaults.removeObject(forKey: Key.grandfatherEvaluated)
    }
#endif
}
