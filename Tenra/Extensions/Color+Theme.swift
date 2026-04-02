//
//  Color+Theme.swift
//  AIFinanceManager
//
//  Created on 2026-02-15
//
//  Color theme extensions and utilities

import SwiftUI

extension Color {

    // MARK: - Transaction Type Colors

    /// Color for income transactions
    static var incomeColor: Color {
        .green
    }

    /// Color for expense transactions
    static var expenseColor: Color {
        .red
    }

    /// Color for transfer transactions
    static var transferColor: Color {
        .blue
    }

    // MARK: - Status Colors

    /// Color for success states
    static var successColor: Color {
        .green
    }

    /// Color for warning states
    static var warningColor: Color {
        .orange
    }

    /// Color for error states
    static var errorColor: Color {
        .red
    }

    /// Color for info states
    static var infoColor: Color {
        .blue
    }

    // MARK: - Semantic Colors

    /// Color for positive values (gains, income)
    static var positiveAmount: Color {
        Color(red: 0.0, green: 0.7, blue: 0.3)
    }

    /// Color for negative values (losses, expenses)
    static var negativeAmount: Color {
        Color(red: 0.9, green: 0.2, blue: 0.2)
    }

    /// Color for neutral values
    static var neutralAmount: Color {
        .gray
    }

    // MARK: - Background Colors

    /// Secondary background color
    static var secondaryBackground: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    /// Tertiary background color
    static var tertiaryBackground: Color {
        Color(uiColor: .tertiarySystemBackground)
    }

    /// Grouped background color
    static var groupedBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    // MARK: - Text Colors

    /// Secondary text color
    static var secondaryText: Color {
        Color(uiColor: .secondaryLabel)
    }

    /// Tertiary text color
    static var tertiaryText: Color {
        Color(uiColor: .tertiaryLabel)
    }

    /// Quaternary text color
    static var quaternaryText: Color {
        Color(uiColor: .quaternaryLabel)
    }

    // MARK: - HEX Conversion

    /// Initialize color from hex string
    /// - Parameter hex: Hex string (e.g., "#FF0000" or "FF0000")
    nonisolated init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Convert color to hex string
    /// - Parameter includeAlpha: Include alpha channel in output
    /// - Returns: Hex string (e.g., "#FF0000")
    func toHex(includeAlpha: Bool = false) -> String {
        guard let components = UIColor(self).cgColor.components else {
            return "#000000"
        }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        let a = components.count >= 4 ? Float(components[3]) : Float(1.0)

        if includeAlpha {
            return String(format: "#%02lX%02lX%02lX%02lX",
                         lroundf(a * 255),
                         lroundf(r * 255),
                         lroundf(g * 255),
                         lroundf(b * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX",
                         lroundf(r * 255),
                         lroundf(g * 255),
                         lroundf(b * 255))
        }
    }

    // MARK: - Color Adjustments

    /// Lighten color by percentage
    /// - Parameter percentage: Amount to lighten (0.0 - 1.0)
    /// - Returns: Lightened color
    func lighter(by percentage: CGFloat = 0.3) -> Color {
        adjust(by: abs(percentage))
    }

    /// Darken color by percentage
    /// - Parameter percentage: Amount to darken (0.0 - 1.0)
    /// - Returns: Darkened color
    func darker(by percentage: CGFloat = 0.3) -> Color {
        adjust(by: -abs(percentage))
    }

    private func adjust(by percentage: CGFloat) -> Color {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return Color(
            red: min(red + percentage, 1.0),
            green: min(green + percentage, 1.0),
            blue: min(blue + percentage, 1.0),
            opacity: alpha
        )
    }
}
