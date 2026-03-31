//
//  AppDelegate.swift
//  AIFinanceManager
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


                // TODO: Navigate to subscription detail view
                // This could be implemented using deep linking or NotificationCenter
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
