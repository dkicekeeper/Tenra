//
//  SpendingReminderCenter.swift
//  Tenra
//
//  What SpendingReminder needs from the notification center, as a protocol so its tests can
//  watch what it schedules (SpendingReminderSchedulingTests). The app uses the system's.
//

import Foundation
import UserNotifications

@MainActor
protocol SpendingReminderCenter: AnyObject {
    func pendingIdentifiers() async -> [String]
    /// Synchronous on purpose: a record removes tonight's reminder before anything can suspend.
    func remove(_ identifiers: [String])
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async
}

final class SystemSpendingReminderCenter: SpendingReminderCenter {
    private var center: UNUserNotificationCenter { .current() }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func remove(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func add(_ request: UNNotificationRequest) async {
        try? await center.add(request)
    }
}
