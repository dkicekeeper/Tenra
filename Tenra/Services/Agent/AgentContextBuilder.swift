//
//  AgentContextBuilder.swift
//  Tenra
//
//  The `<app_context>` block that opens a thread: today's date, locale, base currency, the
//  user's accounts and categories with their ids, so tool inputs can name them, the facts the
//  assistant remembers (AgentMemory), with their ids for `draft_fact`, the savings goals, the
//  open personal debts and the held assets by id and name (amounts come from get_goals /
//  get_debts / get_assets). The assets line is there even without assets ("none"): it tells the
//  model this version of the app has them (older versions send no such line), and the valuation
//  line that it can estimate an asset's value from listings (estimate_asset_value). The state
//  line says how the app is set up for this person (the plan, the free accounts used, automatic
//  capture, backups, the spending reminder, budgets), so help is about them. The
//  format matches the eval fixture (server/assistant/eval/fixture.ts, `appContext`). It
//  carries no balances or amounts: figures only ever come from tools.
//

import Foundation

nonisolated struct AgentContextSnapshot: Sendable, Equatable {
    struct Account: Sendable, Equatable {
        let id: String
        let name: String
        let currency: String
        /// "regular", "deposit" or "loan".
        let kind: String
    }

    struct Category: Sendable, Equatable {
        let id: String
        let name: String
        let isIncome: Bool
    }

    struct Fact: Sendable, Equatable {
        let id: String
        let text: String
    }

    struct Goal: Sendable, Equatable {
        let id: String
        let name: String
        let currency: String
    }

    struct Debt: Sendable, Equatable {
        let id: String
        let person: String
        /// "owed_to_me" or "i_owe".
        let direction: String
        let currency: String
    }

    /// An asset (named apart from the app's Asset, which this snapshot's extension also uses).
    struct OwnedAsset: Sendable, Equatable {
        let id: String
        let name: String
        /// AssetKind's raw value: apartment, house, land, commercial, vehicle, other.
        let kind: String
        let currency: String
    }

    /// How the app is set up for this person: flags and counts, no amounts.
    struct AppState: Sendable, Equatable {
        let isPro: Bool
        /// Regular accounts a free user may keep (PremiumConfig.freeAccountLimit).
        let freeAccountLimit: Int
        /// The Wallet or a bank notification automation has recorded a payment.
        let capturing: Bool
        let automaticBackups: Bool
        let iCloudBackups: Bool
        /// The newest backup, made by hand or automatically.
        let lastBackup: Date?
        let spendingReminder: Bool
        /// Categories with a budget.
        let budgets: Int
    }

    let today: Date
    let timeZone: TimeZone
    let locale: String
    let baseCurrency: String
    let accounts: [Account]
    let categories: [Category]
    var facts: [Fact] = []
    var goals: [Goal] = []
    /// Open debts only.
    var debts: [Debt] = []
    /// Held assets only.
    var assets: [OwnedAsset] = []
    /// Left out by the previews and tests that build a context by hand: no state line then.
    var state: AppState?
}

nonisolated enum AgentContextBuilder {
    static func text(for snapshot: AgentContextSnapshot) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: snapshot.today)
        let date = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let weekday = weekdays[((parts.weekday ?? 1) - 1 + 7) % 7]

        let accounts = snapshot.accounts
            .map { "\($0.id) \"\(clean($0.name))\" (\($0.currency), \($0.kind))" }
            .joined(separator: "; ")
        let expense = snapshot.categories.filter { !$0.isIncome }.map { "\($0.id) \"\(clean($0.name))\"" }.joined(separator: "; ")
        let income = snapshot.categories.filter(\.isIncome).map { "\($0.id) \"\(clean($0.name))\"" }.joined(separator: "; ")
        let facts = snapshot.facts.map { "\($0.id) \"\(clean($0.text))\"" }.joined(separator: "; ")
        let goals = snapshot.goals.map { "\($0.id) \"\(clean($0.name))\" (\($0.currency))" }.joined(separator: "; ")
        let debts = snapshot.debts.map { "\($0.id) \"\(clean($0.person))\" (\($0.direction), \($0.currency))" }.joined(separator: "; ")
        let assets = snapshot.assets.map { "\($0.id) \"\(clean($0.name))\" (\($0.kind), \($0.currency))" }.joined(separator: "; ")

        // The person's date format (Settings › Formats) shown on a fixed sample, and the day
        // their week starts on, so Ten writes dates and weeks the way the app shows them.
        let formats = FormatSettings.snapshot
        var sampleCalendar = Calendar(identifier: .gregorian)
        sampleCalendar.timeZone = .current
        let sample = sampleCalendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12)) ?? snapshot.today
        let dateFormat = DateFormatters.day(sample, includeYear: true, style: formats.dateStyle)
        let weekStarts = weekdays[((formats.firstWeekday - 1) % 7 + 7) % 7]

        var lines = [
            "<app_context>",
            "today: \(date) (\(weekday))",
            "locale: \(snapshot.locale)",
            "base_currency: \(snapshot.baseCurrency)",
            "date_format: \(dateFormat)",
            "week_starts: \(weekStarts)",
            "accounts: \(accounts)",
            "expense categories: \(expense)",
            "income categories: \(income)",
            // Always there: "none" tells the model this version of the app has assets.
            "assets: \(assets.isEmpty ? "none" : assets)",
            // This version runs estimate_asset_value (the server offers it while it is on).
            "valuation: listings",
            // What this version's `open` blocks reach (plan-ten-agent 4.2): the lists of
            // Finances, goals and debts by id, Settings, and the forms for a new one.
            "screens: accounts, deposits, loans, goals, goal, debts, debt, settings, backups, wallet_guide, create (account, deposit, loan, category)",
        ]
        if let state = snapshot.state {
            let regular = snapshot.accounts.filter { $0.kind == "regular" }.count
            let last = state.lastBackup.map { backup -> String in
                let day = calendar.dateComponents([.year, .month, .day], from: backup)
                return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
            } ?? "none"
            let onOff = { (flag: Bool) in flag ? "on" : "off" }
            lines.append([
                "state: plan \(state.isPro ? "pro" : "free")",
                state.isPro ? "regular accounts \(regular)" : "regular accounts \(regular) of \(state.freeAccountLimit) free",
                "auto_capture \(onOff(state.capturing))",
                "backups automatic \(onOff(state.automaticBackups)), icloud \(onOff(state.iCloudBackups)), last \(last)",
                "spending_reminder \(onOff(state.spendingReminder))",
                "budgets \(state.budgets)",
            ].joined(separator: "; "))
        }
        // Without facts the line is left out, as before there was a memory.
        if !facts.isEmpty { lines.append("facts you remember about the user: \(facts)") }
        if !goals.isEmpty { lines.append("savings goals: \(goals)") }
        if !debts.isEmpty { lines.append("open debts: \(debts)") }
        lines.append("</app_context>")
        return lines.joined(separator: "\n")
    }

    /// Names are user data inside a quoted list: keep them on one line and unquoted.
    private static func clean(_ name: String) -> String {
        name.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ")
    }
}
