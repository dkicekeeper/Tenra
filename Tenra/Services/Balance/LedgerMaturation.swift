//
//  LedgerMaturation.swift
//  Tenra
//
//  Decides when realized balances/aggregates must be recomputed because the
//  calendar day advanced. Realized figures exclude future-dated transactions
//  (incl. generated recurring occurrences); when such a transaction's date
//  arrives it must be folded in. Pure, side-effect-free, and testable.
//

import Foundation

enum LedgerMaturation {

    /// Day-granularity key (yyyy-MM-dd) used to detect a day rollover.
    static func dayKey(for date: Date) -> String {
        DateFormatters.dateFormatter.string(from: Calendar.current.startOfDay(for: date))
    }

    /// True when a ledger recalculation is due: either the day changed since the
    /// last run, or it has never run (first launch after install/update — which
    /// also serves as a one-time repair of any pre-existing balance drift).
    static func shouldRecalculate(now: Date, lastRecalcKey: String?) -> Bool {
        lastRecalcKey != dayKey(for: now)
    }
}
