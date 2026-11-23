//
//  AssistantWardrobe.swift
//  Tenra
//
//  The wardrobe's catalogue and rules, no state (that is TenWardrobeStore): what Ten wears
//  (DesignKit 4.12, the owner's plan: events and a wardrobe). On a holiday it
//  dresses up on its own: a party hat from New Year's Eve to 2 January, a taqiya for Nauryz
//  (21 to 23 March); on a day it celebrated a reply with the person it wears a crown. Any other
//  day it wears what the person chose in Ten's wardrobe (a hanger at the top right of the
//  assistant's home), or nothing.
//
//  Unlocking (the owner's scheme): glasses, headphones and the beanie from the start; sunglasses
//  for 7 days in a row with a record and the sleep mask for 30 (TenRecordStreak); the party hat for a first
//  goal, the crown for a goal reached; the taqiya on Nauryz. Once open, an accessory stays open
//  (a deleted goal does not lock it again). The holidays and the crown day dress Ten whatever is
//  open; the wardrobe shows the rest dim, with a lock and what opens it.
//

import SwiftUI

enum AssistantWardrobe {
    /// The person's choice: a `CreatureAccessory`'s raw value, empty for nothing.
    static let choiceKey = "assistant.accessory"
    /// The day Ten last celebrated with the person, `yyyy-MM-dd` (AssistantChatter.dayKey).
    static let crownDayKey = "assistant.crownDay"
    /// The accessories already opened, their raw values joined by commas.
    static let unlockedKey = "assistant.wardrobe.unlocked"

    /// What opens an accessory.
    enum Requirement: Equatable {
        case open
        case streak(Int)
        case firstGoal
        case goalReached
        case nauryz
    }

    static func requirement(_ accessory: CreatureAccessory) -> Requirement {
        switch accessory {
        case .glasses, .headphones, .beanie: .open
        case .sunglasses: .streak(7)
        case .sleepMask: .streak(30)
        case .partyHat: .firstGoal
        case .crown: .goalReached
        case .taqiya: .nauryz
        }
    }

    /// What is open now, given what was opened before: newly met requirements join it.
    static func unlocked(remembered: Set<String>, bestStreak: Int, hasGoal: Bool, hasReachedGoal: Bool,
                         at date: Date, calendar: Calendar = .current) -> Set<String> {
        var open = remembered
        for accessory in CreatureAccessory.allCases {
            let met: Bool
            switch requirement(accessory) {
            case .open: met = true
            case .streak(let days): met = bestStreak >= days
            case .firstGoal: met = hasGoal
            case .goalReached: met = hasReachedGoal
            case .nauryz: met = holiday(at: date, calendar: calendar) == .taqiya
            }
            if met { open.insert(accessory.rawValue) }
        }
        return open
    }

    /// The stored set, and back.
    static func decode(_ stored: String) -> Set<String> {
        Set(stored.split(separator: ",").map(String.init))
    }

    static func encode(_ open: Set<String>) -> String {
        open.sorted().joined(separator: ",")
    }

    /// What opens a locked accessory, for its tile.
    static func condition(_ accessory: CreatureAccessory) -> String {
        switch requirement(accessory) {
        case .open: ""
        case .streak(7): String(localized: "assistant.wardrobe.lock.streak7")
        case .streak: String(localized: "assistant.wardrobe.lock.streak30")
        case .firstGoal: String(localized: "assistant.wardrobe.lock.firstGoal")
        case .goalReached: String(localized: "assistant.wardrobe.lock.goalReached")
        case .nauryz: String(localized: "assistant.wardrobe.lock.nauryz")
        }
    }

    /// What Ten wears at `date`.
    static func accessory(choice: String, crownDay: String, at date: Date,
                          calendar: Calendar = .current) -> CreatureAccessory? {
        if let holiday = holiday(at: date, calendar: calendar) { return holiday }
        if crownDay == AssistantChatter.dayKey(date, calendar: calendar) { return .crown }
        return CreatureAccessory(rawValue: choice)
    }

    /// The holiday's accessory, if `date` is one.
    static func holiday(at date: Date, calendar: Calendar = .current) -> CreatureAccessory? {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        if (month == 12 && day == 31) || (month == 1 && day <= 2) { return .partyHat }
        if month == 3 && (21...23).contains(day) { return .taqiya }
        return nil
    }

    /// The accessory's name; "Nothing" for none.
    static func name(_ accessory: CreatureAccessory?) -> String {
        switch accessory {
        case .none: String(localized: "assistant.wardrobe.none")
        case .partyHat: String(localized: "assistant.wardrobe.partyHat")
        case .crown: String(localized: "assistant.wardrobe.crown")
        case .beanie: String(localized: "assistant.wardrobe.beanie")
        case .taqiya: String(localized: "assistant.wardrobe.taqiya")
        case .headphones: String(localized: "assistant.wardrobe.headphones")
        case .glasses: String(localized: "assistant.wardrobe.glasses")
        case .sunglasses: String(localized: "assistant.wardrobe.sunglasses")
        case .sleepMask: String(localized: "assistant.wardrobe.sleepMask")
        }
    }
}
