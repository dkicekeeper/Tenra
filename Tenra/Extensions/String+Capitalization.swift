//
//  String+Capitalization.swift
//  Tenra
//
//  Shared first-letter capitalization for locale-formatted dates.
//

import Foundation

extension String {
    /// Capitalizes only the first character, leaving the rest untouched.
    ///
    /// Date formatters return lowercase month names in some locales (e.g. Russian
    /// "май 2026"). Date labels used as **headings** should read "Май 2026".
    /// Unlike `.capitalized`, this does not touch subsequent words, so multi-word
    /// labels ("3 января 2026") keep their natural casing.
    nonisolated var capitalizedFirstLetter: String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst()
    }
}
