//
//  MerchantName.swift
//  Tenra
//
//  A merchant as a person would write it, from the text a bank or Wallet sends:
//  "MAGNUM CASH&CARRY 123" → "Magnum Cash&Carry", "TOO «SMALL» ALMATY KZ" →
//  "Small", "SQ *BLUE BOTTLE" → "Blue Bottle". Used to show a merchant and to
//  look up its logo by name (MerchantLogoResolver); the stored description is
//  never rewritten.
//
//  Pure and `nonisolated`, like CategorySuggestionService.
//

import Foundation

nonisolated enum MerchantName {

    /// What card processors put before the merchant. Longest first.
    private static let processorPrefixes = [
        "paypal *", "sumup *", "zettle_*", "paypal*", "sumup*", "tst *", "tst*", "sq *", "sq*", "pp *", "pp*"
    ]

    /// Legal forms, dropped at either end.
    private static let legalForms: Set<String> = [
        "too", "тоо", "ip", "ип", "llp", "llc", "ltd", "inc", "gmbh", "ooo", "ооо", "ao", "ао", "jsc"
    ]

    /// Cities and countries banks append, dropped at the end.
    private static let placeWords: Set<String> = [
        "kz", "kaz", "kazakhstan", "kazakstan", "ru", "rus",
        "almaty", "astana", "shymkent", "karaganda", "qaraghandy", "aktobe", "atyrau", "pavlodar",
        "kostanay", "taraz", "oskemen", "semey", "aktau", "kyzylorda", "turkistan", "turkestan",
        "petropavlovsk", "uralsk", "taldykorgan", "moscow", "moskva",
        "алматы", "астана", "шымкент", "караганда", "актобе", "атырау", "павлодар", "москва"
    ]

    /// Quotes and separators around a word ("«SMALL»", "MAGNUM,").
    private static let wrapping = CharacterSet(charactersIn: "\"'`«»“”„,;:()[]")

    /// A sole proprietor ("ИП ИВАНОВ", "IP IVANOV"): the name is a person's, so it is never
    /// sent anywhere to look up a logo.
    static func isSoleProprietor(_ raw: String) -> Bool {
        guard let first = raw.split(whereSeparator: \.isWhitespace).first else { return false }
        return ["ип", "ip"].contains(first.trimmingCharacters(in: wrapping).lowercased())
    }

    /// What to search for to find this merchant's transactions: the History search matches
    /// a description that contains the text, ignoring case and diacritics. The clean name when
    /// the bank's text contains it ("MAGNUM CASH&CARRY 123" → "Magnum Cash&Carry"), else its
    /// longest word that it contains ("MAGNUM 12 CASH" → "Magnum"), else the text itself.
    static func searchQuery(_ raw: String) -> String {
        let name = displayName(raw)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if raw.range(of: name, options: options) != nil { return name }
        var best: String?
        for part in name.split(separator: " ") {
            let word = String(part)
            guard word.count >= CategorySuggestionService.minimumMerchantLength,
                  raw.range(of: word, options: options) != nil else { continue }
            if let current = best, current.count >= word.count { continue }
            best = word
        }
        return best ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func displayName(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        if let prefix = processorPrefixes.first(where: { lowered.hasPrefix($0) }), text.count > prefix.count {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }

        var words = text
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: wrapping) }
            // Store numbers and codes: "123", "#45", "№12".
            .filter { $0.contains(where: \.isLetter) }

        while words.count > 1, let first = words.first, legalForms.contains(first.lowercased()) {
            words.removeFirst()
        }
        while words.count > 1, let last = words.last?.lowercased(),
              legalForms.contains(last) || placeWords.contains(last) {
            words.removeLast()
        }
        guard !words.isEmpty else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Only text in capitals is re-cased: a name someone typed keeps its own case.
        guard !text.contains(where: \.isLowercase) else { return words.joined(separator: " ") }
        return words.map { word in
            if word.contains(".") { return word.lowercased() }          // a domain: apple.com
            if word.filter(\.isLetter).count <= 3 { return word }       // an acronym: KFC, LC
            return word.lowercased().capitalized
        }
        .joined(separator: " ")
    }
}
