//
//  VisionDocumentExtractor.swift
//  Tenra
//
//  iOS 26 document extraction. RecognizeDocumentsRequest returns a structured
//  document (tables as real grids, paragraphs, barcodes) instead of a bag of
//  text rectangles, which removes the need for the hand-rolled row/column
//  clustering the previous implementation used.
//
//  Language handling: automaticallyDetectLanguage replaces the hardcoded
//  ["ru-RU", "en-US"] list, so the 9 non-Russian locales the app ships in are
//  no longer second-class. useLanguageCorrection is OFF because statement and
//  receipt content is mostly numbers, merchant names, and reference codes,
//  where a language model "correcting" a token silently corrupts an amount.
//

import Foundation
import Vision
import CoreGraphics

enum DocumentExtractionError: LocalizedError {
    case noContentRecognized

    var errorDescription: String? {
        switch self {
        case .noContentRecognized:
            return String(localized: "import.error.noContentRecognized")
        }
    }
}

nonisolated struct VisionDocumentExtractor {

    /// Extra vocabulary that keeps common statement tokens from being mangled.
    private static let customWords = ["IBAN", "SWIFT", "BIC", "POS", "ATM", "P2P"]

    static func extract(images: [CGImage]) async throws -> DocumentSnapshot {
        var pages: [DocumentSnapshot.Page] = []
        for (index, image) in images.enumerated() {
            pages.append(try await extract(image: image, pageIndex: index))
        }
        guard pages.contains(where: { !$0.tables.isEmpty || !$0.lines.isEmpty }) else {
            throw DocumentExtractionError.noContentRecognized
        }
        return DocumentSnapshot(pages: pages, hadTextLayer: false)
    }

    static func extract(image: CGImage, pageIndex: Int) async throws -> DocumentSnapshot.Page {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.customWords = customWords
        // Receipts print totals in small type; the default floor drops them.
        request.textRecognitionOptions.minimumTextHeightFraction = 0.008
        // Fiscal receipts in several markets carry a QR with the authoritative
        // total. Nothing reads it yet; it is collected because it is free here
        // and re-running extraction later would not be. Surfaced on
        // DocumentSnapshot.allBarcodes for a future fiscal-lookup path.
        request.barcodeDetectionOptions.enabled = true

        let observations = try await request.perform(on: image)
        guard let container = observations.first?.document else {
            return DocumentSnapshot.Page(index: pageIndex, tables: [], lines: [], barcodes: [])
        }

        return DocumentSnapshot.Page(
            index: pageIndex,
            tables: container.tables.map(snapshotTable(from:)),
            lines: lines(from: container),
            barcodes: container.barcodes.compactMap { barcode in
                guard let payload = barcode.payloadString else { return nil }
                return DocumentSnapshot.Barcode(
                    payload: payload,
                    symbology: String(describing: barcode.symbology)
                )
            }
        )
    }

    /// Flattens a Vision table into a rectangular grid of strings.
    /// `cell(row:col:)` is used rather than iterating `rows` directly because a
    /// merged cell appears in every row it spans, and the grid accessor already
    /// resolves that.
    private static func snapshotTable(
        from table: DocumentObservation.Container.Table
    ) -> DocumentSnapshot.Table {
        let columnCount = table.columns.count
        let rowCount = table.rows.count
        var grid: [[String]] = []
        grid.reserveCapacity(rowCount)

        for row in 0..<rowCount {
            var cells: [String] = []
            cells.reserveCapacity(columnCount)
            for column in 0..<columnCount {
                let text = table.cell(row: row, col: column)?.content.text.transcript ?? ""
                cells.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            grid.append(cells)
        }
        return DocumentSnapshot.Table(rows: grid)
    }

    /// Every text line on the page, in reading order. Line breaks are preserved
    /// deliberately: the previous implementation joined recognized strings with
    /// a single space, which destroyed every line-oriented fallback.
    ///
    /// Table rows are folded in as lines too. `Container.Table.Cell.content` is
    /// itself a nested `Container`, and the SDK does not document whether cell
    /// text also surfaces in the parent's `text.lines`. On a bank statement the
    /// transactions live almost entirely inside tables, so if it does not, this
    /// "fallback" would be empty exactly when it is needed. Building it from
    /// both sources makes it complete regardless of which way the SDK behaves.
    /// Rows already present verbatim are not appended twice.
    private static func lines(from container: DocumentObservation.Container) -> [String] {
        var lines = container.text.lines
            .map { $0.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set(lines)
        for table in container.tables {
            for row in snapshotTable(from: table).rows {
                let line = row.filter { !$0.isEmpty }.joined(separator: " ")
                guard !line.isEmpty, seen.insert(line).inserted else { continue }
                lines.append(line)
            }
        }
        return lines
    }
}
