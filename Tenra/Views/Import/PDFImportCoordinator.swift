//
//  PDFImportCoordinator.swift
//  Tenra
//
//  PDF import flow coordinator - handles file picker, OCR, and CSV preview
//  Extracted from ContentView for Single Responsibility Principle
//

import SwiftUI
import PDFKit

/// Coordinates the entire PDF import flow: file picker → DocumentImportService → CSV preview
/// Single responsibility: PDF import orchestration
struct PDFImportCoordinator: View {
    // MARK: - Dependencies
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel

    // MARK: - State
    @State private var showingFilePicker = false
    @State private var ocrProgress: (current: Int, total: Int)? = nil
    @State private var importOutcome: ImportOutcome? = nil
    @State private var showingCSVPreview = false
    @State private var parsedCSVFile: CSVFile? = nil

    // MARK: - Body
    var body: some View {
        importButton
            .sheet(isPresented: $showingFilePicker) {
                filePicker
            }
            .sheet(isPresented: $showingCSVPreview) {
                csvPreviewSheet
            }
            .overlay {
                if transactionsViewModel.isLoading {
                    loadingOverlay
                }
            }
    }

    // MARK: - Import Button
    private var importButton: some View {
        Button(action: {
            HapticManager.light()
            showingFilePicker = true
        }) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: AppIconSize.lg))
                .fontWeight(.semibold)
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(String(localized: "accessibility.importStatement"))
        .accessibilityHint(String(localized: "accessibility.importStatementHint"))
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
}
