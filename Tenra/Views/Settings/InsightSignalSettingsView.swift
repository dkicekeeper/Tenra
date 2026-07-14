//
//  InsightSignalSettingsView.swift
//  Tenra
//
//  Insights product audit 2026-07 — Phase C.
//  Master switch + per-kind toggles for insight signal notifications.
//  Enabling the master switch requests notification permission when needed;
//  a denied permission shows an "open iOS Settings" row instead of the toggles
//  silently doing nothing.
//

import SwiftUI

struct InsightSignalSettingsView: View {
    @State private var settings = InsightSignalSettings.shared
    @State private var permissionManager = NotificationPermissionManager.shared

    var body: some View {
        List {
            Section(footer: Text(String(localized: "settings.insightSignals.footer"))) {
                Toggle(String(localized: "settings.insightSignals.master"), isOn: masterBinding)
            }

            if settings.isEnabled {
                if permissionManager.authorizationStatus == .denied {
                    Section {
                        ActionSettingsRow(
                            icon: "bell.slash",
                            title: String(localized: "settings.insightSignals.permissionDenied"),
                            isDestructive: false,
                            action: { permissionManager.openAppSettings() }
                        )
                    }
                }

                Section {
                    ForEach(InsightSignalKind.allCases, id: \.rawValue) { kind in
                        Toggle(kind.displayName, isOn: kindBinding(kind))
                    }
                }

                Section {
                    Toggle(String(localized: "settings.insightSignals.weeklyDigest"), isOn: digestBinding)
                }
            }
        }
        .navigationTitle(String(localized: "settings.insightSignals.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await permissionManager.checkAuthorizationStatus()
        }
    }

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { newValue in
                settings.isEnabled = newValue
                if newValue {
                    Task { await permissionManager.requestAuthorization() }
                }
            }
        )
    }

    private func kindBinding(_ kind: InsightSignalKind) -> Binding<Bool> {
        Binding(
            get: { settings.isKindEnabled(kind) },
            set: { settings.setKind(kind, enabled: $0) }
        )
    }

    private var digestBinding: Binding<Bool> {
        Binding(
            get: { settings.weeklyDigestEnabled },
            set: { newValue in
                settings.weeklyDigestEnabled = newValue
                // Turning the digest off removes the already-pending Monday push;
                // turning it on re-arms on the next insights recompute.
                if !newValue {
                    WeeklyDigestScheduler.shared.cancel()
                }
            }
        )
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        InsightSignalSettingsView()
    }
}
