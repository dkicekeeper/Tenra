//
//  IntelligentColumnRoleResolver.swift
//  Tenra
//
//  Apple Intelligence column-role inference, used ONLY when
//  ColumnRoleResolver's confidence is low. One small prompt per table:
//  the header row plus two sample rows in, a column-index mapping out.
//
//  Why schema inference and not per-row extraction: a 200-row statement does
//  not fit the on-device model's context window, per-row generation would be
//  slow, and an LLM re-typing amounts can hallucinate digits. Inferring the
//  layout once and then parsing every row deterministically keeps the numbers
//  exact while still handling a bank we have never seen.
//

import Foundation
import FoundationModels

/// Structured output schema. Column indices are 0-based; -1 means "absent".
@Generable
struct InferredColumnLayout {
    @Guide(description: "0-based index of the column holding the transaction date. Use -1 if there is none.")
    var dateColumn: Int

    @Guide(description: "0-based index of the column holding a single signed transaction amount. Use -1 if the table instead has separate money-out and money-in columns.")
    var amountColumn: Int

    @Guide(description: "0-based index of the money-out (debit) column. Use -1 if absent.")
    var debitColumn: Int

    @Guide(description: "0-based index of the money-in (credit) column. Use -1 if absent.")
    var creditColumn: Int

    @Guide(description: "0-based index of the currency code column. Use -1 if absent.")
    var currencyColumn: Int

    @Guide(description: "0-based index of the column describing the merchant or counterparty. Use -1 if absent.")
    var descriptionColumn: Int
}

nonisolated struct IntelligentColumnRoleResolver {

    private static let instructions = """
    You analyse bank statement tables. Given a table's header row and a few \
    sample rows, you identify which column index holds which kind of \
    information. You only report column indices. You never invent or restate \
    the values themselves. Column indices are 0-based. When a role is not \
    present in the table, report -1 for it.
    """

    /// Returns nil when Apple Intelligence is unavailable or the model could
    /// not produce a usable layout. Callers must always have a fallback.
    ///
    /// Throws only `CancellationError`, when the enclosing task was cancelled
    /// (e.g. the user backed out of the import). Callers must let that
    /// propagate rather than treating it as "no layout, fall back": a
    /// cancelled import should stop, not silently continue on the
    /// deterministic path.
    static func resolve(table: DocumentSnapshot.Table) async throws -> ColumnRoles? {
        // Checked first, before any availability/session work, so an
        // already-cancelled task exits immediately regardless of whether
        // Apple Intelligence is available on this device.
        try Task.checkCancellation()

        guard IntelligenceAvailability.isAvailable else { return nil }
        guard table.columnCount > 0, !table.rows.isEmpty else { return nil }

        let session = LanguageModelSession(instructions: instructions)
        let prompt = buildPrompt(for: table)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: InferredColumnLayout.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return columnRoles(from: response.content, columnCount: table.columnCount)
        } catch let cancellationError as CancellationError {
            // Cancellation means "the user backed out of the import": it must
            // propagate, not be absorbed into "model unavailable, fall back".
            throw cancellationError
        } catch {
            // Every other FoundationModels failure mode (exceededContextWindowSize,
            // assetsUnavailable, guardrailViolation, rateLimited, ...) means the
            // same thing here: fall back to the deterministic resolver.
            return nil
        }
    }

    private static func buildPrompt(for table: DocumentSnapshot.Table) -> String {
        // Three rows is enough signal and keeps the prompt far inside the
        // context window regardless of statement length.
        let sample = table.rows.prefix(3).enumerated().map { index, row in
            let cells = row.enumerated()
                .map { "[\($0.offset)] \($0.element)" }
                .joined(separator: " | ")
            return "Row \(index): \(cells)"
        }.joined(separator: "\n")

        return """
        The table has \(table.columnCount) columns, indexed 0 to \(table.columnCount - 1).

        \(sample)

        Identify the column index for each role.
        """
    }

    static func columnRoles(
        from layout: InferredColumnLayout,
        columnCount: Int
    ) -> ColumnRoles? {
        func validate(_ index: Int) -> Int? {
            (0..<columnCount).contains(index) ? index : nil
        }

        guard let dateColumn = validate(layout.dateColumn) else { return nil }

        let amount = validate(layout.amountColumn)
        let debit = validate(layout.debitColumn)
        let credit = validate(layout.creditColumn)
        guard amount != nil || debit != nil || credit != nil else { return nil }

        let currency = validate(layout.currencyColumn)
        let description = validate(layout.descriptionColumn)

        // The deterministic ColumnRoleResolver structurally cannot assign two
        // roles to the same column (its money scoring excludes the date
        // column, etc.). If the model does, the layout is semantically
        // impossible: a same-index debit/credit pair makes every
        // transaction's money-in equal its money-out, and a date column read
        // as the amount column corrupts every amount. Reject the whole
        // layout so the caller falls back to the deterministic resolver
        // instead of trusting a plausible-looking but wrong mapping.
        let resolvedIndices = [dateColumn, amount, debit, credit, currency, description].compactMap { $0 }
        guard Set(resolvedIndices).count == resolvedIndices.count else { return nil }

        return ColumnRoles(
            date: dateColumn,
            amount: amount,
            debit: debit,
            credit: credit,
            currency: currency,
            description: description,
            // Model-resolved layouts are trusted, but never above a confidently
            // header-matched deterministic result.
            confidence: 0.8
        )
    }
}
