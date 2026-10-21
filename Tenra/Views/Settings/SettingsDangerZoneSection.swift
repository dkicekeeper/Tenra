//
//  SettingsDangerZoneSection.swift
//  Tenra
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based Danger Zone section for Settings
/// Single Responsibility: Group dangerous actions (reset)
struct SettingsDangerZoneSection: View {
    // MARK: - Props

    let onResetData: () -> Void
    /// Wipes the on-device voice-learning store that biases account suggestions.
    let onResetLearning: () -> Void

    // MARK: - Body

    var body: some View {
        FormSection(header: String(localized: "settings.dangerZone")) {
            UniversalRow(
                String(localized: "settings.resetLearning"),
                icon: "trash",
                role: .destructive,
                accessory: .action(onResetLearning)
            )
            UniversalRow(
                String(localized: "settings.resetData"),
                icon: "trash",
                role: .destructive,
                accessory: .action(onResetData)
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        SettingsDangerZoneSection(
            onResetData: {
            },
            onResetLearning: {
            }
        )
    }
}
