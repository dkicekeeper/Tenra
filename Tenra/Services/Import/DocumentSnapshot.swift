//
//  DocumentSnapshot.swift
//  Tenra
//
//  Sendable seam between document extraction (Vision / PDFKit) and
//  interpretation (statement / receipt parsing). Extraction produces one of
//  these; interpretation consumes only this. Tests build them by hand.
//

import Foundation

/// A fully extracted document, independent of how it was extracted.
nonisolated struct DocumentSnapshot: Sendable, Equatable {

    /// A rectangular table. `rows` is always rectangular: every row has
    /// exactly `columnCount` entries, padded with "" where a cell is missing
    /// or spans. Cell text is already trimmed.
    nonisolated struct Table: Sendable, Equatable {
        let rows: [[String]]
        let columnCount: Int

        init(rows: [[String]]) {
            let width = rows.map(\.count).max() ?? 0
            self.columnCount = width
            self.rows = rows.map { row in
                var padded = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                while padded.count < width { padded.append("") }
                return padded
            }
        }

        /// First row, by convention the header. `nil` for an empty table.
        var headerRow: [String]? { rows.first }

        /// Everything after the header row.
        var bodyRows: ArraySlice<[String]> { rows.dropFirst() }
    }

    nonisolated struct Barcode: Sendable, Equatable {
        let payload: String
        /// Raw symbology identifier, e.g. "qr", "ean13". Free-form on purpose:
        /// interpretation only pattern-matches the payload.
        let symbology: String
    }

    nonisolated struct Page: Sendable, Equatable {
        let index: Int
        let tables: [Table]
        /// Every text line on the page in reading order, table content included.
        /// This is the fallback when no table is detected.
        let lines: [String]
        let barcodes: [Barcode]
    }

    let pages: [Page]

    /// True when the document contained a machine-readable text layer, so no
    /// OCR ran. Used to decide whether to trust the text verbatim.
    let hadTextLayer: Bool

    var allTables: [Table] { pages.flatMap(\.tables) }
    var allLines: [String] { pages.flatMap(\.lines) }
    var allBarcodes: [Barcode] { pages.flatMap(\.barcodes) }

    /// Whole document as plain text, one line per line, pages separated by a
    /// blank line. Line breaks are preserved on purpose: the previous
    /// implementation joined OCR output with spaces and broke every
    /// line-oriented fallback downstream.
    var plainText: String {
        pages.map { $0.lines.joined(separator: "\n") }
            .joined(separator: "\n\n")
    }
}
