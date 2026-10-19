//
//  WalletReviewNotifier.swift
//  Tenra
//
//  "Check a payment": the local notification for an Apple Pay payment that
//  LogWalletPaymentIntent saved with a guessed category or account
//  (docs/plan-auto-capture.md §3, decision 3). A tap opens the To review list
//  (AppDelegate → WalletCaptureStore.isReviewRequested → MainTabView).
//
//  One per merchant: a later payment at a merchant already waiting in To review
//  adds no new notification. Sent only when notifications are allowed; the
//  intent never asks for the permission. No amount in the text: it shows on the
//  lock screen.
//

import Foundation
import UserNotifications

@MainActor
enum WalletReviewNotifier {

    static let identifierPrefix = "walletReview_"

    static func notify(
        transactionId: String,
        payment: WalletPayment,
        guesses: Set<WalletCaptureStore.Guess>,
        categoryName: String,
        accountName: String
    ) async {
        guard !guesses.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let merchant = payment.merchant.isEmpty ? "Apple Pay" : MerchantName.displayName(payment.merchant)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "walletReview.notification.title")
        if guesses.contains(.category) {
            let category = categoryName.isEmpty ? String(localized: "category.uncategorized") : categoryName
            content.body = String(format: String(localized: "walletReview.notification.category"), merchant, category)
        } else {
            content.body = String(format: String(localized: "walletReview.notification.account"), merchant, accountName)
        }
        content.threadIdentifier = "walletReview"

        let request = UNNotificationRequest(
            identifier: identifierPrefix + transactionId,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
