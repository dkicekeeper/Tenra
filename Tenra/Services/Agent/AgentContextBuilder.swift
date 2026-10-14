//
//  AgentContextBuilder.swift
//  Tenra
//
//  The `<app_context>` block that opens a thread: today's date, locale, base currency, the
//  user's accounts and categories with their ids, so tool inputs can name them, the facts the
//  assistant remembers (AgentMemory), with their ids for `draft_fact`, and the savings goals
//  and open personal debts by id and name (amounts come from get_goals / get_debts). The
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

        var lines = [
            "<app_context>",
            "today: \(date) (\(weekday))",
            "locale: \(snapshot.locale)",
            "base_currency: \(snapshot.baseCurrency)",
            "accounts: \(accounts)",
            "expense categories: \(expense)",
            "income categories: \(income)",
        ]
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
