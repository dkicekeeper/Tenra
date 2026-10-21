//
//  WalletSetupGuideView.swift
//  Tenra
//
//  How to set up the Shortcuts Wallet automation with "Log an Apple Pay payment"
//  (LogWalletPaymentIntent, docs/plan-auto-capture.md §8). Settings → Siri & Shortcuts.
//
//  Shortcuts' own labels are named only where the owner's screenshot confirmed them in Russian
//  ("Транзакция", its "Продавец", "Любая категория", "Любой продавец", "Показать при запуске";
//  2026-10-20); the rest is described. Tenra's action and field names come from the intent's
//  own strings, so the guide always matches what Shortcuts shows for them.
//

import SwiftUI

struct WalletSetupGuideView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            ArticleBody(blocks)
                .screenPadding()
                .padding(.vertical, AppSpacing.md)
        }
        // The article scrolls under the button with the soft edge (design-system.md §4).
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .safeAreaBar(edge: .bottom) {
            DSButton(String(localized: "walletSetup.openShortcuts"), fullWidth: true) {
                if let url = URL(string: "shortcuts://") { openURL(url) }
            }
            .screenPadding()
            .padding(.bottom, AppSpacing.md)
        }
        .navigationTitle(String(localized: "walletSetup.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var blocks: [ArticleBody.Block] {
        let action = String(localized: "intent.walletPayment.title")
        let amount = String(localized: "intent.walletPayment.parameter.amount")
        let merchant = String(localized: "intent.walletPayment.parameter.merchant")
        let card = String(localized: "intent.walletPayment.parameter.card")
        let account = String(localized: "intent.walletPayment.parameter.account")
        let currency = String(localized: "intent.walletPayment.parameter.currency")
        let oldAction = String(localized: "intent.addExpense.title")

        let triggerSteps: [String] = [
            String(localized: "walletSetup.step.open"),
            String(localized: "walletSetup.step.cards"),
            String(format: String(localized: "walletSetup.step.action"), action)
        ]
        let fieldSteps: [String] = [
            String(format: String(localized: "walletSetup.step.amount"), amount),
            String(format: String(localized: "walletSetup.step.merchant"), merchant),
            String(format: String(localized: "walletSetup.step.card"), card),
            String(format: String(localized: "walletSetup.step.account"), account),
            String(localized: "walletSetup.step.quiet")
        ]
        let currencyText = String(format: String(localized: "walletSetup.currency.text"), currency)
        let note = String(format: String(localized: "walletSetup.note.oldAction"), oldAction, action)

        var blocks: [ArticleBody.Block] = [.paragraph(String(localized: "walletSetup.intro"))]
        blocks.append(.heading(String(localized: "walletSetup.trigger"), level: 2))
        blocks.append(.steps(triggerSteps))
        blocks.append(.heading(String(localized: "walletSetup.fields"), level: 2))
        blocks.append(.steps(fieldSteps))
        blocks.append(.heading(String(localized: "walletSetup.currency"), level: 2))
        blocks.append(.paragraph(currencyText))
        blocks.append(.note(note))
        return blocks
    }
}

#Preview {
    NavigationStack {
        WalletSetupGuideView()
    }
}
