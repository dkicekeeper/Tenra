//
//  SettingsSiriSection.swift
//  Tenra
//
//  Teaches the Siri phrases. Without this, App Shortcuts are discoverable only
//  by accident, and an undiscovered feature has no effect on retention.
//

import SwiftUI
import AppIntents

struct SettingsSiriSection: View {

    var body: some View {
        Section {
            ForEach(Self.examplePhrases, id: \.self) { phrase in
                Label(phrase, systemImage: "quote.bubble")
                    .font(.subheadline)
            }

            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
        } header: {
            Text("settings.siri.header")
        } footer: {
            Text("settings.siri.footer")
        }
    }

    private static var examplePhrases: [String] {
        [
            String(localized: "settings.siri.example1"),
            String(localized: "settings.siri.example2"),
            String(localized: "settings.siri.example3")
        ]
    }
}
