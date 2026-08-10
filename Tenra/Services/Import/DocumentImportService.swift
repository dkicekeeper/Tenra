//
//  DocumentImportService.swift
//  Tenra
//
//  Orchestrates acquisition -> extraction -> interpretation. Runs entirely off
//  the MainActor over Sendable values (CLAUDE.md Red Flag #9): a 40-page
//  statement must not stall the UI.
//
//  Extraction strategy: text-layer PDFs go through PDFKit (exact, fast, no OCR).
//  Scanned PDFs and camera images go through Vision. Interpretation strategy:
//  deterministic ColumnRoleResolver first; escalate to Apple Intelligence only
//  when confidence is low and the model is available.
//

import Foundation
import PDFKit
import CoreGraphics

struct ImportOutcome: Sendable {
    let csvFile: CSVFile
    let statement: ParsedStatement
    let intelligenceStatus: IntelligenceStatus
}

nonisolated struct DocumentImportService {

    /// Below this, escalate column resolution to Apple Intelligence.
    private static let confidenceEscalationThreshold = 0.7

    static func importStatement(
        from url: URL,
        defaultCurrency: String,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> ImportOutcome {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url)
            ?? (try? Data(contentsOf: url)).flatMap(PDFDocument.init(data:))
        else {
            throw PDFError.invalidDocument
        }

        let snapshot: DocumentSnapshot
        if let textLayer = PDFTextLayerExtractor.extract(document: document) {
            progress?(document.pageCount, document.pageCount)
            snapshot = textLayer
        } else {
            let images = PDFService.renderPages(of: document, scale: 3.5) { current, total in
                progress?(current, total)
            }
            snapshot = try await VisionDocumentExtractor.extract(images: images)
        }

        return try await interpret(snapshot: snapshot, defaultCurrency: defaultCurrency)
    }

    static func importStatement(
        images: [CGImage],
        defaultCurrency: String
    ) async throws -> ImportOutcome {
        let snapshot = try await VisionDocumentExtractor.extract(images: images)
        return try await interpret(snapshot: snapshot, defaultCurrency: defaultCurrency)
    }

    // MARK: - Private

    private static func interpret(
        snapshot: DocumentSnapshot,
        defaultCurrency: String
    ) async throws -> ImportOutcome {
        guard let table = bestTable(in: snapshot) else {
            throw PDFError.noTextFound
        }

        var roles = ColumnRoleResolver.resolve(table: table)

        if (roles?.confidence ?? 0) < confidenceEscalationThreshold {
            // `resolve` is `async throws`: it rethrows CancellationError so a
            // user backing out of an import actually stops the work, and returns
            // nil for every genuine model failure.
            if let inferred = try await IntelligentColumnRoleResolver.resolve(table: table) {
                roles = inferred
            }
        }

        guard let resolvedRoles = roles else { throw PDFError.noTextFound }

        let statement = StatementInterpreter.interpret(
            snapshot: snapshot,
            roles: resolvedRoles,
            defaultCurrency: defaultCurrency
        )

        guard !statement.transactions.isEmpty else { throw PDFError.noTextFound }

        return ImportOutcome(
            csvFile: StatementInterpreter.csvFile(from: statement),
            statement: statement,
            intelligenceStatus: IntelligenceAvailability.status
        )
    }

    /// A statement page can hold several tables (account summary, fees,
    /// transactions). The transaction table is the one with the most rows that
    /// also resolves to a usable set of roles.
    static func bestTable(in snapshot: DocumentSnapshot) -> DocumentSnapshot.Table? {
        snapshot.allTables
            .filter { ColumnRoleResolver.resolve(table: $0)?.hasAmountSignal == true }
            .max { $0.rows.count < $1.rows.count }
            ?? snapshot.allTables.max { $0.rows.count < $1.rows.count }
    }
}
