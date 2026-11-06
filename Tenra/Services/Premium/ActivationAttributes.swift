//
//  ActivationAttributes.swift
//  Tenra
//
//  How far a new person gets, as anonymous RevenueCat subscriber attributes (promotion-plan §7,
//  the first-run funnel; App Privacy: Usage Data › Product Interaction, analytics, not linked):
//  `onboarding` (finished, skipped, restored), `entries` (the milestones 1, 5 and 10 of what the
//  person recorded) and `ten_opened`. Each value is written once, when it changes, so RevenueCat
//  can filter customers and charts by it. Nothing without RevenueCat (tests, the screenshot demo).
//

import Foundation

@MainActor
enum ActivationAttributes {

    enum Name: String {
        case onboarding
        case entries
        case tenOpened = "ten_opened"
    }

    /// How onboarding ended.
    enum OnboardingOutcome: String {
        /// "Start" on the last step (or its ✕), with what was collected.
        case finished
        /// ✕ on an earlier step: no account, no categories.
        case skipped
        /// A backup restored on the welcome screen.
        case restored
    }

    /// The entry counts worth a milestone: the first entry, then 5 and 10.
    nonisolated static let entryMilestones = [1, 5, 10]

    /// Writes an attribute; the app's goes to RevenueCat, the tests replace it.
    static var write: (Name, String) -> Void = { PremiumManager.shared.noteActivation($0.rawValue, $1) }

    /// The highest milestone `count` entries reach, nil below the first.
    nonisolated static func milestone(forEntries count: Int) -> Int? {
        entryMilestones.last { $0 <= count }
    }

    static func noteOnboarding(_ outcome: OnboardingOutcome, defaults: UserDefaults = .standard) {
        writeIfChanged(.onboarding, outcome.rawValue, defaults: defaults)
    }

    static func noteTenOpened(defaults: UserDefaults = .standard) {
        writeIfChanged(.tenOpened, "yes", defaults: defaults)
    }

    /// The store holds `count` transactions: the milestone they reach, if it is a new one.
    static func noteEntries(_ count: Int, defaults: UserDefaults = .standard) {
        guard let milestone = milestone(forEntries: count),
              milestone > defaults.integer(forKey: storageKey(.entries)) else { return }
        defaults.set(milestone, forKey: storageKey(.entries))
        write(.entries, String(milestone))
    }

    /// Transactions were added (TransactionStore.onRecorded) and the store now holds `total`:
    /// the entries move only when one of them is the person's own (SpendingReminderPlan's rule),
    /// not deposit interest or a series occurrence Tenra made.
    static func noteRecorded(
        _ transactions: [Transaction],
        total: Int,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        guard transactions.contains(where: { SpendingReminderPlan.isUserRecord($0, now: now) }) else { return }
        noteEntries(total, defaults: defaults)
    }

    private static func writeIfChanged(_ name: Name, _ value: String, defaults: UserDefaults) {
        guard defaults.string(forKey: storageKey(name)) != value else { return }
        defaults.set(value, forKey: storageKey(name))
        write(name, value)
    }

    /// The value last written, kept on the device so it is written only when it changes.
    private static func storageKey(_ name: Name) -> String {
        "activation.\(name.rawValue)"
    }
}
