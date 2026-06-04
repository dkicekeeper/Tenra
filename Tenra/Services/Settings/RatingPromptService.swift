//
//  RatingPromptService.swift
//  Tenra
//
//  Decides WHEN to ask the user for an App Store rating.
//
//  Strategy (see ASO rating-prompt-strategy):
//  • Only prompt users who have experienced value — never on cold open or after an error.
//  • Success moment = the user has actively tracked finances (>= `txThreshold` manual
//    transactions added) AND is a returning user (>= `sessionThreshold` sessions,
//    >= `daysThreshold` days since install).
//  • A neutral pre-prompt survey ("Are you enjoying Tenra?") filters out unhappy users
//    BEFORE the native StoreKit prompt, so only satisfied users reach the rating UI.
//  • The native prompt itself goes through Apple's official `AppStore.requestReview(in:)`,
//    which Apple throttles to at most 3×/365 days regardless of how often we call it.
//
//  iOS resets ratings per version, so `lastPromptedVersion` is keyed on the marketing
//  version — a fresh version can prompt an engaged user again.
//

import StoreKit
import UIKit
import os

@MainActor
@Observable
final class RatingPromptService {

    static let shared = RatingPromptService()

    // MARK: Thresholds (tunable)

    private let sessionThreshold = 3
    private let txThreshold = 5
    private let daysThreshold = 3

    // MARK: Observable trigger

    /// Set true at a success moment when the user is eligible. MainTabView observes this
    /// and presents the pre-prompt survey sheet. Reset to false when the sheet closes.
    var shouldShowSurvey = false

    // MARK: Storage

    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "Tenra", category: "RatingPrompt")

    private enum Key {
        static let installDate = "rating.installDate"
        static let sessionCount = "rating.sessionCount"
        static let txCount = "rating.txCount"
        static let lastPromptedVersion = "rating.lastPromptedVersion"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private init() {}

    // MARK: Signals

    /// Call once when the app becomes active (cold launch or foreground).
    func recordSession() {
        if defaults.object(forKey: Key.installDate) == nil {
            defaults.set(Date(), forKey: Key.installDate)
        }
        defaults.set(defaults.integer(forKey: Key.sessionCount) + 1, forKey: Key.sessionCount)
    }

    /// Call after every successfully added manual transaction. Fires the survey if the
    /// user just crossed into eligibility — this is the "success moment".
    func recordTransactionAdded() {
        let newCount = defaults.integer(forKey: Key.txCount) + 1
        defaults.set(newCount, forKey: Key.txCount)

        if isEligible {
            log.debug("Rating prompt eligible — presenting survey")
            shouldShowSurvey = true
        }
    }

    // MARK: Eligibility

    private var isEligible: Bool {
        guard OnboardingState.isCompleted else { return false }
        // Already prompted on this version — don't ask again.
        guard defaults.string(forKey: Key.lastPromptedVersion) != appVersion else { return false }
        guard defaults.integer(forKey: Key.sessionCount) >= sessionThreshold else { return false }
        guard defaults.integer(forKey: Key.txCount) >= txThreshold else { return false }
        guard let install = defaults.object(forKey: Key.installDate) as? Date,
              Date().timeIntervalSince(install) >= Double(daysThreshold) * 86_400 else { return false }
        return true
    }

    // MARK: Native prompt

    /// Call ONLY after the user answers "Yes" in the pre-prompt survey. Routes through
    /// Apple's official API and records the version so we don't re-prompt on it.
    func requestNativeReview() {
        markPromptedThisVersion()
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            log.error("No active scene for review request")
            return
        }
        AppStore.requestReview(in: scene)
    }

    /// Call when the user answers "Not really" — we don't show the native prompt, but we
    /// still mark this version as handled so we don't nag them again on the same version.
    func markPromptedThisVersion() {
        defaults.set(appVersion, forKey: Key.lastPromptedVersion)
    }
}
