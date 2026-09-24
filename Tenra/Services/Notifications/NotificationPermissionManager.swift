//
//  NotificationPermissionManager.swift
//  Tenra
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

    /// Pure policy, pinned by `ProvisionalNotificationPolicyTests`: ask for provisional
    /// authorization only while the user has not decided AND something that needs
    /// notifications is switched on (the weekly digest and insight signals default ON).
    nonisolated static func shouldRequestProvisional(
        status: UNAuthorizationStatus,
        signalsEnabled: Bool,
        digestEnabled: Bool
    ) -> Bool {
        status == .notDetermined && (signalsEnabled || digestEnabled)
    }

    /// Requests `.provisional` authorization (no system prompt) when the policy allows.
    ///
    /// Without it the default-ON weekly digest and insight signals never arrived: both
    /// senders skip unless authorized, and a full request only happened when the user
    /// toggled the setting or saved a subscription reminder. Provisional notifications
    /// are delivered quietly to Notification Center with Keep / Turn Off buttons; a later
    /// full request (e.g. subscription reminders) still upgrades to banners.
    func requestProvisionalIfUndetermined() async {
        await checkAuthorizationStatus()
        let settings = InsightSignalSettings.shared
        guard Self.shouldRequestProvisional(
            status: authorizationStatus,
            signalsEnabled: settings.isEnabled,
            digestEnabled: settings.weeklyDigestEnabled
        ) else { return }

        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge, .provisional])
        } catch {
            return
        }
        await checkAuthorizationStatus()
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
