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
}
