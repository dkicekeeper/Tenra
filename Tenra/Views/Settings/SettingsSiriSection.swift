//
//  SettingsSiriSection.swift
//  Tenra
//
//  Settings → Siri & Shortcuts: the way into the Shortcuts Wallet automation, a step-by-step
//  guide to setting it up (WalletSetupGuideView). What the automation keeps (To review, the
//  merchants, the cards) is in the Wallet section under this one.
//

import SwiftUI

struct SettingsSiriSection: View {
    var body: some View {
        Section {
            UniversalRow(
                String(localized: "walletSetup.title"),
                icon: "wallet.pass",
                config: .settings,
                accessory: .navigation { WalletSetupGuideView() }
            )
        } header: {
            SectionHeader(String(localized: "settings.siri.header"))
        } footer: {
            Text(String(localized: "settings.siri.footer"))
        }
    }
}

#Preview {
    NavigationStack {
        List {
            SettingsSiriSection()
        }
    }
}
