//
//  TenWardrobeStore.swift
//  Tenra
//
//  Ten's wardrobe state, one source for the wardrobe, Ten's home and the chat
//  (plan-ten-gamification.md §10): what Ten wears, what is open, the crown day and the record
//  streak (TenRecordStreak). Kept in UserDefaults under the keys the wardrobe always used, and
//  copied into every backup as `ten.json` (CloudBackupService), so restoring a backup on a new
//  phone brings it back. Not the iCloud key-value store: that needs a new entitlement and a new
//  signing profile, for a sync between two phones nobody asked for yet.
//

import Foundation
import Observation

@MainActor
@Observable
final class TenWardrobeStore {
    /// The record streak, JSON.
    nonisolated static let streakKey = "ten.recordStreak"
    /// The streak of app opens it replaced (AppStreak, until 2026-11): read once, then removed.
    nonisolated static let legacyStreakKeys = ["streak.lastDay", "streak.count", "streak.best"]
    /// Its file in a backup's folder.
    nonisolated static let backupFileName = "ten.json"

    /// The person's choice, a `CreatureAccessory`'s raw value; "" for nothing.
    private(set) var choice: String
    /// The day Ten last celebrated with the person, `yyyy-MM-dd`: a crown all that day.
    private(set) var crownDay: String
    /// The accessories opened so far, raw values. Nothing in it ever closes again.
    private(set) var unlocked: Set<String>
    private(set) var streak: TenRecordStreak

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choice = defaults.string(forKey: AssistantWardrobe.choiceKey) ?? ""
        crownDay = defaults.string(forKey: AssistantWardrobe.crownDayKey) ?? ""
        unlocked = AssistantWardrobe.decode(defaults.string(forKey: AssistantWardrobe.unlockedKey) ?? "")
        streak = defaults.data(forKey: Self.streakKey)
            .flatMap { try? JSONDecoder().decode(TenRecordStreak.self, from: $0) } ?? TenRecordStreak()
        keepWhatAppOpensOpened()
    }

    /// The choice as stored, for a view that sets its first state in `init`.
    static func storedChoice(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: AssistantWardrobe.choiceKey) ?? ""
    }

    // MARK: - Reading

    /// What Ten wears at `date`: a holiday's accessory, the crown on a day it celebrated, else
    /// the choice.
    func accessory(at date: Date = .now) -> CreatureAccessory? {
        AssistantWardrobe.accessory(choice: choice, crownDay: crownDay, at: date)
    }

    /// Open from the start, opened before, or worn now (the choice stays open).
    func isOpen(_ accessory: CreatureAccessory?) -> Bool {
        guard let accessory else { return true }
        return accessory.rawValue == choice
            || AssistantWardrobe.requirement(accessory) == .open
            || unlocked.contains(accessory.rawValue)
    }

    // MARK: - Changes

    /// Picked in the wardrobe. A locked accessory is only tried on there, never worn.
    func choose(_ accessory: CreatureAccessory?) {
        guard isOpen(accessory) else { return }
        let value = accessory?.rawValue ?? ""
        guard value != choice else { return }
        choice = value
        save()
    }

    /// Ten celebrated a reply with the person: a crown for the rest of the day.
    func celebrate(at date: Date = .now) {
        crownDay = AssistantChatter.dayKey(date)
        save()
    }

    /// Records just added (TransactionStore.onOwnRecords, imports already left out): the
    /// person's own ones from today move the streak and may open its accessories. A series' own
    /// payments and deposit interest are not the person's (SpendingReminderPlan.isUserRecord).
    func noteRecords(_ transactions: [Transaction], now: Date = .now, calendar: Calendar = .current) {
        guard transactions.contains(where: { SpendingReminderPlan.isUserRecord($0, now: now, calendar: calendar) }) else {
            return
        }
        let before = streak
        streak.record(at: now, calendar: calendar)
        guard streak != before else { return }
        save()
        refreshUnlocks(hasGoal: false, hasReachedGoal: false, at: now, calendar: calendar)
    }

    /// Opens what is met now: the streak, the goals, a holiday. Met conditions only ever add,
    /// so a caller that does not know the goals passes false and closes nothing.
    func refreshUnlocks(hasGoal: Bool, hasReachedGoal: Bool, at date: Date = .now, calendar: Calendar = .current) {
        var remembered = unlocked
        if !choice.isEmpty { remembered.insert(choice) }
        let open = AssistantWardrobe.unlocked(remembered: remembered, bestStreak: streak.best, hasGoal: hasGoal,
                                              hasReachedGoal: hasReachedGoal, at: date, calendar: calendar)
        guard open != unlocked else { return }
        unlocked = open
        save()
    }

    // MARK: - Backup

    /// What a backup keeps of the wardrobe.
    nonisolated struct Snapshot: Codable, Equatable, Sendable {
        var choice: String
        var crownDay: String
        var unlocked: [String]
        var streak: TenRecordStreak
    }

    /// `ten.json` for a new backup.
    func backupData() -> Data? {
        try? JSONEncoder().encode(Snapshot(choice: choice, crownDay: crownDay, unlocked: unlocked.sorted(),
                                           streak: streak))
    }

    /// A restored backup's `ten.json`. Nothing earned is lost on either side: what is open
    /// joins, the longer best run stays, the run with the later day goes on, the choice here
    /// stays unless there is none.
    func merge(backup data: Data) {
        guard let saved = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        unlocked.formUnion(saved.unlocked)
        if choice.isEmpty { choice = saved.choice }
        if saved.crownDay > crownDay { crownDay = saved.crownDay }
        var run = saved.streak.lastDay > streak.lastDay ? saved.streak : streak
        run.best = max(run.best, streak.best, saved.streak.best)
        streak = run
        save()
    }

    // MARK: - Storage

    /// The streak of app opens is gone (§7.1, R3): what it opened stays open, its run does not
    /// carry over, and the record streak starts from zero.
    private func keepWhatAppOpensOpened() {
        guard Self.legacyStreakKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        let best = max(defaults.integer(forKey: "streak.best"), defaults.integer(forKey: "streak.count"))
        for accessory in CreatureAccessory.allCases {
            if case .streak(let days) = AssistantWardrobe.requirement(accessory), best >= days {
                unlocked.insert(accessory.rawValue)
            }
        }
        Self.legacyStreakKeys.forEach(defaults.removeObject(forKey:))
        save()
    }

    private func save() {
        defaults.set(choice, forKey: AssistantWardrobe.choiceKey)
        defaults.set(crownDay, forKey: AssistantWardrobe.crownDayKey)
        defaults.set(AssistantWardrobe.encode(unlocked), forKey: AssistantWardrobe.unlockedKey)
        defaults.set(try? JSONEncoder().encode(streak), forKey: Self.streakKey)
    }
}
