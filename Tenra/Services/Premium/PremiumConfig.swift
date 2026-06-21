//
//  PremiumConfig.swift
//  Tenra
//
//  Central, dependency-free constants for the Premium / "Tenra Pro" feature.
//  Kept separate from PremiumManager so non-RevenueCat code (feature gates,
//  paywall triggers, tests) can reference IDs without importing the SDK.
//
//  See docs/MONETIZATION_STRATEGY.md for the model + pricing rationale.
//

import Foundation

enum PremiumConfig {

    /// RevenueCat **public** SDK key (the `appl_…` key from
    /// RevenueCat Dashboard → Project Settings → API Keys → Apple App Store).
    /// This is a publishable key; it is safe to ship in the binary.
    /// Empty until configured — `PremiumManager.configure()` no-ops while empty,
    /// so the app keeps working (everyone is treated as free) before setup.
    static let revenueCatAPIKey = "appl_dEBwbjgzTzQVFNRAwobsnHHvQFQ"

    /// RevenueCat **entitlement** identifier that unlocks Pro features.
    /// Must match the entitlement created in the RevenueCat dashboard exactly.
    static let entitlementID = "pro"

    /// RevenueCat **offering** identifier whose packages the paywall renders.
    /// "default" is RevenueCat's conventional current-offering id.
    static let offeringID = "default"

    /// StoreKit product identifiers. These must match BOTH:
    ///   • App Store Connect → in-app purchases / subscriptions, AND
    ///   • the products attached to the RevenueCat offering above.
    enum Product {
        static let monthly  = "tenra.pro.monthly"
        static let annual   = "tenra.pro.annual"
        static let lifetime = "tenra.pro.lifetime"
    }

    // MARK: - Free-tier limits

    /// Maximum number of accounts a free (non-Pro) user can create.
    /// The daily logging loop stays free; scale + depth is Pro. See strategy doc §3.
    static let freeAccountLimit = 3
}
