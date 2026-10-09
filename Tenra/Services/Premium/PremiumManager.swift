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
//  Grandfathering (see docs/monetization-strategy.md §7, FoundingUserPolicy): users who had
//  Tenra before Tenra Pro existed are "Founding Users" and keep Pro for free, permanently.
//  Proof is either this device (onboarding already done when the first Pro build ran) or the
//  App Store (StoreKit's AppTransaction: first download before the first Pro build went on
//  sale), so the status survives a reinstall and a new phone. Never revoked.
//

import Foundation
import Observation
import os
import RevenueCat
import StoreKit

/// Snapshot of the active `pro` entitlement for status display (Settings → Tenra Pro).
/// Plain Foundation types only — consumers never touch RevenueCat.
struct ProStatus: Equatable, Sendable {

    enum Plan: Equatable, Sendable {
        case monthly
        case annual
        case lifetime
        case unknown

        init(productID: String) {
            switch productID {
            case PremiumConfig.Product.monthly:  self = .monthly
            case PremiumConfig.Product.annual:   self = .annual
            case PremiumConfig.Product.lifetime: self = .lifetime
            default:                             self = .unknown
            }
        }
    }

    let plan: Plan
    /// Renewal date when `willRenew`, otherwise the date access ends. `nil` for lifetime.
    let expirationDate: Date?
    let willRenew: Bool
    /// Apple's manage-subscription page for this customer (RevenueCat `managementURL`).
    let managementURL: URL?
}

@MainActor
@Observable
final class PremiumManager {

    static let shared = PremiumManager()

    // MARK: - Observable state

    /// True when RevenueCat reports an active `pro` entitlement (paid subscriber
    /// or lifetime buyer). Drives the UI together with `isFounder`.
    private(set) var isSubscriber = false

    /// Details of the active entitlement (plan, renewal date, management URL)
    /// for the Settings status block. `nil` while not a subscriber.
    private(set) var proStatus: ProStatus?

    /// True for grandfathered existing users (FoundingUserPolicy). Stored in UserDefaults and
    /// observable, so gates re-render when the App Store check confirms a founder after launch.
    /// Only ever set to true.
    private(set) var isFounder: Bool

    /// THE gate every feature checks.
    var isPro: Bool { isFounder || isSubscriber }

    /// True once RevenueCat has been configured this session. While false the app
    /// treats everyone as free (safe default before the API key / package is set up).
    private(set) var isConfigured = false

    /// Whether the paywall has something to sell, from the last `checkOfferings()`; nil until
    /// the first check (the launch health check runs one after the first frame).
    private(set) var offeringsAvailability: OfferingsAvailability?

    /// RevenueCat anonymous app user ID. Shown in Settings → About as "Support ID"
    /// so users can share it for purchase-issue support and promotional entitlement
    /// grants (RevenueCat dashboard → Customers → find by this ID).
    var appUserID: String? {
        guard isConfigured else { return nil }
        return Purchases.shared.appUserID
    }

    // MARK: - Internals

    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "Tenra", category: "Premium")
    private var customerInfoTask: Task<Void, Never>?

    private enum Key {
        static let grandfatherEvaluated = "tenra.premium.grandfatherEvaluated.v1"
        static let isFounder            = "tenra.premium.isFounder.v1"
        static let softPaywallCount     = "tenra.premium.softPaywallCount.v1"
        static let softPaywallLastShown = "tenra.premium.softPaywallLastShown.v1"
        static let lastKnownSubscriber  = "tenra.premium.lastKnownSubscriber.v1"
        /// A production App Store record was read: the first-download date never changes,
        /// so the founder check against it is final.
        static let appStoreFounderChecked = "tenra.premium.appStoreFounderChecked.v1"
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

    private init() {
        // Start from the last entitlement RevenueCat reported. It arrives asynchronously
        // on every launch, and starting from `false` made paying subscribers see the
        // locked Voice/Import tabs flash (and treated cold intent runs as free) until then.
        // The live CustomerInfo stream corrects it either way within moments.
        isSubscriber = UserDefaults.standard.bool(forKey: Key.lastKnownSubscriber)
        isFounder = UserDefaults.standard.bool(forKey: Key.isFounder)
    }

    // MARK: - Configuration

    /// Call ONCE, as early as possible (AppDelegate.didFinishLaunching). Safe to
    /// call before onboarding completes — grandfathering reads the onboarding flag's
    /// value AS IT WAS at launch (existing user = already completed; fresh install =
    /// not yet completed), which is exactly the discriminator we want.
    func configure() {
        evaluateGrandfatheringOnce()
        confirmFounderWithAppStoreIfNeeded()

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
        let entitlement = info.entitlements[PremiumConfig.entitlementID]
        let active = entitlement?.isActive == true

        var status: ProStatus?
        if active, let entitlement {
            status = ProStatus(
                plan: ProStatus.Plan(productID: entitlement.productIdentifier),
                expirationDate: entitlement.expirationDate,
                willRenew: entitlement.willRenew,
                managementURL: info.managementURL
            )
        }

        // Compare the full snapshot, not just `active` — plan switches and
        // renewal-date changes must reach the Settings status block too.
        defaults.set(active, forKey: Key.lastKnownSubscriber)
        guard active != isSubscriber || status != proStatus else { return }
        isSubscriber = active
        proStatus = status
        log.info("pro entitlement active=\(active, privacy: .public)")
    }

    // MARK: - Offerings

    /// Asks RevenueCat whether the current offering has packages (its cache answers when warm)
    /// and stores the answer in `offeringsAvailability`. The paywall shows RevenueCatUI only
    /// when this says `.available`; otherwise RevenueCatUI would show its raw error alert,
    /// whose OK closes the sheet.
    @discardableResult
    func checkOfferings() async -> OfferingsAvailability {
        guard isConfigured else {
            offeringsAvailability = .notConfigured
            return .notConfigured
        }
        let availability: OfferingsAvailability
        do {
            let offerings = try await Purchases.shared.offerings()
            availability = .loaded(currentPackageCount: offerings.current?.availablePackages.count)
        } catch {
            availability = .failure(revenueCatCode: (error as? RevenueCat.ErrorCode)?.rawValue)
            log.error("Offerings failed to load: \(error.localizedDescription, privacy: .public)")
        }
        if !availability.canSell {
            log.error("Paywall can't sell: \(String(describing: availability), privacy: .public)")
        }
        offeringsAvailability = availability
        return availability
    }

    // MARK: - Purchases / restore (used by custom flows; RevenueCatUI handles its own)

    /// Applies the CustomerInfo a RevenueCatUI purchase or restore callback hands over, and says
    /// whether the `pro` entitlement is now active. A restore "completes" even when it found
    /// nothing, so the paywall closes only on true. The paywall passes the value through
    /// without reading it, so it never needs RevenueCat.
    @discardableResult
    func applyPaywallResult(_ info: CustomerInfo) -> Bool {
        apply(info)
        return info.entitlements[PremiumConfig.entitlementID]?.isActive == true
    }

    /// Restore previous purchases (App Store "Restore" requirement). RevenueCatUI's
    /// PaywallView exposes its own restore button; this is for any custom entry point.
    func restorePurchases() async throws {
        guard isConfigured else { return }
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
    }

    /// After the App Store's offer-code sheet closes (Settings → Tenra Pro → "Redeem code",
    /// StoreKit's `offerCodeRedemption`). A redeemed code is a StoreKit transaction that
    /// RevenueCat's own listener picks up too; syncing now makes Pro unlock without waiting
    /// for it. A sheet closed without a code syncs nothing new.
    func syncAfterOfferCodeRedemption() async {
        guard isConfigured else { return }
        do {
            let info = try await Purchases.shared.syncPurchases()
            apply(info)
        } catch {
            log.error("Sync after offer code redemption failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Grandfathering

    /// The device rule, decided once: the first time a Pro build runs, a user who already
    /// finished onboarding is a founder. A brand-new install has not completed onboarding at
    /// this point, so it stays a normal free user (until the App Store check below says otherwise).
    private func evaluateGrandfatheringOnce() {
        // Re-read: ScreenshotDemoMode writes the flag directly before configure().
        isFounder = defaults.bool(forKey: Key.isFounder)
        let evaluatedBefore = defaults.bool(forKey: Key.grandfatherEvaluated)
        defaults.set(true, forKey: Key.grandfatherEvaluated)

        let inputs = FoundingUserPolicy.Inputs(
            storedFlag: isFounder,
            evaluatedBefore: evaluatedBefore,
            onboardingCompleted: OnboardingState.isCompleted,
            originalDownload: nil
        )
        if let reason = FoundingUserPolicy.reason(for: inputs), reason != .alreadyFounder {
            markFounder(reason)
        }
    }

    /// The App Store rule, for a reinstall or a new phone where the device flag is gone: the
    /// signed app transaction's first-download date, compared with the first Pro build's
    /// release. Runs off the launch path; an unavailable record is retried next launch.
    private func confirmFounderWithAppStoreIfNeeded() {
        guard !isFounder, !defaults.bool(forKey: Key.appStoreFounderChecked) else { return }
        Task(priority: .utility) { [weak self] in
            let download = await Self.originalDownload()
            self?.applyOriginalDownload(download)
        }
    }

    private func applyOriginalDownload(_ download: FoundingUserPolicy.OriginalDownload?) {
        guard let download else { return }
        if FoundingUserPolicy.downloadedBeforePro(download) {
            markFounder(.downloadedBeforePro)
        }
        // TestFlight / sandbox records carry a placeholder date and never count: keep asking,
        // in case this install is later replaced by the App Store build (same container).
        if download.isProduction {
            defaults.set(true, forKey: Key.appStoreFounderChecked)
        }
    }

    /// Reads StoreKit's app transaction (cached on device; StoreKit refreshes it as needed).
    /// nil when it is unavailable or fails verification.
    private nonisolated static func originalDownload() async -> FoundingUserPolicy.OriginalDownload? {
        do {
            guard case .verified(let transaction) = try await AppTransaction.shared else { return nil }
            return FoundingUserPolicy.OriginalDownload(
                purchaseDate: transaction.originalPurchaseDate,
                isProduction: transaction.environment == .production
            )
        } catch {
            return nil
        }
    }

    /// Sets the founder flag. Release builds never clear it (only `_debugClearFounder` does).
    private func markFounder(_ reason: FoundingUserPolicy.Reason) {
        defaults.set(true, forKey: Key.isFounder)
        isFounder = true
        log.info("Founding User (\(reason.rawValue, privacy: .public))")
    }

#if DEBUG
    /// Test/QA helper: clear the founder flag so the paywall can be exercised.
    func _debugClearFounder() {
        defaults.removeObject(forKey: Key.isFounder)
        defaults.removeObject(forKey: Key.grandfatherEvaluated)
        defaults.removeObject(forKey: Key.appStoreFounderChecked)
        isFounder = false
    }
#endif
}
