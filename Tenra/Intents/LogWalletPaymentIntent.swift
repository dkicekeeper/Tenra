//
//  LogWalletPaymentIntent.swift
//  Tenra
//
//  The action for the Shortcuts "Wallet" automation (When I tap any card →
//  "Log an Apple Pay payment"): records the payment silently, with its merchant,
//  card and currency. Nothing is asked: what Tenra could not know is saved as a
//  guess and listed under To review (WalletPaymentRecorder, WalletCaptureStore).
//
//  The amount and the currency code are separate parameters because Wallet nests
//  the code inside its Amount: the automation saves Amount to a variable and passes
//  that variable's number and Currency Code (docs/plan-auto-capture.md §8).
//
//  AddExpenseIntent stays as it is, for automations set up before this action.
//

import AppIntents
import SwiftUI

struct LogWalletPaymentIntent: AppIntent {

    static var title: LocalizedStringResource = "intent.walletPayment.title"
    static var description = IntentDescription("intent.walletPayment.description")

    /// Never brought to the foreground: an automation runs while the phone is in a pocket.
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "intent.walletPayment.parameter.amount")
    var amount: Double

    @Parameter(title: "intent.walletPayment.parameter.currency")
    var currencyCode: String?

    @Parameter(title: "intent.walletPayment.parameter.merchant")
    var merchant: String?

    @Parameter(title: "intent.walletPayment.parameter.card")
    var card: String?

    @Parameter(title: "intent.walletPayment.parameter.account")
    var account: AccountAppEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = try await IntentEnvironment.shared.services()

        // Payments that waited for an exchange rate go first, so the history keeps its order.
        await WalletPaymentRecorder.recordPending(services: services)

        let payment = WalletPayment(
            id: UUID().uuidString,
            amount: amount,
            currencyCode: WalletPaymentResolver.currencyCode(currencyCode),
            merchant: (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            card: (card ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            accountId: account?.id,
            date: Date()
        )

        switch try await WalletPaymentRecorder.record(payment, services: services) {
        case .saved(let amount, let currency, let categoryName):
            let text = String(
                format: String(localized: "intent.addExpense.saved"),
                Formatting.formatCurrencySmart(amount, currency: currency),
                categoryName.isEmpty ? String(localized: "category.uncategorized") : categoryName
            )
            return .result(dialog: IntentDialog(stringLiteral: text))
        case .duplicate:
            return .result(dialog: "intent.walletPayment.duplicate")
        case .noAmount:
            return .result(dialog: "intent.walletPayment.noAmount")
        case .queued:
            return .result(dialog: "intent.walletPayment.queued")
        case .noAccount:
            return .result(dialog: "intent.walletPayment.noAccount")
        }
    }
}
