//
//  Notification+Extensions.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Notification names for app-wide events

import Foundation

extension Notification.Name {
    
    // MARK: - Recurring Series Events
    
    /// Posted when a NEW recurring series is created
    /// UserInfo keys:
    /// - "seriesId": String - ID of the new series
    static let recurringSeriesCreated = Notification.Name("recurringSeriesCreated")
    
    /// Posted when a recurring series is changed in a way that requires regenerating transactions
    /// UserInfo keys:
    /// - "seriesId": String - ID of the changed series
    /// - "oldSeries": RecurringSeries - Previous version of the series (optional)
    static let recurringSeriesChanged = Notification.Name("recurringSeriesChanged")
    
    /// Posted when a recurring series is deleted
    /// UserInfo keys:
    /// - "seriesId": String - ID of the deleted series
    static let recurringSeriesDeleted = Notification.Name("recurringSeriesDeleted")
    
    // MARK: - Account Events
    
    /// Posted when account balances are recalculated
    /// UserInfo keys:
    /// - "accountIds": [String] - IDs of affected accounts
    static let accountBalancesRecalculated = Notification.Name("accountBalancesRecalculated")
    
    /// Posted when an account is deleted
    /// UserInfo keys:
    /// - "accountId": String - ID of the deleted account
    static let accountDeleted = Notification.Name("accountDeleted")
    
    // MARK: - Transaction Events
    
    /// Posted when transactions are imported in batch
    /// UserInfo keys:
    /// - "count": Int - Number of imported transactions
    static let transactionsBatchImported = Notification.Name("transactionsBatchImported")
    
    /// Posted when a large data operation completes
    /// UserInfo keys:
    /// - "operation": String - Name of the operation
    /// - "duration": TimeInterval - Duration in seconds
    static let dataOperationCompleted = Notification.Name("dataOperationCompleted")

    // MARK: - Subscription Notification Events

    /// Posted when user taps on a subscription notification
    /// UserInfo keys:
    /// - "seriesId": String - ID of the subscription
    static let subscriptionNotificationTapped = Notification.Name("subscriptionNotificationTapped")

    // MARK: - Application Lifecycle Events

    /// Posted when application becomes active (for notification rescheduling)
    static let applicationDidBecomeActive = Notification.Name("applicationDidBecomeActive")
}
