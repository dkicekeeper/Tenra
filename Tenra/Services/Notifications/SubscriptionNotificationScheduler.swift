//
//  SubscriptionNotificationScheduler.swift
//  Tenra
//
//  Created on 2024
//

import Foundation
import UserNotifications

@MainActor
class SubscriptionNotificationScheduler {
    static let shared = SubscriptionNotificationScheduler()
    
    private init() {}
    
    /// ID scheme: "subscription_\(seriesId)_\(offsetDays)"
    private func notificationId(for seriesId: String, offsetDays: Int) -> String {
        return "subscription_\(seriesId)_\(offsetDays)"
    }
    
    /// Request notification permissions
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }
    
    /// Schedule notifications for a subscription
    func scheduleNotifications(for series: RecurringSeries, nextChargeDate: Date) async {
        guard series.isSubscription,
              series.subscriptionStatus == .active,
              let reminderOffsets = series.reminderOffsets,
              !reminderOffsets.isEmpty else {
            return
        }

        // Check notification permissions
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        // First, cancel existing notifications for this subscription
        await cancelNotifications(for: series.id)
        
        let calendar = Calendar.current
        let center = UNUserNotificationCenter.current()
        
        // Format amount and currency
        let amountString = Formatting.formatCurrency(
            NSDecimalNumber(decimal: series.amount).doubleValue,
            currency: series.currency
        )
        
        // Create notifications for each reminder offset
        var requests: [UNNotificationRequest] = []
        for offsetDays in reminderOffsets {
            guard offsetDays > 0 else { continue }
            
            // Calculate notification date: nextChargeDate - offsetDays at 09:00 local time.
            // nextChargeDate is normalized to startOfDay (00:00); without overriding hour/minute
            // here the notification would fire at midnight.
            guard let dayDate = calendar.date(byAdding: .day, value: -offsetDays, to: nextChargeDate),
                  let notificationDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayDate),
                  notificationDate > Date() else {
                // Skip if notification date is in the past
                continue
            }

            // Create date components for the notification
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            // Create notification content
            let content = UNMutableNotificationContent()
            content.title = String(localized: "notification.subscription.reminderTitle")
            content.body = String(localized: "notification.subscription.reminderBody \(series.description) \(amountString) \(offsetDays)")
            content.sound = .default
            content.badge = NSNumber(value: 1)
            
            // Create notification request
            let identifier = notificationId(for: series.id, offsetDays: offsetDays)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            requests.append(request)
        }
        
        // Add all notifications
        var successCount = 0
        var failureCount = 0

        for request in requests {
            do {
                try await center.add(request)
                successCount += 1
            } catch {
                failureCount += 1
            }
        }

    }
    
    /// Cancel all notifications for a subscription
    func cancelNotifications(for seriesId: String) async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        
        // Find all notification IDs that match this subscription
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix("subscription_\(seriesId)_") }
            .map { $0.identifier }
        
        if !identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        }
    }
    
    /// Cancel all subscription notifications (cleanup)
    func cancelAllSubscriptionNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix("subscription_") }
            .map { $0.identifier }
        
        if !identifiersToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        }
    }
    
    /// Reschedule notifications for all active subscriptions
    /// This should be called when app becomes active or after a notification is delivered
    func rescheduleAllActiveSubscriptions(subscriptions: [RecurringSeries]) async {

        var rescheduledCount = 0

        for subscription in subscriptions {
            guard subscription.isSubscription,
                  subscription.subscriptionStatus == .active,
                  let reminderOffsets = subscription.reminderOffsets,
                  !reminderOffsets.isEmpty else {
                continue
            }

            if let nextChargeDate = calculateNextChargeDate(for: subscription) {
                await scheduleNotifications(for: subscription, nextChargeDate: nextChargeDate)
                rescheduledCount += 1
            }
        }

    }

    /// Calculate next charge date for a subscription
    /// This method properly calculates the next occurrence based on startDate and frequency
    func calculateNextChargeDate(for series: RecurringSeries) -> Date? {
        guard series.isSubscription,
              series.subscriptionStatus == .active else {
            return nil
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateFormatter = DateFormatters.dateFormatter

        guard let startDate = dateFormatter.date(from: series.startDate) else {
            return nil
        }

        let normalizedStartDate = calendar.startOfDay(for: startDate)

        // If startDate is in the future, return it
        if normalizedStartDate > today {
            return normalizedStartDate
        }

        // Calculate how many periods have passed since startDate
        var nextDate = normalizedStartDate

        switch series.frequency {
        case .daily:
            // Calculate days between start and today
            let daysPassed = calendar.dateComponents([.day], from: normalizedStartDate, to: today).day ?? 0
            // Next charge is (daysPassed + 1) days from start
            if let date = calendar.date(byAdding: .day, value: daysPassed + 1, to: normalizedStartDate) {
                nextDate = date
            }

        case .weekly:
            // Calculate weeks between start and today
            let weeksPassed = calendar.dateComponents([.weekOfYear], from: normalizedStartDate, to: today).weekOfYear ?? 0
            // Next charge is (weeksPassed + 1) weeks from start
            if let date = calendar.date(byAdding: .weekOfYear, value: weeksPassed + 1, to: normalizedStartDate) {
                nextDate = date
            }

        case .monthly:
            // Calculate months between start and today
            let monthsPassed = calendar.dateComponents([.month], from: normalizedStartDate, to: today).month ?? 0
            // Next charge is (monthsPassed + 1) months from start
            if let date = calendar.date(byAdding: .month, value: monthsPassed + 1, to: normalizedStartDate) {
                nextDate = date
            }

        case .quarterly:
            let monthsPassed = calendar.dateComponents([.month], from: normalizedStartDate, to: today).month ?? 0
            let quartersPassed = monthsPassed / 3
            if let date = calendar.date(byAdding: .month, value: (quartersPassed + 1) * 3, to: normalizedStartDate) {
                nextDate = date
            }

        case .yearly:
            // Calculate years between start and today
            let yearsPassed = calendar.dateComponents([.year], from: normalizedStartDate, to: today).year ?? 0
            // Next charge is (yearsPassed + 1) years from start
            if let date = calendar.date(byAdding: .year, value: yearsPassed + 1, to: normalizedStartDate) {
                nextDate = date
            }
        }


        return nextDate
    }
}
