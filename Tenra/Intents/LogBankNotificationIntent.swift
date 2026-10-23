//
//  LogBankNotificationIntent.swift
//  Tenra
//
//  The action for the iOS 27 notification automation (When I get a notification from
//  a bank's app → "Log a bank notification"): reads the operation out of the
//  notification (BankNotificationParser, bank-agnostic) and records an expense or an
//  income silently, through the Wallet action's path (WalletPaymentRecorder: currency,
//  queue, To review, the merchant and card memories). The bank's app plus the card's
//  last digits is the "card" whose account Tenra remembers.
//
//  A transfer between the user's own accounts reaches each bank's notification as one side:
//  the side waits in WalletCaptureStore until the other bank's arrives, and the pair becomes
//  one transfer (OwnTransferRecorder). A cash withdrawal is not recorded. Plan:
//  docs/plan-notification-capture.md.
//

import AppIntents
import SwiftUI

struct LogBankNotificationIntent: AppIntent {

    static var title: LocalizedStringResource = "intent.bankNotification.title"
    static var description = IntentDescription("intent.bankNotification.description")

    /// Never brought to the foreground: an automation runs while the phone is in a pocket.
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "intent.bankNotification.parameter.title")
    var notificationTitle: String?

    @Parameter(title: "intent.bankNotification.parameter.subtitle")
    var subtitle: String?

    @Parameter(title: "intent.bankNotification.parameter.text")
    var text: String?

    @Parameter(title: "intent.bankNotification.parameter.app")
    var app: String?

    @Parameter(title: "intent.bankNotification.parameter.date")
    var date: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The notification's own time; the moment the action starts when it has none.
        let when = date ?? Date()
        guard let operation = BankNotificationParser.parse(
            title: notificationTitle ?? "",
            subtitle: subtitle ?? "",
            body: text ?? ""
        ) else {
            return .result(dialog: "intent.bankNotification.notOperation")
        }
        let bank = (app ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch operation.kind {
        case .ownTransfer:
            WalletCaptureStore.shared.enqueueTransferSide(OwnTransferMatcher.Side(
                id: UUID().uuidString,
                card: BankNotificationParser.cardName(app: bank, digits: operation.cardDigits),
                amount: operation.amount,
                currency: operation.currencyCode,
                isIncoming: operation.isIncoming,
                date: when
            ))
            // The other bank's side may be here already: a pair becomes a transfer at once.
            let services = try await IntentEnvironment.shared.services()
            await OwnTransferRecorder.recordPairs(services: services)
            return .result(dialog: "intent.bankNotification.ownTransfer")
        case .cashWithdrawal:
            return .result(dialog: "intent.bankNotification.cash")
        case .expense, .income:
            break
        }

        let services = try await IntentEnvironment.shared.services()
        // Payments that waited for an exchange rate go first, so the history keeps its order.
        await WalletPaymentRecorder.recordPending(services: services)

        let payment = WalletPayment(
            id: UUID().uuidString,
            amount: operation.amount,
            currencyCode: operation.currencyCode,
            merchant: operation.counterparty,
            card: BankNotificationParser.cardName(app: bank, digits: operation.cardDigits),
            accountId: nil,
            date: when,
            bankApp: bank,
            isIncome: operation.kind == .income
        )

        switch try await WalletPaymentRecorder.record(payment, services: services) {
        case .saved(let amount, let currency, let categoryName):
            let message = String(
                format: String(localized: "intent.addExpense.saved"),
                Formatting.formatCurrencySmart(amount, currency: currency),
                categoryName.isEmpty ? String(localized: "category.uncategorized") : categoryName
            )
            return .result(dialog: IntentDialog(stringLiteral: message))
        case .duplicate:
            return .result(dialog: "intent.walletPayment.duplicate")
        case .subscription(let name):
            let message = String(format: String(localized: "intent.walletPayment.subscription"), name)
            return .result(dialog: IntentDialog(stringLiteral: message))
        case .noAmount:
            return .result(dialog: "intent.bankNotification.notOperation")
        case .queued:
            return .result(dialog: "intent.walletPayment.queued")
        case .noAccount:
            return .result(dialog: "intent.walletPayment.noAccount")
        }
    }
}
