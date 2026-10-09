//
//  FoundingUserPolicy.swift
//  Tenra
//
//  Who is a Founding User: someone who had Tenra before Tenra Pro existed, and so keeps every
//  Pro feature for free, forever (docs/monetization-strategy.md §7).
//
//  Two independent proofs, either one is enough:
//  - this device: onboarding was already completed the first time a Pro build ran (the
//    original rule, kept for everyone it already covered);
//  - the App Store: the Apple Account first downloaded the app before the first Pro build
//    went on sale. This survives a reinstall and a new phone, which the device flag
//    (UserDefaults) does not.
//
//  A founder is never demoted: the stored flag always wins, and nothing writes it back to false.
//  Pure logic: PremiumManager gathers the inputs (UserDefaults, StoreKit's AppTransaction).
//

import Foundation

nonisolated enum FoundingUserPolicy {

    /// What the App Store's signed app transaction says about the first download.
    struct OriginalDownload: Equatable, Sendable {
        /// `AppTransaction.originalPurchaseDate`: unchanged by deleting and reinstalling.
        let purchaseDate: Date
        /// False in TestFlight, sandbox and Xcode builds, where the date is a fixed placeholder
        /// (2013-08-01) that would make every tester a founder.
        let isProduction: Bool
    }

    struct Inputs: Equatable, Sendable {
        /// The founder flag already stored on this device.
        var storedFlag: Bool
        /// The one-time onboarding check already ran on this device (any earlier Pro-build launch).
        var evaluatedBefore: Bool
        /// Onboarding state as it was when this launch started.
        var onboardingCompleted: Bool
        /// The verified App Store record, when known.
        var originalDownload: OriginalDownload?
    }

    enum Reason: String, Equatable, Sendable {
        case alreadyFounder
        case existingUserAtProLaunch
        case downloadedBeforePro
    }

    /// Why this user is a Founding User, or nil when they are not.
    static func reason(
        for inputs: Inputs,
        cutoff: Date = PremiumConfig.foundingUserDownloadCutoff
    ) -> Reason? {
        if inputs.storedFlag { return .alreadyFounder }
        if !inputs.evaluatedBefore && inputs.onboardingCompleted { return .existingUserAtProLaunch }
        if downloadedBeforePro(inputs.originalDownload, cutoff: cutoff) { return .downloadedBeforePro }
        return nil
    }

    /// True when a production App Store record shows a first download before `cutoff`.
    static func downloadedBeforePro(
        _ download: OriginalDownload?,
        cutoff: Date = PremiumConfig.foundingUserDownloadCutoff
    ) -> Bool {
        guard let download, download.isProduction else { return false }
        return download.purchaseDate < cutoff
    }
}
