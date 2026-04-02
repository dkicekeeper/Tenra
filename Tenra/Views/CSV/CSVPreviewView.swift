//
//  CSVPreviewView.swift
//  AIFinanceManager
//
//  Created on 2024
//  Refactored: 2026-02-03 (Phase 4 - Props + Callbacks)
//

import SwiftUI

/// CSV file preview with stats and header/data display
/// Refactored to use Props + Callbacks pattern (no ViewModel dependencies)
struct CSVPreviewView: View {
    // MARK: - Props

    let csvFile: CSVFile
    let onContinue: () -> Void
    let onCancel: () -> Void

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                // File information card
                fileInfoSection

                // Headers section
                headersSection

                // Data preview section
                dataPreviewSection

                Spacer()

                // Continue button
                continueButton
            }
            .navigationTitle(String(localized: "csvImport.preview.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(localized: "csvImport.preview.fileInfo"))
                .font(AppTypography.h4)

            HStack {
                Text(String(localized: "csvImport.preview.columns"))
                Spacer()
                Text("\(csvFile.headers.count)")
                    .font(AppTypography.bodyEmphasis)
            }

            HStack {
                Text(String(localized: "csvImport.preview.rows"))
                Spacer()
                Text("\(csvFile.rowCount)")
                    .font(AppTypography.bodyEmphasis)
            }
        }
        .cardContentPadding()
        .background(AppColors.surface)
        .clipShape(.rect(cornerRadius: AppRadius.card))
    }

    private var headersSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(localized: "csvImport.preview.headersTitle"))
                .font(AppTypography.h4)

            UniversalCarousel(config: .csvPreview) {
                ForEach(csvFile.headers, id: \.self) { header in
                    Text(header)
                        .font(AppTypography.caption)
                        .padding(AppSpacing.sm)
                        .background(AppColors.accent.opacity(0.2))
                        .clipShape(.rect(cornerRadius: AppRadius.compact))
                }
            }
        }
        .cardContentPadding()
    }

    private var dataPreviewSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(
                format: String(localized: "csvImport.preview.dataPreview"),
                csvFile.preview.count
            ))
            .font(AppTypography.h4)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(Array(csvFile.preview.enumerated()), id: \.offset) { index, row in
                        previewRow(index: index, row: row)
                    }
                }
            }
            .frame(maxHeight: AppSize.previewScrollHeight)
        }
        .cardContentPadding()
    }

    private func previewRow(index: Int, row: [String]) -> some View {
        HStack(alignment: .top) {
            Text("\(index + 1).")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 30, alignment: .leading)

            UniversalCarousel(config: .compact) {
                ForEach(Array(row.enumerated()), id: \.offset) { colIndex, value in
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(csvFile.headers[safe: colIndex] ?? "?")
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(value.isEmpty
                            ? String(localized: "csv.emptyCell")
                            : value
                        )
                        .font(AppTypography.caption)
                        .lineLimit(2)
                    }
                    .padding(AppSpacing.compact)
                    .frame(width: AppSize.subscriptionCardWidth, alignment: .leading)
                    .background(AppColors.surface)
                    .clipShape(.rect(cornerRadius: AppRadius.xs))
                }
            }
        }
    }

    private var continueButton: some View {
        Button(action: {
            onContinue()
        }) {
            Text(String(localized: "button.continue"))
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.md)
                .background(AppColors.accent)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: AppRadius.button))
        }
        .cardContentPadding()
    }
}

// MARK: - Collection Extension

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
