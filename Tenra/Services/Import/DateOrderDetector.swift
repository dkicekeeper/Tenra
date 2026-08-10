//
//  DateOrderDetector.swift
//  Tenra
//
//  "01/08/2026" is 8 January on a US statement and 1 August on a European one.
//  No amount of cleverness resolves that from one token. A column resolves it:
//  a single "13/08/2026" proves the column is day-first, a single "01/25/2026"
//  proves it is month-first.
//

import Foundation

enum DateOrder: Sendable, Equatable {
    case dayFirst
    case monthFirst
}

nonisolated enum DateOrderDetector {

    /// Two 1-2 digit components followed by a 2-4 digit year, with a separator
    /// that carries no ordering information. ISO dates are excluded by
    /// requiring the year last.
    private static let ambiguousPattern = /\b(\d{1,2})[.\/\-](\d{1,2})[.\/\-](\d{2,4})\b/

    /// Day-first is the default: it is the convention in every market the app
    /// ships in except the United States, and it is what the previous importer
    /// assumed, so an ambiguous column behaves as it always has.
    static func detect(tokens: [String]) -> DateOrder {
        var dayFirstEvidence = 0
        var monthFirstEvidence = 0

        for token in tokens {
            guard let match = token.firstMatch(of: ambiguousPattern) else { continue }
            guard let first = Int(match.1), let second = Int(match.2) else { continue }

            // Only a component above 12 is evidence. Anything 1...12 is
            // consistent with both orders and tells us nothing.
            if first > 12 { dayFirstEvidence += 1 }
            if second > 12 { monthFirstEvidence += 1 }
        }

        // Conflicting evidence means OCR noise or a mixed column. Prefer
        // day-first rather than rejecting the column outright.
        if dayFirstEvidence > 0 { return .dayFirst }
        if monthFirstEvidence > 0 { return .monthFirst }
        return .dayFirst
    }
}
