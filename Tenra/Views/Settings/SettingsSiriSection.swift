//
//  SettingsSiriSection.swift
//  Tenra
//
//  Settings → Siri & Shortcuts: the way into the Shortcuts Wallet automation, a step-by-step
//  guide to setting it up (WalletSetupGuideView), and on iOS 27 the bank notification
//  automation's (BankNotificationGuideView). What the automation keeps (To review, the
//  merchants, the cards) is in the Wallet section under this one.
//

import SwiftUI

struct SettingsSiriSection: View {
    var body: some View {
        FormSection(header: String(localized: "settings.siri.header"), footer: String(localized: "settings.siri.footer")) {
            UniversalRow(
                String(localized: "walletSetup.title"),
                icon: "wallet.pass",
                accessory: .navigation { WalletSetupGuideView() }
            )
            // The notification trigger exists from iOS 27 (docs/domains/intents.md §7).
            if BankNotificationGuideView.isAvailable {
                UniversalRow(
                    String(localized: "bankSetup.title"),
                    icon: "bell.badge",
                    accessory: .navigation { BankNotificationGuideView() }
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            SettingsSiriSection()
        }
    }
}
