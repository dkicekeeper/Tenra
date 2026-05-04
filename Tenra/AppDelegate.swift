//
//  AppDelegate.swift
//  Tenra
//
//  Created on 2026-02-14
//  Purpose: Handle notification delegation and automatic rescheduling
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        CoreDataStack.shared.preWarm()

        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self


        // Note: applicationDidBecomeActive fires naturally after launch completes —
        // no need to post it manually here (it fired before TransactionStore existed).

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {

        // Clear any badge left over from delivered subscription notifications.
        UNUserNotificationCenter.current().setBadgeCount(0)

        // Also drop already-delivered notifications from the lock screen / NC so
        // their badge counts don't re-add when iOS re-applies the badge.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        // Post notification to reschedule all subscriptions
        NotificationCenter.default.post(name: .applicationDidBecomeActive, object: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when a notification is delivered while the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {

        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Called when user taps on a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier


        // Parse notification ID: "subscription_{seriesId}_{offsetDays}"
        if identifier.hasPrefix("subscription_") {
            let components = identifier.components(separatedBy: "_")
            if components.count >= 3 {
                let seriesId = components[1]

                // Cold-launch path: coordinator may not exist yet — stash for init().
                // Warm-launch path: post a Notification so MainTabView.onReceive
                // can switch tabs and set the live coordinator's pending id.
                AppCoordinator.pendingDeepLinkSeriesIdOnLaunch = seriesId
                NotificationCenter.default.post(
                    name: .subscriptionNotificationTapped,
                    object: nil,
                    userInfo: ["seriesId": seriesId]
                )
            }
        }

        completionHandler()
    }
}
