//
//  StatementImportReminder.swift
//  Tenra
//
//  "Time for a bank statement" (docs/plan-auto-capture.md §6): transfers, QR and online
//  payments reach Tenra only with a statement, since Wallet sees taps at a terminal only. Once
//  a statement was imported, Tenra reminds the person after the chosen interval without another
//  (every week by default, Settings → Export and import; the owner's decision of 2026-10-20).
//  Every statement import moves the reminders; the next few are scheduled ahead, so they come
//  even when Tenra is not opened. None before the first statement import, so a person who never
//  imports is not reminded. Sent only when notifications are allowed; this never asks.
//

import Foundation
import UserNotifications

@MainActor
enum StatementImportReminder {

    static let identifierPrefix = "importReminder_"
    /// Days between reminders, 0 = off: `@AppStorage` in the Settings row.
    nonisolated static let intervalKey = "settings.importReminderDays"
    nonisolated static let defaultIntervalDays = 7
    /// The Settings choices: off, every week, every 2 weeks, every month.
    nonisolated static let intervalChoices = [0, 7, 14, 30]
    /// Reminders scheduled ahead of the next app launch.
    nonisolated static let scheduledAhead = 3
    /// Local hour a reminder comes at.
    nonisolated static let hour = 10

    private static let lastImportKey = "importReminder.lastImport"

    static func intervalDays(defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: intervalKey) == nil ? defaultIntervalDays : defaults.integer(forKey: intervalKey)
    }

    /// A statement was imported: the reminders start over from today.
    static func recordImport(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastImportKey)
        Task { await reschedule(now: now, defaults: defaults) }
    }

    /// Replaces the pending reminders with the next `scheduledAhead` ones. Called after an
    /// import, when the interval changes and when Tenra comes to the front.
    static func reschedule(now: Date = Date(), defaults: UserDefaults = .standard) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let dates = reminderDates(
            lastImport: defaults.object(forKey: lastImportKey) as? Date,
            intervalDays: intervalDays(defaults: defaults),
            now: now,
            count: scheduledAhead
        )
        guard !dates.isEmpty else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "importReminder.notification.title")
            content.body = String(localized: "importReminder.notification.body")
            content.threadIdentifier = "importReminder"
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + String(index),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// The reminders after the last import: every `intervalDays` days from its day, at `hour`,
    /// the first `count` still ahead of `now`. None when off or never imported.
    nonisolated static func reminderDates(
        lastImport: Date?,
        intervalDays: Int,
        now: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard let lastImport, intervalDays > 0, count > 0 else { return [] }
        let startDay = calendar.startOfDay(for: lastImport)
        // Skip the intervals already behind `now` without walking them one by one.
        let elapsedDays = calendar.dateComponents([.day], from: startDay, to: now).day ?? 0
        var step = max(1, elapsedDays / intervalDays)
        var dates: [Date] = []
        while dates.count < count {
            guard let day = calendar.date(byAdding: .day, value: intervalDays * step, to: startDay),
                  let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { break }
            if date > now { dates.append(date) }
            step += 1
        }
        return dates
    }
}
