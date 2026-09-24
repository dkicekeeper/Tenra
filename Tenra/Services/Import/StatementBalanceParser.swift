//
//  StatementBalanceParser.swift
//  Tenra
//
//  The closing balance a statement prints, so the review screen can compare it
//  with what the account will show in Tenra after the import. Duplicates that
//  slip through (a manual entry off by a few tenge, two days late, or on another
//  account) cannot all be caught row by row; a balance that does not match the
//  bank's own figure catches every one of them at once.
//
//  Two shapes, both seen on real statements:
//   • a labelled line: "Доступно на 24.09.26: + 12 345,67 ₸" (Kaspi prints the
//     opening one too; the latest date wins), "Closing balance 1 234.56";
//   • an account table row: "KZ00… KZT 27,000.50 ₸" (Freedom lists every
//     currency account), dated by the statement period's end.
//  Only amounts with cents are taken, so a stray integer is never a balance.
//

import Foundation

struct StatementBalance: Sendable, Equatable {
    /// Signed: a negative closing balance stays negative.
    let amount: Double
    /// ISO code when the statement shows one (symbol or code), else nil.
    let currency: String?
    /// "yyyy-MM-dd" the balance is as of.
    let asOf: String
}

nonisolated enum StatementBalanceParser {

    /// Closing balances, one per currency (latest date wins). Empty when the
    /// statement prints none or its date cannot be told.
    static func closingBalances(in lines: [String]) -> [StatementBalance] {
        let periodEnd = self.periodEnd(in: lines)
        var byCurrency: [String: StatementBalance] = [:]
        func keep(_ balance: StatementBalance) {
            let key = balance.currency ?? ""
            if let current = byCurrency[key], current.asOf >= balance.asOf { return }
            byCurrency[key] = balance
        }

        // Labelled lines first; account-table rows only fill currencies they miss.
        for line in lines {
            if let balance = labelledBalance(in: line, fallbackDate: periodEnd) { keep(balance) }
        }
        if let periodEnd {
            for line in lines {
                if let balance = accountRowBalance(in: line, asOf: periodEnd),
                   byCurrency[balance.currency ?? ""] == nil {
                    byCurrency[balance.currency ?? ""] = balance
                }
            }
        }
        return byCurrency.values.sorted { ($0.currency ?? "") < ($1.currency ?? "") }
    }

    // MARK: - Labelled line

    /// Lowercased labels of a closing / current balance. Opening-balance labels are
    /// deliberately absent; "доступно на" appears for both ends and the latest
    /// date decides.
    private static let closingLabels = [
        "доступно на", "остаток на", "исходящий остаток", "конечный остаток", "баланс на",
        "залишок на", "вихідний залишок",
        "closing balance", "ending balance", "balance as of", "balance on", "available balance",
        "endsaldo", "neuer kontostand", "kontostand am", "saldo final", "saldo al",
        "nouveau solde", "solde final", "solde au", "saldo finale", "saldo em",
        "kapanış bakiyesi", "dönem sonu bakiye"
    ]

    private static func labelledBalance(in line: String, fallbackDate: String?) -> StatementBalance? {
        let lowered = line.lowercased()
        guard let label = closingLabels.compactMap({ lowered.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound })
        else { return nil }
        // Work on the original string from the same offset (lowercasing keeps offsets
        // for the scripts involved here).
        let offset = lowered.distance(from: lowered.startIndex, to: label.upperBound)
        guard let start = line.index(line.startIndex, offsetBy: offset, limitedBy: line.endIndex) else { return nil }
        var rest = line[start...]

        var asOf = fallbackDate
        if let date = rest.firstMatch(of: datePattern) {
            asOf = DateTokenParser.parse(String(date.output)) ?? asOf
            rest = rest[date.range.upperBound...]
        }
        guard let asOf, let money = firstMoney(in: rest) else { return nil }
        return StatementBalance(amount: money.isNegative ? -money.amount : money.amount,
                                currency: money.currency, asOf: asOf)
    }

    // MARK: - Account table row

    /// "KZ00… KZT 27,000.50 ₸": an IBAN, an ISO code, then the balance.
    private static let accountRowPattern = /\b[A-Z]{2}\d{2}[A-Z0-9]{12,30}\b\s+([A-Z]{3})\s+(.+)/

    private static func accountRowBalance(in line: String, asOf: String) -> StatementBalance? {
        guard let match = line.firstMatch(of: accountRowPattern),
              let money = firstMoney(in: match.2) else { return nil }
        // The row's ISO code wins over the symbol: "CNY 0.00 ¥" is yuan, not yen.
        return StatementBalance(amount: money.isNegative ? -money.amount : money.amount,
                                currency: String(match.1), asOf: asOf)
    }

    // MARK: - Period

    private static let periodWords = ["период", "період", "period", "zeitraum", "período", "periodo", "période", "dönem"]
    private static let datePattern = /\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[.\/]\d{1,2}[.\/]\d{2,4}/

    /// "с 01.09.2026 по 20.09.2026", "from 01/09/2026 to 20/09/2026": a range whose
    /// word may sit on another line (Freedom prints "период" below it).
    private static let rangePattern =
        /(?i)(?:^|\s)(?:с|з|from|von|del|du|dal|de)\s+(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[.\/]\d{1,2}[.\/]\d{2,4})\s+(?:по|до|to|until|bis|al|au|a|até)\s+(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[.\/]\d{1,2}[.\/]\d{2,4})/

    /// The statement period's end: the later date of the first line that names the
    /// period ("за период с 01.09.2026 по 20.09.2026"), else of the first date range.
    static func periodEnd(in lines: [String]) -> String? {
        for line in lines {
            let lowered = line.lowercased()
            guard periodWords.contains(where: { lowered.contains($0) }) else { continue }
            let dates = line.matches(of: datePattern).compactMap { DateTokenParser.parse(String($0.output)) }
            if dates.count >= 2 { return dates.max() }
        }
        for line in lines {
            guard let range = line.firstMatch(of: rangePattern) else { continue }
            let dates = [range.1, range.2].compactMap { DateTokenParser.parse(String($0)) }
            if let end = dates.max() { return end }
        }
        return nil
    }

    // MARK: - Money

    /// The first amount with cents: "+ 12 345,67 ₸", "27,000.50 ₸", "-1 000.00".
    private static let moneyPattern = /[+\-−]?\s?\d[\d \u{00A0}\u{202F},.]*[.,]\d{2}(?!\d)(\s?[^\s\d]{1,3})?/

    private static func firstMoney(in text: Substring) -> MoneyTokenParser.ParsedMoney? {
        guard let match = text.firstMatch(of: moneyPattern) else { return nil }
        return MoneyTokenParser.parse(String(match.output.0))
    }
}

/// The review screen's balance check: what the statement account will hold at the
/// statement's closing date once the selected rows are saved.
nonisolated enum ImportReconciliation {

    /// How the selected rows move the statement account up to `asOf`, the same way
    /// saving does: income (or a transfer in) adds, an expense (or a transfer out)
    /// subtracts, and rows dated before the account's creation day change nothing
    /// (ImportBalanceCompensation keeps the balance the user entered).
    static func importEffect(
        of rows: [Transaction],
        asOf: String,
        compensatedBefore creationDay: String?
    ) -> Double {
        rows.reduce(0) { sum, row in
            guard row.date <= asOf else { return sum }
            if let creationDay, row.date < creationDay { return sum }
            switch row.type {
            case .income: return sum + row.amount
            case .expense: return sum - row.amount
            default: return sum
            }
        }
    }
}
