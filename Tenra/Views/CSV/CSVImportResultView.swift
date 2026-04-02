//
//  CSVImportResultView.swift
//  AIFinanceManager
//
//  Created on 2024
//  Refactored: 2026-02-03 (Phase 4 - ImportStatistics + Props + Callbacks)
//

import SwiftUI

/// Import result display with comprehensive statistics and performance metrics
/// Refactored to use ImportStatistics instead of ImportResult
struct CSVImportResultView: View {
    // MARK: - Props

    let statistics: ImportStatistics
    let onDone: () -> Void
    let onViewErrors: (() -> Void)?

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xxl) {
                // Persistence failure banner — shown above everything else
                if let persistenceError = statistics.persistenceError {
                    InlineStatusText(
                        message: String(localized: "csvImport.error.persistenceFailed") + " \(persistenceError)",
                        type: .error
                    )
                }

                // Result icon
                resultIcon

                // Statistics section
                statisticsSection

                // Performance metrics section
                performanceSection

                // Errors section
                if statistics.hasErrors {
                    errorsSection
                }

                Spacer()

                // Done button
                doneButton
            }
            .screenPadding()
            .navigationTitle(String(localized: "csvImport.result.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if statistics.persistenceError != nil {
                HapticManager.error()
            } else if statistics.successRate > 0.8 {
                HapticManager.success()
            } else {
                HapticManager.warning()
            }
        }
    }

    // MARK: - Sections

    private var resultIcon: some View {
        Image(systemName: statistics.successRate > 0.8 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: AppIconSize.mega))
            .foregroundStyle(statistics.successRate > 0.8 ? AppColors.success : AppColors.warning)
    }

    private var statisticsSection: some View {
        VStack(spacing: AppSpacing.lg) {
            StatRow(
                label: String(format: String(localized: "csvImport.result.imported"), statistics.importedCount),
                value: "",
                color: AppColors.success,
                icon: "checkmark.circle"
            )

            if statistics.duplicatesSkipped > 0 {
                StatRow(
                    label: String(format: String(localized: "csvImport.result.duplicates"), statistics.duplicatesSkipped),
                    value: "",
                    color: .purple,
                    icon: "arrow.triangle.2.circlepath"
                )
            }

            if statistics.skippedCount - statistics.duplicatesSkipped > 0 {
                StatRow(
                    label: String(format: String(localized: "csvImport.result.skipped"), statistics.skippedCount - statistics.duplicatesSkipped),
                    value: "",
                    color: AppColors.warning,
                    icon: "exclamationmark.circle"
                )
            }

            Divider()

            if statistics.createdAccounts > 0 {
                StatRow(
                    label: String(format: String(localized: "csvImport.result.createdAccounts"), statistics.createdAccounts),
                    value: "",
                    color: AppColors.accent,
                    icon: "plus.circle"
                )
            }

            if statistics.createdCategories > 0 {
                StatRow(
                    label: String(format: String(localized: "csvImport.result.createdCategories"), statistics.createdCategories),
                    value: "",
                    color: AppColors.accent,
                    icon: "plus.circle"
                )
            }

            if statistics.createdSubcategories > 0 {
                StatRow(
                    label: String(format: String(localized: "csvImport.result.createdSubcategories"), statistics.createdSubcategories),
                    value: "",
                    color: AppColors.accent,
                    icon: "plus.circle"
                )
            }
        }
        .cardContentPadding()
        .background(AppColors.surface)
        .clipShape(.rect(cornerRadius: AppRadius.card))
    }

    private var performanceSection: some View {
        VStack(spacing: AppSpacing.md) {
            Text(String(localized: "csvImport.result.performance"))
                .font(AppTypography.h4)

            HStack {
                Text(String(localized: "csvImport.result.duration"))
                Spacer()
                Text(String(format: "%.1fs", statistics.duration))
                    .fontWeight(.semibold)
            }

            HStack {
                Text(String(localized: "csvImport.result.speed"))
                Spacer()
                Text(String(format: "%.0f rows/s", statistics.rowsPerSecond))
                    .fontWeight(.semibold)
            }

            HStack {
                Text(String(localized: "csvImport.result.successRate"))
                Spacer()
                Text("\(statistics.successPercentage)%")
                    .fontWeight(.semibold)
                    .foregroundStyle(statistics.successRate > 0.8 ? AppColors.success : AppColors.warning)
            }
        }
        .cardContentPadding()
        .background(AppColors.surface)
        .clipShape(.rect(cornerRadius: AppRadius.card))
    }

    private var errorsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text(String(localized: "csvImport.result.errors"))
                    .font(AppTypography.h4)

                Spacer()

                if let onViewErrors = onViewErrors {
                    Button(action: onViewErrors) {
                        Text(String(localized: "csvImport.button.viewErrors"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(Array(statistics.errors.prefix(10).enumerated()), id: \.offset) { _, error in
                        Text("• \(error.localizedDescription)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.destructive)
                    }

                    if statistics.validationErrorCount > 10 {
                        Text(String(
                            format: String(localized: "csvImport.result.moreErrors"),
                            statistics.validationErrorCount - 10
                        ))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .frame(maxHeight: AppSize.resultListHeight)
        }
        .cardContentPadding()
        .background(AppColors.surface)
        .clipShape(.rect(cornerRadius: AppRadius.card))
    }

    private var doneButton: some View {
        Button(action: {
            onDone()
            dismiss()
        }) {
            Text(String(localized: "button.done"))
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.md)
                .background(AppColors.accent)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: AppRadius.button))
        }
        .cardContentPadding()
    }
}

// MARK: - StatRow Component

/// Reusable statistics row component
struct StatRow: View {
    let label: String
    let value: String
    let color: Color
    let icon: String?

    init(label: String, value: String, color: Color, icon: String? = nil) {
        self.label = label
        self.value = value
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            Text(label)
                .font(AppTypography.body)
            Spacer()
            Text(value)
                .font(AppTypography.bodyEmphasis)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}
