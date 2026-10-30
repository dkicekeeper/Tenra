//
//  NetWorthCalculator.swift
//  Tenra
//
//  Net worth (docs/domains/assets.md, plan-assets.md §5): money on the accounts, plus the assets
//  at the person's share, plus what others owe them, minus what is left of the loans, minus what
//  they owe. Every part converts to the base currency (CurrencyConverter.convertSync, the amount
//  itself as the cold-cache fallback). Pure and nonisolated: the Insights pass runs it off the
//  main actor on its snapshot; the parts that live in stores of their own (assets, personal
//  debts) come in as `Holdings`, read on the main actor. `history` gives net worth at the end of
//  each period of an Insights granularity (its chart): the money's running balance, each asset on
//  that day, the debts as they stood, the loans as their schedule left them. Investments join as
//  one more line when they come (plan-investments.md).
//

import Foundation

nonisolated enum NetWorthCalculator {
    /// An amount in its own currency.
    nonisolated struct Holding: Equatable, Sendable {
        var amount: Double
        var currency: String
    }

    /// The parts kept outside the accounts, read on the main actor.
    nonisolated struct Holdings: Equatable, Sendable {
        /// Held assets counted in net worth, each at the person's share (AssetStore).
        var assets: [Holding]
        /// What is left of the open debts others owe the person (DebtStore).
        var owedToMe: [Holding]
        /// What is left of the open debts the person owes.
        var iOwe: [Holding]
        /// Every asset counted in net worth, held or sold, as it stood over time (`history`).
        var timelines: [AssetValuationMath.Timeline] = []
        /// Every debt, open or settled, with its repayments (`history`).
        var debts: [PersonalDebt] = []

        static let empty = Holdings(assets: [], owedToMe: [], iOwe: [])
    }

    nonisolated struct Line: Identifiable, Equatable, Sendable {
        enum Kind: String, CaseIterable, Sendable {
            case money, assets, owedToMe, loans, iOwe

            /// Counts against net worth.
            var isLiability: Bool { self == .loans || self == .iOwe }
        }

        var kind: Kind
        /// Above zero, in the base currency; a liability's sign is its kind's.
        var amount: Double

        var id: String { kind.rawValue }
        /// The line's part of net worth: negative for a liability.
        var signedAmount: Double { kind.isLiability ? -amount : amount }
    }

    nonisolated struct Result: Equatable, Sendable {
        /// Every kind, in `Line.Kind` order (money always, the others even at zero).
        var lines: [Line]
        var total: Double

        func amount(_ kind: Line.Kind) -> Double {
            lines.first { $0.kind == kind }?.amount ?? 0
        }
    }

    /// - Parameters:
    ///   - accounts: Money is the accounts that are not loans and count in the balance (as the
    ///     Finances total); loans are the loan accounts that count in the balance and are not
    ///     paid off, at their remaining principal.
    ///   - balanceFor: An account's balance in its own currency.
    static func compute(
        accounts: [Account],
        balanceFor: (String) -> Double,
        holdings: Holdings,
        baseCurrency: String,
        convert: (Double, String, String) -> Double? = { CurrencyConverter.convertSync(amount: $0, from: $1, to: $2) }
    ) -> Result {
        func base(_ amount: Double, _ currency: String) -> Double {
            currency == baseCurrency ? amount : convert(amount, currency, baseCurrency) ?? amount
        }
        func total(_ holdings: [Holding]) -> Double {
            holdings.reduce(0) { $0 + base($1.amount, $1.currency) }
        }

        var money = 0.0
        var loans = 0.0
        for account in accounts where account.includeInBalance {
            if let loan = account.loanInfo {
                guard !loan.isPaidOff else { continue }
                loans += base(NSDecimalNumber(decimal: loan.remainingPrincipal).doubleValue, account.currency)
            } else {
                money += base(balanceFor(account.id), account.currency)
            }
        }

        let amounts: [Line.Kind: Double] = [
            .money: money,
            .assets: total(holdings.assets),
            .owedToMe: total(holdings.owedToMe),
            .loans: loans,
            .iOwe: total(holdings.iOwe),
        ]
        let lines = Line.Kind.allCases.map { Line(kind: $0, amount: amounts[$0] ?? 0) }
        return Result(lines: lines, total: lines.reduce(0) { $0 + $1.signedAmount })
    }

    // MARK: - Over time (phase 3)

    /// Net worth at the end of each period, oldest first, in the base currency.
    ///
    /// - Parameters:
    ///   - periodEnds: Each period's end (exclusive, as `PeriodDataPoint.periodEnd`); a period
    ///     not over yet counts up to today.
    ///   - money: The accounts' money at the end of each period (`cumulativeBalancePoints`).
    ///   - accounts: The loans among them count at what their schedule left of them on that day,
    ///     never less than is left today (a principal only goes down); none before the loan began.
    static func history(
        periodEnds: [Date],
        money: [Double],
        accounts: [Account],
        holdings: Holdings,
        baseCurrency: String,
        today: Date = Date(),
        calendar: Calendar = .current,
        convert: (Double, String, String) -> Double? = { CurrencyConverter.convertSync(amount: $0, from: $1, to: $2) }
    ) -> [Double] {
        func base(_ amount: Double, _ currency: String) -> Double {
            currency == baseCurrency ? amount : convert(amount, currency, baseCurrency) ?? amount
        }
        let todayStart = calendar.startOfDay(for: today)

        /// Each loan once: when it began, its schedule (day, what was left), what is left today.
        let loans: [(start: Date, schedule: [(day: Date, left: Double)], original: Double, now: Double, currency: String)] =
            accounts.compactMap { account in
                guard account.includeInBalance, let loan = account.loanInfo,
                      let start = FastDateParser.date(from: loan.startDate) else { return nil }
                let schedule = LoanPaymentService.generateAmortizationSchedule(loanInfo: loan).compactMap { entry in
                    FastDateParser.date(from: entry.date).map { (day: $0, left: NSDecimalNumber(decimal: entry.remainingBalance).doubleValue) }
                }
                let now = loan.isPaidOff ? 0 : NSDecimalNumber(decimal: loan.remainingPrincipal).doubleValue
                return (start: start, schedule: schedule, original: NSDecimalNumber(decimal: loan.originalPrincipal).doubleValue, now: now, currency: account.currency)
            }

        return periodEnds.enumerated().map { index, end in
            // The last day of the period, or today for one not over yet.
            let last = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: end)) ?? end
            let day = min(last, todayStart)

            let assets = holdings.timelines.reduce(0.0) { sum, timeline in
                let value = AssetValuationMath.estimate(timeline, on: day, calendar: calendar)?.value ?? 0
                return sum + base(value * timeline.share, timeline.currency)
            }

            var owedToMe = 0.0
            var iOwe = 0.0
            for debt in holdings.debts {
                let left = debtLeft(debt, on: day, calendar: calendar)
                guard left > 0 else { continue }
                if debt.direction == .owedToMe {
                    owedToMe += base(left, debt.currency)
                } else {
                    iOwe += base(left, debt.currency)
                }
            }

            let loansLeft = loans.reduce(0.0) { sum, loan in
                guard day >= calendar.startOfDay(for: loan.start) else { return sum }
                let left: Double
                if day >= todayStart {
                    left = loan.now
                } else {
                    let scheduled = loan.schedule.last { calendar.startOfDay(for: $0.day) <= day }?.left ?? loan.original
                    left = max(scheduled, loan.now)
                }
                return sum + base(left, loan.currency)
            }

            let cash = index < money.count ? money[index] : 0
            return cash + assets + owedToMe - loansLeft - iOwe
        }
    }

    /// What was still owed of a debt at the end of `day`: nothing before it was lent or from its
    /// settling on, else the amount less the repayments up to that day.
    static func debtLeft(_ debt: PersonalDebt, on day: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: day)
        guard calendar.startOfDay(for: debt.date) <= start else { return 0 }
        if let settledAt = debt.settledAt, calendar.startOfDay(for: settledAt) <= start { return 0 }
        let repaid = debt.repayments
            .filter { calendar.startOfDay(for: $0.date) <= start }
            .reduce(0) { $0 + $1.amount }
        let left = debt.amount - repaid
        return left < PersonalDebt.centTolerance ? 0 : left
    }
}
