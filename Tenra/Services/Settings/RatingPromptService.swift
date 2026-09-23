//
//  RatingPromptService.swift
//  Tenra
//
//  Decides WHEN to ask the user for an App Store rating.
//
//  Strategy (see ASO rating-prompt-strategy):
//  • Only prompt users who have experienced value — never on cold open or after an error.
//  • Eligible = the user has actively tracked finances (>= `txThreshold` transactions
//    added through ANY path: manual form, voice, receipt scan, statement/CSV import,
//    Siri) AND is a returning user (>= `sessionThreshold` sessions OR >= `daysThreshold`
//    days since install). v1 required all three and only checked on manual adds, which
//    for a small user base meant the survey practically never fired.
//  • Eligibility is re-checked at three moments: a transaction save, a returning
//    session (delayed, never on cold open), and a success moment (e.g. the user opens
//    an insight / weekly digest notification).
//  • A neutral pre-prompt survey ("Are you enjoying Tenra?") filters out unhappy users
//    BEFORE the native StoreKit prompt, so only satisfied users reach the rating UI.
//  • The native prompt itself goes through Apple's official `AppStore.requestReview(in:)`,
//    which Apple throttles to at most 3×/365 days regardless of how often we call it.
//  • The survey is presented only when no other sheet is on screen (most saves happen
//    inside a modal) and at most once per version — shown counts as asked, even if the
//    user swipes it away.
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

    nonisolated static let sessionThreshold = 2
    nonisolated static let txThreshold = 5
    nonisolated static let daysThreshold = 2

    /// Pure eligibility rule, pinned by `RatingPromptServiceTests`.
    nonisolated static func meetsThresholds(sessions: Int, transactions: Int, daysSinceInstall: Double) -> Bool {
        guard transactions >= txThreshold else { return false }
        return sessions >= sessionThreshold || daysSinceInstall >= Double(daysThreshold)
    }

    // MARK: Observable trigger

    /// Set true when an eligible user reaches a prompt moment and nothing else is on
    /// screen. MainTabView observes this and presents the pre-prompt survey sheet.
    /// Reset to false when the sheet closes.
    var shouldShowSurvey = false

    // MARK: Storage

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: "Tenra", category: "RatingPrompt")
    @ObservationIgnored private var presentationTask: Task<Void, Never>?

    private enum Key {
        static let installDate = "rating.installDate"
        static let sessionCount = "rating.sessionCount"
        static let txCount = "rating.txCount"
        static let lastPromptedVersion = "rating.lastPromptedVersion"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Signals

    /// Call once when the app becomes active (cold launch or foreground). A returning
    /// user who is already eligible gets the survey after they've settled in, not on open.
    func recordSession() {
        if defaults.object(forKey: Key.installDate) == nil {
            defaults.set(Date(), forKey: Key.installDate)
        }
        defaults.set(defaults.integer(forKey: Key.sessionCount) + 1, forKey: Key.sessionCount)
        scheduleSurveyIfEligible(after: .seconds(20))
    }

    /// Call after transactions are successfully saved by the user (form, voice, receipt,
    /// import, Siri). `count` > 1 for batch saves such as a statement import.
    /// `promptNow: false` only counts — for flows that stay busy after the save (the Voice
    /// tab re-arms the microphone); eligibility is then picked up on the next session.
    func recordTransactionAdded(count: Int = 1, promptNow: Bool = true) {
        guard count > 0 else { return }
        defaults.set(defaults.integer(forKey: Key.txCount) + count, forKey: Key.txCount)
        if promptNow {
            scheduleSurveyIfEligible(after: .seconds(1))
        }
    }

    /// Call at a positive moment that is not a save, e.g. the user opened an insight
    /// or weekly-digest notification.
    func recordSuccessMoment() {
        scheduleSurveyIfEligible(after: .seconds(3))
    }

    // MARK: Eligibility

    var isEligible: Bool {
        guard OnboardingState.isCompleted else { return false }
        // Already prompted on this version — don't ask again.
        guard defaults.string(forKey: Key.lastPromptedVersion) != appVersion else { return false }
        let days = (defaults.object(forKey: Key.installDate) as? Date)
            .map { Date().timeIntervalSince($0) / 86_400 } ?? 0
        return Self.meetsThresholds(
            sessions: defaults.integer(forKey: Key.sessionCount),
            transactions: defaults.integer(forKey: Key.txCount),
            daysSinceInstall: days
        )
    }

    // MARK: Presentation

    /// Waits `delay`, then presents the survey once no other modal is on screen. Most
    /// saves happen inside a sheet (add form, import, voice), and SwiftUI silently drops
    /// a second sheet while one is presented — so poll for a clear screen (bounded).
    private func scheduleSurveyIfEligible(after delay: Duration) {
        guard presentationTask == nil, !shouldShowSurvey, isEligible else { return }
        presentationTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            for _ in 0..<60 {
                guard let self, !Task.isCancelled else { return }
                guard self.isEligible else { self.presentationTask = nil; return }
                if Self.isScreenClear {
                    self.log.debug("Rating prompt eligible — presenting survey")
                    // Shown counts as asked: a swipe-dismissed survey must not return on
                    // every later save of the same version.
                    self.markPromptedThisVersion()
                    self.shouldShowSurvey = true
                    self.presentationTask = nil
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
            self?.presentationTask = nil
        }
    }

    /// True when the app is in the foreground and its root has nothing presented on top.
    private static var isScreenClear: Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return false }
        return root.presentedViewController == nil && !AppLockService.shared.shouldShowOverlay
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

    /// Records that this version has been handled, so we don't nag again on it.
    func markPromptedThisVersion() {
        defaults.set(appVersion, forKey: Key.lastPromptedVersion)
    }
}
