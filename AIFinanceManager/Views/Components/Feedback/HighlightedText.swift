//
//  HighlightedText.swift
//  AIFinanceManager
//
//  Created on 2026-01-19
//

import SwiftUI

/// Displays text with highlighted entities based on confidence levels
struct HighlightedText: View {

    // MARK: - Properties

    /// Original text to display
    let text: String

    /// Recognized entities to highlight
    let entities: [RecognizedEntity]

    /// Font for the text
    var font: Font = AppTypography.body

    // MARK: - Body

    var body: some View {
        Text(attributedString)
            .font(font)
    }

    // MARK: - Private Computed Properties

    /// Generate AttributedString with highlighted entities
    private var attributedString: AttributedString {
        var attributed = AttributedString(text)

        // Apply highlighting to each entity
        for entity in entities {
            // Convert NSRange to AttributedString range
            guard let range = Range(entity.range, in: text),
                  let attributedRange = attributed.range(of: String(text[range])) else {
                continue
            }

            // Choose color based on confidence
            let color = colorForConfidence(entity.confidence)

            // Apply foreground color
            attributed[attributedRange].foregroundColor = color

            // Add bold weight for high confidence
            if entity.confidence >= 0.8 {
                attributed[attributedRange].font = AppTypography.bodyEmphasis
            }
        }

        return attributed
    }

    // MARK: - Private Methods

    /// Get color for confidence level
    /// - Parameter confidence: Confidence value (0.0 - 1.0)
    /// - Returns: Color for highlighting
    private func colorForConfidence(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...1.0:
            return .green // High confidence
        case 0.5..<0.8:
            return .orange // Medium confidence
        default:
            return .red // Low confidence
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // High confidence example
        HighlightedText(
            text: "500 тенге на продукты",
            entities: [
                RecognizedEntity(type: .amount, range: NSRange(location: 0, length: 10), value: "500 тенге", confidence: 0.9),
                RecognizedEntity(type: .category, range: NSRange(location: 14, length: 8), value: "продукты", confidence: 0.85)
            ]
        )

        // Medium confidence example
        HighlightedText(
            text: "тысяча на еду",
            entities: [
                RecognizedEntity(type: .amount, range: NSRange(location: 0, length: 6), value: "тысяча", confidence: 0.7),
                RecognizedEntity(type: .category, range: NSRange(location: 10, length: 3), value: "еду", confidence: 0.6)
            ]
        )

        // Low confidence example
        HighlightedText(
            text: "деньги на что-то",
            entities: [
                RecognizedEntity(type: .amount, range: NSRange(location: 0, length: 6), value: "деньги", confidence: 0.3)
            ]
        )
    }
    .padding()
}
