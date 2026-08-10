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
        // Deliberately excludes "operation"/"операция": that word labels a
        // transaction-type/category field (e.g. "Покупка" = "Purchase"),
        // not free-text merchant detail. Conflating the two misclassifies
        // any statement that has both an operation-type column and a
        // separate details column (see russianHeaders test).
        .description: ["description", "details", "detail", "narrative", "merchant",
                       "payee", "описание", "детали",
                       "назначение", "получатель", "verwendungszweck", "buchungstext",
                       "beschreibung", "concepto", "descripción", "libellé",
                       "descrição", "descrizione", "açıklama", "内容", "摘要", "내용"]
    ]

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

        guard let dateColumn = dateScores
            .filter({ $0.value >= contentThreshold })
            .max(by: { $0.value < $1.value })?.key
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
            if debitColumn == nil, creditColumn == nil {
                amountColumn = columnMatching(.amount, in: header).flatMap {
                    moneyColumns.contains($0) ? $0 : nil
                }
            }
        }

        // Content fallback: no usable header signal, so pick money columns
        // positionally. Two adjacent money columns read as debit/credit.
        if amountColumn == nil, debitColumn == nil, creditColumn == nil {
            if moneyColumns.count >= 2,
               let last = moneyColumns.last,
               let secondLast = moneyColumns.dropLast().last,
               last - secondLast == 1 {
                debitColumn = secondLast
                creditColumn = last
            } else {
                amountColumn = moneyColumns.first
            }
        }

        let descriptionColumn = header.flatMap { columnMatching(.description, in: $0) }
            ?? textScores
                .filter { $0.value >= contentThreshold }
                .max(by: { $0.value < $1.value })?.key

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
