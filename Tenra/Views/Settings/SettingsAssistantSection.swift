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
            FormSection(header: String(localized: "settings.assistant.header"), footer: String(localized: "settings.assistant.footer")) {
                UniversalRow(
                    String(localized: "settings.assistant.cloud"),
                    icon: "cloud",
                    accessory: .toggle($hasConsent)
                )
                UniversalRow(
                    String(localized: "settings.assistant.chatter"),
                    icon: "text.bubble",
                    accessory: .toggle($chatterOn)
                )
                UniversalRow(
                    String(localized: "assistant.memory.title"),
                    icon: "brain",
                    accessory: .navigation {
                        AssistantMemoryView(memory: memory)
                    }
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            SettingsAssistantSection()
        }
    }
}
