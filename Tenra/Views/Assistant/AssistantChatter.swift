//
//  AssistantChatter.swift
//  Tenra
//
//  What Ten says and does around the conversation (DesignKit 4.10, the owner's list): a greeting
//  once a day on the assistant's home (morning, afternoon, evening, a whisper late at night), a
//  hint pointing at the ready-made questions while there are no chats, a thought while it works,
//  a cheer for a celebrated reply, a word when something goes wrong, and a line now and then
//  when it is tapped. "Ten chats" in Settings turns the lines off; the gestures stay. The details
//  of an error stay in the thread: the bubble is only Ten's reaction.
//

import SwiftUI

enum AssistantChatter {
    /// "Ten chats" (Settings → Assistant), on by default.
    static let enabledKey = "assistant.chatter"
    /// The day Ten last greeted, `yyyy-MM-dd`.
    static let greetedDayKey = "assistant.greetedDay"
    /// How long Ten works before a thought appears.
    static let thoughtDelay: Duration = .seconds(1.5)
    /// The shortest gap between two lines for taps, and the window three taps make Ten dizzy in
    /// (as ParticleCreature's own dizzy reaction).
    static let tapLineGap: TimeInterval = 2
    static let dizzyWindow: TimeInterval = 2

    /// A day as `yyyy-MM-dd` in the person's calendar.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The greeting for the hour, and its wave (none for the late-night whisper).
    static func greeting(at date: Date, calendar: Calendar = .current) -> (CreatureSpeech, CreatureGesture?) {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return (CreatureSpeech(String(localized: "assistant.chatter.morning")), .wave)
        case 12..<18:
            return (CreatureSpeech(String(localized: "assistant.chatter.afternoon")), .wave)
        case 18..<23:
            return (CreatureSpeech(String(localized: "assistant.chatter.evening")), .wave)
        default:
            return (CreatureSpeech(String(localized: "assistant.chatter.night"), style: .whisper), nil)
        }
    }

    /// While there are no chats: a hint at the ready-made questions under Ten.
    static var askMe: CreatureSpeech {
        CreatureSpeech(String(localized: "assistant.chatter.askMe"))
    }

    /// The thought while Ten works, taking turns.
    static func thought(_ turn: Int) -> CreatureSpeech {
        let lines = [
            String(localized: "assistant.chatter.hmm"),
            String(localized: "assistant.chatter.counting"),
            String(localized: "assistant.chatter.looking"),
        ]
        return CreatureSpeech(lines[turn % lines.count], style: .think, placement: .trailing,
                              maxWidth: AssistantMetrics.chatBubbleWidth, duration: .untilChanged, id: turn)
    }

    /// A celebrated reply.
    static var cheer: CreatureSpeech {
        CreatureSpeech(String(localized: "assistant.chatter.yay"), style: .shout, placement: .trailing,
                       maxWidth: AssistantMetrics.chatBubbleWidth)
    }

    /// Ten's reaction to a question that was not answered, and its gesture; `nil` for the
    /// failures the thread explains on its own (limits, Pro, the region).
    static func reaction(to failure: AssistantFailure) -> (CreatureSpeech?, CreatureGesture) {
        switch failure {
        case .offline:
            return (CreatureSpeech(String(localized: "assistant.chatter.offline"), style: .whisper,
                                   placement: .trailing, maxWidth: AssistantMetrics.chatBubbleWidth), .flinch)
        case .refused, .generic:
            return (CreatureSpeech(String(localized: "assistant.chatter.unclear"), placement: .trailing,
                                   maxWidth: AssistantMetrics.chatBubbleWidth), .shrug)
        case .busy, .limitReached, .proRequired, .regionUnavailable, .unavailable, .freeLimit:
            return (nil, .flinch)
        }
    }

    /// A line for a tap on Ten, taking turns, so the same one never comes twice in a row.
    static func tapLine(_ turn: Int) -> CreatureSpeech {
        let lines = [
            String(localized: "assistant.chatter.tickles"),
            String(localized: "assistant.chatter.here"),
            String(localized: "assistant.chatter.help"),
            String(localized: "assistant.chatter.hehe"),
        ]
        return CreatureSpeech(lines[turn % lines.count], id: "tap-\(turn)")
    }

    /// Three quick taps.
    static func dizzy(_ turn: Int) -> CreatureSpeech {
        CreatureSpeech(String(localized: "assistant.chatter.dizzy"), style: .shout, id: "dizzy-\(turn)")
    }
}
