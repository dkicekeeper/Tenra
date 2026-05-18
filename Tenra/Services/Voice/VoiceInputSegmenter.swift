//
//  VoiceInputSegmenter.swift
//  Tenra
//
//  Splits a single voice-input transcription into independent "clauses",
//  each of which is then parsed into its own `ParsedOperation`.
//
//  Heuristics
//  ----------
//  • A clause boundary is a conjunction word ("и", "также", "потом", ...) or
//    punctuation (.,;) — but ONLY when both sides of the boundary contain at
//    least one number that looks like an amount. This prevents naive splits
//    on phrases like "пятьсот рублей и десять копеек на хлеб" where the "и"
//    joins parts of one amount, not two clauses.
//  • The segmenter is text-only and stateless. Forward-fill of inherited
//    fields (currency, account, type, date) happens in `VoiceInputParser`
//    after each clause has been parsed individually.
//

import Foundation

enum VoiceInputSegmenter {

    /// Conjunction words that may separate two transaction clauses.
    /// Matched as whole words (with word boundaries) so we don't cut inside
    /// other tokens. Order doesn't matter — regex alternation handles all.
    private static let conjunctionWords: [String] = [
        "и ещё", "и еще",
        "а также", "также",
        "потом", "затем",
        "плюс",
        "ещё", "еще",
        "и",
    ]

    /// Returns the input split into clauses. Always returns a non-empty array
    /// — if no boundary fires, the result is `[text]` unchanged.
    static func segment(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let candidates = candidateSplits(in: trimmed)
        guard !candidates.isEmpty else { return [trimmed] }

        // Walk candidates left-to-right, accepting a split only when both
        // the accumulated left fragment AND the projected right fragment
        // each contain at least one amount-shaped number.
        var clauses: [String] = []
        var cursor = trimmed.startIndex
        for split in candidates {
            let left = String(trimmed[cursor..<split.range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(trimmed[split.range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Both sides need a plausible amount, otherwise this boundary
            // is decorative ("на молоко и хлеб") not structural.
            guard containsAmount(left), containsAmount(right) else { continue }

            if !left.isEmpty { clauses.append(left) }
            cursor = split.range.upperBound
        }

        let tail = String(trimmed[cursor...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { clauses.append(tail) }

        return clauses.isEmpty ? [trimmed] : clauses
    }

    // MARK: - Candidate boundaries

    private struct Candidate {
        let range: Range<String.Index>
    }

    private static let boundaryRegex: NSRegularExpression = {
        // Conjunction words (with word boundaries on both sides) OR a
        // hard punctuation followed by whitespace.
        let conjAlt = conjunctionWords
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        // \b doesn't play well with Cyrillic in NSRegularExpression on some
        // platforms — instead require either start/end of string or a
        // non-letter character on each side.
        let pattern = #"(?:(?:^|[^\p{L}])(?:"# + conjAlt + #")(?:$|[^\p{L}]))|(?:[.,;](?:\s|$))"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static func candidateSplits(in text: String) -> [Candidate] {
        let ns = text as NSString
        let matches = boundaryRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match -> Candidate? in
            guard let range = Range(match.range, in: text) else { return nil }
            return Candidate(range: range)
        }
    }

    // MARK: - Amount-shaped probe

    /// Cheap "does this fragment look like it contains an amount" check.
    /// Matches either a digit run (with optional currency suffix) or a
    /// quantity word like "тысяча/сто/пятьсот". Intentionally lax — false
    /// positives just mean we segment more aggressively; the parser will
    /// drop clauses that fail to produce a real amount.
    private static let amountProbeRegex: NSRegularExpression = {
        let words = [
            "тысяч", "миллион",
            "сто", "двести", "триста", "четыреста", "пятьсот",
            "шестьсот", "семьсот", "восемьсот", "девятьсот",
            "десять", "двадцать", "тридцать", "сорок", "пятьдесят",
            "шестьдесят", "семьдесят", "восемьдесят", "девяносто",
            "один", "одна", "два", "две", "три", "четыре",
            "пять", "шесть", "семь", "восемь", "девять",
            "полтора", "полторы",
        ]
        let wordAlt = words.joined(separator: "|")
        // Each entry above is a stem, not a full word — Russian quantity
        // words inflect (тысяча/тысячи/тысяч), so we accept any letter
        // suffix after the stem.
        let pattern = #"(\d{1,3}(?:[\s.,]\d{3})*|\d+)|(?:(?:^|[^\p{L}])(?:"# + wordAlt + #")\p{L}*)"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static func containsAmount(_ fragment: String) -> Bool {
        guard !fragment.isEmpty else { return false }
        let ns = fragment as NSString
        return amountProbeRegex.firstMatch(in: fragment, range: NSRange(location: 0, length: ns.length)) != nil
    }
}
