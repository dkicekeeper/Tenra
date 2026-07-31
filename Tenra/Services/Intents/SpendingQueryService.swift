//
//  SpendingQueryService.swift
//  Tenra
//
//  Period totals for CheckSpendingIntent.
//
//  Reads CoreData directly with a bounded date predicate instead of going
//  through TransactionStore: an intent process has an empty in-memory
//  transactions array by design, and loading 19k rows is precisely the cost the
//  fast-path bootstrap exists to avoid.
//

import Foundation
import CoreData

enum SpendingPeriod {
    case today
    case thisWeek
    case thisMonth
}

struct SpendingTotal: Equatable {
    let amount: Double
    let currency: String
    let transactionCount: Int
}

enum SpendingQueryService {

    static func total(
        period: SpendingPeriod,
        baseCurrency: String,
        context: NSManagedObjectContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> SpendingTotal {

        // TransactionEntity.date is a real Date at local midnight (written by
        // TransactionRepository through DateFormatters.dateFormatter, which uses
        // TimeZone.current), so the bounds are Dates in the same calendar.
        let start = startDate(for: period, now: now, calendar: calendar)

        let request = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
        request.predicate = NSPredicate(
            format: "date >= %@ AND date <= %@ AND type == %@",
            start as NSDate,
            now as NSDate,
            TransactionType.expense.rawValue
        )

        let rows = try context.fetch(request)

        var sum: Double = 0
        for row in rows {
            let currency = row.currency ?? baseCurrency
            // Convert each row into the base currency. Never sum
            // convertedAmount across currencies: it is stored in ACCOUNT
            // currency, not base currency.
            if let converted = CurrencyConverter.convertSync(
                amount: row.amount,
                from: currency,
                to: baseCurrency
            ) {
                sum += converted
            } else {
                // Cold cache. convertedAmount is a non-optional Double where 0
                // means "no conversion was stored", so it is only a usable
                // approximation when non-zero.
                sum += row.convertedAmount > 0 ? row.convertedAmount : row.amount
            }
        }

        return SpendingTotal(
            amount: sum,
            currency: baseCurrency,
            transactionCount: rows.count
        )
    }

    private static func startDate(
        for period: SpendingPeriod,
        now: Date,
        calendar: Calendar
    ) -> Date {
        switch period {
        case .today:
            return calendar.startOfDay(for: now)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start
                ?? calendar.startOfDay(for: now)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)?.start
                ?? calendar.startOfDay(for: now)
        }
    }
}
