//
//  AnimatedTranscriptionText.swift
//  Tenra
//
//  Word-by-word streaming transcription with slide-up entrance.
//  Used by VoiceInputView to surface live speech recognition output.
//
//  Performance notes
//  -----------------
//  • Words are tokenised once per `text` change into `@State`, not per body
//    eval. The previous computed-property approach re-tokenised on every
//    body call (and `body` was invoked many times per second by Apple Speech).
//  • Per-word color is precomputed at tokenization time so layout passes
//    don't re-scan entities O(N·M).
//  • Stable IDs are assigned to words whose text matches the previous
//    snapshot, so Speech "refinements" don't re-trigger entrance animations
//    for words that are already visible.
//  • The entrance is the shared `.blurSlideWord` transition (slide + fade +
//    blur). Per-word blur was once the dominant cost when many words appeared
//    at once, so the word preset keeps the radius small and blur only runs on
//    words actually transitioning (stable IDs skip settled ones).
//

import SwiftUI

struct AnimatedTranscriptionText: View {

    let text: String
    let entities: [RecognizedEntity]
    var font: Font = AppTypography.h1
    var alignment: HorizontalAlignment = .leading

    @State private var tokens: [WordToken] = []
    @State private var nextWordID: Int = 0

    var body: some View {
        WordFlowLayout(spacing: 8, lineSpacing: 6, alignment: alignment) {
            ForEach(tokens) { token in
                Text(token.text)
                    .font(font)
                    .foregroundStyle(token.color)
                    .transition(.blurSlideWord)
            }
        }
        .onAppear { refreshTokens() }
        .onChange(of: text) { _, _ in refreshTokens() }
        .onChange(of: entities.count) { _, _ in refreshTokens() }
    }

    private func refreshTokens() {
        let parsed = Self.parseWords(text: text, entities: entities)
        let next = Self.reconcile(previous: tokens, parsed: parsed, startingID: nextWordID)
        withAnimation(AppAnimation.gentleSpring) {
            tokens = next.tokens
        }
        nextWordID = next.nextID
    }

    // MARK: - Tokenization

    fileprivate struct WordToken: Identifiable, Equatable {
        let id: Int
        let text: String
        let color: Color
    }

    private struct ParsedWord: Equatable {
        let text: String
        let color: Color
    }

    private static func parseWords(text: String, entities: [RecognizedEntity]) -> [ParsedWord] {
        guard !text.isEmpty else { return [] }
        var result: [ParsedWord] = []
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        ns.enumerateSubstrings(in: fullRange, options: .byWords) { sub, subRange, _, _ in
            guard let s = sub, !s.isEmpty else { return }
            result.append(ParsedWord(text: s, color: colorFor(range: subRange, entities: entities)))
        }
        return result
    }

    private static func colorFor(range: NSRange, entities: [RecognizedEntity]) -> Color {
        for entity in entities where NSIntersectionRange(entity.range, range).length > 0 {
            switch entity.confidence {
            case 0.8...1.0: return AppColors.success
            case 0.5..<0.8: return AppColors.warning
            default: return AppColors.destructive
            }
        }
        return AppColors.textPrimary
    }

    /// Match new parsed words against existing tokens by content from the head.
    /// Words that match keep their ID (no entrance re-animation), trailing new
    /// words get fresh IDs, and any orphaned tail tokens are dropped.
    private static func reconcile(
        previous: [WordToken],
        parsed: [ParsedWord],
        startingID: Int
    ) -> (tokens: [WordToken], nextID: Int) {
        var result: [WordToken] = []
        result.reserveCapacity(parsed.count)
        var nextID = startingID

        for (idx, word) in parsed.enumerated() {
            if idx < previous.count, previous[idx].text == word.text {
                // Same word in same slot — keep identity; refresh color in case
                // entities resolved later.
                result.append(WordToken(id: previous[idx].id, text: word.text, color: word.color))
            } else {
                result.append(WordToken(id: nextID, text: word.text, color: word.color))
                nextID += 1
            }
        }
        return (result, nextID)
    }
}

// MARK: - Word Flow Layout

private struct WordFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading

    struct LayoutCache {
        var rows: [Row] = []
        var measuredWidth: CGFloat = -1
        var subviewCount: Int = -1
    }

    struct Row {
        var items: [RowItem]
        var width: CGFloat
        var height: CGFloat
    }

    struct RowItem {
        let index: Int
        let size: CGSize
    }

    func makeCache(subviews: Subviews) -> LayoutCache { LayoutCache() }

    func updateCache(_ cache: inout LayoutCache, subviews: Subviews) {
        if cache.subviewCount != subviews.count {
            cache.measuredWidth = -1
            cache.subviewCount = subviews.count
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout LayoutCache) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        ensureRows(maxWidth: maxWidth, subviews: subviews, cache: &cache)
        let rows = cache.rows
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + max(0, CGFloat(rows.count - 1)) * lineSpacing
        let width = rows.map { $0.width }.max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout LayoutCache) {
        ensureRows(maxWidth: bounds.width, subviews: subviews, cache: &cache)
        var y = bounds.minY
        for row in cache.rows {
            let rowStartX: CGFloat
            switch alignment {
            case .center: rowStartX = bounds.minX + (bounds.width - row.width) / 2
            case .trailing: rowStartX = bounds.maxX - row.width
            default: rowStartX = bounds.minX
            }
            var x = rowStartX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func ensureRows(maxWidth: CGFloat, subviews: Subviews, cache: inout LayoutCache) {
        if cache.measuredWidth == maxWidth, cache.subviewCount == subviews.count, !cache.rows.isEmpty {
            return
        }

        var rows: [Row] = []
        var current = Row(items: [], width: 0, height: 0)

        for (idx, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let projectedWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if projectedWidth > maxWidth && !current.items.isEmpty {
                rows.append(current)
                current = Row(items: [], width: 0, height: 0)
            }
            if current.items.isEmpty {
                current.width = size.width
            } else {
                current.width += spacing + size.width
            }
            current.height = max(current.height, size.height)
            current.items.append(RowItem(index: idx, size: size))
        }
        if !current.items.isEmpty { rows.append(current) }

        cache.rows = rows
        cache.measuredWidth = maxWidth
        cache.subviewCount = subviews.count
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
