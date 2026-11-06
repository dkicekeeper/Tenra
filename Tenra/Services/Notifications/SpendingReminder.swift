//
//  SpendingReminder.swift
//  Tenra
//
//  Ten's evening reminder on days nothing was recorded (docs/plan-spending-reminder.md): off
//  until the person says yes (Ten's offer after the first entry, or Settings), at 20:00 by
//  default. iOS does not wake Tenra at that hour, so the whole series SpendingReminderPlan
//  returns is scheduled ahead, one id per day, and replaced whenever Tenra comes to the front,
//  something is recorded (in the app or by auto-capture in the background) or the setting
//  changes. Replacements run one at a time and collapse (CoalescingTask): a statement import of
//  200 rows asks 200 times and replaces once or twice. Opening Tenra is the reaction the series
//  counts from; a record removes that day's reminder at once, before anything can suspend.
//  Sent only when notifications are allowed; it asks only on a yes.
//

import Foundation
import UIKit
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
    /// The RevenueCat attribute last written, so it is written only when it changes.
    private static let attributeKey = "spendingReminder.attribute"

    // Seams for the tests (SpendingReminderSchedulingTests); the app keeps the defaults.
    static var center: SpendingReminderCenter = SystemSpendingReminderCenter()
    static var drawArt: (ParticleCreature.Mood) -> Data? = { TenNotificationArt.pngData(mood: $0) }
    static var writeAttribute: (String) -> Void = { PremiumManager.shared.noteSpendingReminder($0) }

    /// Ten's picture per mood and appearance, drawn once a process.
    private static var artCache: [String: Data] = [:]

    private struct Request {
        let now: Date?
        let defaults: UserDefaults
    }

    private static let rescheduler = CoalescingTask<Request> { request in
        await reschedule(now: request.now ?? Date(), defaults: request.defaults)
    }

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

    /// The day's notification id: `spendingReminder_2026-11-05` in the phone's calendar.
    static func identifier(for date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return identifierPrefix + String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// The anonymous RevenueCat attribute for this state (docs/plan-spending-reminder.md §3.7):
    /// `on`, `denied` (on, but iOS does not deliver), `off`, `declined`; nil while not asked.
    static func attributeValue(enabled: Bool, offer: OfferState, status: UNAuthorizationStatus) -> String? {
        if enabled { return status == .denied ? "denied" : "on" }
        switch offer {
        case .declined: return "declined"
        case .accepted: return "off"
        case .notAsked: return nil
        }
    }

    // MARK: - Events

    /// Tenra came to the front: the series starts over from today.
    static func noteAppOpened(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastReactionKey)
        requestReschedule(now: now, defaults: defaults)
    }

    /// Transactions were added (TransactionStore.onRecorded), in the app or in the background:
    /// a record by the person takes tonight's reminder away at once and gives tomorrow's its
    /// hook. Not a reaction: auto-capture alone never keeps the series going.
    static func noteRecorded(_ transactions: [Transaction], now: Date = Date(), defaults: UserDefaults = .standard) {
        guard transactions.contains(where: { SpendingReminderPlan.isUserRecord($0, now: now) }) else { return }
        // Before anything async: a background intent may be suspended right after it returns.
        center.remove([identifier(for: now)])
        defaults.set(now.timeIntervalSince1970, forKey: lastRecordedKey)
        if let hook = SpendingReminderPlan.hook(from: transactions, now: now) {
            defaults.set(hook.category, forKey: hookCategoryKey)
            defaults.set(hook.day, forKey: hookDayKey)
        }
        requestReschedule(now: now, defaults: defaults)
    }

    /// A recurring series was created (TransactionStore.onSeriesCreated): the person recorded
    /// something today even if its first payment is not due yet, so tonight's reminder goes.
    /// No hook: a series names no expense of the day.
    static func noteSeriesCreated(now: Date = Date(), defaults: UserDefaults = .standard) {
        center.remove([identifier(for: now)])
        defaults.set(now.timeIntervalSince1970, forKey: lastRecordedKey)
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
        requestReschedule(defaults: defaults)
    }

    /// The switch in Settings (and the offer's yes). Turning it on asks for full permission
    /// (from provisional too) and answers the offer. Returns once the series is replaced.
    static func setEnabled(_ on: Bool, defaults: UserDefaults = .standard) async {
        defaults.set(on, forKey: enabledKey)
        if on {
            if offerState(defaults: defaults) == .notAsked {
                defaults.set(OfferState.accepted.rawValue, forKey: offerKey)
            }
            await NotificationPermissionManager.shared.requestAuthorization()
        }
        requestReschedule(defaults: defaults)
        await waitUntilIdle()
    }

    // MARK: - Scheduling

    /// Replaces the series soon, after any replacement under way; `now` nil means the time it
    /// runs.
    static func requestReschedule(now: Date? = nil, defaults: UserDefaults = .standard) {
        rescheduler.request(Request(now: now, defaults: defaults))
    }

    static func waitUntilIdle() async {
        await rescheduler.waitUntilIdle()
    }

    /// Replaces the pending reminders with SpendingReminderPlan's series and keeps the
    /// RevenueCat attribute up to date. Nothing while off or without permission; a switch-off
    /// during the replacement stops it.
    static func reschedule(now: Date = Date(), defaults: UserDefaults = .standard) async {
        let stale = await center.pendingIdentifiers().filter { $0.hasPrefix(identifierPrefix) }
        center.remove(stale)

        let status = await center.authorizationStatus()
        syncAttribute(status: status, defaults: defaults)
        guard isEnabled(defaults: defaults), status == .authorized || status == .provisional else { return }

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

        for reminder in reminders {
            guard isEnabled(defaults: defaults) else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "spendingReminder.notification.title")
            content.body = body(for: reminder.phrase)
            content.threadIdentifier = "spendingReminder"
            content.sound = .default
            let isFarewell = if case .farewell = reminder.phrase { true } else { false }
            if let data = art(mood: isFarewell ? .idle : .happy),
               let attachment = TenNotificationArt.attachment(png: data) {
                content.attachments = [attachment]
            }
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let request = UNNotificationRequest(
                identifier: identifier(for: reminder.date),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            await center.add(request)
        }
    }

    static func resetArtCache() {
        artCache = [:]
    }

    private static func art(mood: ParticleCreature.Mood) -> Data? {
        let key = "\(mood)-\(UITraitCollection.current.userInterfaceStyle == .dark)"
        if let cached = artCache[key] { return cached }
        let data = drawArt(mood)
        if let data { artCache[key] = data }
        return data
    }

    private static func syncAttribute(status: UNAuthorizationStatus, defaults: UserDefaults) {
        guard let value = attributeValue(
            enabled: isEnabled(defaults: defaults),
            offer: offerState(defaults: defaults),
            status: status
        ), value != defaults.string(forKey: attributeKey) else { return }
        defaults.set(value, forKey: attributeKey)
        writeAttribute(value)
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
