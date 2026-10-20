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
//  A PDF is a statement or the receipt of one payment (DocumentImportService.importDocument):
//  a receipt opens the receipt confirmation, as a scanned one does. A PDF opened in Tenra
//  from another app while the assistant cannot take it arrives as `incomingFile`.
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
    /// A PDF handed over from another app ("Open in Tenra"); read once, then its copy goes.
    var incomingFile: URL? = nil
    /// Called as `incomingFile` is taken, so the sender stops offering it.
    var onIncomingFileTaken: () -> Void = {}

    // MARK: - State
    @State private var showingFilePicker = false
    @State private var ocrProgress: (current: Int, total: Int)? = nil
    @State private var importOutcome: ImportOutcome? = nil
    @State private var showingTransactionPreview = false
    @State private var parsedTransactions: [Transaction] = []
    @State private var suggestedCategories: [String: String] = [:]
    @State private var uncheckedMoves: [String: StatementOperationKind] = [:]
    @State private var transferEligibleIds: Set<String> = []
    @State private var statementAccountId: String?
    @State private var subcategoryHistory = CategorySuggestionService.SubcategoryIndex()
    @State private var transferHistory = ImportTransferHistory.Index()
    @State private var showingScanner = false
    @State private var showingDiagnostics = false
    @State private var receiptDraft: ReceiptDraft? = nil
    /// Why the last statement or receipt could not be read: a banner over the sources, where
    /// the person tried, until the next attempt (DesignKit's `StatusBanner`).
    @State private var importError: String?

    // MARK: - Body
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            if let importError {
                StatusBanner(importError, status: .negative)
                    .screenPadding()
                    .transition(.opacity)
            }

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
                    .softScrollEdges()
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
            .animation(AppAnimation.smooth, value: importError)
            .onChange(of: incomingFile, initial: true) { _, url in
                guard let url else { return }
                onIncomingFileTaken()
                Task {
                    await analyzePDF(url: url)
                    DocumentImportService.discardCopy(url)
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
                style: .circle(size: AppIconSize.Tile.sm,
                               tint: .monochrome(AppColors.accent),
                               backgroundColor: AppColors.pale(AppColors.accent))
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
            categoriesViewModel: categoriesViewModel,
            suggestedCategories: suggestedCategories,
            subcategoryHistory: subcategoryHistory,
            transferHistory: transferHistory,
            uncheckedMoves: uncheckedMoves,
            transferEligibleIds: transferEligibleIds,
            defaultStatementAccountId: statementAccountId,
            closingBalances: importOutcome?.closingBalances ?? []
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
        importError = nil
        ocrProgress = nil

        do {
            let baseCurrency = transactionsViewModel.transactionStore?.baseCurrency ?? "KZT"
            let content = try await DocumentImportService.importDocument(
                from: url,
                defaultCurrency: baseCurrency
            ) { current, total in
                Task { @MainActor in
                    ocrProgress = (current: current, total: total)
                }
            }
            let outcome: ImportOutcome
            switch content {
            case .receipt(let draft):
                // The receipt of one payment a bank app shared: confirmed like a scanned one.
                transactionsViewModel.isLoading = false
                ocrProgress = nil
                receiptDraft = draft
                return
            case .statement(let statement):
                outcome = statement
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
                let review = await StatementReviewPreparer.prepare(
                    outcome,
                    baseCurrency: baseCurrency,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel
                )
                suggestedCategories = review.suggestedCategories
                subcategoryHistory = review.subcategoryHistory
                transferHistory = review.transferHistory
                statementAccountId = review.statementAccountId
                uncheckedMoves = review.uncheckedMoves
                transferEligibleIds = review.transferEligibleIds
                parsedTransactions = review.transactions
                showingTransactionPreview = true
            }
        } catch {
            importError = error.localizedDescription
        }

        transactionsViewModel.isLoading = false
        ocrProgress = nil
    }

    // MARK: - Receipt Analysis
    private func analyzeReceipt(images: [CGImage]) async {
        transactionsViewModel.isLoading = true
        importError = nil

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
                importError = String(localized: "import.error.receiptNotRecognized")
            }
        } catch is CancellationError {
            // The user backed out of the scan mid-interpretation. Per
            // ReceiptInterpreter's contract this must stop silently, not
            // surface as an error the user never asked to see.
        } catch {
            importError = error.localizedDescription
        }

        transactionsViewModel.isLoading = false
    }
}
