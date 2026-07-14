//
//  WeeklyDigestScheduler.swift
//  Tenra
//
//  Insights product audit 2026-07 — Phase D.
//  Schedules the Monday-09:00 "weekly summary" local notification — the single
//  most-liked analytical push across benchmark apps (Copilot: Monday, Apple
//  Card: Sunday). Local-notifications-only constraint: content is computed from
//  the LAST insights recompute and re-scheduled on every recompute, so the body
//  names the week it covers (a stale digest reads as "week of 3–9 July", never
//  as silently wrong numbers).
//

import Foundation
import UserNotifications
import os

@MainActor
final class WeeklyDigestScheduler {
    static let shared = WeeklyDigestScheduler()

    private static let logger = Logger(subsystem: "Tenra", category: "WeeklyDigestScheduler")

    /// Reuses the insight-signal prefix so a tap deep-links to the Analytics tab.
    static let notificationId = InsightSignalService.notificationIdPrefix + "weekly_digest"

    private let settings: InsightSignalSettings

    init(settings: InsightSignalSettings = .shared) {
        self.settings = settings
    }

    /// Builds the digest body from weekly period points. Exposed for tests.
    /// Returns nil when the current week has no realized expenses (an empty
    /// digest is noise, not ritual).
    nonisolated static func digestBody(weekPoints: [PeriodDataPoint], baseCurrency: String) -> String? {
        let currentKey = InsightGranularity.week.currentPeriodKey
        guard let current = weekPoints.last(where: { $0.key == currentKey }) ?? weekPoints.last,
              current.expenses > 0 else { return nil }

        let weekLabel = InsightGranularity.week.headingLabel(for: current.key)
        let expensesText = Formatting.formatCurrencySmart(current.expenses, currency: baseCurrency)

        // Previous week for the comparison clause.
        if let idx = weekPoints.firstIndex(where: { $0.id == current.id }), idx > 0 {
            let previous = weekPoints[idx - 1]
            if previous.expenses > 0 {
                let pct = ((current.expenses - previous.expenses) / previous.expenses) * 100
                return String(
                    format: String(localized: "notification.weeklyDigest.body.withComparison"),
                    weekLabel, expensesText, String(format: "%+.0f%%", pct)
                )
            }
        }
        return String(
            format: String(localized: "notification.weeklyDigest.body.simple"),
            weekLabel, expensesText
        )
    }

    /// Re-schedules the digest for the next Monday 09:00 with fresh content.
    /// Called after every insights recompute; safe to call repeatedly.
    func reschedule(weekPoints: [PeriodDataPoint], baseCurrency: String, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()

        guard settings.isEnabled, settings.weeklyDigestEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
            return
        }
        let auth = await center.notificationSettings().authorizationStatus
        guard auth == .authorized || auth == .provisional else { return }

        guard let body = Self.digestBody(weekPoints: weekPoints, baseCurrency: baseCurrency) else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
            return
        }

        // Next Monday 09:00 local time (strictly after now).
        var target = DateComponents()
        target.weekday = 2 // Monday
        target.hour = 9
        target.minute = 0
        guard let fireDate = Calendar.current.nextDate(
            after: now, matching: target, matchingPolicy: .nextTime
        ) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.weeklyDigest.title")
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: trigger)

        // Replace the pending digest (same identifier overwrites).
        do {
            try await center.add(request)
            Self.logger.debug("📬 [Digest] scheduled for \(fireDate, privacy: .public): \(body, privacy: .public)")
        } catch {
            Self.logger.warning("📬 [Digest] scheduling failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Immediately removes the pending digest (settings toggle turned off).
    func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
    }
}
