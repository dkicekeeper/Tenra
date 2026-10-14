//
//  SavingsGoal.swift
//  Tenra
//
//  A savings goal (docs/domains/goals-and-debts.md): what the person saves for, how much, by
//  when, and how the saved amount is counted. With a linked account it is that account's
//  balance; without one it is the sum of the contributions the person marks by hand. A goal
//  never changes an account balance or a transaction. Goals are free (no Pro gate).
//

import Foundation

/// Money the person put towards a goal (or took back, when negative), in the goal's currency.
nonisolated struct GoalContribution: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var amount: Double
    var date: Date
    var note: String?

    init(id: String = UUID().uuidString, amount: Double, date: Date, note: String? = nil) {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
    }
}

nonisolated struct SavingsGoal: Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var iconSource: IconSource?
    var targetAmount: Double
    var currency: String
    /// The day it should be reached by; nil for no date.
    var deadline: Date?
    /// The account whose balance is the saved amount; nil counts `contributions`.
    var linkedAccountId: String?
    /// Newest last.
    var contributions: [GoalContribution]
    var createdAt: Date
    /// When it was first seen reached; nil while it is not (or after it fell back below the
    /// target).
    var reachedAt: Date?
    /// Position in the list.
    var order: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        iconSource: IconSource? = nil,
        targetAmount: Double,
        currency: String,
        deadline: Date? = nil,
        linkedAccountId: String? = nil,
        contributions: [GoalContribution] = [],
        createdAt: Date = Date(),
        reachedAt: Date? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.iconSource = iconSource
        self.targetAmount = targetAmount
        self.currency = currency
        self.deadline = deadline
        self.linkedAccountId = linkedAccountId
        self.contributions = contributions
        self.createdAt = createdAt
        self.reachedAt = reachedAt
        self.order = order
    }

    /// The sum of the contributions, in the goal's currency.
    var contributed: Double {
        contributions.reduce(0) { $0 + $1.amount }
    }

    /// The icon shown when the person picked none.
    static var defaultIcon: IconSource { .sfSymbol("target") }
}
