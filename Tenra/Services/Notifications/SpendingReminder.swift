//
//  SpendingReminder.swift
//  Tenra
//
//  Ten's evening reminder on days nothing was recorded (docs/plan-spending-reminder.md): off
//  until the person says yes (Ten's offer after the first entry, or Settings), at 20:00 by
//  default. iOS does not wake Tenra at that hour, so the whole series SpendingReminderPlan
//  returns is scheduled ahead and replaced whenever Tenra comes to the front, something is
//  recorded (in the app or by auto-capture in the background) or the setting changes.
//  Opening Tenra is the reaction the series counts from; a background record only takes that
//  day's reminder away. Sent only when notifications are allowed; it asks only on a yes.
//

import Foundation
import UserNotifications

@MainActor
enum SpendingReminder {

    static let identifierPrefix = "spendingReminder_"
    /// The reminder is on: `@AppStorage` on the Settings page and the offer cards.
    nonisolated static let enabledKey = "settings.spendingReminder.enabled"
    /// Minutes after midnight it comes at.
    nonisolated static let minutesKey = "settings.spendingReminder.minutes"
    nonisolated static let defaultMinutes = 20 * 60
    /// What the person answered Ten's offer: `OfferState.rawValue`.
    nonisolated static let offerKey = "spendingReminder.offer"
    /// When the person last recorded something, seconds since 1970 (a Double, so the offer card
    /// in Ten's chat can watch it through `@AppStorage`).
    nonisolated static let lastRecordedKey = "spendingReminder.lastRecorded"

    enum OfferState: String {
        case notAsked, accepted, declined
    }

    private static let lastReactionKey = "spendingReminder.lastReaction"
    private static let hookCategoryKey = "spendingReminder.hookCategory"
    private static let hookDayKey = "spendingReminder.hookDay"

    /// The last reschedule asked for: each one waits for the one before, so two never
    /// interleave their removals and additions.
    private static var rescheduling: Task<Void, Never>?

    // MARK: - State

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func minutes(defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: minutesKey) == nil ? defaultMinutes : defaults.integer(forKey: minutesKey)
    }

    static func offerState(defaults: UserDefaults = .standard) -> OfferState {
        OfferState(rawValue: defaults.string(forKey: offerKey) ?? "") ?? .notAsked
    }

    static func lastReaction(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastReactionKey) as? Date
    }

    static func lastRecorded(defaults: UserDefaults = .standard) -> Date? {
        (defaults.object(forKey: lastRecordedKey) as? Double).map(Date.init(timeIntervalSince1970:))
    }

    /// Ten offers the reminder once there is a record, until the person answers.
    static func shouldOffer(hasRecords: Bool, defaults: UserDefaults = .standard) -> Bool {
        hasRecords && offerState(defaults: defaults) == .notAsked && !isEnabled(defaults: defaults)
    }

    // MARK: - Events

    /// Tenra came to the front: the series starts over from today.
    static func noteAppOpened(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastReactionKey)
        requestReschedule(now: now, defaults: defaults)
    }

    /// Transactions were added (TransactionStore.onRecorded), in the app or in the background:
    /// a record by the person takes tonight's reminder away and gives tomorrow's its hook. Not a
    /// reaction: auto-capture alone never keeps the series going.
    static func noteRecorded(_ transactions: [Transaction], now: Date = Date(), defaults: UserDefaults = .standard) {
        guard transactions.contains(where: { SpendingReminderPlan.isUserRecord($0, now: now) }) else { return }
        defaults.set(now.timeIntervalSince1970, forKey: lastRecordedKey)
        if let hook = SpendingReminderPlan.hook(from: transactions, now: now) {
            defaults.set(hook.category, forKey: hookCategoryKey)
            defaults.set(hook.day, forKey: hookDayKey)
        }
        requestReschedule(now: now, defaults: defaults)
    }

    /// "Remind me" on Ten's offer: on, and the system's permission prompt.
    static func acceptOffer(defaults: UserDefaults = .standard) async {
        defaults.set(OfferState.accepted.rawValue, forKey: offerKey)
        await setEnabled(true, defaults: defaults)
    }

    /// ✕ on Ten's offer: never offered again; Settings can still turn it on.
    static func declineOffer(defaults: UserDefaults = .standard) {
        defaults.set(OfferState.declined.rawValue, forKey: offerKey)
        PremiumManager.shared.noteSpendingReminder("declined")
    }

    /// The switch in Settings (and the offer's yes). Turning it on asks for full permission
    /// (from provisional too) and answers the offer.
    static func setEnabled(_ on: Bool, defaults: UserDefaults = .standard) async {
        defaults.set(on, forKey: enabledKey)
        if on {
            if offerState(defaults: defaults) == .notAsked {
                defaults.set(OfferState.accepted.rawValue, forKey: offerKey)
            }
            let granted = await NotificationPermissionManager.shared.requestAuthorization()
            PremiumManager.shared.noteSpendingReminder(granted ? "on" : "denied")
        } else {
            PremiumManager.shared.noteSpendingReminder("off")
        }
        await reschedule(defaults: defaults)
    }

    // MARK: - Scheduling

    static func requestReschedule(now: Date = Date(), defaults: UserDefaults = .standard) {
        let previous = rescheduling
        rescheduling = Task {
            await previous?.value
            await reschedule(now: now, defaults: defaults)
        }
    }

    /// Replaces the pending reminders with SpendingReminderPlan's series. Nothing while off or
    /// without permission.
    static func reschedule(now: Date = Date(), defaults: UserDefaults = .standard) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        guard isEnabled(defaults: defaults) else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let time = minutes(defaults: defaults)
        let hook = (defaults.string(forKey: hookCategoryKey), defaults.object(forKey: hookDayKey) as? Date)
        let reminders = SpendingReminderPlan.reminders(
            lastReaction: lastReaction(defaults: defaults) ?? now,
            lastRecorded: lastRecorded(defaults: defaults),
            hook: hook.0.flatMap { category in hook.1.map { SpendingReminderPlan.Hook(category: category, day: $0) } },
            now: now,
            hour: time / 60,
            minute: time % 60
        )
        guard !reminders.isEmpty else { return }

        // Ten drawn once per mood, each notification with a copy of its own.
        let ordinaryArt = TenNotificationArt.pngData(mood: .happy)
        let farewellArt = TenNotificationArt.pngData(mood: .idle)
        for (index, reminder) in reminders.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "spendingReminder.notification.title")
            content.body = body(for: reminder.phrase)
            content.threadIdentifier = "spendingReminder"
            content.sound = .default
            let isFarewell = if case .farewell = reminder.phrase { true } else { false }
            if let data = isFarewell ? farewellArt : ordinaryArt,
               let attachment = TenNotificationArt.attachment(png: data) {
                content.attachments = [attachment]
            }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + String(index),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    private static func body(for phrase: SpendingReminderPlan.Phrase) -> String {
        switch phrase {
        case .regular(let number):
            String(localized: String.LocalizationValue("spendingReminder.phrase.\(number)"))
        case .hook(let category):
            String(format: String(localized: "spendingReminder.hook"), category)
        case .farewell(let number):
            String(localized: String.LocalizationValue("spendingReminder.farewell.\(number)"))
        }
    }
}
