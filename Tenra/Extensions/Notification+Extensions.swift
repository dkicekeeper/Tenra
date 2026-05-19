//
//  Notification+Extensions.swift
//  Tenra
//
//  Notification names for app-wide events.
//

import Foundation

extension Notification.Name {

    // MARK: - Recurring Series Events
    //
    // ⚠️ Currently observed by TransactionsViewModel but never posted —
    //    the post side of the flow appears to be missing.

    /// Posted when a NEW recurring series is created.
    /// UserInfo: `seriesId: String`.
    static let recurringSeriesCreated = Notification.Name("recurringSeriesCreated")

    /// Posted when a recurring series is changed in a way that requires regenerating transactions.
    /// UserInfo: `seriesId: String`, optional `oldSeries: RecurringSeries`.
    static let recurringSeriesChanged = Notification.Name("recurringSeriesChanged")

    // MARK: - Subscription Notification Events

    /// Posted when user taps on a subscription notification.
    /// UserInfo: `seriesId: String`.
    static let subscriptionNotificationTapped = Notification.Name("subscriptionNotificationTapped")

    // MARK: - Application Lifecycle Events

    /// Posted when application becomes active (for notification rescheduling).
    static let applicationDidBecomeActive = Notification.Name("applicationDidBecomeActive")
}
