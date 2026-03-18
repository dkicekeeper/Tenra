//
//  LettermarkProvider.swift
//  AIFinanceManager
//
//  Generates lettermark icons with deterministic colors
//

import UIKit

/// Generates a lettermark image (1-2 letters on colored background).
/// Always succeeds — this is the final fallback in the chain.
nonisolated final class LettermarkProvider: LogoProvider {
    let name = "lettermark"

    // 14 colors matching CategoryColors palette
    private static let palette: [UIColor] = [
        UIColor(red: 0x3b/255.0, green: 0x82/255.0, blue: 0xf6/255.0, alpha: 1),
        UIColor(red: 0x8b/255.0, green: 0x5c/255.0, blue: 0xf6/255.0, alpha: 1),
        UIColor(red: 0xec/255.0, green: 0x48/255.0, blue: 0x99/255.0, alpha: 1),
        UIColor(red: 0xf9/255.0, green: 0x73/255.0, blue: 0x16/255.0, alpha: 1),
        UIColor(red: 0xea/255.0, green: 0xb3/255.0, blue: 0x08/255.0, alpha: 1),
        UIColor(red: 0x22/255.0, green: 0xc5/255.0, blue: 0x5e/255.0, alpha: 1),
        UIColor(red: 0x14/255.0, green: 0xb8/255.0, blue: 0xa6/255.0, alpha: 1),
        UIColor(red: 0x06/255.0, green: 0xb6/255.0, blue: 0xd4/255.0, alpha: 1),
        UIColor(red: 0x63/255.0, green: 0x66/255.0, blue: 0xf1/255.0, alpha: 1),
        UIColor(red: 0xd9/255.0, green: 0x46/255.0, blue: 0xef/255.0, alpha: 1),
        UIColor(red: 0xf4/255.0, green: 0x3f/255.0, blue: 0x5e/255.0, alpha: 1),
        UIColor(red: 0xa8/255.0, green: 0x55/255.0, blue: 0xf7/255.0, alpha: 1),
        UIColor(red: 0x10/255.0, green: 0xb9/255.0, blue: 0x81/255.0, alpha: 1),
        UIColor(red: 0xf5/255.0, green: 0x9e/255.0, blue: 0x0b/255.0, alpha: 1),
    ]

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
