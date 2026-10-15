//
//  AssistantChatter.swift
//  Tenra
//
//  What Ten says and does around the conversation (DesignKit 4.10, the owner's list): a greeting
//  once a day on the assistant's home (morning, afternoon, evening, a whisper late at night), a
//  hint pointing at the ready-made questions while there are no chats, a thought while it works,
//  a cheer for a celebrated reply, a word when something goes wrong, and a line now and then
//  when it is tapped. "Ten chats" in Settings turns the lines off; the gestures stay. The details
//  of an error stay in the thread: the words are only Ten's reaction. Each line's emotion sets
//  how its letters move (joy hops, a thought sways, worry trembles); unset, it follows the mood.
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

    /// The greeting for the hour, glad, and its wave (none for the late-night whisper).
    static func greeting(at date: Date, calendar: Calendar = .current) -> (CreatureSpeech, CreatureGesture?) {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return (CreatureSpeech(String(localized: "assistant.chatter.morning"), emotion: .joy), .wave)
        case 12..<18:
            return (CreatureSpeech(String(localized: "assistant.chatter.afternoon"), emotion: .joy), .wave)
        case 18..<23:
            return (CreatureSpeech(String(localized: "assistant.chatter.evening"), emotion: .joy), .wave)
        default:
            return (CreatureSpeech(String(localized: "assistant.chatter.night"), emotion: .whisper), nil)
        }
    }

    /// While there are no chats: a hint at the ready-made questions under Ten.
    static var askMe: CreatureSpeech {
        CreatureSpeech(String(localized: "assistant.chatter.askMe"))
    }

    /// The thought while Ten works, taking turns: words, and every other time a picture drawn
    /// in dots of light (DesignKit 4.11), read by VoiceOver as the words it stands for.
    static func thought(_ turn: Int) -> CreatureSpeech {
        let lines = [
            String(localized: "assistant.chatter.hmm"),
            String(localized: "assistant.chatter.counting"),
            String(localized: "assistant.chatter.looking"),
        ]
        if turn % 2 == 1 {
            let pictures = [
                ("chart.bar.fill", String(localized: "assistant.chatter.counting")),
                ("magnifyingglass", String(localized: "assistant.chatter.looking")),
                ("creditcard.fill", String(localized: "assistant.chatter.counting")),
            ]
            let picture = pictures[(turn / 2) % pictures.count]
            return CreatureSpeech(symbol: picture.0, label: picture.1, placement: .trailing,
                                  duration: .untilChanged, id: turn)
        }
        return CreatureSpeech(lines[(turn / 2) % lines.count], emotion: .thought, placement: .trailing,
                              maxWidth: AssistantMetrics.chatSpeechWidth, duration: .untilChanged, id: turn)
    }

    /// A celebrated reply.
    static var cheer: CreatureSpeech {
        CreatureSpeech(String(localized: "assistant.chatter.yay"), emotion: .joy, placement: .trailing,
                       maxWidth: AssistantMetrics.chatSpeechWidth)
    }

    /// Ten's reaction to a question that was not answered, and its gesture; `nil` for the
    /// failures the thread explains on its own (limits, Pro, the region).
    static func reaction(to failure: AssistantFailure) -> (CreatureSpeech?, CreatureGesture) {
        switch failure {
        case .offline:
            return (CreatureSpeech(String(localized: "assistant.chatter.offline"), emotion: .worry,
                                   placement: .trailing, maxWidth: AssistantMetrics.chatSpeechWidth), .flinch)
        case .refused, .generic:
            return (CreatureSpeech(String(localized: "assistant.chatter.unclear"), emotion: .calm, placement: .trailing,
                                   maxWidth: AssistantMetrics.chatSpeechWidth), .shrug)
        case .busy, .limitReached, .proRequired, .regionUnavailable, .unavailable, .freeLimit:
            return (nil, .flinch)
        }
    }

    /// A line for a tap on Ten, tickled, taking turns, so the same one never comes twice in a row.
    static func tapLine(_ turn: Int) -> CreatureSpeech {
        let lines = [
            String(localized: "assistant.chatter.tickles"),
            String(localized: "assistant.chatter.here"),
            String(localized: "assistant.chatter.help"),
            String(localized: "assistant.chatter.hehe"),
        ]
        return CreatureSpeech(lines[turn % lines.count], emotion: .joy, id: "tap-\(turn)")
    }

    /// Three quick taps.
    static func dizzy(_ turn: Int) -> CreatureSpeech {
        CreatureSpeech(String(localized: "assistant.chatter.dizzy"), emotion: .dizzy, id: "dizzy-\(turn)")
    }
}
