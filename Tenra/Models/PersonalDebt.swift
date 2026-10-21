//
//  PersonalDebt.swift
//  Tenra
//
//  A debt between the person and someone they know (docs/domains/goals-and-debts.md): who,
//  which way, how much, by when, and what came back. Bank loans are accounts with LoanInfo;
//  these are not, and they never change an account balance or a transaction. Debts are a
//  Tenra Pro feature: adding one goes through the paywall, debts already kept stay open to
//  view and to mark repaid.
//

import Foundation

nonisolated enum DebtDirection: String, Codable, CaseIterable, Sendable {
    /// Someone owes the person.
    case owedToMe
    /// The person owes someone.
    case iOwe
}

/// Money that came back on a debt, in the debt's currency.
nonisolated struct DebtRepayment: Codable, Equatable, Hashable, Identifiable, Sendable {
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

nonisolated struct PersonalDebt: Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var direction: DebtDirection
    /// Who: "Askhat", "Mum".
    var person: String
    /// The amount lent or borrowed.
    var amount: Double
    var currency: String
    /// The day it was lent or borrowed.
    var date: Date
    /// When it should be returned; nil for no date.
    var dueDate: Date?
    var note: String?
    /// Oldest first.
    var repayments: [DebtRepayment]
    /// When it was settled; nil while it is open.
    var settledAt: Date?
    /// Where the person put it in its list (DesignKit 8.0.0's drag to reorder); nil keeps the
    /// list's own order (the soonest due first).
    var order: Int?

    init(
        id: String = UUID().uuidString,
        direction: DebtDirection,
        person: String,
        amount: Double,
        currency: String,
        date: Date = Date(),
        dueDate: Date? = nil,
        note: String? = nil,
        repayments: [DebtRepayment] = [],
        settledAt: Date? = nil,
        order: Int? = nil
    ) {
        self.id = id
        self.direction = direction
        self.person = person
        self.amount = amount
        self.currency = currency
        self.date = date
        self.dueDate = dueDate
        self.note = note
        self.repayments = repayments
        self.settledAt = settledAt
        self.order = order
    }

    /// What came back so far.
    var repaid: Double {
        repayments.reduce(0) { $0 + $1.amount }
    }

    /// Amounts are Doubles: ten repayments of 19.99 add up to 199.89999999999998, a hair under
    /// 199.90. Within half a cent counts as covered, so a debt that reads "0 left" settles.
    static let centTolerance = 0.005

    /// What came back covers the amount.
    var isCovered: Bool {
        repaid >= amount - Self.centTolerance
    }

    /// What is still owed; 0 once settled or covered.
    var remaining: Double {
        guard settledAt == nil else { return 0 }
        let left = amount - repaid
        return left < Self.centTolerance ? 0 : left
    }

    var isSettled: Bool { settledAt != nil }

    /// 0…1, the share that came back (1 once settled).
    var progress: Double {
        guard settledAt == nil else { return 1 }
        guard amount > 0 else { return 0 }
        return min(1, max(0, repaid / amount))
    }

    /// Open and its due date is before today.
    func isOverdue(today: Date, calendar: Calendar = .current) -> Bool {
        guard settledAt == nil, let dueDate else { return false }
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: today)
    }

    /// The icon of a debt in lists and cards.
    var iconSource: IconSource {
        .sfSymbol(direction == .owedToMe ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
    }
}
