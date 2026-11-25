//
//  JanuaryPlan.swift
//  Tenra
//
//  The plan for January (docs/plan-release-1.9.md §4): Ten's message on Home in the first days of
//  January (AssistantNotices.januaryPlan) and the year review's last button open a chat where Ten
//  drafts January's budgets from what is really spent, a goal for the year and the evening
//  spending reminder. The phone only decides when to offer it; the plan is the model's (its rule
//  in server/assistant/src/prompt.ts) and every part of it is a draft the person saves.
//

import Foundation

nonisolated enum JanuaryPlan {
    /// The last January day the message on Home posts.
    static let lastPostingDay = 5
    /// Expenses in October, November and December for there to be a plan to make from them.
    static let minimumExpenses = 30

    /// The year whose January a plan made on `now` is for: this year in January, the next one
    /// the rest of the year (the year review's button opens it from December).
    static func year(on now: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: now)
        let year = parts.year ?? 0
        return parts.month == 1 ? year : year + 1
    }

    /// The year whose message posts on `now`: the first `lastPostingDay` days of January; nil
    /// the rest of the year.
    static func postingYear(on now: Date, calendar: Calendar = .current) -> Int? {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, parts.month == 1, let day = parts.day, day <= lastPostingDay else { return nil }
        return year
    }

    /// The year whose January it is on `now`, while the message may stay on Home; nil outside
    /// January.
    static func shownYear(on now: Date, calendar: Calendar = .current) -> Int? {
        let parts = calendar.dateComponents([.year, .month], from: now)
        guard parts.month == 1 else { return nil }
        return parts.year
    }

    /// Whether the three full months before `year`'s January hold enough expenses for Ten to
    /// suggest budgets from (`suggest_budgets` reads the same three months). Stored "yyyy-MM-dd"
    /// dates compare as strings; it stops at the first `minimumExpenses`.
    static func isEligible(year: Int, transactions: [Transaction]) -> Bool {
        let from = String(format: "%04d-10-01", year - 1)
        let to = String(format: "%04d-01-01", year)
        var expenses = 0
        for tx in transactions where tx.type == .expense && tx.date >= from && tx.date < to {
            expenses += 1
            if expenses >= minimumExpenses { return true }
        }
        return false
    }
}
