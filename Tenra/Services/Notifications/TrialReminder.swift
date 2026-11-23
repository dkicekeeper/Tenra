//
//  TrialReminder.swift
//  Tenra
//
//  The reminder two days before a Tenra Pro trial ends (docs/promotion-plan.md §6, 2026-11-23):
//  every trial of November had its renewal turned off, most on the second day, which reads as
//  fear of a charge nobody warns about. The paywall promises this reminder. It comes two calendar
//  days before the trial's last day at 10:00 and says what happens next: the subscription and its
//  price, or, with renewal off, that Pro closes and the records stay. Its words hold even when
//  renewal is turned off in iOS Settings after it was scheduled ("unless you cancel it").
//
//  PremiumManager reschedules it whenever the entitlement changes; after a trial starts on the
//  paywall Tenra asks for banners first (`afterPurchase`), since the quiet delivery every
//  onboarded person has would only reach Notification Center. Sent only when allowed.
//

import Foundation
import StoreKit
import UserNotifications

@MainActor
enum TrialReminder {

    static let identifier = "trialReminder"
    /// Calendar days between the reminder and the trial's last day.
    nonisolated static let daysBefore = 2
    /// Local hour the reminder comes at.
    nonisolated static let hour = 10

    /// What the reminder says after its title.
    enum Message: Equatable {
        /// Renewal is on: the subscription that starts, at the App Store's price when known.
        case renews(ProStatus.Plan, price: String?)
        /// Renewal is off: no charge, Pro closes, the records stay.
        case cancelled
    }

    /// When the reminder comes for a trial ending at `expiration`: `daysBefore` calendar days
    /// before its last day, at `hour`. Nil when that moment has passed.
    nonisolated static func reminderDate(expiration: Date, now: Date, calendar: Calendar = .current) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: calendar.startOfDay(for: expiration)),
              let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
              date > now else { return nil }
        return date
    }

    /// The reminder's body.
    static func body(_ message: Message) -> String {
        switch message {
        case .cancelled:
            return String(localized: "trialReminder.body.cancelled")
        case .renews(.annual, let price?):
            return String(format: String(localized: "trialReminder.body.annual"), price)
        case .renews(.monthly, let price?):
            return String(format: String(localized: "trialReminder.body.monthly"), price)
        case .renews:
            return String(localized: "trialReminder.body.noPrice")
        }
    }

    /// Replaces the pending reminder with the one `status` calls for: a trial gets one, anything
    /// else (no Pro, a paid period, lifetime) none.
    static func reschedule(for status: ProStatus?, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let status, status.isTrial, let expiration = status.expirationDate,
              let date = reminderDate(expiration: expiration, now: now) else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let message: Message = status.willRenew
            ? .renews(status.plan, price: await displayPrice(for: status.plan))
            : .cancelled
        let content = UNMutableNotificationContent()
        content.title = String(localized: "trialReminder.title")
        content.body = body(message)
        content.threadIdentifier = identifier
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    /// A trial was started on the paywall: Tenra asks for banners when it has only quiet
    /// notifications or none yet (the system prompt, once a session), then schedules. Nothing
    /// for a paid purchase or lifetime.
    static func afterPurchase(_ status: ProStatus?) async {
        guard let status, status.isTrial else { return }
        let permission = NotificationPermissionManager.shared
        await permission.checkAuthorizationStatus()
        if permission.shouldRequestPermission {
            await permission.requestAuthorization()
        }
        await reschedule(for: status)
    }

    /// The plan's price as the App Store formats it for this storefront; nil when unknown.
    private static func displayPrice(for plan: ProStatus.Plan) async -> String? {
        let productID: String
        switch plan {
        case .annual: productID = PremiumConfig.Product.annual
        case .monthly: productID = PremiumConfig.Product.monthly
        case .lifetime, .unknown: return nil
        }
        return try? await StoreKit.Product.products(for: [productID]).first?.displayPrice
    }
}
