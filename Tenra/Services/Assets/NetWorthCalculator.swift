//
//  NetWorthCalculator.swift
//  Tenra
//
//  Net worth (docs/domains/assets.md, plan-assets.md §5): money on the accounts, plus the assets
//  at the person's share, plus what others owe them, minus what is left of the loans, minus what
//  they owe. Every part converts to the base currency (CurrencyConverter.convertSync, the amount
//  itself as the cold-cache fallback). Pure and nonisolated: the Insights pass runs it off the
//  main actor on its snapshot; the parts that live in stores of their own (assets, personal
//  debts) come in as `Holdings`, read on the main actor. Investments join as one more line when
//  they come (plan-investments.md).
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
}
