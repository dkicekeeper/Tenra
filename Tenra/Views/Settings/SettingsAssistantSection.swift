//
//  SettingsAssistantSection.swift
//  Tenra
//
//  Settings → Assistant, where the assistant works (AssistantAvailability): cloud answers (the
//  consent the chat asks for before the first question; turned off, it asks again), "Ten chats"
//  (the lines it says, AssistantChatter; turned off, it still gestures) and "What Ten knows
//  about me", the facts it remembers (AssistantMemoryView). Ten's wardrobe opens from the
//  assistant's home (a hanger at the top right).
//

import SwiftUI

struct SettingsAssistantSection: View {
    @AppStorage(AssistantMetrics.consentKey) private var hasConsent = false
    @AppStorage(AssistantChatter.enabledKey) private var chatterOn = true
    @State private var memory = AgentMemory.shared

    var body: some View {
        if AssistantAvailability.isAvailable {
            Section {
                UniversalRow(
                    String(localized: "settings.assistant.cloud"),
                    icon: "cloud",
                    config: .settings,
                    accessory: .toggle($hasConsent)
                )
                UniversalRow(
                    String(localized: "settings.assistant.chatter"),
                    icon: "text.bubble",
                    config: .settings,
                    accessory: .toggle($chatterOn)
                )
                UniversalRow(
                    String(localized: "assistant.memory.title"),
                    icon: "brain",
                    config: .settings,
                    accessory: .navigation {
                    AssistantMemoryView(memory: memory)
                }
                )
            } header: {
                SectionHeader(String(localized: "settings.assistant.header"), style: .compact)
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
