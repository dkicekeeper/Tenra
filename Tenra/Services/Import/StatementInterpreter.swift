//
//  StatementInterpreter.swift
//  Tenra
//
//  DocumentSnapshot + ColumnRoles -> transactions. Bank-agnostic: it knows
//  nothing about any specific institution, only about column roles.
//
//  Every row that cannot be used is recorded in `skipped` with a reason. The
//  previous implementation dropped such rows silently, so a user could import
//  20 of 60 operations and never learn about the other 40.
//

import Foundation

enum TransactionDirection: String, Sendable, Equatable {
    case income
    case expense
    case transfer
}

struct ParsedTransaction: Sendable, Equatable {
    let date: String            // canonical "yyyy-MM-dd"
    let amount: Double          // always positive; direction is separate
    let currency: String?       // nil means "use the caller's default"
    let descriptionText: String
    let direction: TransactionDirection
}

struct SkippedRow: Sendable, Equatable {
    let rowIndex: Int
    let cells: [String]
    /// Localization key describing why, e.g. "import.skip.noDate".
    let reason: String
}

struct ParsedStatement: Sendable, Equatable {
    let transactions: [ParsedTransaction]
    let skipped: [SkippedRow]
    let resolvedRoles: ColumnRoles?
}

nonisolated enum StatementInterpreter {

    /// Header layout of the CSV pipeline this feeds into. Must stay aligned
    /// with the existing CSV import flow (Tenra/Services/CSV/CSVImporter.swift).
    static let csvHeaders = [
        "Date", "Type", "Amount", "Currency", "Description", "Account", "Category", "Subcategory"
    ]

    static func interpret(
        snapshot: DocumentSnapshot,
        roles: ColumnRoles,
        defaultCurrency: String
    ) -> ParsedStatement {
        var transactions: [ParsedTransaction] = []
        var skipped: [SkippedRow] = []
        var rowIndex = 0

        for table in snapshot.allTables {
            // Re-resolving per table would be wrong: the caller resolved roles
            // for the table it chose. Only interpret tables of matching width.
            guard table.columnCount > roles.date else { continue }

            for row in table.rows {
                rowIndex += 1

                guard let date = cell(row, roles.date).flatMap(DateTokenParser.parse) else {
                    // A header row is expected to have no date; do not report it.
                    if !isLikelyHeader(row) {
                        skipped.append(SkippedRow(rowIndex: rowIndex,
                                                  cells: row,
                                                  reason: "import.skip.noDate"))
                    }
                    continue
                }

                guard let money = extractMoney(from: row, roles: roles) else {
                    skipped.append(SkippedRow(rowIndex: rowIndex,
                                              cells: row,
                                              reason: "import.skip.noAmount"))
                    continue
                }

                let explicitCurrency = cell(row, roles.currency)
                    .flatMap { MoneyTokenParser.parse($0)?.currency ?? normalizedISO($0) }

                transactions.append(ParsedTransaction(
                    date: date,
                    amount: money.amount,
                    currency: money.currency ?? explicitCurrency ?? defaultCurrency,
                    descriptionText: description(from: row, roles: roles),
                    direction: money.direction
                ))
            }
        }

        return ParsedStatement(transactions: transactions,
                               skipped: skipped,
                               resolvedRoles: roles)
    }

    /// Bridges into the existing CSV mapping UI, which every import path already
    /// funnels through. Amount is emitted unsigned; `Type` carries direction.
    static func csvFile(from statement: ParsedStatement) -> CSVFile {
        let rows = statement.transactions.map { transaction in
            [
                transaction.date,
                transaction.direction.rawValue,
                String(transaction.amount),
                transaction.currency ?? "",
                transaction.descriptionText,
                "",   // Account, filled during entity mapping
                "",   // Category, filled during entity mapping
                ""    // Subcategory, filled during entity mapping
            ]
        }
        return CSVFile(headers: csvHeaders, rows: rows, preview: Array(rows.prefix(5)))
    }

    // MARK: - Private

    private struct MoneyWithDirection {
        let amount: Double
        let currency: String?
        let direction: TransactionDirection
    }

    private static func extractMoney(from row: [String], roles: ColumnRoles) -> MoneyWithDirection? {
        // Debit/credit layout: whichever side is populated decides direction.
        if roles.debit != nil || roles.credit != nil {
            if let debitCell = cell(row, roles.debit),
               let parsed = MoneyTokenParser.parse(debitCell), parsed.amount > 0 {
                return MoneyWithDirection(amount: parsed.amount,
                                          currency: parsed.currency,
                                          direction: .expense)
            }
            if let creditCell = cell(row, roles.credit),
               let parsed = MoneyTokenParser.parse(creditCell), parsed.amount > 0 {
                return MoneyWithDirection(amount: parsed.amount,
                                          currency: parsed.currency,
                                          direction: .income)
            }
            return nil
        }

        // Single signed amount column.
        guard let amountCell = cell(row, roles.amount),
              let parsed = MoneyTokenParser.parse(amountCell) else { return nil }
        return MoneyWithDirection(amount: parsed.amount,
                                  currency: parsed.currency,
                                  direction: parsed.isNegative ? .expense : .income)
    }

    private static func description(from row: [String], roles: ColumnRoles) -> String {
        if let text = cell(row, roles.description), !text.isEmpty {
            return clean(text)
        }
        // No description column: join every cell that is neither the date nor
        // an amount, so the user still sees something recognizable.
        let structuralColumns = Set([roles.date, roles.amount, roles.debit,
                                     roles.credit, roles.currency].compactMap { $0 })
        let parts = row.enumerated()
            .filter { !structuralColumns.contains($0.offset) }
            .map(\.element)
            .filter { !$0.isEmpty }
        return clean(parts.joined(separator: " "))
    }

    /// Strips transport noise banks append to every line. Keep this list short:
    /// over-cleaning destroys merchant names.
    private static func clean(_ text: String) -> String {
        var cleaned = text
        let noisePatterns = [
            #"(?i)Референс:\s*\S+"#,
            #"(?i)Код авторизации:\s*\S+"#,
            #"(?i)Reference:\s*\S+"#,
            #"(?i)Auth(?:orization)? code:\s*\S+"#,
            #"(?i)Ref\.?\s*No\.?:?\s*\S+"#
        ]
        for pattern in noisePatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cell(_ row: [String], _ index: Int?) -> String? {
        guard let index, row.indices.contains(index) else { return nil }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedISO(_ token: String) -> String? {
        let candidate = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return candidate.count == 3 && candidate.allSatisfy(\.isLetter) ? candidate : nil
    }

    /// A row with no date and no parseable money is almost certainly a header
    /// or a section label. Reporting those as "skipped" would be noise.
    private static func isLikelyHeader(_ row: [String]) -> Bool {
        !row.contains { MoneyTokenParser.looksLikeMoney($0) }
    }
}
