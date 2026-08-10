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

            // The model is allowed to *choose* among numbers printed on the
            // receipt (e.g. pick the final total over a subtotal), but it
            // must never invent one. Ground it: at least one money-shaped run
            // anywhere in the recognized text has to equal the reported
            // total, or the draft is discarded in favor of the heuristic.
            let groundedAmounts = allMoneyRuns(in: snapshot.allLines)
            guard groundedAmounts.contains(where: { abs($0 - extracted.total) < 0.005 }) else {
                return nil
            }

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

    /// Total-line keywords in the 11 shipped locales, lowercased. Every entry
    /// here must be pure ASCII/Latin, Cyrillic, or CJK/Hangul as appropriate
    /// for its language — never a mix, which is how a Cyrillic homoglyph
    /// (У+043C "м" vs Latin "m") silently broke a Latin match. See the
    /// audit note above `excludedKeywords`.
    private static let totalKeywords = [
        "total", "итого", "всего", "к оплате", "сумма", "gesamt", "summe",
        "gesamtbetrag", "total a pagar", "importe total", "montant total",
        "totale", "toplam", "genel toplam", "合計", "합계", "총액", "valor total"
    ]

    /// Lines that carry an amount but are never the final total.
    ///
    /// Homoglyph audit (Fix 1): every entry in this list and in
    /// `totalKeywords` was checked character-by-character for a script mix
    /// (Cyrillic а е о р с у х vs visually identical Latin a e o p c y x).
    /// Only one entry was affected: "мwst" had a Cyrillic У+043C "м" where a
    /// real German "MwSt" line is all-Latin, so it never matched. Fixed to
    /// "mwst". Every other Cyrillic entry (итого, всего, к оплате, сумма,
    /// подытог, промежуточный, ндс, сдача, чаевые) is pure Cyrillic
    /// end-to-end, every Latin entry is pure Latin, and 合計/합계/총액 are pure
    /// CJK/Hangul. Nothing else in either list is affected.
    private static let excludedKeywords = [
        "subtotal", "подытог", "промежуточный", "zwischensumme", "sous-total",
        "subtotale", "ara toplam", "tax", "vat", "ндс", "mwst", "iva", "tva",
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
            let tokens = wordTokens(in: lowered)
            guard totalKeywords.contains(where: { lineMatches($0, tokens: tokens, lowered: lowered) }) else { continue }
            guard !excludedKeywords.contains(where: { lineMatches($0, tokens: tokens, lowered: lowered) }) else { continue }
            if let money = lastAmount(in: line), money.amount > 0 { return money }
        }
        return nil
    }

    private static func largestAmount(_ lines: [String]) -> MoneyTokenParser.ParsedMoney? {
        lines
            .filter { line in
                let lowered = line.lowercased()
                let tokens = wordTokens(in: lowered)
                return !excludedKeywords.contains { lineMatches($0, tokens: tokens, lowered: lowered) }
            }
            .compactMap(lastAmount(in:))
            .max { $0.amount < $1.amount }
    }

    /// Splits a lowercased line into word tokens on every non-letter
    /// character (digits, punctuation, whitespace). `.isLetter` is
    /// script-agnostic, so a CJK/Hangul run of letters with no internal
    /// separator still comes out as a single token.
    private static func wordTokens(in lowered: String) -> Set<String> {
        Set(lowered.split(whereSeparator: { !$0.isLetter }).map(String.init))
    }

    /// True when `phrase` occurs in `text` with a non-letter (or string-edge)
    /// boundary on both sides, so a multi-word or hyphenated keyword like
    /// "ara toplam" / "sous-total" cannot match inside a longer, unrelated
    /// run of letters. Multi-word keywords can never satisfy plain token
    /// equality (they are never a single token), so they need this separate,
    /// boundary-aware containment check instead.
    private static func containsAsPhrase(_ phrase: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: phrase, range: searchStart..<text.endIndex) {
            let beforeIsBoundary = range.lowerBound == text.startIndex
                || !text[text.index(before: range.lowerBound)].isLetter
            let afterIsBoundary = range.upperBound == text.endIndex
                || !text[range.upperBound].isLetter
            if beforeIsBoundary && afterIsBoundary { return true }
            searchStart = range.upperBound
        }
        return false
    }

    /// A keyword matches a line only at a word boundary: a single-word
    /// keyword must equal one of the line's tokens (so "tax" no longer
    /// matches inside "taxi"); a keyword that contains a space or hyphen can
    /// never be one token, so it is matched as a boundary-aware phrase
    /// instead.
    private static func lineMatches(_ keyword: String, tokens: Set<String>, lowered: String) -> Bool {
        if keyword.contains(where: { !$0.isLetter }) {
            return containsAsPhrase(keyword, in: lowered)
        }
        return tokens.contains(keyword)
    }

    /// Grouping-space characters PDF/OCR output uses for digit runs. Kept
    /// narrower than `MoneyTokenParser`'s own set since it only needs to
    /// cover the characters that plausibly separate thousands in a run.
    private static let groupingSpaceChars = " \u{00A0}\u{2009}\u{202F}"

    /// A money-shaped run: a digit group, optionally space-grouped into
    /// thousands, with an optional 1-2 digit decimal part. The negative
    /// lookbehind for a letter excludes a run that starts immediately after
    /// one, e.g. the "2" in "x2 500", so a quantity marker is never read as
    /// part of the price.
    ///
    /// Built via `NSRegularExpression` (ICU), not a Swift `Regex` literal:
    /// the compiled literal syntax in this toolchain rejects lookbehind
    /// ("lookbehind is not currently supported"), while ICU supports it.
    private static let moneyRunPattern: NSRegularExpression = {
        let pattern = #"(?<![\p{L}])\d{1,3}(?:[\#(groupingSpaceChars)]\d{3})*(?:[.,]\d{1,2})?|(?<![\p{L}])\d+(?:[.,]\d{1,2})?"#
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// Every money-shaped run in `line`, left to right, as String ranges.
    private static func moneyRunRanges(in line: String) -> [Range<String.Index>] {
        let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
        return moneyRunPattern.matches(in: line, range: fullRange).compactMap { match in
            Range(match.range, in: line)
        }
    }

    /// The amount on a receipt line is the rightmost money-shaped run, since
    /// the label sits on the left. Parsed from the run's start through the
    /// end of the line (not the run text alone) so a trailing currency
    /// marker like "€" or "KZT" is still picked up by
    /// `MoneyTokenParser.parse`'s own currency detection.
    private static func lastAmount(in line: String) -> MoneyTokenParser.ParsedMoney? {
        guard let rightmost = moneyRunRanges(in: line).last else { return nil }
        let candidate = String(line[rightmost.lowerBound...])
        guard let money = MoneyTokenParser.parse(candidate), money.amount > 0 else { return nil }
        return money
    }

    /// Every money-shaped run across the whole recognized text, in reading
    /// order. Shared by `lastAmount` above (per-line, used by the heuristic
    /// path) and by `intelligentDraft`'s grounding check: a model-reported
    /// total is only trusted when it equals one of these.
    private static func allMoneyRuns(in lines: [String]) -> [Double] {
        lines.flatMap { line in
            moneyRunRanges(in: line).compactMap { range in
                MoneyTokenParser.parse(String(line[range]))?.amount
            }
        }
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
