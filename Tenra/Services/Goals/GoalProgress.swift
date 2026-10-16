//
//  GoalProgress.swift
//  Tenra
//
//  Where a savings goal stands (docs/domains/goals-and-debts.md): the share saved, what is
//  left, and, with a deadline, how many months are left and what to put aside each month to
//  make it. The saved amount comes from GoalStore (a linked account's balance or the
//  contributions); this is the arithmetic on top, the same on every screen and for Ten.
//

import Foundation

nonisolated enum GoalProgress {
    nonisolated struct Status: Equatable {
        var saved: Double
        var target: Double
        /// 0…1.
        var fraction: Double
        /// What is still to save; 0 once reached.
        var left: Double
        var isReached: Bool
        /// Months to the deadline, the current one counted (at least 1); nil without a
        /// deadline, once reached, or once the deadline passed.
        var monthsLeft: Int?
        /// What to put aside each month to make the deadline; nil when `monthsLeft` is nil.
        var monthly: Double?
        /// The deadline passed before the goal was reached.
        var isOverdue: Bool
    }

    static func status(
        target: Double,
        saved: Double,
        deadline: Date?,
        today: Date,
        calendar: Calendar = .current
    ) -> Status {
        // Within half a cent: amounts are Doubles, and a sum of contributions can fall a hair
        // short of a target it matches (PersonalDebt.centTolerance).
        let isReached = target > 0 && saved >= target - PersonalDebt.centTolerance
        let left = isReached ? 0 : max(0, target - saved)
        let fraction = target > 0 ? min(1, max(0, saved / target)) : 0
        var monthsLeft: Int?
        var isOverdue = false
        if let deadline, !isReached {
            monthsLeft = months(from: today, to: deadline, calendar: calendar)
            isOverdue = monthsLeft == nil
        }
        return Status(
            saved: saved,
            target: target,
            fraction: fraction,
            left: left,
            isReached: isReached,
            monthsLeft: monthsLeft,
            monthly: monthsLeft.map { left / Double($0) },
            isOverdue: isOverdue
        )
    }

    /// Months from today to the deadline, the current one counted, at least 1; nil once the
    /// deadline is behind today. 14 Oct → 31 Oct is 1, 14 Oct → 14 Apr is 6, 14 Oct → 20 Apr
    /// is 7.
    static func months(from today: Date, to deadline: Date, calendar: Calendar = .current) -> Int? {
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: deadline)
        guard end >= start else { return nil }
        let parts = calendar.dateComponents([.month, .day], from: start, to: end)
        let months = (parts.month ?? 0) + ((parts.day ?? 0) > 0 ? 1 : 0)
        return max(1, months)
    }
}
