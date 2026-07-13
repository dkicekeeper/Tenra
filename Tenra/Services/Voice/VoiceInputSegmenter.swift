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
        // EN — safe like "и": a boundary only fires when BOTH sides
        // contain an amount, so decorative "milk and bread" never splits.
        "and then", "and also", "then", "also", "plus", "and",
        // DE
        "und noch", "und dann", "außerdem", "danach", "dann", "sowie", "und",
        // ES
        "y luego", "y también", "luego", "después", "también", "además", "y",
        // FR
        "et puis", "et aussi", "ensuite", "puis", "aussi", "et",
        // TR
        "ve sonra", "bir de", "ayrıca", "sonra", "artı", "ve",
        // PT-BR
        "e depois", "e também", "depois", "também", "e",
        // IT
        "e poi", "e anche", "poi", "inoltre", "anche", "e",
        // UK
        "і ще", "та також", "потім", "також", "ще", "і", "та", "й",
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
            // Skip boundaries that fall inside an already-consumed prefix.
            guard split.range.lowerBound >= cursor else { continue }
            let left = String(trimmed[cursor..<split.range.lowerBound])
                .trimmingCharacters(in: Self.fragmentTrim)
            let right = String(trimmed[split.range.upperBound...])
                .trimmingCharacters(in: Self.fragmentTrim)

            // Both sides need a plausible amount, otherwise this boundary
            // is decorative ("на молоко и хлеб") not structural.
            guard containsAmount(left), containsAmount(right) else { continue }

            if !left.isEmpty { clauses.append(left) }
            cursor = split.range.upperBound
        }

        let tail = String(trimmed[cursor...])
            .trimmingCharacters(in: Self.fragmentTrim)
        if !tail.isEmpty { clauses.append(tail) }

        return clauses.isEmpty ? [trimmed] : clauses
    }

    /// Fragments are trimmed not just of whitespace but of any leftover
    /// punctuation/comma from the boundary itself ("500 на такси, " → "500 на такси").
    private static let fragmentTrim: CharacterSet = .whitespacesAndNewlines.union(.punctuationCharacters)

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
        let conjunctionCandidates = conjunctionBoundaries(in: text)
        let amountAnchored = amountAnchoredBoundaries(in: text)
        var merged = conjunctionCandidates + amountAnchored
        merged.sort { $0.range.lowerBound < $1.range.lowerBound }
        return merged
    }

    /// Conjunction-/punctuation-based boundaries (original behavior).
    private static func conjunctionBoundaries(in text: String) -> [Candidate] {
        let ns = text as NSString
        let matches = boundaryRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match -> Candidate? in
            guard let range = Range(match.range, in: text) else { return nil }
            return Candidate(range: range)
        }
    }

    /// Zero-width boundaries placed right before each amount expression after
    /// the first. Catches natural speech like "500 на такси 100 на такси"
    /// where users don't say "и"/"потом" between operations.
    ///
    /// Adjacent amount-token matches (e.g. "пятьсот тысяч") are collapsed
    /// into one "cluster" so they aren't mistakenly split mid-expression.
    private static func amountAnchoredBoundaries(in text: String) -> [Candidate] {
        let ns = text as NSString
        let matches = amountStartRegex
            .matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { tokenRange(of: $0) }
            .sorted { $0.location < $1.location }

        var clusterStarts: [Int] = []
        // `nil` until the first match — avoids `start - Int.min` overflow on
        // the very first iteration (signed subtraction traps on underflow).
        var prevEnd: Int? = nil
        for tokenRange in matches {
            let start = tokenRange.location
            let end = start + tokenRange.length
            // Same logical amount expression if the previous match ended at
            // (or one space before) where this one starts. Otherwise it's a
            // new amount and qualifies as a clause anchor.
            if prevEnd == nil || start - prevEnd! > 1 {
                clusterStarts.append(start)
            }
            prevEnd = end
        }

        var result: [Candidate] = []
        for (idx, start) in clusterStarts.enumerated() where idx > 0 {
            let nsRange = NSRange(location: start, length: 0)
            if let range = Range(nsRange, in: text) {
                result.append(Candidate(range: range))
            }
        }
        return result
    }

    /// Picks whichever capture group of `amountStartRegex` actually matched —
    /// group 1 for a digit amount, group 2 for a word amount. The returned
    /// range starts exactly at the amount token (no leading non-letter).
    private static func tokenRange(of match: NSTextCheckingResult) -> NSRange? {
        let digit = match.range(at: 1)
        if digit.location != NSNotFound { return digit }
        let word = match.range(at: 2)
        if word.location != NSNotFound { return word }
        return nil
    }

    /// Anchored at the START of an amount token. Uses two capture groups so
    /// the match's "token range" begins exactly at the amount's first char,
    /// with no leading non-letter "consumed" inside the group.
    private static let amountStartRegex: NSRegularExpression = {
        // Stems for Russian quantity words. Each accepts any letter suffix.
        // "тыщ" is the colloquial sibling of "тысяч" — both must be matched.
        let stems = [
            "тысяч", "тыщ", "миллион",
            "сто", "двести", "триста", "четыреста", "пятьсот",
            "шестьсот", "семьсот", "восемьсот", "девятьсот",
            "десят", "двадцат", "тридцат", "сорок", "пятьдесят",
            "шестьдесят", "семьдесят", "восемьдесят", "девяност",
            "один", "одна", "два", "две", "три", "четыре",
            "пять", "шесть", "семь", "восемь", "девять",
            "полтор",
        ]
        let stemAlt = stems.joined(separator: "|")
        // Group 1: digit amount. Group 2: word amount. Leading non-letter
        // for the word branch is consumed OUTSIDE group 2, so group 2's
        // location is the first letter of the word stem.
        let pattern = #"(\d+(?:[.,]\d+)?)|(?:^|[^\p{L}])((?:"# + stemAlt + #")\p{L}*)"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    // MARK: - Amount-shaped probe

    /// Cheap "does this fragment look like it contains an amount" check.
    /// Matches either a digit run (with optional currency suffix) or a
    /// quantity word like "тысяча/сто/пятьсот". Intentionally lax — false
    /// positives just mean we segment more aggressively; the parser will
    /// drop clauses that fail to produce a real amount.
    private static let amountProbeRegex: NSRegularExpression = {
        let words = [
            "тысяч", "тыщ", "миллион",
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
