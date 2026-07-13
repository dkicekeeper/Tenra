//
//  CSVValidationService.swift
//  Tenra
//
//  Created on 2026-02-03
//

import Foundation

/// Service for validating CSV rows and converting them to structured DTOs
/// Handles all field validation, parsing, and type conversions
nonisolated class CSVValidationService: CSVValidationServiceProtocol {

    // MARK: - Properties

    private let headers: [String]

    // MARK: - Initialization

    init(headers: [String]) {
        self.headers = headers
    }

    // MARK: - CSVValidationServiceProtocol

    func validateRow(
        _ row: [String],
        at index: Int,
        mapping: CSVColumnMapping
    ) -> Result<CSVRow, CSVValidationError> {

        // Get column indices from headers
        guard let dateIdx = headers.firstIndex(of: mapping.dateColumn ?? ""),
              let typeIdx = headers.firstIndex(of: mapping.typeColumn ?? ""),
              let amountIdx = headers.firstIndex(of: mapping.amountColumn ?? "") else {
            return .failure(CSVValidationError(
                rowIndex: index,
                column: nil,
                code: .missingRequiredColumn,
                context: [:]
            ))
        }

        // Validate and parse date
        guard let dateString = row[safe: dateIdx]?.trimmingCharacters(in: .whitespaces),
              !dateString.isEmpty else {
            return .failure(CSVValidationError(
                rowIndex: index,
                column: "date",
                code: .emptyValue,
                context: ["value": row[safe: dateIdx] ?? ""]
            ))
        }

        guard let date = parseDate(dateString, format: mapping.dateFormat) else {
            return .failure(CSVValidationError(
                rowIndex: index,
                column: "date",
                code: .invalidDateFormat,
                context: ["value": dateString]
            ))
        }

        // Validate and parse type
        guard let typeString = row[safe: typeIdx]?.trimmingCharacters(in: .whitespaces),
              !typeString.isEmpty else {
            return .failure(CSVValidationError(
                rowIndex: index,
                column: "type",
                code: .emptyValue,
                context: ["value": row[safe: typeIdx] ?? ""]
            ))
        }

        guard let type = parseType(typeString, mappings: mapping.typeMappings) else {
            return .failure(CSVValidationError(
                rowIndex: index,
                column: "type",
                code: .invalidType,
                context: ["value": typeString]
            ))
        }

        // Validate and parse amount
        guard let amountString = row[safe: amountIdx]?.trimmingCharacters(in: .whitespaces),
              !amountString.isEmpty else {
            return .failure(CSVValidationError(
                rowIndex: index,
                column: "amount",
                code: .emptyValue,
                context: ["value": row[safe: amountIdx] ?? ""]
            ))
        }

        guard let amount = parseAmount(amountString) else {
            return .failure(CSVValidationError(
                rowIndex: index,
                column: "amount",
                code: .invalidAmount,
                context: ["value": amountString]
            ))
        }

        // Extract optional fields
        let currency = extractCurrency(from: row, mapping: mapping)
        let rawAccountValue = extractAccount(from: row, mapping: mapping)
        let rawCategoryValue = extractCategory(from: row, mapping: mapping)
        let rawTargetAccountValue = extractTargetAccount(from: row, mapping: mapping)
        let targetCurrency = extractTargetCurrency(from: row, mapping: mapping)
        let targetAmount = extractTargetAmount(from: row, mapping: mapping)
        let subcategoryNames = extractSubcategories(from: row, mapping: mapping)
        let note = extractNote(from: row, mapping: mapping)

        // Create validated CSVRow
        let csvRow = CSVRow(
            rowIndex: index,
            date: date,
            type: type,
            amount: amount,
            currency: currency,
            rawAccountValue: rawAccountValue,
            rawTargetAccountValue: rawTargetAccountValue,
            targetCurrency: targetCurrency,
            targetAmount: targetAmount,
            rawCategoryValue: rawCategoryValue,
            subcategoryNames: subcategoryNames,
            note: note
        )

        return .success(csvRow)
    }

    func validateFile(
        _ csvFile: CSVFile,
        mapping: CSVColumnMapping
    ) async -> [Result<CSVRow, CSVValidationError>] {
        var results: [Result<CSVRow, CSVValidationError>] = []
        results.reserveCapacity(csvFile.rowCount)

        for (index, row) in csvFile.rows.enumerated() {
            let result = validateRow(row, at: index, mapping: mapping)
            results.append(result)
        }

        return results
    }

    // MARK: - Parallel Validation

    /// Validates CSV file rows in parallel batches for improved performance
    /// Uses Task groups to validate multiple batches concurrently
    func validateFileParallel(
        _ csvFile: CSVFile,
        mapping: CSVColumnMapping,
        batchSize: Int = 500
    ) async -> [Result<CSVRow, CSVValidationError>] {

        let batches = csvFile.rows.chunked(into: batchSize)
        var allResults: [Result<CSVRow, CSVValidationError>] = []
        allResults.reserveCapacity(csvFile.rowCount)

        // Collect indexed results, then sort by globalIndex to preserve row order
        var indexedResults: [(Int, Result<CSVRow, CSVValidationError>)] = []
        indexedResults.reserveCapacity(csvFile.rowCount)

        await withTaskGroup(of: [(Int, Result<CSVRow, CSVValidationError>)].self) { group in
            for (batchIndex, batch) in batches.enumerated() {
                group.addTask {
                    var batchResults: [(Int, Result<CSVRow, CSVValidationError>)] = []
                    batchResults.reserveCapacity(batch.count)

                    for (indexInBatch, row) in batch.enumerated() {
                        let globalIndex = batchIndex * batchSize + indexInBatch
                        let result = self.validateRow(row, at: globalIndex, mapping: mapping)
                        batchResults.append((globalIndex, result))
                    }

                    return batchResults
                }
            }

            for await batchResults in group {
                indexedResults.append(contentsOf: batchResults)
            }
        }

        // Sort by original row index — TaskGroup does not guarantee order
        indexedResults.sort { $0.0 < $1.0 }
        allResults = indexedResults.map { $0.1 }

        return allResults
    }

    // MARK: - Field Extraction Helpers

    private func extractCurrency(from row: [String], mapping: CSVColumnMapping) -> String {
        guard let columnName = mapping.currencyColumn,
              let currencyIdx = headers.firstIndex(of: columnName) else {
            return "KZT" // Default currency
        }
        return row[safe: currencyIdx]?.trimmingCharacters(in: .whitespaces) ?? "KZT"
    }

    private func extractAccount(from row: [String], mapping: CSVColumnMapping) -> String {
        guard let columnName = mapping.accountColumn,
              let accountIdx = headers.firstIndex(of: columnName) else {
            return ""
        }
        return row[safe: accountIdx]?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private func extractCategory(from row: [String], mapping: CSVColumnMapping) -> String {
        guard let columnName = mapping.categoryColumn,
              let categoryIdx = headers.firstIndex(of: columnName) else {
            return ""
        }
        return row[safe: categoryIdx]?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private func extractTargetAccount(from row: [String], mapping: CSVColumnMapping) -> String? {
        guard let columnName = mapping.targetAccountColumn,
              let targetAccountIdx = headers.firstIndex(of: columnName) else {
            return nil
        }
        let value = row[safe: targetAccountIdx]?.trimmingCharacters(in: .whitespaces)
        return value?.isEmpty == false ? value : nil
    }

    private func extractTargetCurrency(from row: [String], mapping: CSVColumnMapping) -> String? {
        guard let columnName = mapping.targetCurrencyColumn,
              let targetCurrencyIdx = headers.firstIndex(of: columnName) else {
            return nil
        }
        let value = row[safe: targetCurrencyIdx]?.trimmingCharacters(in: .whitespaces)
        return value?.isEmpty == false ? value : nil
    }

    private func extractTargetAmount(from row: [String], mapping: CSVColumnMapping) -> Double? {
        guard let columnName = mapping.targetAmountColumn,
              let targetAmountIdx = headers.firstIndex(of: columnName),
              let targetAmountString = row[safe: targetAmountIdx]?.trimmingCharacters(in: .whitespaces),
              !targetAmountString.isEmpty else {
            return nil
        }
        return parseAmount(targetAmountString)
    }

    private func extractSubcategories(from row: [String], mapping: CSVColumnMapping) -> [String] {
        guard let columnName = mapping.subcategoriesColumn,
              let subcategoriesIdx = headers.firstIndex(of: columnName),
              let subcategoriesValue = row[safe: subcategoriesIdx]?.trimmingCharacters(in: .whitespaces),
              !subcategoriesValue.isEmpty else {
            return []
        }

        return subcategoriesValue
            .components(separatedBy: mapping.subcategoriesSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func extractNote(from row: [String], mapping: CSVColumnMapping) -> String? {
        guard let columnName = mapping.noteColumn,
              let noteIdx = headers.firstIndex(of: columnName) else {
            return nil
        }
        let value = row[safe: noteIdx]?.trimmingCharacters(in: .whitespaces)
        return value?.isEmpty == false ? value : nil
    }

    // MARK: - Parsing Helpers

    private func parseDate(_ dateString: String, format: DateFormatType) -> Date? {
        let formatter = DateFormatter()

        switch format {
        case .iso:
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: dateString)

        case .ddmmyyyy:
            formatter.dateFormat = "dd.MM.yyyy"
            return formatter.date(from: dateString)

        case .auto:
            // Try multiple formats
            let formats = ["yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy", "MM/dd/yyyy"]
            for fmt in formats {
                formatter.dateFormat = fmt
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
            return nil
        }
    }

    func parseType(_ typeString: String, mappings: [String: TransactionType]) -> TransactionType? {
        let normalized = typeString.lowercased().trimmingCharacters(in: .whitespaces)

        // 1. Exact match — covers canonical export names AND short aliases ("in", "+", "-", "out").
        if let type = mappings[normalized] {
            return type
        }

        // 2. Fuzzy fallback for hand-authored cells: the cell CONTAINS a canonical key.
        //    Longest keys first so "internal"/"transfer" win, and only keys longer than 3
        //    chars qualify — otherwise short aliases like "in" match inside unrelated words
        //    ("internal transfer" must NOT resolve to income). The old code also tested
        //    key.contains(normalized) in nondeterministic dict order, which made the result
        //    flaky and could misclassify transfer/deposit/loan rows as income.
        for key in mappings.keys.filter({ $0.count > 3 }).sorted(by: { $0.count > $1.count })
        where normalized.contains(key) {
            return mappings[key]
        }

        return nil
    }

    /// Locale-tolerant amount parsing. CSV files mix EU and US conventions:
    /// "1.234,56" (de/es/fr), "1,234.56" (en), "1 234,56" (fr/ru — incl.
    /// NBSP/narrow-NBSP group separators). Rule: when both "." and "," are
    /// present, the LAST one is the decimal separator and the other is
    /// grouping; a single separator followed by exactly 3 digits is grouping
    /// (money never has 3 decimals), otherwise it's the decimal point.
    func parseAmount(_ amountString: String) -> Double? {
        var cleaned = amountString.trimmingCharacters(in: .whitespaces)
        for space in [" ", "\u{00A0}", "\u{202F}", "'"] {
            cleaned = cleaned.replacingOccurrences(of: space, with: "")
        }
        guard !cleaned.isEmpty else { return nil }

        let lastDot = cleaned.lastIndex(of: ".")
        let lastComma = cleaned.lastIndex(of: ",")

        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            let decimalSep: Character = dot > comma ? "." : ","
            let groupSep: Character = dot > comma ? "," : "."
            cleaned = cleaned
                .replacingOccurrences(of: String(groupSep), with: "")
                .replacingOccurrences(of: String(decimalSep), with: ".")
        case let (sep?, nil), let (nil, sep?):
            let tail = cleaned.distance(from: cleaned.index(after: sep), to: cleaned.endIndex)
            let occurrences = cleaned.filter { $0 == cleaned[sep] }.count
            if occurrences > 1 || tail == 3 {
                // "1.234.567" / "1,234" → grouping only
                cleaned = cleaned
                    .replacingOccurrences(of: String(cleaned[sep]), with: "")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            }
        case (nil, nil):
            break
        }

        return Double(cleaned)
    }
}

// MARK: - Array Extensions

extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    /// Splits array into chunks of specified size for parallel processing.
    nonisolated func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
