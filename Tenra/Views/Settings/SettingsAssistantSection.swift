//
//  SettingsAssistantSection.swift
//  Tenra
//
//  Settings → Assistant, where the assistant works (AssistantAvailability): cloud answers (the
//  consent the chat asks for before the first question; turned on here, the same consent screen
//  asks first, App Review 5.1.2(i); turned off, the chat asks again), "Ten chats"
//  (the lines it says, AssistantChatter; turned off, it still gestures) and "What Ten knows
//  about me", the facts it remembers (AssistantMemoryView). Where the cloud answers, the first
//  row is "Ask Ten about the app": a new chat with questions on how to do things in Tenra
//  (AssistantTopic.app). Ten's wardrobe opens from the
//  assistant's home (a hanger at the top right).
//

import SwiftUI

struct SettingsAssistantSection: View {
    @AppStorage(AssistantMetrics.consentKey) private var hasConsent = false
    @AppStorage(AssistantChatter.enabledKey) private var chatterOn = true
    @State private var memory = AgentMemory.shared
    @State private var showingConsent = false
    @Environment(AppCoordinator.self) private var coordinator
    @AppStorage(AssistantRegion.outOfRegionKey) private var outOfRegionAt: Double = 0

    /// Off at once; on only through the consent screen, whose "Turn on" stores the consent.
    private var cloudToggle: Binding<Bool> {
        Binding(
            get: { hasConsent },
            set: { on in
                if on { showingConsent = true } else { hasConsent = false }
            }
        )
    }

    var body: some View {
        if AssistantAvailability.isAvailable {
            FormSection(header: String(localized: "settings.assistant.header"), footer: String(localized: "settings.assistant.footer")) {
                if !AssistantRegion.isOutOfRegion(markedAt: outOfRegionAt, now: Date()) {
                    UniversalRow(
                        String(localized: "settings.assistant.ask"),
                        icon: "questionmark.bubble",
                        accessory: .action {
                            HapticManager.light()
                            coordinator.ask(about: .app)
                        }
                    )
                }
                UniversalRow(
                    String(localized: "settings.assistant.cloud"),
                    icon: "cloud",
                    accessory: .toggle(cloudToggle)
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
            .assistantConsent(isPresented: $showingConsent, onAllow: {}, onDecline: {})
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            SettingsAssistantSection()
        }
    }
    .environment(AppCoordinator())
}
