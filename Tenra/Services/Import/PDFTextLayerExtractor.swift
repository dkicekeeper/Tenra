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
//  character inside a per-line PDFSelection back to a page-relative index,
//  this tracks its own running glyph cursor across selectionsByLine(),
//  advanced by each line's own NSString length — NOT PDFSelection's
//  range(at:on:). range(at:on:)'s location is in the same index space as
//  page.string/numberOfCharacters, which counts PDFKit's synthesized `\n`
//  between lines; characterBounds(at:) is indexed densely over only the
//  glyphs actually painted, with no reserved slot for those separators. The
//  two spaces disagree by one glyph per preceding line, confirmed by
//  dumping characterBounds(at:) across a 3-line test PDF (see git history /
//  task-7-report.md for the reproduction). Indexing is done via NSString
//  (UTF-16) throughout, matching the index space characterBounds(at:) uses,
//  rather than Swift's Character-based indexing which can diverge from
//  UTF-16 offsets for multi-code-unit characters.
//

import Foundation
import PDFKit
import CoreGraphics

nonisolated struct PDFTextLayerExtractor {

    private struct PositionedWord {
        let text: String
        let minX: CGFloat
        let maxX: CGFloat
        let minY: CGFloat
        let maxY: CGFloat
        /// Vertical center of the word's glyph bounds. Used to group words
        /// into visual rows independent of PDF paint order (see `rows(from:)`).
        var midY: CGFloat { (minY + maxY) / 2 }
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

            let pageWords = words(on: page)
            guard !pageWords.isEmpty else {
                // The page's text layer is non-empty (page.string passed the
                // guard above) but the geometry walk found zero words —
                // e.g. a selection failure on an unusual font/encoding, or
                // protected content. Silently emitting an empty page here
                // would drop that page's content (its tables AND its lines)
                // with no signal at all: `sawText` would already be true
                // from an earlier page, so the document-level nil below
                // would never trip and the caller would never fall back to
                // Vision OCR. Deliberately fail the WHOLE document instead,
                // so the caller re-renders and OCRs every page. Rendering
                // and OCRing a page we could have read cheaply is a small
                // cost; silently dropping a page of a user's bank statement
                // is not. Do not "optimize" this into a per-page skip.
                return nil
            }

            let lineWords = rows(from: pageWords)
            let lines = lineWords.map { rowWords in
                rowWords.map(\.text).joined(separator: " ")
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

    /// Collects every word on the page into one flat array carrying its real
    /// glyph bounds. `selectionsByLine()` is used purely as a word source
    /// here (turning PDFKit selections into per-character bounds via
    /// `characterBounds(at:)`) — its line grouping is discarded. PDFKit
    /// inserts a synthetic `\n` into `selectionsByLine()` when words at the
    /// same visual y are painted out of left-to-right order in the content
    /// stream (column-major table renderers, right-aligned amount columns),
    /// which silently splits one visual row into multiple single-cell
    /// "lines". Rows are re-derived from real glyph geometry in
    /// `rows(from:)` instead.
    ///
    /// Offset note: this does NOT use `PDFSelection.range(at:on:)` to find
    /// where a line begins, despite that looking like the obvious answer.
    /// Empirically (built a 3-line PDF, dumped `characterBounds(at:)` for
    /// every page index): `range(at:on:)`'s location is in the same index
    /// space as `page.string`/`numberOfCharacters`, which counts PDFKit's
    /// synthesized `\n` between lines. `characterBounds(at:)` is indexed
    /// densely over only the *actually painted* glyphs, with no reserved
    /// slot for those synthetic separators (out-of-range indices at the end
    /// return a degenerate zero rect instead). Using `range(at:on:)`'s
    /// location as a `characterBounds` offset is therefore off by one glyph
    /// per preceding line — confirmed to corrupt every line after the first
    /// ("just a note" lost its leading "j" and its bounds went to (0,0)).
    /// Instead this tracks its own running glyph cursor, advanced by each
    /// line's own `nsLineText.length` (which excludes the synthetic
    /// separators), matching `characterBounds`' dense numbering exactly.
    private static func words(on page: PDFPage) -> [PositionedWord] {
        guard let fullSelection = page.selection(for: page.bounds(for: .mediaBox)) else {
            return []
        }

        let characterCount = page.numberOfCharacters
        var result: [PositionedWord] = []
        var glyphCursor = 0

        for lineSelection in fullSelection.selectionsByLine() {
            guard let lineText = lineSelection.string, !lineText.isEmpty else { continue }

            let nsLineText = lineText as NSString
            let lineOffset = glyphCursor
            glyphCursor += nsLineText.length

            var currentCharacters = ""
            var currentMinX: CGFloat = .greatestFiniteMagnitude
            var currentMaxX: CGFloat = -.greatestFiniteMagnitude
            var currentMinY: CGFloat = .greatestFiniteMagnitude
            var currentMaxY: CGFloat = -.greatestFiniteMagnitude

            for localOffset in 0..<nsLineText.length {
                let unichar = nsLineText.character(at: localOffset)
                let isWhitespace = UnicodeScalar(unichar).map {
                    CharacterSet.whitespacesAndNewlines.contains($0)
                } ?? false

                if isWhitespace {
                    if !currentCharacters.isEmpty {
                        result.append(PositionedWord(text: currentCharacters,
                                                      minX: currentMinX,
                                                      maxX: currentMaxX,
                                                      minY: currentMinY,
                                                      maxY: currentMaxY))
                        currentCharacters = ""
                        currentMinX = .greatestFiniteMagnitude
                        currentMaxX = -.greatestFiniteMagnitude
                        currentMinY = .greatestFiniteMagnitude
                        currentMaxY = -.greatestFiniteMagnitude
                    }
                    continue
                }

                let pageOffset = lineOffset + localOffset
                guard pageOffset < characterCount else { continue }
                let bounds = page.characterBounds(at: pageOffset)

                currentCharacters += nsLineText.substring(with: NSRange(location: localOffset, length: 1))
                currentMinX = min(currentMinX, bounds.minX)
                currentMaxX = max(currentMaxX, bounds.maxX)
                currentMinY = min(currentMinY, bounds.minY)
                currentMaxY = max(currentMaxY, bounds.maxY)
            }

            if !currentCharacters.isEmpty {
                result.append(PositionedWord(text: currentCharacters,
                                              minX: currentMinX,
                                              maxX: currentMaxX,
                                              minY: currentMinY,
                                              maxY: currentMaxY))
            }
        }

        return result
    }

    /// Groups words into visual rows by vertical proximity, independent of
    /// PDF paint order. Two words belong to the same row when their glyph
    /// midpoints (`midY`) differ by less than a tolerance derived from the
    /// page's own typography (median word height * 0.5, floored at 2.0pt) —
    /// not a fixed fraction of page height, so it adapts to the page's own
    /// font size. PDFKit's coordinate origin is bottom-left with y increasing
    /// upward, so rows are sorted by descending y (top of page first).
    private static func rows(from words: [PositionedWord]) -> [[PositionedWord]] {
        guard !words.isEmpty else { return [] }

        let heights = words.map { $0.maxY - $0.minY }.sorted()
        let medianHeight = heights[heights.count / 2]
        let tolerance = max(medianHeight * 0.5, 2.0)

        let sortedByY = words.sorted { lhs, rhs in
            if lhs.midY != rhs.midY { return lhs.midY > rhs.midY }
            return lhs.minX < rhs.minX
        }

        var rowGroups: [[PositionedWord]] = []
        for word in sortedByY {
            // Compare against the row's anchor (its first word, i.e. the
            // highest midY seen in this row so far) rather than the previous
            // word, so tolerance doesn't drift across a wide row.
            if let lastIndex = rowGroups.indices.last,
               let anchor = rowGroups[lastIndex].first,
               abs(word.midY - anchor.midY) < tolerance {
                rowGroups[lastIndex].append(word)
            } else {
                rowGroups.append([word])
            }
        }

        // Left-to-right within each row.
        return rowGroups.map { row in row.sorted { $0.minX < $1.minX } }
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
