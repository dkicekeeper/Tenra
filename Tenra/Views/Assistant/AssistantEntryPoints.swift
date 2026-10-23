//
//  AssistantEntryPoints.swift
//  Tenra
//
//  Asking Ten from where the question comes up (docs/domains/assistant.md §7, context entry
//  points): an account, a category, an insight, the history, a goal, a debt, For today. The screen names its topic
//  (`AppCoordinator.ask(about:)`), the assistant opens over the tabs with ready-made questions
//  about it in place of its general ones; nothing is sent before the person picks one or types.
//  The entries show only where the assistant works (`AssistantAvailability`).
//

import SwiftUI

/// Where the assistant can run: its server is configured and the device has App Attest.
enum AssistantAvailability {
    static var isAvailable: Bool {
        AgentConfig.serverURL != nil && deviceSupported
    }

    /// The device has App Attest, which the server asks of every turn. The screenshot capture
    /// (DEBUG) runs in the Simulator, which has none: its answers are scripted on the phone
    /// (ScreenshotDemoTransport).
    static var deviceSupported: Bool {
        #if DEBUG
        if ScreenshotDemoMode.isActive { return true }
        #endif
        return AgentAttestation.isSupported
    }
}

/// What a screen asks Ten about.
enum AssistantTopic: Equatable, Sendable {
    case account(name: String)
    case category(name: String, isIncome: Bool)
    case insight(title: String)
    case history
    case goal(name: String)
    case debt(person: String, owedToMe: Bool)
    /// "For today" (DailyAllowanceDetailView).
    case allowance

    /// Ready-made questions about it, in the app's language.
    var questions: [String] {
        switch self {
        case .account(let name):
            return [
                String(format: String(localized: "assistant.topic.account.status"), name),
                String(format: String(localized: "assistant.topic.account.spending"), name),
                String(format: String(localized: "assistant.topic.account.forecast"), name),
            ]
        case .category(let name, let isIncome):
            if isIncome {
                return [
                    String(format: String(localized: "assistant.topic.income.trend"), name),
                    String(format: String(localized: "assistant.topic.income.compare"), name),
                ]
            }
            return [
                String(format: String(localized: "assistant.topic.category.spending"), name),
                String(format: String(localized: "assistant.topic.category.cut"), name),
                String(format: String(localized: "assistant.topic.category.budget"), name),
            ]
        case .insight(let title):
            return [String(format: String(localized: "assistant.topic.insight"), title)]
        case .history:
            return [
                String(localized: "assistant.topic.history.changes"),
                String(localized: "assistant.topic.history.unusual"),
                String(localized: "assistant.preset.compare"),
            ]
        case .goal(let name):
            return [
                String(format: String(localized: "assistant.topic.goal.onTrack"), name),
                String(format: String(localized: "assistant.topic.goal.faster"), name),
            ]
        case .debt(let person, let owedToMe):
            let status = String(format: String(localized: "assistant.topic.debt.status"), person)
            return owedToMe ? [status] : [status, String(format: String(localized: "assistant.topic.debt.plan"), person)]
        case .allowance:
            return [
                String(localized: "assistant.topic.allowance.enough"),
                String(localized: "assistant.topic.allowance.save"),
            ]
        }
    }
}

/// The creature's glyph at the sizes of a bar button and a menu row (DesignKit 4.7.0), drawn once.
private enum AskAssistantGlyph {
    static let toolbar = CreatureGlyph.templateImage(size: AppIconSize.lg)
    static let menu = CreatureGlyph.templateImage(size: AppIconSize.md)
}

/// "Ask Ten" in a screen's toolbar: the creature's glyph.
struct AskAssistantToolbarButton: View {
    @Environment(AppCoordinator.self) private var coordinator
    let topic: AssistantTopic

    var body: some View {
        if AssistantAvailability.isAvailable {
            Button {
                HapticManager.light()
                coordinator.ask(about: topic)
            } label: {
                Label {
                    Text(String(localized: "assistant.ask"))
                } icon: {
                    Image(uiImage: AskAssistantGlyph.toolbar)
                }
            }
        }
    }
}

/// "Ask Ten" in a screen's "…" menu.
struct AskAssistantMenuItem: View {
    @Environment(AppCoordinator.self) private var coordinator
    let topic: AssistantTopic

    var body: some View {
        if AssistantAvailability.isAvailable {
            Button {
                coordinator.ask(about: topic)
            } label: {
                Label {
                    Text(String(localized: "assistant.ask"))
                } icon: {
                    Image(uiImage: AskAssistantGlyph.menu)
                }
            }
            Divider()
        }
    }
}
