//
//  PDFImportCoordinator.swift
//  Tenra
//
//  PDF import flow coordinator - handles file picker, OCR, and the
//  transaction-card review screen (Task 15: recognized statement
//  transactions are reviewed as real transaction cards, not the CSV
//  preview / column-mapping flow — that flow remains a separate path for
//  actual .csv file imports, see ImportFlowCoordinator).
//  Extracted from ContentView for Single Responsibility Principle
//

import SwiftUI
import PDFKit
import CoreGraphics

/// Coordinates the entire PDF import flow: file picker → DocumentImportService → transaction preview
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
    @State private var showingTransactionPreview = false
    @State private var parsedTransactions: [Transaction] = []
    @State private var suggestedCategories: [String: String] = [:]
    @State private var duplicateReasons: [String: ImportDuplicateDetector.Reason] = [:]
    @State private var cashWithdrawalIds: Set<String> = []
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
            .sheet(isPresented: $showingTransactionPreview) {
                transactionPreviewSheet
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
                        accountsViewModel: accountsViewModel,
                        categoriesViewModel: categoriesViewModel
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

    // MARK: - Transaction Preview Sheet
    /// Recognized statement transactions are reviewed as real transaction
    /// cards, the way voice input presents its result, rather than the CSV
    /// preview / column-mapping flow. `ImportTransactionPreviewView` reads
    /// `TransactionStore` from the environment, inherited here from
    /// `MainTabView`'s `.environment(coordinator.transactionStore)`.
    private var transactionPreviewSheet: some View {
        ImportTransactionPreviewView(
            transactionsViewModel: transactionsViewModel,
            accountsViewModel: accountsViewModel,
            transactions: parsedTransactions,
            customCategories: categoriesViewModel.customCategories,
            suggestedCategories: suggestedCategories,
            duplicateReasons: duplicateReasons,
            cashWithdrawalIds: cashWithdrawalIds
        )
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
            if outcome.statement.transactions.isEmpty {
                // Nothing survived interpretation. Route straight to
                // diagnostics instead of presenting an empty transaction
                // preview sheet with no explanation — outcome.statement.skipped
                // carries every row (and every unreadable page) with its
                // reason, which is exactly what the user needs to see here.
                showingDiagnostics = true
            } else {
                let mapped = ParsedTransactionMapper.transactions(
                    from: outcome.statement,
                    defaultCurrency: baseCurrency
                )
                // Recognized rows arrive uncategorized; pre-fill the review
                // screen's category pickers from history, known merchants and
                // the voice keyword dictionary.
                let parser = VoiceInputParser(
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel,
                    transactionsViewModel: transactionsViewModel
                )
                suggestedCategories = await CategorySuggestionProvider.suggestions(
                    for: mapped,
                    history: transactionsViewModel.transactionStore?.transactions ?? [],
                    categories: categoriesViewModel.customCategories,
                    keywordMatcher: { parser.keywordCategory(in: $0) }
                )
                // Rows already in Tenra (a re-imported statement, or a charge a
                // subscription series already generated) start unchecked.
                let regularAccounts = accountsViewModel.regularAccounts
                var importedAccounts: [String: String] = [:]
                for tx in mapped {
                    if let account = ImportTransactionPreviewView.availableAccounts(
                        for: tx, regularAccounts: regularAccounts
                    ).first {
                        importedAccounts[tx.id] = account.id
                    }
                }
                let existing = transactionsViewModel.transactionStore?.transactions ?? []
                duplicateReasons = await Task.detached(priority: .userInitiated) {
                    ImportDuplicateDetector.detect(
                        imported: mapped,
                        importedAccounts: importedAccounts,
                        existing: existing
                    )
                }.value
                // Cash withdrawals move money into cash; the spending happens later
                // (and is logged separately), so importing them as expenses would count
                // it twice. They start unchecked. The mapper keeps statement order.
                cashWithdrawalIds = Set(zip(outcome.statement.transactions, mapped).compactMap { parsed, tx in
                    StatementOperationKind.classify(parsed.operation) == .cashWithdrawal ? tx.id : nil
                })
                parsedTransactions = mapped
                showingTransactionPreview = true
            }
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
