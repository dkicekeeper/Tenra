//
//  ReceiptInterpreter.swift
//  Tenra
//
//  Receipts are the case where Apple Intelligence direct extraction is the
//  right tool: the payload is tiny (one merchant, one total, one date), the
//  layout is wildly inconsistent across the world, and the whole receipt fits
//  comfortably in the model's context window.
//
//  The heuristic path below is the guaranteed floor for the roughly half of
//  the install base without Apple Intelligence.
//

import Foundation
import FoundationModels

struct ReceiptDraft: Sendable, Equatable {
    let merchant: String
    let total: Double
    let currency: String?
    /// Canonical "yyyy-MM-dd", nil when the receipt showed no date.
    let date: String?
}

/// Structured output schema for the Apple Intelligence path.
@Generable
struct ExtractedReceipt {
    @Guide(description: "The shop or restaurant name printed on the receipt, without address or tax identifiers.")
    var merchant: String

    @Guide(description: "The final total paid, as a positive number. Not the subtotal, not the tax, not the cash tendered.")
    var total: Double

    @Guide(description: "ISO 4217 currency code such as USD, EUR, KZT. Empty string if the receipt shows none.")
    var currency: String

    @Guide(description: "Purchase date as yyyy-MM-dd. Empty string if the receipt shows none.")
    var date: String
}

nonisolated struct ReceiptInterpreter {

    private static let instructions = """
    You read the raw text of a shop receipt and report the merchant name, the \
    final total paid, the currency, and the purchase date. You copy values \
    exactly as printed. You never estimate or compute a total that is not \
    printed on the receipt. If a field is not present, you report an empty \
    string for it.
    """

    /// Apple Intelligence first, deterministic heuristics as the fallback.
    ///
    /// Throws only `CancellationError`, when the enclosing task was cancelled
    /// (e.g. the user backed out of the scan). Callers must let that
    /// propagate rather than treating it as "model unavailable, fall back
    /// silently": a cancelled scan should stop, not resolve into a draft the
    /// user never asked to see.
    static func interpret(
        snapshot: DocumentSnapshot,
        defaultCurrency: String
    ) async throws -> ReceiptDraft? {
        // Checked first, before any availability/session work, so an
        // already-cancelled task exits immediately regardless of whether
        // Apple Intelligence is available on this device.
        try Task.checkCancellation()

        if IntelligenceAvailability.isAvailable,
           let draft = try await intelligentDraft(snapshot: snapshot, defaultCurrency: defaultCurrency) {
            return draft
        }
        return heuristicDraft(snapshot: snapshot, defaultCurrency: defaultCurrency)
    }

    // MARK: - Apple Intelligence path

    private static func intelligentDraft(
        snapshot: DocumentSnapshot,
        defaultCurrency: String
    ) async throws -> ReceiptDraft? {
        let text = snapshot.plainText
        guard !text.isEmpty else { return nil }

        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: "Receipt text:\n\n\(text)",
                generating: ExtractedReceipt.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let extracted = response.content
            guard extracted.total > 0 else { return nil }

            return ReceiptDraft(
                merchant: extracted.merchant.trimmingCharacters(in: .whitespacesAndNewlines),
                total: extracted.total,
                currency: extracted.currency.isEmpty ? defaultCurrency : extracted.currency,
                date: extracted.date.isEmpty ? nil : DateTokenParser.parse(extracted.date)
            )
        } catch let cancellationError as CancellationError {
            // Cancellation means "the user backed out of the scan": it must
            // propagate, not be absorbed into "model unavailable, fall back".
            throw cancellationError
        } catch {
            // Every other FoundationModels failure mode (exceededContextWindowSize,
            // assetsUnavailable, guardrailViolation, rateLimited, ...) means the
            // same thing here: fall back to the deterministic heuristic.
            return nil
        }
    }

    // MARK: - Deterministic path

    /// Total-line keywords in the 11 shipped locales, lowercased.
    private static let totalKeywords = [
        "total", "итого", "всего", "к оплате", "сумма", "gesamt", "summe",
        "gesamtbetrag", "total a pagar", "importe total", "montant total",
        "totale", "toplam", "genel toplam", "合計", "합계", "총액", "valor total"
    ]

    /// Lines that carry an amount but are never the final total.
    private static let excludedKeywords = [
        "subtotal", "подытог", "промежуточн", "zwischensumme", "sous-total",
        "subtotale", "ara toplam", "tax", "vat", "ндс", "мwst", "iva", "tva",
        "kdv", "change", "сдача", "rückgeld", "cambio", "monnaie", "tip", "чаевые"
    ]

    static func heuristicDraft(
        snapshot: DocumentSnapshot,
        defaultCurrency: String
    ) -> ReceiptDraft? {
        let lines = snapshot.allLines.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let total = totalFromLabelledLine(lines) ?? largestAmount(lines)
        guard let total else { return nil }

        return ReceiptDraft(
            merchant: merchant(from: lines),
            total: total.amount,
            currency: total.currency ?? defaultCurrency,
            date: lines.compactMap(DateTokenParser.parse).first
        )
    }

    private static func totalFromLabelledLine(
        _ lines: [String]
    ) -> MoneyTokenParser.ParsedMoney? {
        // Search from the bottom: the final total is the last one printed.
        for line in lines.reversed() {
            let lowered = line.lowercased()
            guard totalKeywords.contains(where: { lowered.contains($0) }) else { continue }
            guard !excludedKeywords.contains(where: { lowered.contains($0) }) else { continue }
            if let money = lastAmount(in: line), money.amount > 0 { return money }
        }
        return nil
    }

    private static func largestAmount(_ lines: [String]) -> MoneyTokenParser.ParsedMoney? {
        lines
            .filter { line in
                let lowered = line.lowercased()
                return !excludedKeywords.contains { lowered.contains($0) }
            }
            .compactMap(lastAmount(in:))
            .max { $0.amount < $1.amount }
    }

    /// Receipt lines lay out label and amount as columns separated by a wide
    /// gap (2+ spaces); a lone space inside the amount itself is a
    /// thousands-grouping separator ("2 500"), not a field boundary.
    /// Splitting on single spaces would tear a grouped amount apart and pick
    /// up only its last digit run, so the field boundary must be the wider
    /// gap instead.
    private static let fieldGapPattern = /\s{2,}/

    /// The amount on a receipt line is the rightmost field, since the label
    /// sits on the left.
    private static func lastAmount(in line: String) -> MoneyTokenParser.ParsedMoney? {
        let fields = line.split(separator: fieldGapPattern).map(String.init)
        for field in fields.reversed() {
            if let money = MoneyTokenParser.parse(field), money.amount > 0 { return money }
        }
        // Fall back to parsing the whole line, for lines with no wide gap at
        // all (e.g. a bare "3 600" total on its own line).
        return MoneyTokenParser.parse(line)
    }

    private static func merchant(from lines: [String]) -> String {
        // The shop name is printed at the top, above any amount or date.
        for line in lines.prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else { continue }
            guard !MoneyTokenParser.looksLikeMoney(trimmed) else { continue }
            guard !DateTokenParser.looksLikeDate(trimmed) else { continue }
            guard trimmed.contains(where: \.isLetter) else { continue }
            return trimmed
        }
        return lines.first ?? ""
    }
}
