//
//  SettingsProSection.swift
//  Tenra
//
//  "Tenra Pro" row at the top of Settings, opening its page (TenraProView): the pitch for a
//  free user (with DesignKit's shine sweeping across it once), the status for a subscriber or a
//  Founding User. Self-contained: reads PremiumManager from the environment, so SettingsView
//  just drops `SettingsProSection()` into its List.
//

import SwiftUI

struct SettingsProSection: View {

    @Environment(PremiumManager.self) private var premium

    /// Bumped each time a free user's row appears: DesignKit's shine sweeps across it once.
    @State private var ctaShine = 0

    var body: some View {
        FormSection {
            UniversalRow(
                premium.isPro ? "Tenra Pro" : String(localized: "settings.pro.cta.title"),
                icon: "crown.fill",
                value: status,
                hint: premium.isPro ? nil : String(localized: "settings.pro.cta.subtitle"),
                accessory: .navigation { TenraProView() }
            )
            .shine(trigger: ctaShine, in: Rectangle())
            .onAppear {
                if !premium.isPro { ctaShine += 1 }
            }
        }
    }

    /// "Active" for a subscriber, "Free forever" for a Founding User.
    private var status: String? {
        if premium.isSubscriber { return String(localized: "settings.pro.status.active") }
        if premium.isFounder { return String(localized: "settings.pro.founder") }
        return nil
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScrollView {
            SettingsProSection()
        }
    }
    .environment(PremiumManager.shared)
}
