//
//  PDFImportCoordinator.swift
//  AIFinanceManager
//
//  PDF import flow coordinator - handles file picker, OCR, and CSV preview
//  Extracted from ContentView for Single Responsibility Principle
//

import SwiftUI
import PDFKit

/// Coordinates the entire PDF import flow: file picker → OCR → recognized text → CSV preview
/// Single responsibility: PDF import orchestration
struct PDFImportCoordinator: View {
    // MARK: - Dependencies
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel

    // MARK: - State
    @State private var showingFilePicker = false
    @State private var ocrProgress: (current: Int, total: Int)? = nil
    @State private var recognizedText: String? = nil
    @State private var structuredRows: [[String]]? = nil
    @State private var showingRecognizedText = false
    @State private var showingCSVPreview = false
    @State private var parsedCSVFile: CSVFile? = nil

    // MARK: - Body
    var body: some View {
        importButton
            .sheet(isPresented: $showingFilePicker) {
                filePicker
            }
            .sheet(isPresented: $showingRecognizedText) {
                recognizedTextSheet
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
                .frame(width: AppSize.buttonLarge, height: AppSize.buttonLarge)
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

    // MARK: - Recognized Text Sheet
    @ViewBuilder
    private var recognizedTextSheet: some View {
        if let text = recognizedText, !text.isEmpty {
            RecognizedTextView(
                recognizedText: text,
                structuredRows: structuredRows,
                viewModel: transactionsViewModel,
                onImport: { csvFile in
                    showingRecognizedText = false
                    recognizedText = nil
                    structuredRows = nil
                    // Open CSVPreviewView for continued import
                    showingCSVPreview = true
                    parsedCSVFile = csvFile
                },
                onCancel: {
                    showingRecognizedText = false
                    recognizedText = nil
                    structuredRows = nil
                    transactionsViewModel.isLoading = false
                }
            )
        } else {
            // Fallback - empty screen if text not loaded
            NavigationStack {
                VStack(spacing: AppSpacing.md) {
                    Text(String(localized: "error.loadTextFailed"))
                        .font(AppTypography.h4)
                    Text(String(localized: "error.tryAgain"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                }
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
        recognizedText = nil

        do {
            // Extract text via PDFKit or OCR
            let ocrResult = try await PDFService.shared.extractText(from: url) { current, total in
                Task { @MainActor in
                    ocrProgress = (current: current, total: total)
                }
            }

            // Check that text is not empty
            let trimmedText = ocrResult.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                transactionsViewModel.errorMessage = String(localized: "error.pdfExtraction")
                transactionsViewModel.isLoading = false
                ocrProgress = nil
                return
            }

            recognizedText = ocrResult.fullText
            structuredRows = ocrResult.structuredRows
            ocrProgress = nil
            transactionsViewModel.isLoading = false
            showingRecognizedText = true

        } catch let error as PDFError {
            transactionsViewModel.errorMessage = error.localizedDescription
            transactionsViewModel.isLoading = false
            ocrProgress = nil
            recognizedText = nil
            structuredRows = nil
        } catch {
            transactionsViewModel.errorMessage = String(
                format: String(localized: "error.pdfRecognitionFailed"),
                error.localizedDescription
            )
            transactionsViewModel.isLoading = false
            ocrProgress = nil
            recognizedText = nil
            structuredRows = nil
        }
    }
}
