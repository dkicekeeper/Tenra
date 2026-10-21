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
    /// Registry domain of the bank that issued the statement ("kaspi.kz"), when its
    /// web domain is printed on the pages. Picks the review screen's default account.
    var bankDomain: String? = nil
    /// Closing balances the statement prints (StatementBalanceParser), for the
    /// review screen's balance check.
    var closingBalances: [StatementBalance] = []
}

/// What a PDF from a bank app holds: a statement, or the receipt of one payment or transfer.
enum DocumentContent: Sendable {
    case statement(ImportOutcome)
    case receipt(ReceiptDraft)
}

nonisolated struct DocumentImportService {

    /// Below this, escalate column resolution to Apple Intelligence.
    private static let confidenceEscalationThreshold = 0.7

    static func importStatement(
        from url: URL,
        defaultCurrency: String,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> ImportOutcome {
        let (snapshot, unreadablePages) = try await extractText(of: url, progress: progress)
        return try await interpret(snapshot: snapshot, defaultCurrency: defaultCurrency, unreadablePages: unreadablePages)
    }

    /// A PDF a bank app shares (every bank's is different): a statement, or the receipt of one
    /// payment or transfer, which has no table of operations. See `content(snapshot:)`.
    static func importDocument(
        from url: URL,
        defaultCurrency: String,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> DocumentContent {
        let (snapshot, unreadablePages) = try await extractText(of: url, progress: progress)
        return try await content(snapshot: snapshot, defaultCurrency: defaultCurrency, unreadablePages: unreadablePages)
    }

    /// Read as a statement first. When no table of operations resolves (`noTextFound`,
    /// `layoutNotRecognized`) and the text reads as one payment
    /// (`ReceiptInterpreter.looksLikeOnePayment`: one page, at most three dated lines, a labelled
    /// total or recipient), it is read as a receipt. A statement the parser cannot read keeps
    /// its error, and one whose rows were all skipped stays a statement for its diagnostics.
    static func content(
        snapshot: DocumentSnapshot,
        defaultCurrency: String,
        unreadablePages: [Int] = []
    ) async throws -> DocumentContent {
        do {
            return .statement(try await interpret(
                snapshot: snapshot,
                defaultCurrency: defaultCurrency,
                unreadablePages: unreadablePages
            ))
        } catch let error as PDFError {
            switch error {
            case .noTextFound, .layoutNotRecognized:
                guard ReceiptInterpreter.looksLikeOnePayment(snapshot),
                      let draft = try await ReceiptInterpreter.interpret(
                    snapshot: snapshot,
                    defaultCurrency: defaultCurrency
                ) else { throw error }
                return .receipt(draft)
            default:
                throw error
            }
        }
    }

    /// Deletes the copy of a document once read: the picker's in the temporary folder, the
    /// one "Open in" leaves in Documents/Inbox. Never a file elsewhere.
    static func discardCopy(_ url: URL) {
        let path = url.standardizedFileURL.path
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let inbox = URL.documentsDirectory.appending(path: "Inbox").standardizedFileURL.path
        guard path.hasPrefix(temporary) || path.hasPrefix(inbox) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// The PDF's text: its text layer, else Vision over the rendered pages, with the pages
    /// that could not be rendered.
    private static func extractText(
        of url: URL,
        progress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> (DocumentSnapshot, [Int]) {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url)
            ?? (try? Data(contentsOf: url)).flatMap(PDFDocument.init(data:))
        else {
            throw PDFError.invalidDocument
        }

        let snapshot: DocumentSnapshot
        // Indices of pages `PDFService.renderPages` could not rasterize
        // (page(at:) or cgImage nil — more likely now that scale 3.5 raises
        // memory pressure on large multi-page statements). Reported to the
        // user as skipped rows rather than silently vanishing, which would
        // otherwise shift every later page's index into the wrong slot.
        var unreadablePages: [Int] = []
        if let textLayer = PDFTextLayerExtractor.extract(document: document) {
            progress?(document.pageCount, document.pageCount)
            snapshot = textLayer
        } else {
            let images = PDFService.renderPages(of: document, scale: 3.5) { current, total in
                progress?(current, total)
            }
            unreadablePages = images.enumerated().compactMap { $0.element == nil ? $0.offset : nil }
            snapshot = try await VisionDocumentExtractor.extract(images: images)
        }
        return (snapshot, unreadablePages)
    }

    static func importStatement(
        images: [CGImage],
        defaultCurrency: String
    ) async throws -> ImportOutcome {
        let snapshot = try await VisionDocumentExtractor.extract(images: images)
        return try await interpret(snapshot: snapshot, defaultCurrency: defaultCurrency)
    }

    // MARK: - Internal (not private: exercised directly by DocumentImportServiceTests
    // against hand-built DocumentSnapshot values, the same way bestTable(in:) below is).

    static func interpret(
        snapshot: DocumentSnapshot,
        defaultCurrency: String,
        unreadablePages: [Int] = []
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

        // Distinct from noTextFound: we DID read the document, we just could not
        // work out which column means what. Telling the user "no text found"
        // there is both wrong and unactionable.
        guard let resolvedRoles = roles else { throw PDFError.layoutNotRecognized }

        var statement = StatementInterpreter.interpret(
            snapshot: snapshot,
            roles: resolvedRoles,
            defaultCurrency: defaultCurrency
        )

        if !unreadablePages.isEmpty {
            // `cells` deliberately holds the raw 1-based page number, not a
            // localized "Page N" string: everywhere else in this pipeline
            // `cells` is raw document content and `reason` is a pure
            // localization key (see SkippedRow's doc comment), and mixing
            // resolved UI text into `cells` here would be the only
            // exception. ImportDiagnosticsView prefixes the localized
            // "Page" label at render time instead.
            let pageSkips = unreadablePages.map { pageIndex in
                SkippedRow(rowIndex: -(pageIndex + 1),
                          cells: ["\(pageIndex + 1)"],
                          reason: "import.skip.pageUnreadable")
            }
            statement = ParsedStatement(transactions: statement.transactions,
                                        skipped: pageSkips + statement.skipped,
                                        resolvedRoles: statement.resolvedRoles)
        }

        // Layout resolved, rows read, but nothing survived interpretation:
        // still returned rather than thrown, with an empty transaction list
        // and a populated `skipped` array. The all-skipped case must reach
        // the diagnostics screen just like the partial-recognition case
        // does — that screen exists precisely so a user importing a
        // statement the interpreter misreads can see which rows failed and
        // why, instead of a generic error and no way to find out.
        return ImportOutcome(
            csvFile: StatementInterpreter.csvFile(from: statement),
            statement: statement,
            intelligenceStatus: IntelligenceAvailability.status,
            bankDomain: StatementBankDetector.bankDomain(in: snapshot.allLines),
            closingBalances: StatementBalanceParser.closingBalances(in: snapshot.allLines)
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
