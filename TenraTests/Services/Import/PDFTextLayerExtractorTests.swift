//
//  PDFTextLayerExtractorTests.swift
//  TenraTests
//
//  Builds a real text-layer PDF in memory (via UIGraphicsPDFRenderer, so
//  words are drawn as actual vector text at known coordinates, not images)
//  and asserts the extractor recovers the true glyph positions rather than
//  synthesizing evenly spaced ones. This is the regression the extractor
//  exists to fix: the old implementation would report a uniform gap between
//  every word regardless of how the text was actually laid out.
//

import Testing
import PDFKit
import UIKit
@testable import Tenra

struct PDFTextLayerExtractorTests {

    /// Draws two words on one line with a large, deliberate gap between them
    /// (mimicking a statement's "date ... amount" row) and a short, ordinary
    /// space-separated gap on another line (mimicking prose). Only the first
    /// line should read as two columns.
    private func makeStatementPDF() -> PDFDocument {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 100)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
            ("01.01.2026" as NSString).draw(at: CGPoint(x: 20, y: 10), withAttributes: attrs)
            ("150.00" as NSString).draw(at: CGPoint(x: 300, y: 10), withAttributes: attrs)
            ("just a note" as NSString).draw(at: CGPoint(x: 20, y: 50), withAttributes: attrs)
        }
        return PDFDocument(data: data)!
    }

    @Test("real glyph gaps drive column detection, not uniform spacing")
    func realGapsDriveColumns() throws {
        let document = makeStatementPDF()
        let snapshot = try #require(PDFTextLayerExtractor.extract(document: document))

        #expect(snapshot.hadTextLayer)
        let table = try #require(snapshot.allTables.first)

        // The wide-gap line must split into (at least) two cells, the first
        // containing the date and the second the amount.
        let dateRow = try #require(table.rows.first { row in
            row.contains { $0.contains("01.01.2026") }
        })
        #expect(dateRow.count >= 2)
        #expect(dateRow.contains { $0.contains("150.00") })

        // The prose line ("just a note") uses ordinary single-space gaps and
        // must NOT be split into separate columns by the same threshold —
        // proof the threshold is derived from real gaps on this page, not a
        // fixed fraction that happens to work for one row.
        let noteRow = table.rows.first { row in
            row.contains { $0.contains("just") }
        }
        if let noteRow {
            #expect(noteRow.contains { $0.contains("just a note") || $0 == "just a note" })
        }
    }

    @Test("no text layer returns nil")
    func noTextLayerReturnsNil() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            // A page with no text drawn at all.
        }
        let document = PDFDocument(data: data)!
        #expect(PDFTextLayerExtractor.extract(document: document) == nil)
    }

    /// Draws a single visual row's two cells in REVERSE content-stream order:
    /// the right-hand amount is painted before the left-hand date, even
    /// though both sit at the same y. Real column-major table renderers (and
    /// right-aligned amount columns) do this. `selectionsByLine()` inserts a
    /// synthetic `\n` when it sees words at the same y painted out of visual
    /// order, splitting one visual row into two `PDFSelection` "lines" — a
    /// row-grouping strategy built on `selectionsByLine()` misreads this as
    /// two single-cell rows instead of one two-cell row.
    private func makeReversePaintOrderPDF() -> PDFDocument {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 100)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
            // Amount (right column) painted FIRST, date (left column) SECOND,
            // both at the same y — reverse of visual left-to-right order.
            ("150.00" as NSString).draw(at: CGPoint(x: 300, y: 20), withAttributes: attrs)
            ("01.01.2026" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: attrs)
            // A second, ordinary-order prose row elsewhere on the page. This
            // is required so the column-gap threshold (median inter-word gap
            // on the page * 3) has more than one gap sample to work with —
            // with only the single wide date/amount gap on the page, the
            // "median" IS that gap, and a gap can never exceed 3x itself, so
            // no split would ever fire. Mirrors makeStatementPDF's baseline.
            ("just a note" as NSString).draw(at: CGPoint(x: 20, y: 60), withAttributes: attrs)
        }
        return PDFDocument(data: data)!
    }

    @Test("row grouping survives reverse paint order (geometry, not PDF line breaks)")
    func rowGroupingSurvivesReversePaintOrder() throws {
        let document = makeReversePaintOrderPDF()
        let snapshot = try #require(PDFTextLayerExtractor.extract(document: document))

        let table = try #require(snapshot.allTables.first)

        // Must be ONE row containing both cells, not two single-cell rows.
        let matchingRows = table.rows.filter { row in
            row.contains { $0.contains("01.01.2026") } || row.contains { $0.contains("150.00") }
        }
        #expect(matchingRows.count == 1)

        let row = try #require(matchingRows.first)
        #expect(row.count >= 2)

        // Left-to-right order: date cell must come before amount cell.
        let dateColumnIndex = row.firstIndex { $0.contains("01.01.2026") }
        let amountColumnIndex = row.firstIndex { $0.contains("150.00") }
        let dateIndex = try #require(dateColumnIndex)
        let amountIndex = try #require(amountColumnIndex)
        #expect(dateIndex < amountIndex)
    }

    /// Pins the `glyphCursor` offset scheme (see the long comment above
    /// `words(on:)`) against drift. `glyphCursor` is a running total advanced
    /// by each line's raw `NSString.length` and never reset or independently
    /// re-verified against `characterBounds(at:)` — if it drifts by even one
    /// UTF-16 unit per line, every word from line 2 onward keeps correct TEXT
    /// but gets WRONG glyph bounds, silently corrupting row grouping and
    /// column splitting on any statement with more than a couple of lines.
    /// Five lines, drawn top-to-bottom in normal paint order (so the last one
    /// drawn is also the last one PDFKit walks and therefore carries the
    /// largest accumulated cursor offset if the scheme is wrong), each at a
    /// distinct known y. Line 2 is Cyrillic, since this app's largest market
    /// is Russian-speaking and Cyrillic is exactly where a UTF-16-vs-Character
    /// index mix-up would surface. The last line carries a deliberate wide
    /// date/amount gap (must split into two columns); the other four lines
    /// carry only ordinary single-space gaps (must NOT split), giving the
    /// gap-threshold logic more than one sample to work from, same as
    /// `makeStatementPDF`.
    ///
    /// The Cyrillic line intentionally avoids the letter "к" (U+043A):
    /// empirically (this test originally used "Покупка кофе..."),
    /// `UIFont.systemFont` drawn via `UIGraphicsPDFRenderer` round-trips
    /// every other Cyrillic letter faithfully but PDFKit's text extraction
    /// silently substitutes "к" with the visually near-identical "ĸ"
    /// (U+0138 LATIN SMALL LETTER KRA) -- a font/glyph-substitution artifact
    /// in the PDF's ToUnicode table, confirmed to happen already in
    /// `lineSelection.string` before this extractor's own code runs at all.
    /// It is unrelated to the offset scheme under test here (see
    /// task-7-report.md Fix pass 2 for the reproduction) so the word choice
    /// below just sidesteps it rather than the test asserting around it.
    private func makeFiveLineStatementPDF() -> PDFDocument {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 220)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
            // Drawn top (largest y) to bottom (smallest y) -- normal reading
            // order -- five distinct rows, 40pt apart.
            ("Statement header text" as NSString).draw(at: CGPoint(x: 20, y: 10), withAttributes: attrs)
            ("Собор старт буфет" as NSString).draw(at: CGPoint(x: 20, y: 50), withAttributes: attrs)
            ("Second sample detail row" as NSString).draw(at: CGPoint(x: 20, y: 90), withAttributes: attrs)
            ("Third filler description text" as NSString).draw(at: CGPoint(x: 20, y: 130), withAttributes: attrs)
            // Last line: wide date/amount gap that must split into 2 columns.
            ("01.01.2026" as NSString).draw(at: CGPoint(x: 20, y: 170), withAttributes: attrs)
            ("150.00" as NSString).draw(at: CGPoint(x: 300, y: 170), withAttributes: attrs)
        }
        return PDFDocument(data: data)!
    }

    @Test("glyph offsets stay accurate across many lines, including non-ASCII text (Finding A)")
    func multiLineOffsetsSurviveDrift() throws {
        let document = makeFiveLineStatementPDF()
        let snapshot = try #require(PDFTextLayerExtractor.extract(document: document))
        #expect(snapshot.hadTextLayer)

        let table = try #require(snapshot.allTables.first)

        // Five lines drawn -> five rows. If the glyph cursor drifted and
        // merged/split rows incorrectly, this count would be wrong.
        #expect(table.rows.count == 5)

        // The last row (bottom of page, last line drawn, largest possible
        // accumulated cursor drift) must have EXACTLY two cells with EXACT
        // content: the date and the amount, cleanly split on the wide gap.
        // This is the assertion with the most power to catch drift: if
        // `glyphCursor` is off by even one unit per preceding line, by line 5
        // the character bounds fed into `rows(from:)`/`table(from:)` no
        // longer correspond to the real glyphs, and this exact-match would
        // fail (wrong split point, corrupted characters, or wrong cell
        // count) even though the row's raw TEXT still reads correctly.
        let lastRow = try #require(table.rows.last)
        #expect(lastRow == ["01.01.2026", "150.00"])

        // The Cyrillic line (line 2 of 5) must survive with its exact text
        // intact and ungarbled -- proof the offset scheme (and the
        // NSString/UTF-16 indexing built on top of it) doesn't mis-handle
        // non-ASCII glyphs partway through the document.
        let cyrillicRow = try #require(table.rows.first { row in
            row.contains { $0.contains("Собор") }
        })
        #expect(cyrillicRow[0] == "Собор старт буфет")
    }
}
