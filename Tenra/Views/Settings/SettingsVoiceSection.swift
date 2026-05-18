//
//  SettingsVoiceSection.swift
//  Tenra
//
//  Voice-input settings section. Currently surfaces a single action: wipe
//  the on-device learning store that biases account suggestions toward the
//  user's past confirmations.
//

import SwiftUI

struct SettingsVoiceSection: View {

    let onResetLearning: () -> Void

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: "Голосовой ввод")) {
            ActionSettingsRow(
                icon: "trash",
                title: "Сбросить обученные предпочтения",
                isDestructive: true,
                action: onResetLearning
            )
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        List {
            SettingsVoiceSection(onResetLearning: {})
        }
    }
}
