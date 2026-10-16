//
//  AssistantAttachmentSources.swift
//  Tenra
//
//  Where an attachment comes from (docs/plan-ai-assistant.md §3.8): the paperclip's menu
//  (`AssistantAttachmentMenu`) picks a source, and this modifier presents it and reads what was
//  picked with the import pipelines (docs/domains/import.md), on the phone:
//  - a receipt from the camera scanner or from photos: VisionDocumentExtractor, then
//    ReceiptInterpreter;
//  - a PDF statement: DocumentImportService, then StatementReviewPreparer;
//  - a CSV file: the CSV import flow as it is (preview, column mapping, result), with no card;
//    Tenra Pro, as Settings → Import CSV is.
//  A file opened in Tenra from another app (AppCoordinator.pendingAttachment) is read the same
//  way. Statements hold names, account numbers and balances: the copy read here is deleted once
//  read.
//

import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum AssistantAttachmentSource: Equatable {
    case scanner
    case photos
    case file
}

/// The paperclip: a menu of sources.
struct AssistantAttachmentMenu: View {
    let onPick: (AssistantAttachmentSource) -> Void

    var body: some View {
        Menu {
            Button(String(localized: "assistant.attach.scan"), systemImage: "doc.viewfinder") { onPick(.scanner) }
            Button(String(localized: "assistant.attach.photo"), systemImage: "photo") { onPick(.photos) }
            Button(String(localized: "assistant.attach.file"), systemImage: "doc.text") { onPick(.file) }
        } label: {
            MessageComposerAccessory(systemImage: "paperclip")
        }
        .accessibilityLabel(String(localized: "assistant.attach"))
    }
}

extension View {
    /// Presents the picked source and reads the attachment. `reading` is on while it reads.
    /// - Parameter takesHandedOverFiles: this page also reads a file opened in Tenra from another
    ///   app (the assistant's home; a chat leaves it to the home).
    func assistantAttachmentSources(
        source: Binding<AssistantAttachmentSource?>,
        reading: Binding<Bool>,
        takesHandedOverFiles: Bool,
        onRead: @escaping (AgentAttachment, AgentAttachmentSummary) -> Void,
        onFailure: @escaping (String) -> Void
    ) -> some View {
        modifier(AssistantAttachmentSources(
            source: source,
            reading: reading,
            takesHandedOverFiles: takesHandedOverFiles,
            onRead: onRead,
            onFailure: onFailure
        ))
    }
}

private struct AssistantAttachmentSources: ViewModifier {
    @Binding var source: AssistantAttachmentSource?
    @Binding var reading: Bool
    let takesHandedOverFiles: Bool
    let onRead: (AgentAttachment, AgentAttachmentSummary) -> Void
    let onFailure: (String) -> Void

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(PremiumManager.self) private var premium
    @State private var photo: PhotosPickerItem?
    /// A CSV waiting on the paywall.
    @State private var csvAwaitingPro: URL?
    @State private var showingPaywall = false
    /// The CSV flow; replaced by a wired one when a CSV is picked.
    @State private var csvFlow = ImportFlowCoordinator(transactionsViewModel: nil, categoriesViewModel: nil, accountsViewModel: nil)

    func body(content: Content) -> some View {
        ImportFlowSheetsContainer(flowCoordinator: csvFlow, onCancel: { csvFlow.cancel() }) {
            content
        }
        .fullScreenCover(isPresented: presenting(.scanner)) {
            DocumentScannerView(
                onScan: { images in
                    source = nil
                    read { try await receipt(from: images) }
                },
                onCancel: { source = nil }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: presenting(.photos), selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            read {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data).flatMap(Self.upright) else {
                    throw AttachmentReadError.unreadable
                }
                return try await receipt(from: [image])
            }
        }
        .sheet(isPresented: presenting(.file)) {
            DocumentPicker(contentTypes: [.pdf, .commaSeparatedText]) { url in
                source = nil
                openFile(url)
            }
        }
        .onChange(of: coordinator.pendingAttachment, initial: true) { _, url in
            guard takesHandedOverFiles, url != nil, let url = coordinator.consumePendingAttachment() else { return }
            openFile(url)
        }
        .paywallSheet(isPresented: $showingPaywall) {
            guard let url = csvAwaitingPro else { return }
            csvAwaitingPro = nil
            importCSV(url)
        }
        .onChange(of: showingPaywall) { _, shown in
            // Closed without Pro: the copy of the file goes.
            guard !shown, !premium.isPro, let url = csvAwaitingPro else { return }
            csvAwaitingPro = nil
            Self.discardCopy(url)
        }
    }

    /// A picked or handed-over file: a CSV into its import flow, a PDF read as a statement.
    private func openFile(_ url: URL) {
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .commaSeparatedText) == true {
            guard premium.isPro else {
                csvAwaitingPro = url
                // Once the file picker's sheet is gone: a sheet asked for while another is
                // closing never shows.
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    showingPaywall = true
                }
                return
            }
            importCSV(url)
        } else {
            read {
                defer { Self.discardCopy(url) }
                return try await statement(from: url)
            }
        }
    }

    private func importCSV(_ url: URL) {
        csvFlow = ImportFlowCoordinator(
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel
        )
        Task {
            await csvFlow.startImport(from: url)
            Self.discardCopy(url)
        }
    }

    /// Deletes the copy of a document once read: the picker's in the temporary folder, the
    /// one "Open in" leaves in Documents/Inbox. Never a file elsewhere.
    private static func discardCopy(_ url: URL) {
        let path = url.standardizedFileURL.path
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let inbox = URL.documentsDirectory.appending(path: "Inbox").standardizedFileURL.path
        guard path.hasPrefix(temporary) || path.hasPrefix(inbox) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func presenting(_ kind: AssistantAttachmentSource) -> Binding<Bool> {
        Binding(
            get: { source == kind },
            set: { if !$0, source == kind { source = nil } }
        )
    }

    private enum AttachmentReadError: Error {
        case unreadable
    }

    /// Runs one reading; a failure becomes a line under the composer. A cancelled scan says
    /// nothing (ReceiptInterpreter's contract).
    private func read(_ work: @escaping () async throws -> (AgentAttachment, AgentAttachmentSummary)?) {
        reading = true
        Task {
            defer { reading = false }
            do {
                if let read = try await work() {
                    onRead(read.0, read.1)
                }
            } catch is CancellationError {
            } catch AttachmentReadError.unreadable {
                onFailure(String(localized: "import.error.noContentRecognized"))
            } catch {
                onFailure(error.localizedDescription)
            }
        }
    }

    private func receipt(from images: [CGImage]) async throws -> (AgentAttachment, AgentAttachmentSummary)? {
        let snapshot = try await VisionDocumentExtractor.extract(images: images)
        let baseCurrency = coordinator.transactionStore.baseCurrency
        guard let draft = try await ReceiptInterpreter.interpret(snapshot: snapshot, defaultCurrency: baseCurrency) else {
            onFailure(String(localized: "import.error.receiptNotRecognized"))
            return nil
        }
        return (.receipt(draft), .receipt(draft, baseCurrency: baseCurrency))
    }

    private func statement(from url: URL) async throws -> (AgentAttachment, AgentAttachmentSummary)? {
        let baseCurrency = coordinator.transactionStore.baseCurrency
        let outcome = try await DocumentImportService.importStatement(from: url, defaultCurrency: baseCurrency)
        guard !outcome.statement.transactions.isEmpty else { throw AttachmentReadError.unreadable }
        let review = await StatementReviewPreparer.prepare(
            outcome,
            baseCurrency: baseCurrency,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel
        )
        let accountName = review.statementAccountId.flatMap { id in coordinator.transactionStore.accounts.first { $0.id == id }?.name }
        return (.statement(review), .statement(review, accountName: accountName))
    }

    /// A photo as Vision reads it: drawn upright (a camera photo keeps its rotation in EXIF,
    /// which `cgImage` ignores).
    private static func upright(_ image: UIImage) -> CGImage? {
        guard image.imageOrientation != .up else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format)
            .image { _ in image.draw(at: .zero) }
            .cgImage
    }
}
