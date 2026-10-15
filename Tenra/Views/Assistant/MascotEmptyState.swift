//
//  MascotEmptyState.swift
//  Tenra
//
//  Ten in an empty list (the owner's plan, DesignKit 4.13's EmptyState artwork): in place of the
//  grey icon, Ten says a line and points down at the button that adds the first one (or waves
//  where there is no button). It plays each time the empty screen opens; "Ten chats" off keeps
//  the gesture and drops the line; under Reduce Motion Ten stands still with the line whole.
//  Where the assistant is not available on the device, the screen keeps its icon. Errors, empty
//  searches and empty details keep their icons too.
//

import SwiftUI

struct MascotEmptyState: View {
    let icon: String
    let title: String
    var description: String?
    var actionTitle: String?
    var action: (() -> Void)?
    /// What Ten says.
    let line: String

    var body: some View {
        if AssistantAvailability.isAvailable {
            EmptyState(title: title, description: description, actionTitle: actionTitle, action: action) {
                EmptyMascot(line: line, gesture: actionTitle != nil && action != nil ? .point(.down) : .wave)
            }
        } else {
            EmptyState(icon: icon, title: title, description: description, actionTitle: actionTitle, action: action)
        }
    }
}

/// Ten saying `line` a moment after it appears, with `gesture`.
private struct EmptyMascot: View {
    let line: String
    let gesture: CreatureGesture

    @AppStorage(AssistantChatter.enabledKey) private var chatterOn = true
    @State private var speech: CreatureSpeech?
    @State private var played = 0

    var body: some View {
        ParticleCreature(mood: .happy, speech: chatterOn ? speech : nil)
            .creatureGesture(gesture, trigger: played)
            .frame(width: EmptyMascotMetrics.size, height: EmptyMascotMetrics.size)
            // Room over Ten for its words.
            .padding(.top, EmptyMascotMetrics.speechRoom)
            .task {
                try? await Task.sleep(for: EmptyMascotMetrics.delay)
                guard !Task.isCancelled else { return }
                speech = CreatureSpeech(line, emotion: .calm, duration: .untilChanged)
                played += 1
            }
    }
}

private enum EmptyMascotMetrics {
    static let size: CGFloat = 140
    /// A two-line line over Ten.
    static let speechRoom: CGFloat = 60
    /// After the screen settles.
    static let delay: Duration = .seconds(0.6)
}
