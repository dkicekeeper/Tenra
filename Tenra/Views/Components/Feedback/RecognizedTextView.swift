//
//  RecognizedTextView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct RecognizedTextView: View {
    let recognizedText: String
    let structuredRows: [[String]]?
    let viewModel: TransactionsViewModel
    let onImport: (CSVFile) -> Void
    let onCancel: () -> Void
    @State private var showingCopyAlert = false
    @State private var isParsing = false
    @State private var showingParseError = false
    @State private var parseErrorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Заголовок
                VStack(spacing: AppSpacing.sm) {
                    Text(String(localized: "modal.recognizedText.title"))
                        .font(AppTypography.h4)
                    Text(String(localized: "modal.recognizedText.message"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .cardContentPadding()
                .frame(maxWidth: .infinity)
                .background(AppColors.surface)

                // Текст
                ScrollView {
                    Text(recognizedText)
                        .font(.system(.body, design: .monospaced))
                        .padding(AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled) // Позволяет копировать текст
                }

                // Кнопки
                VStack(spacing: AppSpacing.md) {
                    // Основная кнопка - импорт транзакций
                    Button(action: {
                        isParsing = true
                        HapticManager.success()

                        // Парсим текст выписки в CSV формат с использованием структурированных данных
                        let csvFile = StatementTextParser.parseStatementToCSV(recognizedText, structuredRows: structuredRows)

                        isParsing = false

                        if csvFile.rows.isEmpty {
                            // Если не найдено транзакций, показываем ошибку
                            if structuredRows != nil {
                                parseErrorMessage = String(localized: "error.noTransactionsStructured")
                            } else {
                                parseErrorMessage = String(localized: "error.noTransactionsFound")
                            }
                            showingParseError = true
                        } else {
                            // Импортируем
                            onImport(csvFile)
                        }
                    }) {
                        Label(String(localized: "transaction.importTransactions"), systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(AppSpacing.md)
                            .background(AppColors.accent)
                            .foregroundStyle(.white)
                            .clipShape(.rect(cornerRadius: AppRadius.button))
                    }
                    .disabled(isParsing)

                    HStack(spacing: AppSpacing.md) {
                        Button(action: {
                            UIPasteboard.general.string = recognizedText
                            showingCopyAlert = true
                            HapticManager.success()
                        }) {
                            Label(String(localized: "button.copy"), systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                                .padding(AppSpacing.md)
                                .background(AppColors.secondaryBackground)
                                .foregroundStyle(AppColors.textPrimary)
                                .clipShape(.rect(cornerRadius: AppRadius.button))
                        }

                        Button(action: onCancel) {
                            Text(String(localized: "button.close"))
                                .frame(maxWidth: .infinity)
                                .padding(AppSpacing.md)
                                .background(AppColors.secondaryBackground)
                                .foregroundStyle(AppColors.textPrimary)
                                .clipShape(.rect(cornerRadius: AppRadius.button))
                        }
                    }
                }
                .cardContentPadding()
            }
            .navigationTitle(String(localized: "navigation.statementText"))
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isParsing {
                    AppColors.backgroundPrimary.opacity(0.6)
                        .ignoresSafeArea()
                    ProgressView(String(localized: "progress.parsingStatement"))
                        .cardContentPadding()
                        .background(AppColors.backgroundPrimary)
                        .clipShape(.rect(cornerRadius: AppRadius.card))
                }
            }
            .alert(String(localized: "alert.textCopied.title"), isPresented: $showingCopyAlert) {
                Button(String(localized: "button.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "alert.textCopied.message"))
            }
            .alert(String(localized: "alert.parseError.title"), isPresented: $showingParseError) {
                Button(String(localized: "button.ok"), role: .cancel) {}
            } message: {
                Text(parseErrorMessage)
            }
        }
    }
}
