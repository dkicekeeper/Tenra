//
//  PDFImportCoordinator.swift
//  Tenra
//
//  PDF import flow coordinator - handles file picker, OCR, and CSV preview
//  Extracted from ContentView for Single Responsibility Principle
//

import SwiftUI
import PDFKit
import CoreGraphics

/// Coordinates the entire PDF import flow: file picker → DocumentImportService → CSV preview
/// Single responsibility: PDF import orchestration
struct PDFImportCoordinator: View {
    // MARK: - Dependencies
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    // MARK: - State
    @State private var showingFilePicker = false
    @State private var ocrProgress: (current: Int, total: Int)? = nil
    @State private var importOutcome: ImportOutcome? = nil
    @State private var showingCSVPreview = false
    @State private var parsedCSVFile: CSVFile? = nil
    @State private var showingScanner = false
    @State private var showingDiagnostics = false
    @State private var receiptDraft: ReceiptDraft? = nil

    // MARK: - Body
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            sourcePicker

            if let outcome = importOutcome {
                diagnosticsLink(for: outcome)
            }
        }
            .sheet(isPresented: $showingFilePicker) {
                filePicker
            }
            .sheet(isPresented: $showingCSVPreview) {
                csvPreviewSheet
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScannerView(
                    onScan: { images in
                        showingScanner = false
                        Task { await analyzeReceipt(images: images) }
                    },
                    onCancel: { showingScanner = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingDiagnostics) {
                if let outcome = importOutcome {
                    NavigationStack {
                        ImportDiagnosticsView(
                            statement: outcome.statement,
                            intelligenceStatus: outcome.intelligenceStatus
                        )
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { receiptDraft != nil },
                set: { isPresented in if !isPresented { receiptDraft = nil } }
            )) {
                if let draft = receiptDraft {
                    ReceiptConfirmationView(
                        draft: draft,
                        baseCurrency: transactionsViewModel.transactionStore?.baseCurrency ?? "KZT",
                        transactionsViewModel: transactionsViewModel,
                        accountsViewModel: accountsViewModel
                    )
                }
            }
            .overlay {
                if transactionsViewModel.isLoading {
                    loadingOverlay
                }
            }
    }

    // MARK: - Source Picker
    private var sourcePicker: some View {
        ImportSourcePicker(
            onPickPDF: { showingFilePicker = true },
            onScanReceipt: { showingScanner = true }
        )
    }

    // MARK: - Diagnostics Link
    /// Reuses the same UniversalRow shell as `ImportSourcePicker.sourceRow`
    /// rather than hand-rolling another card. Shown once an import has run, so
    /// the user always has a path to the skipped-row reasons — not just when
    /// something got skipped.
    private func diagnosticsLink(for outcome: ImportOutcome) -> some View {
        let summary = "\(outcome.statement.transactions.count) / \(outcome.statement.transactions.count + outcome.statement.skipped.count)"
        return UniversalRow(
            config: .standard,
            leadingIcon: .custom(
                source: .sfSymbol("list.bullet.clipboard"),
                style: .circle(size: AppIconSize.xxl,
                               tint: .monochrome(AppColors.accent),
                               backgroundColor: AppColors.accent.opacity(0.15))
            ),
            hint: summary,
            title: String(localized: "import.diagnostics.title")
        ) {
            Image(systemName: "chevron.right")
                .font(.system(size: AppIconSize.sm, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .cardStyle()
        .actionRow {
            HapticManager.light()
            showingDiagnostics = true
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.lg)
        .accessibilityLabel(String(localized: "import.diagnostics.title"))
    }

    // MARK: - File Picker
    private var filePicker: some View {
        DocumentPicker { url in
            Task {
                await analyzePDF(url: url)
            }
        }
    }

    // MARK: - CSV Preview Sheet
    @ViewBuilder
    private var csvPreviewSheet: some View {
        if let csvFile = parsedCSVFile {
            CSVPreviewView(
                csvFile: csvFile,
                onContinue: {
                    // TODO: Navigate to column mapping or import flow
                    showingCSVPreview = false
                },
                onCancel: {
                    showingCSVPreview = false
                    parsedCSVFile = nil
                }
            )
        }
    }

    // MARK: - Loading Overlay
    @ViewBuilder
    private var loadingOverlay: some View {
        VStack(spacing: AppSpacing.md) {
            if let progress = ocrProgress {
                ProgressView(value: Double(progress.current), total: Double(progress.total)) {
                    Text(String(localized: "progress.recognizingText", defaultValue: "Recognizing text..."))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                }
                Text(String(format: String(localized: "progress.page", defaultValue: "Page %d of %d"), progress.current, progress.total))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView(String(localized: "progress.processingPDF", defaultValue: "Processing PDF..."))
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    // MARK: - PDF Analysis
    private func analyzePDF(url: URL) async {
        transactionsViewModel.isLoading = true
        transactionsViewModel.errorMessage = nil
        ocrProgress = nil

        do {
            let baseCurrency = transactionsViewModel.transactionStore?.baseCurrency ?? "KZT"
            let outcome = try await DocumentImportService.importStatement(
                from: url,
                defaultCurrency: baseCurrency
            ) { current, total in
                Task { @MainActor in
                    ocrProgress = (current: current, total: total)
                }
            }
            importOutcome = outcome
            parsedCSVFile = outcome.csvFile
            showingCSVPreview = true
        } catch {
            transactionsViewModel.errorMessage = error.localizedDescription
        }

        transactionsViewModel.isLoading = false
        ocrProgress = nil
    }

    // MARK: - Receipt Analysis
    private func analyzeReceipt(images: [CGImage]) async {
        transactionsViewModel.isLoading = true
        transactionsViewModel.errorMessage = nil

        do {
            let snapshot = try await VisionDocumentExtractor.extract(images: images)
            let baseCurrency = transactionsViewModel.transactionStore?.baseCurrency ?? "KZT"
            let draft = try await ReceiptInterpreter.interpret(
                snapshot: snapshot,
                defaultCurrency: baseCurrency
            )
            if let draft {
                receiptDraft = draft
            } else {
                transactionsViewModel.errorMessage = String(localized: "import.error.receiptNotRecognized")
            }
        } catch is CancellationError {
            // The user backed out of the scan mid-interpretation. Per
            // ReceiptInterpreter's contract this must stop silently, not
            // surface as an error the user never asked to see.
        } catch {
            transactionsViewModel.errorMessage = error.localizedDescription
        }

        transactionsViewModel.isLoading = false
    }
}
