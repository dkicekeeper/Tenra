//
//  NotificationPermissionManager.swift
//  AIFinanceManager
//
//  Created on 2026-02-14
//  Purpose: Manage notification permissions and authorization status
//

import Foundation
import UserNotifications
import UIKit

@MainActor
@Observable
class NotificationPermissionManager {
    static let shared = NotificationPermissionManager()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var hasRequestedPermission: Bool = false

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus

    }

    /// Request notification authorization
    /// - Returns: true if granted, false otherwise
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            hasRequestedPermission = true
            await checkAuthorizationStatus()


            return granted
        } catch {
            return false
        }
    }

    /// Check if we should request permission (only once per install)
    var shouldRequestPermission: Bool {
        return authorizationStatus == .notDetermined && !hasRequestedPermission
    }

    /// Check if notifications are enabled
    var areNotificationsEnabled: Bool {
        return authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    /// Get user-friendly status description
    private func statusDescription(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    /// Open app settings (for when user denied permissions)
    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
