//
//  SettingsPrivacySection.swift
//  Tenra
//
//  Opt-in app lock (Face ID / Touch ID / passcode). Enabling requires one
//  successful authentication first (AppLockService.setEnabled), so the toggle
//  simply stays off if the user cancels. Under it, the anonymous usage statistics
//  (UsageEvents, docs/plan-sales.md §4): on by default, off sends nothing.
//

import SwiftUI

struct SettingsPrivacySection: View {
    @State private var lock = AppLockService.shared
    @State private var biometry: AppLockBiometry = .unavailable
    @State private var usageOn = UsageEvents.shared.isEnabled

    var body: some View {
        Group {
        FormSection(header: String(localized: "settings.privacy.header"), footer: String(localized: biometry == .unavailable ? "settings.appLock.unavailable" : "settings.appLock.footer")) {
            UniversalRow(
                toggleTitle,
                icon: symbolName,
                accessory: .toggle(Binding(
                    get: { lock.isEnabled },
                    set: { newValue in
                        Task { await lock.setEnabled(newValue) }
                    }
                ))
            )
            .disabled(biometry == .unavailable && !lock.isEnabled)
        }
        FormSection(footer: String(localized: "settings.usageStats.footer")) {
            UniversalRow(
                String(localized: "settings.usageStats"),
                icon: "chart.bar",
                accessory: .toggle($usageOn)
            )
        }
        }
        .onChange(of: usageOn) { _, on in
            UsageEvents.shared.isEnabled = on
        }
        .task {
            biometry = lock.authenticator.biometry()
        }
    }

    private var toggleTitle: String {
        switch biometry {
        case .faceID: String(localized: "settings.appLock.faceID")
        case .touchID: String(localized: "settings.appLock.touchID")
        case .passcodeOnly, .unavailable: String(localized: "settings.appLock.passcode")
        }
    }

    private var symbolName: String {
        switch biometry {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .passcodeOnly, .unavailable: "lock"
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            SettingsPrivacySection()
        }
    }
}
