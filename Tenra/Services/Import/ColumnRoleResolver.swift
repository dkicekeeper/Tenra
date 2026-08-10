//
//  ColumnRoleResolver.swift
//  Tenra
//
//  Maps table columns to semantic roles. Two signals, combined:
//    1. Header keywords, in the 11 languages the app ships in.
//    2. Column content statistics (how many cells parse as a date / as money).
//  Content wins over header, because content cannot be mistranslated.
//
//  When confidence is low the caller may escalate to
//  IntelligentColumnRoleResolver (Apple Intelligence). This type never does.
//

import Foundation

nonisolated enum ColumnRole: Sendable, Equatable {
    case date
    case amount
    case debit
    case credit
    case currency
    case description
}

nonisolated struct ColumnRoles: Sendable, Equatable {
    let date: Int
    /// Single signed amount column. Nil when the table uses debit/credit pairs.
    let amount: Int?
    /// Money-out column, used with `credit`.
    let debit: Int?
    /// Money-in column, used with `debit`.
    let credit: Int?
    let currency: Int?
    let description: Int?
    /// 0...1. Below 0.7 the caller should consider Apple Intelligence.
    let confidence: Double

    /// True when the table carries usable amount information in some shape.
    var hasAmountSignal: Bool {
        amount != nil || debit != nil || credit != nil
    }
}

nonisolated enum ColumnRoleResolver {

    /// Header keywords per role, lowercased, in the 11 shipped locales.
    /// Matching is substring-based so "Дата операции" matches "дата".
    private static let keywords: [ColumnRole: [String]] = [
        .date: ["date", "дата", "datum", "fecha", "data", "tarih", "日付", "날짜", "日期"],
        .amount: ["amount", "sum", "сумма", "betrag", "importe", "montant",
                  "valor", "importo", "tutar", "金額", "금액", "quantia"],
        .debit: ["debit", "withdrawal", "expense", "расход", "списание", "soll",
                 "belastung", "cargo", "débit", "debito", "addebito", "borç",
                 "saída", "出金", "출금"],
        .credit: ["credit", "deposit", "income", "приход", "поступление", "haben",
                  "gutschrift", "abono", "crédit", "credito", "accredito",
                  "alacak", "entrada", "入金", "입금"],
        .currency: ["currency", "валюта", "währung", "moneda", "devise", "moeda",
                    "valuta", "para birimi", "通貨", "통화"],
        // Description matching is priority-ordered, not positional (see
        // descriptionColumnMatching). Strong keywords name a free-text
        // narrative field unambiguously. "operation"/"операция" is weak: it
        // often labels a transaction-type/category field (e.g. "Покупка" =
        // "Purchase") rather than merchant detail, so it only wins when no
        // strong keyword matched anywhere in the header (see russianHeaders,
        // which has both "операция" and "детали", and must keep resolving to
        // "детали").
        .description: descriptionKeywordsStrong + descriptionKeywordsWeak
    ]

    private static let descriptionKeywordsStrong: [String] = [
        "description", "details", "detail", "narrative", "merchant",
        "payee", "описание", "детали", "назначение", "получатель",
        "verwendungszweck", "buchungstext", "beschreibung", "concepto",
        "descripción", "libellé", "descrição", "descrizione", "açıklama",
        "内容", "摘要", "내용"
    ]

    private static let descriptionKeywordsWeak: [String] = ["operation", "операция"]

    /// Fraction of body cells that must parse for a content-based role claim.
    private static let contentThreshold = 0.6

    static func resolve(table: DocumentSnapshot.Table) -> ColumnRoles? {
        guard table.columnCount > 0, !table.rows.isEmpty else { return nil }

        let header = table.headerRow.map { row in row.map { $0.lowercased() } }
        let headerIsRecognized = header.map { hasAnyKeyword($0) } ?? false

        // Score on body rows only. Including row 0 would dilute every column
        // score by one non-conforming cell whenever the table has a header,
        // recognized or not, and a 1-header + 1-data table would score 0.5 and
        // fall under the 0.6 threshold. A single-row table has no header to
        // strip, so it scores itself.
        let body = Array(table.bodyRows)
        let rows = body.isEmpty ? table.rows : body

        var dateScores: [Int: Double] = [:]
        var moneyScores: [Int: Double] = [:]
        var textScores: [Int: Double] = [:]

        for column in 0..<table.columnCount {
            let cells = rows.compactMap { $0.indices.contains(column) ? $0[column] : nil }
            let nonEmpty = cells.filter { !$0.isEmpty }
            guard !nonEmpty.isEmpty else { continue }

            let dateHits = Double(nonEmpty.filter { DateTokenParser.looksLikeDate($0) }.count)
            let moneyHits = Double(nonEmpty.filter { MoneyTokenParser.looksLikeMoney($0) }.count)
            let total = Double(nonEmpty.count)

            dateScores[column] = dateHits / total
            moneyScores[column] = moneyHits / total
            textScores[column] = (total - dateHits - moneyHits) / total
        }

        guard let dateColumn = bestColumn(in: dateScores, atLeast: contentThreshold)
        else { return nil }

        let currencyColumn = header.flatMap { columnMatching(.currency, in: $0) }

        let moneyColumns = moneyScores
            .filter { $0.value >= contentThreshold && $0.key != dateColumn && $0.key != currencyColumn }
            .keys
            .sorted()

        var amountColumn: Int?
        var debitColumn: Int?
        var creditColumn: Int?

        if let header {
            debitColumn = columnMatching(.debit, in: header).flatMap {
                moneyColumns.contains($0) ? $0 : nil
            }
            creditColumn = columnMatching(.credit, in: header).flatMap {
                moneyColumns.contains($0) ? $0 : nil
            }
            // Run even when only one of debit/credit matched: a header can
            // legitimately carry a "Debit" column and a separate, genuinely
            // named "Amount" column. Only "both matched" means the pair is
            // already fully accounted for.
            if debitColumn == nil || creditColumn == nil {
                amountColumn = columnMatching(.amount, in: header).flatMap { column -> Int? in
                    guard moneyColumns.contains(column),
                          column != debitColumn,
                          column != creditColumn
                    else { return nil }
                    return column
                }
            }
        }

        // Content fallback: no usable header signal, so pick money columns
        // positionally. Two adjacent money columns are debit/credit only when
        // most rows populate exactly one of the two (an amount/balance pair
        // populates both on essentially every row instead); otherwise the
        // first money column is the amount and the second - most likely a
        // running balance - is left unassigned rather than misread as income.
        if amountColumn == nil, debitColumn == nil, creditColumn == nil {
            if moneyColumns.count >= 2,
               let last = moneyColumns.last,
               let secondLast = moneyColumns.dropLast().last,
               last - secondLast == 1,
               isDebitCreditPair(secondLast, last, in: rows) {
                debitColumn = secondLast
                creditColumn = last
            } else {
                amountColumn = moneyColumns.first
            }
        }

        let descriptionColumn = header.flatMap { descriptionColumnMatching(in: $0) }
            ?? bestColumn(in: textScores, atLeast: contentThreshold)

        let confidence = confidenceScore(
            headerRecognized: headerIsRecognized,
            bodyRowCount: rows.count,
            dateScore: dateScores[dateColumn] ?? 0,
            hasAmount: amountColumn != nil || debitColumn != nil || creditColumn != nil,
            hasDescription: descriptionColumn != nil
        )

        return ColumnRoles(
            date: dateColumn,
            amount: amountColumn,
            debit: debitColumn,
            credit: creditColumn,
            currency: currencyColumn,
            description: descriptionColumn,
            confidence: confidence
        )
    }

    private static func hasAnyKeyword(_ header: [String]) -> Bool {
        keywords.values.contains { list in
            header.contains { cell in list.contains { cell.contains($0) } }
        }
    }

    private static func columnMatching(_ role: ColumnRole, in header: [String]) -> Int? {
        guard let list = keywords[role] else { return nil }
        return header.firstIndex { cell in list.contains { cell.contains($0) } }
    }

    /// Description matching, priority-ordered rather than positional: strong
    /// narrative keywords are tried across the whole header first, and the
    /// weak ("operation"/"операция") keywords are only consulted if no
    /// strong keyword matched anywhere. This keeps a genuine narrative
    /// column ("Детали") winning over a transaction-type column
    /// ("Операция") when both are present, while still letting a statement
    /// whose only narrative-ish column is literally "Operation" resolve.
    private static func descriptionColumnMatching(in header: [String]) -> Int? {
        if let strongMatch = header.firstIndex(where: { cell in
            descriptionKeywordsStrong.contains { cell.contains($0) }
        }) {
            return strongMatch
        }
        return header.firstIndex { cell in
            descriptionKeywordsWeak.contains { cell.contains($0) }
        }
    }

    /// Deterministic column selection: highest score wins, ties broken by
    /// the lowest column index. `Dictionary.max(by:)`/`min(by:)` over
    /// `[Int: Double]` is non-deterministic on ties because dictionary
    /// iteration order depends on Swift's per-process hash seed - the same
    /// statement could resolve to a different column on different launches.
    private static func bestColumn(in scores: [Int: Double], atLeast threshold: Double) -> Int? {
        scores
            .filter { $0.value >= threshold }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .first?.key
    }

    /// True when a clear majority of the given rows populate exactly one of
    /// the two columns - the population signature of a genuine debit/credit
    /// pair. An amount/balance pair populates both columns on essentially
    /// every row instead.
    private static func isDebitCreditPair(_ first: Int, _ second: Int, in rows: [[String]]) -> Bool {
        guard !rows.isEmpty else { return false }
        let exclusiveRows = rows.filter { row in
            let firstFilled = row.indices.contains(first) && !row[first].isEmpty
            let secondFilled = row.indices.contains(second) && !row[second].isEmpty
            return firstFilled != secondFilled
        }.count
        return Double(exclusiveRows) / Double(rows.count) >= contentThreshold
    }

    private static func confidenceScore(
        headerRecognized: Bool,
        bodyRowCount: Int,
        dateScore: Double,
        hasAmount: Bool,
        hasDescription: Bool
    ) -> Double {
        var score = 0.0
        score += headerRecognized ? 0.35 : 0.0
        score += min(Double(bodyRowCount) / 5.0, 1.0) * 0.2
        score += dateScore * 0.25
        score += hasAmount ? 0.15 : 0.0
        score += hasDescription ? 0.05 : 0.0
        return min(score, 1.0)
    }
}
