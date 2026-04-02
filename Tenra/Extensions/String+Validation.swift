//
//  String+Validation.swift
//  AIFinanceManager
//
//  Created on 2026-02-15
//
//  String validation and utility methods

import Foundation

extension String {

    // MARK: - Validation

    /// Check if string is not empty after trimming whitespace
    var isNotEmpty: Bool {
        !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Check if string contains only digits
    var isNumeric: Bool {
        !isEmpty && rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }

    /// Check if string is a valid email format
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: self)
    }

    /// Check if string contains at least one letter
    var containsLetter: Bool {
        rangeOfCharacter(from: .letters) != nil
    }

    /// Check if string contains at least one digit
    var containsDigit: Bool {
        rangeOfCharacter(from: .decimalDigits) != nil
    }

    // MARK: - Trimming

    /// Trim whitespace and newlines
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove all whitespace and newlines
    var withoutWhitespace: String {
        components(separatedBy: .whitespacesAndNewlines).joined()
    }

    // MARK: - Case Conversions

    /// Convert to snake_case
    var snakeCase: String {
        let pattern = "([a-z0-9])([A-Z])"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: count)
        return regex?.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "$1_$2").lowercased() ?? self
    }

    /// Convert to camelCase
    var camelCase: String {
        guard !isEmpty else { return "" }
        let components = self.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let first = components.first?.lowercased() ?? ""
        let rest = components.dropFirst().map { $0.capitalized }
        return ([first] + rest).joined()
    }

    // MARK: - Subscript

    /// Safe character access by index
    subscript(safe index: Int) -> Character? {
        guard index >= 0, index < count else { return nil }
        return self[self.index(startIndex, offsetBy: index)]
    }

    /// Safe substring by range
    subscript(safe range: Range<Int>) -> String? {
        guard range.lowerBound >= 0,
              range.upperBound <= count,
              range.lowerBound < range.upperBound else { return nil }
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(startIndex, offsetBy: range.upperBound)
        return String(self[start..<end])
    }

    // MARK: - Number Parsing

    /// Parse string to Decimal
    var asDecimal: Decimal? {
        Decimal(string: self)
    }

    /// Parse string to Int
    var asInt: Int? {
        Int(self)
    }

    /// Parse string to Double
    var asDouble: Double? {
        Double(self)
    }

    // MARK: - Contains

    /// Case-insensitive contains
    /// - Parameter string: String to search for
    /// - Returns: True if found
    func containsIgnoringCase(_ string: String) -> Bool {
        range(of: string, options: .caseInsensitive) != nil
    }

    // MARK: - Truncation

    /// Truncate string to maximum length with ellipsis
    /// - Parameter length: Maximum length (including ellipsis)
    /// - Returns: Truncated string
    func truncated(to length: Int, addEllipsis: Bool = true) -> String {
        if count <= length {
            return self
        }
        let endIndex = index(startIndex, offsetBy: addEllipsis ? length - 3 : length)
        return String(self[..<endIndex]) + (addEllipsis ? "..." : "")
    }

    // MARK: - Capitalization

    /// Capitalize first letter only
    var capitalizedFirst: String {
        guard !isEmpty else { return self }
        return prefix(1).uppercased() + dropFirst()
    }
}
