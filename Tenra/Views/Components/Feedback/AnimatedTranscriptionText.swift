//
//  AnimatedTranscriptionText.swift
//  Tenra
//
//  Word-by-word streaming transcription with slide-up entrance.
//  Used by VoiceInputView to surface live speech recognition output.
//
//  Adapter over DesignKit's `StreamingText` (2.9.0): the words, their stable identities and
//  the `.blurSlideWord` entrance are DesignKit's; the recognised entities and the colour of
//  their confidence stay here.
//

import SwiftUI

struct AnimatedTranscriptionText: View {

    let text: String
    let entities: [RecognizedEntity]
    var font: Font = AppTypography.h1
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        StreamingText(text, highlights: highlights, font: font, alignment: alignment)
    }

    /// Each recognised entity tints its words by how sure the recogniser is.
    private var highlights: [StreamingText.Highlight] {
        entities.map { entity in
            StreamingText.Highlight(range: entity.range, color: Self.color(confidence: entity.confidence))
        }
    }

    private static func color(confidence: Double) -> Color {
        switch confidence {
        case 0.8...1.0: return AppColors.success
        case 0.5..<0.8: return AppColors.warning
        default: return AppColors.destructive
        }
    }
}

// MARK: - Preview

#Preview {
    struct Demo: View {
        @State private var text = ""
        private let words = ["Создать", "новое", "приложение", "будильника", "для", "ежедневных", "напоминаний"]
        var body: some View {
            VStack(alignment: .leading) {
                AnimatedTranscriptionText(text: text, entities: [])
                Spacer()
                Button("Add word") {
                    let next = words[min(text.split(separator: " ").count, words.count - 1)]
                    text += text.isEmpty ? next : " \(next)"
                }
            }
            .padding()
        }
    }
    return Demo()
}
