//
//  PDFTextLayerExtractor.swift
//  Tenra
//
//  Text-layer PDFs (the large majority of bank statements) need no OCR at all:
//  PDFKit already holds exact glyph positions. This extractor uses
//  PDFPage.characterBounds(at:) to find real word boundaries and clusters
//  columns from real horizontal gaps.
//
//  The previous implementation divided each line's width evenly across its
//  words, discarding true positions, and then tried to infer columns from the
//  resulting uniform gaps. That is why long descriptions shifted columns.
//
//  API note: characterBounds(at:) is declared only on PDFPage, not
//  PDFSelection (verified against the iOS 26 SDK headers). To map a
//  character inside a per-line PDFSelection back to a page-relative index we
//  use PDFSelection.range(at:on:), which returns the exact NSRange the
//  selection occupies within page.string. That is PDFKit's own alignment
//  answer, so there is no hand-rolled offset tracking across whitespace or
//  line breaks between selections to get wrong. Indexing is done via NSString
//  (UTF-16) throughout, matching the index space characterBounds(at:) and
//  range(at:on:) both use, rather than Swift's Character-based indexing
//  which can diverge from UTF-16 offsets for multi-code-unit characters.
//

import Foundation
import PDFKit
import CoreGraphics

nonisolated struct PDFTextLayerExtractor {

    private struct PositionedWord {
        let text: String
        let minX: CGFloat
        let maxX: CGFloat
    }

    /// Returns nil when the document has no text layer, so the caller can fall
    /// back to rendering pages and running VisionDocumentExtractor.
    static func extract(document: PDFDocument) -> DocumentSnapshot? {
        var pages: [DocumentSnapshot.Page] = []
        var sawText = false

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            guard let pageText = page.string,
                  !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                pages.append(.init(index: pageIndex, tables: [], lines: [], barcodes: []))
                continue
            }
            sawText = true

            let lineWords = wordsPerLine(on: page)
            let lines = lineWords.map { words in
                words.map(\.text).joined(separator: " ")
            }
            let table = table(from: lineWords)

            pages.append(.init(
                index: pageIndex,
                tables: table.map { [$0] } ?? [],
                lines: lines,
                barcodes: []
            ))
        }

        guard sawText else { return nil }
        return DocumentSnapshot(pages: pages, hadTextLayer: true)
    }

    /// Splits each line into words carrying their real horizontal extent.
    private static func wordsPerLine(on page: PDFPage) -> [[PositionedWord]] {
        guard let fullSelection = page.selection(for: page.bounds(for: .mediaBox)) else {
            return []
        }

        let characterCount = page.numberOfCharacters
        var result: [[PositionedWord]] = []

        for lineSelection in fullSelection.selectionsByLine() {
            guard let lineText = lineSelection.string, !lineText.isEmpty else { continue }
            guard lineSelection.numberOfTextRanges(on: page) > 0 else { continue }

            // The exact page-string offset this line's text begins at. Using
            // PDFKit's own range mapping rather than manually tracking an
            // offset across selections avoids drift from whitespace or line
            // breaks between them.
            let pageRange = lineSelection.range(at: 0, on: page)
            let nsLineText = lineText as NSString

            var words: [PositionedWord] = []
            var currentCharacters = ""
            var currentMinX: CGFloat = .greatestFiniteMagnitude
            var currentMaxX: CGFloat = -.greatestFiniteMagnitude

            for localOffset in 0..<nsLineText.length {
                let unichar = nsLineText.character(at: localOffset)
                let isWhitespace = UnicodeScalar(unichar).map {
                    CharacterSet.whitespacesAndNewlines.contains($0)
                } ?? false

                if isWhitespace {
                    if !currentCharacters.isEmpty {
                        words.append(PositionedWord(text: currentCharacters,
                                                    minX: currentMinX,
                                                    maxX: currentMaxX))
                        currentCharacters = ""
                        currentMinX = .greatestFiniteMagnitude
                        currentMaxX = -.greatestFiniteMagnitude
                    }
                    continue
                }

                let pageOffset = pageRange.location + localOffset
                guard pageOffset < characterCount else { continue }
                let bounds = page.characterBounds(at: pageOffset)

                currentCharacters += nsLineText.substring(with: NSRange(location: localOffset, length: 1))
                currentMinX = min(currentMinX, bounds.minX)
                currentMaxX = max(currentMaxX, bounds.maxX)
            }

            if !currentCharacters.isEmpty {
                words.append(PositionedWord(text: currentCharacters,
                                            minX: currentMinX,
                                            maxX: currentMaxX))
            }
            if !words.isEmpty { result.append(words) }
        }

        return result
    }

    /// Groups words into columns using real inter-word gaps. A gap wider than
    /// `gapThreshold` starts a new column. The threshold is derived from the
    /// page's own typography rather than a fixed page-width fraction, so it
    /// adapts to dense and sparse statements alike.
    private static func table(from lineWords: [[PositionedWord]]) -> DocumentSnapshot.Table? {
        let allGaps: [CGFloat] = lineWords.flatMap { words -> [CGFloat] in
            guard words.count > 1 else { return [] }
            return (0..<(words.count - 1)).map { words[$0 + 1].minX - words[$0].maxX }
        }
        guard !allGaps.isEmpty else { return nil }

        let sortedGaps = allGaps.sorted()
        // Median gap approximates a single space at this font size. A column
        // break is a gap several times wider than that.
        let medianGap = sortedGaps[sortedGaps.count / 2]
        let gapThreshold = max(medianGap * 3.0, 6.0)

        var rows: [[String]] = []
        for words in lineWords {
            var cells: [String] = []
            var current: [String] = []

            for (index, word) in words.enumerated() {
                if index > 0 {
                    let gap = word.minX - words[index - 1].maxX
                    if gap > gapThreshold, !current.isEmpty {
                        cells.append(current.joined(separator: " "))
                        current = []
                    }
                }
                current.append(word.text)
            }
            if !current.isEmpty { cells.append(current.joined(separator: " ")) }
            rows.append(cells)
        }

        // A table needs at least two columns somewhere, otherwise this page is
        // prose and the caller should use `lines`.
        guard rows.contains(where: { $0.count >= 2 }) else { return nil }
        return DocumentSnapshot.Table(rows: rows)
    }
}
