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
        accountName: String,
        subscriptionName: String? = nil
    ) async {
        guard !guesses.isEmpty || subscriptionName != nil, await isAllowed() else { return }

        let merchant = payment.merchant.isEmpty
            ? "Apple Pay"
            : MerchantLogoStore.shared.customName(forDescription: payment.merchant) ?? MerchantName.displayName(payment.merchant)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "walletReview.notification.title")
        if let subscriptionName {
            content.body = String(format: String(localized: "walletReview.notification.subscription"), merchant, subscriptionName)
        } else if guesses.contains(.category) {
            let category = categoryName.isEmpty ? String(localized: "category.uncategorized") : categoryName
            content.body = String(format: String(localized: "walletReview.notification.category"), merchant, category)
        } else {
            content.body = String(format: String(localized: "walletReview.notification.account"), merchant, accountName)
        }
        await deliver(content, transactionId: transactionId)
    }

    /// An expense and an income of two banks Tenra takes for a transfer between the person's own
    /// accounts on the amount and the time alone (OwnTransferPairing): "Freedom → Kaspi.kz".
    static func notifyOwnTransfer(transactionId: String, from: String, to: String) async {
        guard await isAllowed() else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "walletReview.notification.title")
        content.body = String(format: String(localized: "walletReview.notification.ownTransfer"), from, to)
        await deliver(content, transactionId: transactionId)
    }

    private static func isAllowed() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    private static func deliver(_ content: UNMutableNotificationContent, transactionId: String) async {
        content.threadIdentifier = "walletReview"
        let request = UNNotificationRequest(
            identifier: identifierPrefix + transactionId,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Takes a reviewed payment's notification out of Notification Center: a tap on it would
    /// only open a list it has left.
    static func removeDelivered(transactionId: String) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [identifierPrefix + transactionId])
    }
}
