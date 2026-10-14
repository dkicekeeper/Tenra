//
//  SettingsAssistantSection.swift
//  Tenra
//
//  Settings → Assistant, where the assistant works (AssistantAvailability): cloud answers (the
//  consent the chat asks for before the first question; turned off, it asks again), "Ten chats"
//  (the lines it says, AssistantChatter; turned off, it still gestures) and "What Ten knows
//  about me", the facts it remembers (AssistantMemoryView).
//

import SwiftUI

struct SettingsAssistantSection: View {
    @AppStorage(AssistantMetrics.consentKey) private var hasConsent = false
    @AppStorage(AssistantChatter.enabledKey) private var chatterOn = true
    @State private var memory = AgentMemory.shared

    var body: some View {
        if AssistantAvailability.isAvailable {
            Section {
                ToggleSettingsRow(
                    icon: "cloud",
                    title: String(localized: "settings.assistant.cloud"),
                    isOn: $hasConsent
                )
                ToggleSettingsRow(
                    icon: "text.bubble",
                    title: String(localized: "settings.assistant.chatter"),
                    isOn: $chatterOn
                )
                NavigationSettingsRow(
                    icon: "brain",
                    title: String(localized: "assistant.memory.title")
                ) {
                    AssistantMemoryView(memory: memory)
                }
            } header: {
                Text(String(localized: "settings.assistant.header"))
            } footer: {
                Text(String(localized: "settings.assistant.footer"))
            }
        }
    }
}

#Preview {
    NavigationStack {
        List {
            SettingsAssistantSection()
        }
    }
}
