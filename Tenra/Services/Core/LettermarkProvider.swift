//
//  LettermarkProvider.swift
//  Tenra
//
//  Generates lettermark icons with deterministic colors
//

import SwiftUI
import UIKit

/// Generates a lettermark image (1-2 letters on colored background).
/// Always succeeds — this is the final fallback in the chain.
nonisolated final class LettermarkProvider: LogoProvider {
    let name = "lettermark"

    // DesignKit's category palette (CategoryColors.paletteColors): a lettermark takes the
    // colour its name would have as a category.
    private static let palette: [UIColor] = CategoryColors.paletteColors.map { UIColor($0) }

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        let letters = Self.extractLetters(from: domain)
        let color = Self.deterministicColor(for: domain)
        return Self.renderLettermark(letters: letters, color: color, size: size)
    }

    /// Extract 1-2 representative letters from domain or display name.
    /// Uses ServiceLogoRegistry for display name lookup.
    static func extractLetters(from domain: String) -> String {
        // Try to get display name from registry
        let displayName = ServiceLogoRegistry.domainMap[domain.lowercased()]?.displayName

        if let name = displayName {
            let words = name.split(separator: " ")
            if words.count >= 2 {
                let first = String(words[0].prefix(1))
                let second = String(words[1].prefix(1))
                return (first + second).uppercased()
            } else {
                return String(name.prefix(2)).uppercased()
            }
        }

        // Fallback: use domain name part (before first dot)
        let namePart = domain.split(separator: ".").first.map(String.init) ?? domain
        return String(namePart.prefix(2)).uppercased()
    }

    /// Deterministic color using djb2 hash (stable across app launches).
    static func deterministicColor(for domain: String) -> UIColor {
        let lowered = domain.lowercased()
        var hash: UInt64 = 5381
        for byte in lowered.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(palette.count))
        return palette[index]
    }

    /// Render lettermark image
    static func renderLettermark(letters: String, color: UIColor, size: CGFloat) -> UIImage {
        let actualSize = max(size, 64)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: actualSize, height: actualSize))

        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: actualSize, height: actualSize))
            let cornerRadius = actualSize * 0.2
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            color.setFill()
            path.fill()

            let fontSize = actualSize * 0.38
            let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
            ]

            let textSize = (letters as NSString).size(withAttributes: attributes)
            let textRect = CGRect(
                x: (actualSize - textSize.width) / 2,
                y: (actualSize - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (letters as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }
}
